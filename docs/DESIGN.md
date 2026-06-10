# SafeClip — App Design & Architecture

_Last updated: June 2026. Status: pre-build (planning complete). Reflects all decisions made in Session 1._

---

## Table of Contents

1. [Mental model — one app, three surfaces](#1-mental-model--one-app-three-surfaces)
2. [App lifecycle](#2-app-lifecycle)
3. [Surface 1 — Menu Bar](#3-surface-1--menu-bar)
4. [Surface 2 — Floating Panel](#4-surface-2--floating-panel)
5. [Surface 3 — Settings Window](#5-surface-3--settings-window)
6. [Shared service layer](#6-shared-service-layer)
7. [Data flow end-to-end](#7-data-flow-end-to-end)
8. [SwiftUI / AppKit split](#8-swiftui--appkit-split)
9. [File & module layout (target)](#9-file--module-layout-target)
10. [Key constraints that drive every design decision](#10-key-constraints-that-drive-every-design-decision)

---

## 1. Mental model — one app, three surfaces

SafeClip is **one application bundle**, one process, zero Dock icon. It exposes three distinct UI surfaces that share one data layer:

```
┌─────────────────────────────────────────────────────┐
│  SafeClip.app  (single process, no Dock icon)        │
│                                                       │
│  ┌──────────────┐  ┌────────────────┐  ┌──────────┐  │
│  │  Menu Bar    │  │ Floating Panel │  │ Settings │  │
│  │ NSStatusItem │  │   NSPanel      │  │ NSWindow │  │
│  └──────┬───────┘  └───────┬────────┘  └────┬─────┘  │
│         │                  │                │         │
│         └──────────────────┴────────────────┘         │
│                            │                          │
│         ┌──────────────────▼───────────────────────┐  │
│         │              AppState                     │  │
│         │   ClipboardMonitor · HistoryStore         │  │
│         │   KeychainManager · ScreenRecordWatcher   │  │
│         └──────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

The three surfaces never open simultaneously (panel and settings are both dismissable; the menu bar is always present but its menu is ephemeral). They communicate exclusively through the shared `AppState` object — no direct references between surface controllers.

---

## 2. App lifecycle

### No Dock icon (`LSUIElement`)

The app sets `LSUIElement = YES` in `Info.plist`. This means:
- No Dock icon
- No standard app menu bar (`File`, `Edit`, `View`, …)
- The menu bar icon (`NSStatusItem`) is the only persistent UI
- Cmd+, and other standard app shortcuts don't fire — we handle shortcuts ourselves

### SwiftUI entry point with AppKit delegate

```swift
// SafeClipApp.swift
@main
struct SafeClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // No scenes declared — all UI is managed imperatively by AppDelegate.
        // This is intentional: NSPanel (non-activating) and NSStatusItem
        // don't map cleanly to SwiftUI scene lifecycle.
    }
}
```

`AppDelegate` owns the root `AppState` and hands it to every surface controller at startup.

### Startup sequence

```
application(_:didFinishLaunching:)
  1. KeychainManager.ensureKey()       ← generate or load AES key
  2. HistoryStore.open()               ← open/migrate SQLite
  3. AppState init                     ← root observable object
  4. MenuBarController.setup()         ← create NSStatusItem
  5. FloatingPanelController.setup()   ← pre-create NSPanel (hidden)
  6. ClipboardMonitor.start()          ← begin changeCount polling
  7. ScreenRecordWatcher.start()       ← watch CGDisplayStream / SCStream
  8. SMAppService.mainApp.register()   ← launch-at-login
  9. FirstLaunchOnboarding (if needed) ← show onboarding window
```

The panel is **pre-created at startup** (hidden) so it appears in <100ms when the shortcut fires — no allocation on the hot path.

### Termination

`applicationWillTerminate`: flush any pending writes to SQLite, stop the clipboard monitor, unregister the global hotkey. No data loss risk — every copy is written to disk immediately.

---

## 3. Surface 1 — Menu Bar

### What it is

A persistent `NSStatusItem` in the system menu bar. It is the app's only always-visible UI element. It does not show a dropdown list of clips — that's the floating panel's job. The menu bar is for app control.

### Icon states

| State | Icon | Meaning |
|-------|------|---------|
| Active | clipboard icon | Capturing normally |
| Paused | clipboard icon with slash | User paused capture |
| Recording | clipboard icon with dot | Screen recording detected, history hidden |

Icons are PDF/SVG template images so they respect the menu-bar appearance (dark/light, tinted when open).

### Menu structure

```
SafeClip                     ← title item (non-clickable, shows app name)
─────────────────────────────
Show History      ⌃⇧V        ← opens the floating panel at cursor
─────────────────────────────
● Capturing                  ← toggle; shows "Paused" when off
─────────────────────────────
Clear All History…           ← destructive; shows confirmation sheet
─────────────────────────────
Preferences…                 ← opens settings window
About SafeClip               ← standard about panel
─────────────────────────────
Quit SafeClip     ⌘Q
```

"Capturing" is a state-bound `NSMenuItem` with a checkmark. "Clear All History…" presents a `NSAlert` before acting — never destructive on first click.

### Implementation notes

- `NSStatusItem.button` holds the icon. `NSStatusItem.menu` is set directly (no `target/action` pattern needed for a static menu).
- The "Show History" item duplicates the global shortcut action so the app is discoverable even before the user learns the hotkey.
- "Capturing" toggle goes through `AppState.captureEnabled` — the `ClipboardMonitor` observes that property and suspends polling when false.

---

## 4. Surface 2 — Floating Panel

### What it is

An `NSPanel` that appears **at the mouse cursor** when the user presses the global shortcut (default `⌃⇧V`). It does not steal focus from the active app. The user selects a clip and presses Return; the clip lands on the pasteboard and the panel closes. The user then presses ⌘V in their app as usual.

This is the primary use surface — the menu bar is secondary.

### Panel configuration

```swift
let panel = NSPanel(
    contentRect: .zero,
    styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
    backing: .buffered,
    defer: true
)
panel.isFloatingPanel     = true   // stays above normal windows
panel.level               = .floating
panel.hidesOnDeactivate   = false  // stays open when user clicks away
panel.isMovableByWindowBackground = true   // drag anywhere to reposition
panel.titleVisibility     = .hidden
panel.titlebarAppearsTransparent = true
panel.backgroundColor     = .clear
panel.hasShadow           = true
```

`.nonactivatingPanel` is the critical flag — it prevents the panel from taking key focus from the app the user is typing in.

### Positioning logic

```
origin = NSEvent.mouseLocation           // global coordinates
origin.y -= panelHeight                  // place below cursor, not over it
clamp origin to screen.visibleFrame      // don't go off-screen or under notch
```

Multi-monitor: `NSScreen.screens` is iterated to find which screen contains `mouseLocation`; that screen's `visibleFrame` is used for clamping.

### SwiftUI content

The panel hosts an `NSHostingView<ClipboardPanelView>`. The SwiftUI view owns all interactivity:

```
ClipboardPanelView
├── SearchField          ← focused on open; filters list
├── ClipListView         ← scrollable, arrow-key navigable
│   └── ClipRowView ×N   ← each item; right-click for context menu
└── HintBarView          ← "↩ paste · ⌥↩ keep format · ⎋ close"
```

### Keyboard handling

Because the panel is non-activating, key events go to the **active app by default**. To capture keystrokes inside the panel:

- The `NSPanel` subclass overrides `keyDown(_:)` and routes them to the SwiftUI content via a `FocusState` / `@FocusedValue` mechanism, or by making the panel the key window temporarily while keeping the first responder in the app.
- Alternatively, a local event monitor (`NSEvent.addLocalMonitorForEvents(matching: .keyDown)`) captures keys while the panel is visible.
- `Escape` calls `panel.orderOut(nil)` — no focus change, user is back where they were.

### Opening / closing

- **Open:** `panel.orderFront(nil)` — does not change key window.
- **Close:** `panel.orderOut(nil)` on Escape, on paste (Return/⌥Return), on clicking outside (via `NSEvent.addGlobalMonitorForEvents` watching `.leftMouseDown` outside the panel frame).
- **Screen recording active:** `ClipListView` is replaced with a blurred placeholder. The panel can still be opened but content is hidden.

### Empty state

"No clipboard history yet. Copy something and it'll appear here." Shown when `HistoryStore.clips` is empty.

---

## 5. Surface 3 — Settings Window

### What it is

A standard `NSWindow` (activating, titled, resizable) that opens when the user clicks "Preferences…" in the menu bar. It is a normal window — it takes focus, appears in Mission Control, and can be Command-W closed.

It is **not** an `NSPanel`. Unlike the floating clipboard panel, it intentionally activates the app so the user can interact with form controls normally.

### Opening the settings window

Since `LSUIElement = YES` removes the standard `Cmd+,` app menu, settings is opened programmatically:

```swift
// In MenuBarController, "Preferences…" menu item action:
func openSettings() {
    if settingsWindowController == nil {
        settingsWindowController = SettingsWindowController()
    }
    settingsWindowController?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)   // bring app to front
}
```

`NSApp.activate(ignoringOtherApps: true)` is safe here because the user explicitly clicked "Preferences…" — they expect focus to shift to the settings window.

### Window configuration

```swift
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
    styleMask: [.titled, .closable, .miniaturizable],
    backing: .buffered,
    defer: false
)
window.title = "SafeClip Preferences"
window.center()
window.setFrameAutosaveName("SafeClipSettings")  // remembers position
```

`setFrameAutosaveName` stores the last position in `UserDefaults` for free.

### Settings tab structure

The settings window uses a tab-bar layout (SwiftUI `TabView` with `.tabViewStyle(.grouped)` or a custom sidebar on macOS 14+):

#### Tab 1 — General
| Setting | UI control | Notes |
|---------|-----------|-------|
| Global shortcut | `KeyboardShortcuts.Recorder` | Sindre Sorhus component; shows current binding, click to rebind |
| History limit | Stepper + text field | 50 / 100 / 200 / 500 / Unlimited |
| Auto-expiry | Picker | 1 day / 7 days / 30 days / Never |
| Default paste | Toggle | On = strip formatting (plain text); Off = keep formatting |
| Launch at login | Toggle | Calls `SMAppService.mainApp.register()` / `.unregister()` |

#### Tab 2 — Privacy
| Setting | UI control | Notes |
|---------|-----------|-------|
| Hide history while screen recording | Toggle | Default: On. Drives `ScreenRecordWatcher` behaviour |
| App exclusion list | List + Add/Remove | Bundle IDs; user types or uses app picker |
| _(Add app)_ | Button → NSOpenPanel | Filter for `.app` bundles; reads `CFBundleIdentifier` |

**App picker detail:** "Add App…" opens `NSOpenPanel` with `allowedContentTypes: [.application]`, reads the selected `.app`'s `Info.plist` to extract `CFBundleIdentifier`, and adds it to the list. Displayed as the app's localized name with its bundle ID in secondary text.

#### Tab 3 — Advanced
| Setting | UI control | Notes |
|---------|-----------|-------|
| Pattern detection | Toggle (master) | Default: Off |
| └ API keys (`ghp_`, `sk-`, `AKIA…`) | Toggle | Enabled only when master is On |
| └ Credit card numbers (Luhn) | Toggle | |
| └ Private key headers | Toggle | |
| └ Auto-burn flagged items | Toggle | Deletes after one paste |
| ClickFix / pastejacking detection | Toggle | Default: Off (P2 feature, greyed until M5) |
| Clear All History | Button (destructive red) | Shows confirmation alert |
| Export history | Button | Exports decrypted history as JSON (for migration) |

#### Tab 4 — About
- App icon, version string, build number
- "View source on GitHub" link
- "Read Terms of Use" link (opens TERMS.md / rendered HTML)
- "Third-party licenses" disclosure (GRDB.swift, KeyboardShortcuts)

### State binding

Settings views bind directly to `AppState` (passed as `@EnvironmentObject` or via the SwiftUI environment). Changes take effect immediately — no "Apply" button. Each setting change:
1. Updates the in-memory `AppState` property.
2. Persists to `UserDefaults` (non-sensitive) or calls the relevant service method (`ClipboardMonitor.setExclusionList`, `HistoryStore.setExpiry`, etc.).

Destructive actions (Clear All, remove exclusion app) have inline confirmation in the settings UI before calling through to the store.

---

## 6. Shared service layer

These objects are owned by `AppDelegate`, injected into `AppState`, and observed by all three surfaces.

### `AppState` (root observable)

```swift
@Observable
final class AppState {
    var clips: [ClipItem] = []          // decrypted list (lazy; loaded on panel open)
    var captureEnabled: Bool = true     // drives ClipboardMonitor
    var isRecording: Bool = false       // drives panel blur
    var settings: Settings              // all persisted preferences
}
```

### `ClipboardMonitor`

Polls `NSPasteboard.general.changeCount` every ~200ms on a background thread (macOS 14–15). On macOS 16+, uses the `detect`-before-read API (read type metadata without content, avoiding the per-copy permission prompt). When a change is detected:

1. Check `captureEnabled` — if false, skip.
2. Check `sourceBundle` against exclusion list — if excluded, skip.
3. Read plain string + rich representation.
4. Run ClickFix heuristic (if enabled).
5. Call `HistoryStore.insert(_:)`.

The macOS version check is a compile-time `#available(macOS 16, *)` with a protocol-based abstraction so both paths can be tested separately.

### `HistoryStore`

Wraps GRDB.swift. All reads/writes happen on a dedicated database queue (serial, off-main). Public API:

- `insert(_ item: ClipItem)` — encrypts and writes; deduplicates by `content_hash`.
- `fetchAll() -> [ClipItem]` — decrypts all; used when panel opens.
- `fetchFiltered(query: String) -> [ClipItem]` — decrypts lazily for search.
- `delete(id: UUID)` — removes row.
- `deleteAll()` — clears all rows.
- `sweepExpired()` — deletes rows older than the expiry window; called daily.

### `KeychainManager`

Single responsibility: read/write the AES-256 key from the macOS Keychain with `kSecAttrAccessControl` binding. If the key is missing (first launch or Keychain wiped), generates a new one with `SymmetricKey(size: .bits256)`. If the key is corrupt/unreadable, surfaces an error to `AppState` — the user is offered to reset (which wipes the now-unreadable history).

### `ScreenRecordWatcher`

Polls `CGDisplayStreamCreate` or observes `SCShareableContentInfo` (macOS 15+) to detect active screen recording. Sets `AppState.isRecording`. The floating panel's content view watches this flag and blurs its list content accordingly.

---

## 7. Data flow end-to-end

### Copy path

```
NSPasteboard changeCount changes
  ↓ ClipboardMonitor (background thread, ~200ms poll)
  ↓ [exclusion check]
  ↓ read plain string + rich data
  ↓ [ClickFix heuristic if enabled]
  ↓ HistoryStore.insert()
      ↓ SHA-256 hash → dedup check
      ↓ AES-256-GCM encrypt (plain + rich separately)
      ↓ GRDB INSERT or UPDATE last_used_at
  ↓ AppState.clips updated on main thread (via @MainActor)
  ↓ Menu bar icon stays unchanged (no visual feedback on copy — by design)
```

### Panel open path

```
Global shortcut fires (KeyboardShortcuts callback, main thread)
  ↓ FloatingPanelController.show()
  ↓ position panel at NSEvent.mouseLocation (clamp to screen)
  ↓ if AppState.clips is empty → HistoryStore.fetchAll() → decrypt
  ↓ panel.orderFront(nil)  ← does NOT steal focus
  ↓ SearchField becomes first responder inside panel
  ↓ ClipListView renders decrypted items
```

### Paste path

```
User presses Return (or ⌥Return) on selected item
  ↓ ClipboardPanelView sends paste action to FloatingPanelController
  ↓ HistoryStore.fetchDecrypted(id:) → plain (or rich) string
  ↓ NSPasteboard.general.setString(plain, forType: .string)
      — OR —
      NSPasteboard.general.setData(richData, forType: richUTI)   [⌥Return]
  ↓ panel.orderOut(nil)
  ↓ [if burn-after-paste] HistoryStore.delete(id:)
  ↓ User presses ⌘V in their app  ← SafeClip plays no further role
```

The paste window limitation lives here: plaintext sits on `NSPasteboard` from the moment SafeClip writes it until the receiving app reads it (typically <1s). This is disclosed in TERMS §3 and there is no technical mitigation — only honest disclosure.

---

## 8. SwiftUI / AppKit split

SafeClip uses both frameworks with a deliberate split:

| Layer | Framework | Reason |
|-------|-----------|--------|
| `NSStatusItem` + `NSMenu` | AppKit | SwiftUI `MenuBarExtra` is too limited (can't mix static and dynamic items cleanly, no custom icons) |
| `NSPanel` (the floating panel window itself) | AppKit | `.nonactivatingPanel` style mask not available in SwiftUI scenes; cursor positioning requires AppKit |
| Content inside the panel | SwiftUI | List, search field, keyboard navigation — SwiftUI handles these cleanly |
| Settings window (the `NSWindow`) | AppKit | Manual controller so we control activation behaviour |
| Content inside settings | SwiftUI | All form controls, tab view — SwiftUI is ideal for settings UIs |
| `NSApplicationDelegate` | AppKit | App lifecycle, NSStatusItem, global event monitors — no pure SwiftUI equivalent |
| `ClipboardMonitor`, `HistoryStore`, etc. | Swift (no UI framework) | Service layer is framework-agnostic; testable without AppKit |

The rule: AppKit for **window chrome and system integration**; SwiftUI for **content inside windows**.

---

## 9. File & module layout (target)

```
SafeClip/
├── SafeClipApp.swift            ← @main, NSApplicationDelegateAdaptor
├── AppDelegate.swift            ← startup sequence, owns all controllers
├── AppState.swift               ← @Observable root state
│
├── MenuBar/
│   └── MenuBarController.swift  ← NSStatusItem, NSMenu, icon state
│
├── Panel/
│   ├── FloatingPanelController.swift   ← NSPanel setup, show/hide, positioning
│   ├── ClipboardPanelView.swift        ← SwiftUI root view for the panel
│   ├── ClipListView.swift              ← scrollable list + keyboard nav
│   ├── ClipRowView.swift               ← individual row + context menu
│   └── HintBarView.swift               ← keyboard shortcut hints
│
├── Settings/
│   ├── SettingsWindowController.swift  ← NSWindow setup, opens on menu action
│   ├── SettingsView.swift              ← SwiftUI TabView root
│   ├── GeneralSettingsView.swift
│   ├── PrivacySettingsView.swift
│   ├── AdvancedSettingsView.swift
│   └── AboutView.swift
│
├── Services/
│   ├── ClipboardMonitor.swift          ← changeCount polling + macOS 16 path
│   ├── HistoryStore.swift              ← GRDB wrapper, all DB operations
│   ├── KeychainManager.swift           ← AES key read/write/generate
│   ├── EncryptionService.swift         ← AES-256-GCM encrypt/decrypt
│   └── ScreenRecordWatcher.swift       ← recording detection
│
├── Models/
│   ├── ClipItem.swift                  ← value type, encrypted + decrypted forms
│   ├── Settings.swift                  ← persisted preferences (UserDefaults-backed)
│   └── FlagReason.swift                ← enum: apiKey, card, privateKey, clickfix
│
├── Onboarding/
│   ├── OnboardingWindowController.swift
│   └── OnboardingView.swift            ← 3-screen flow
│
└── Resources/
    ├── SafeClip.entitlements           ← Hardened Runtime; no sandbox
    ├── Info.plist                      ← LSUIElement = YES
    └── Assets.xcassets/                ← menu bar icons (template images)
```

Dependencies (via Swift Package Manager):
- `GRDB.swift` — SQLite ORM
- `KeyboardShortcuts` — global hotkey recorder + listener

---

## 10. Key constraints that drive every design decision

These are non-negotiable. Every design choice above flows from them:

| Constraint | Implication |
|-----------|-------------|
| **Zero special permissions at launch** | No synthesized ⌘V (would need Accessibility). User presses ⌘V themselves. |
| **Non-activating panel** | Panel cannot host a standard `NSTextField` first responder trivially — requires local key event monitoring. |
| **LSUIElement = YES** | No app menu bar → Cmd+, doesn't work → settings opened from menu bar menu only. |
| **Non-sandboxed (off-MAS .dmg)** | Simpler pasteboard access; no entitlement dance for `com.apple.security.temporary-exception.apple-events`. Hardened Runtime still required for notarization. |
| **AES key bound to code signature** | Re-signing with a different certificate (even for a version update) does not break Keychain access as long as the same Developer ID is used. Changing teams = lost history. Document this. |
| **Paste window is unavoidable** | Never advertise "delete after use" as cryptographic. The `burn-after-paste` tooltip must say "best-effort." |
| **macOS 16 clipboard API** | Abstract `ClipboardMonitor` behind a protocol with two concrete implementations. The macOS 16 path requires a one-time permission grant — degrade gracefully (pause capture + prompt) if denied. |
