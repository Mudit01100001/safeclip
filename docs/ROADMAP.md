# SafeClip — Design, Operations & Research Roadmap

_Last updated: 16 June 2026 (Session 6 — opt-in caret-anchored panel). Distribution decided: paid notarized .dmg sold on Mudit's own website (payment gateway); MIT source public for build/audit; Mac App Store deferred until website revenue funds the Apple Developer license._

> ⚠️ **This document stopped being updated after Session 6 (16 June 2026).** Everything since — milestones M3–M5, v0.2.0, OCR, sync, snippets, auto-update, the whole beta release cycle, the app going public/MIT again — lives session-by-session in [../CLAUDE.md](../CLAUDE.md), which is the actual current source of truth. Treat the content below as historical/architectural background, not live status.

---

## Table of Contents

1. [Where we are](#1-where-we-are)
2. [Milestone overview](#2-milestone-overview)
3. [M0 — Foundation scaffold](#3-m0--foundation-scaffold)
4. [M1 — Capture & encrypted store](#4-m1--capture--encrypted-store)
5. [M2 — Floating panel](#5-m2--floating-panel)
6. [M3 — v1.0 ship](#6-m3--v10-ship)
7. [M4 — v1.1 privacy layer](#7-m4--v11-privacy-layer)
8. [M5 — v1.2 advanced features](#8-m5--v12-advanced-features)
9. [Post-v1 horizon](#9-post-v1-horizon)
10. [Technical research log](#10-technical-research-log)
11. [Open decisions tracker](#11-open-decisions-tracker)
12. [Closed decisions (do not re-litigate)](#12-closed-decisions-do-not-re-litigate)
13. [Risk register](#13-risk-register)
14. [Competitive gap analysis](#14-competitive-gap-analysis)

---

## 1. Where we are — **BUILT (10 June 2026)**

| Item | Status |
|------|--------|
| Product spec (PRD.md) | Complete |
| Architecture design (docs/DESIGN.md) | Complete (see "implementation deltas" notes) |
| Terms of Use (TERMS.md) | Complete — username filled, paths corrected |
| Xcode project + all M0–M5 source | ✅ **Built** — zero warnings, Swift 6 strict concurrency |
| Core test suite | ✅ 43 tests passing (`SafeClipCore`) |
| Live security smoke test | ✅ encrypted-on-disk, keychain key, dedup, relaunch persistence |
| Git repo + GitHub remote | ✅ [Mudit01100001/safeclip](https://github.com/Mudit01100001/safeclip) |
| CI | ✅ `.github/workflows/ci.yml` — tests + zero-warning gate |
| Notarized release | ✅ **0.2.2 shipped 18 Jul AND LIVE** — `SafeClip-0.2.2.dmg` (build 4), notarization Accepted + stapled + Sparkle-signed, served from the beta site (`safeclip-web-git-beta-…vercel.app/downloads/`), first real appcast `<item>` published, Ed25519 signature verified against the live feed. Caveat: the earlier 0.2.1's `SUFeedURL` pointed at the unregistered `safeclip.app`, so 0.2.1 installs can never self-update (only affected the owner's machine; replaced manually). |
| Interactive UI QA | ⏳ needs a human at the keyboard |

**Milestone status:** M0 ✅ · M1 ✅ · M2 ✅ (code; interactive QA pending) · M3 ✅ except notarization · M4 ✅ (screen-record detection is heuristic — see R12) · M5 ✅ · **v0.2.0 ✅** images + file copies + Liquid Glass (R13) · **Session 5 ✅** screen-region OCR (⌥C) + shortcut remap (⌥V) + classifier fix (R15), 43 tests, OCR live-verified on macOS 26.5 · **Session 6 ✅** opt-in caret-anchored panel + callout arrow (R16), zero-warning build, 43 tests (interactive QA pending)

**Next actions:** interactive QA of the panel and onboarding; Developer ID + first notarized release; stand up the website + payment gateway; product call (name trademark check, price point).

---

## 2. Milestone overview

| Milestone | Name | Core deliverable | Target |
|-----------|------|-----------------|--------|
| **M0** | Foundation | Clean Xcode build, menu-bar icon visible | Start of build |
| **M1** | Capture + Store | Encrypted clipboard history persists | Weeks 1–2 |
| **M2** | Floating Panel | Panel opens at cursor, paste works | Weeks 3–4 |
| **M3** | v1.0 Ship | Onboarding, settings, notarized .dmg | Weeks 5–6 (aim: fall 2026 near macOS 16 GA) |
| **M4** | v1.1 Privacy | Burn-after-paste, screen-record hide, auto-expiry | Post-ship |
| **M5** | v1.2 Advanced | ClickFix detection, pattern detection, pinning | Post-ship |

**Strategic timing note:** macOS 16 will introduce a "Paste from Other Apps" permission prompt that changes clipboard capture. SafeClip is designed for it. Aligning M3 with macOS 16 GA (expected fall 2026) gives a strong launch narrative: "built for the new macOS clipboard privacy model."

---

## 3. M0 — Foundation scaffold

**Exit criteria:** `⌘B` in Xcode produces zero warnings. The app launches and shows a menu-bar icon. The menu has the correct structure. Nothing crashes.

### Tasks

#### 3.1 Repo setup
- [ ] `git init` in `/Users/mudit/Developer/SafeClip`
- [ ] Create GitHub repo: `safeclip` (public, MIT)
- [ ] Replace `YOUR_USERNAME` in `TERMS.md` (2 occurrences)
- [ ] Push initial planning files as first commit
- [ ] Add `.gitignore` for Xcode (`.xcuserdata`, `DerivedData`, `*.xcuserdatad`)
- [ ] Add `SECURITY.md` stub (private advisory process via GitHub Security Advisories)

#### 3.2 Xcode project
- [ ] Create new project: macOS App, Swift, SwiftUI, bundle ID `com.yourdomain.safeclip`
- [ ] Set minimum deployment: macOS 14.0
- [ ] Set Swift version: 6 (strict concurrency)
- [ ] Set `LSUIElement = YES` in `Info.plist` (removes Dock icon and app menu bar)
- [ ] Set app category: `NSApplicationCategoryUtilities`
- [ ] Remove default `ContentView.swift` (we manage all UI imperatively)

#### 3.3 Entitlements (non-sandboxed, notarization-ready)
File: `SafeClip.entitlements`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Hardened Runtime required for notarization -->
    <key>com.apple.security.cs.allow-jit</key>        <false/>
    <key>com.apple.security.cs.disable-library-validation</key> <false/>
    <!-- Keychain: no extra entitlement needed; all apps can use Keychain -->
    <!-- No sandbox: intentional for menu-bar utility off-MAS -->
</dict>
</plist>
```

**No `com.apple.security.app-sandbox`** — decided. This is the simplest path for a .dmg distributed outside the App Store. Hardened Runtime (`com.apple.security.cs.hardened-runtime`) is enabled separately in Xcode's Signing & Capabilities and is required for notarization regardless of sandbox stance.

#### 3.4 SPM dependencies
Add via Xcode → File → Add Package Dependencies:
- `https://github.com/groue/GRDB.swift` — pin to current stable (v7.x)
- `https://github.com/sindresorhus/KeyboardShortcuts` — pin to current stable (v2.x)

Both are MIT-licensed. Both are auditable. Neither has transitive dependencies of concern.

#### 3.5 App shell
- [ ] `SafeClipApp.swift` — `@main`, `@NSApplicationDelegateAdaptor`
- [ ] `AppDelegate.swift` — `applicationDidFinishLaunching`, empty impl except menu bar setup
- [ ] `MenuBarController.swift` — `NSStatusItem` with a template image, `NSMenu` with correct structure (see DESIGN.md §3)
- [ ] Build passes clean, app launches, icon visible in menu bar, menu opens

#### 3.6 Code quality baseline
- [ ] Enable all Swift strict concurrency warnings (`SWIFT_STRICT_CONCURRENCY = complete`)
- [ ] Zero warnings policy from day one — CI/CD gate
- [ ] SwiftLint config (optional but recommended): enforce consistent style

---

## 4. M1 — Capture & encrypted store

**Exit criteria:** Copy any text. Quit and relaunch the app. The clipboard history persists. `strings ~/Library/Application\ Support/SafeClip/history.db` shows no recognisable clipboard content.

### Tasks

#### 4.1 Keychain key management
- [ ] `KeychainManager.swift`
  - `ensureKey() -> SymmetricKey` — generate on first launch, load on subsequent
  - `kSecAttrAccessControl` bound to `kSecAccessControlUserPresence` or code-signature lock
  - Error path: if key unreadable, surface `KeychainError.unreadable` → `AppState` shows alert
- [ ] Unit test: key survives app restart; wrong-bundle cannot read it

#### 4.2 Encryption service
- [ ] `EncryptionService.swift`
  - `encrypt(_ plaintext: Data, key: SymmetricKey) throws -> (ciphertext: Data, nonce: Data)`
  - `decrypt(_ ciphertext: Data, nonce: Data, key: SymmetricKey) throws -> Data`
  - Uses `CryptoKit.AES.GCM` with `.bits256`
  - Per-item nonce: `AES.GCM.Nonce()` (12 bytes, cryptographically random each time)
- [ ] Unit test: round-trip equality; wrong key throws; tampered ciphertext throws

#### 4.3 Data model
- [ ] `ClipItem.swift` — value type
  ```swift
  struct ClipItem: Identifiable {
      let id: UUID
      var plainText: String?          // nil if not yet decrypted
      var richData: Data?             // nil if not stored or not decrypted
      let richType: UTType?
      let charCount: Int              // stored unencrypted for display
      let sourceBundle: String?
      var isPinned: Bool
      var isBurn: Bool
      var isFlagged: Bool
      var flagReason: FlagReason?
      let createdAt: Date
      var lastUsedAt: Date?
  }
  ```
- [ ] `FlagReason.swift` — enum: `apiKey`, `card`, `privateKey`, `clickfix`

#### 4.4 History store (GRDB)
- [ ] `HistoryStore.swift`
  - Database file: `~/Library/Application Support/SafeClip/history.db`
  - Schema migration using GRDB's `DatabaseMigrator`
  - `insert(_ item: ClipItem)` — encrypt, dedup by SHA-256 hash
  - `fetchAll() -> [ClipItem]` — decrypt all, sort by `last_used_at DESC`
  - `delete(id: UUID)`
  - `deleteAll()`
  - `sweepExpired(olderThan: Date)` — honours pinned flag
- [ ] Integration test: insert 5 items, reopen DB, fetch back, verify content equality

#### 4.5 Clipboard monitor
- [ ] `ClipboardMonitor.swift` — protocol + two concrete implementations:
  ```swift
  protocol ClipboardMonitoring {
      func start()
      func stop()
  }
  // LegacyClipboardMonitor: changeCount polling, Timer-based, 200ms interval
  // ModernClipboardMonitor: macOS 16+ detect-before-read API
  ```
- [ ] Factory: `ClipboardMonitor.make() -> ClipboardMonitoring` — `#available(macOS 16, *)`
- [ ] On change detected: read `NSPasteboard.general`, extract plain string + best rich type
- [ ] Write to `HistoryStore` on a background actor
- [ ] Update `AppState.clips` on `@MainActor`
- [ ] Honour `AppState.captureEnabled` (pause if false)
- [ ] Honour exclusion list (skip if `sourceBundle` in exclusion set)

#### 4.6 Security smoke test
```bash
# After M1 these must pass:
strings ~/Library/Application\ Support/SafeClip/history.db  # no clipboard text
security find-generic-password -s SafeClip                   # key exists, ACL-locked
```

---

## 5. M2 — Floating panel

**Exit criteria:** Global shortcut `⌥V` (Session-5 default; was `⌃⇧V`) opens the panel within 100ms at the cursor. User can search, select with arrows, and press Return to paste plain text into any app without focus being stolen. Panel closes on Escape.

### Tasks

#### 5.1 Panel controller
- [ ] `FloatingPanelController.swift`
  - Pre-create `NSPanel` at app startup (hidden); show on shortcut — no allocation latency
  - `show()` — position at cursor, `orderFront(nil)`, enable local key monitor
  - `hide()` — `orderOut(nil)`, disable local key monitor
  - Cursor positioning: `NSEvent.mouseLocation`, clamp to `NSScreen.screens` visible frames
  - Multi-monitor: find correct screen by checking which screen contains mouse location

#### 5.2 Panel SwiftUI views
- [ ] `ClipboardPanelView.swift` — root view, binds to `AppState`
- [ ] `ClipListView.swift` — `List` or `ScrollView` + `LazyVStack`; arrow-key selection via `@FocusState`
- [ ] `ClipRowView.swift` — shows first 80 chars of plain text, `charCount`, source app icon, flag badge
- [ ] `HintBarView.swift` — static row: "↩ paste  ⌥↩ keep format  ⎋ close"
- [ ] Empty state view: "No clipboard history yet."

#### 5.3 Keyboard handling
- [ ] Local `NSEvent` monitor while panel is visible: intercept `↑`, `↓`, `Return`, `⌥Return`, `Escape`, `⌘Delete`
- [ ] `Return` → paste plain text → close panel
- [ ] `⌥Return` → paste rich data (fallback to plain if no rich stored) → close panel
- [ ] `Escape` → close panel, no paste
- [ ] `⌘Delete` → delete selected item, stay open
- [ ] Typing any other character → focus `SearchField` and append character

#### 5.4 Paste mechanics
- [ ] Write to `NSPasteboard.general` — plain: `setString(_:forType: .string)`, rich: `setData(_:forType:)` with stored UTI
- [ ] After paste: close panel, update `ClipItem.lastUsedAt`
- [ ] After paste if `isBurn`: `HistoryStore.delete(id:)`

#### 5.5 Search
- [ ] `SearchField` is focused on panel open (`@FocusState`)
- [ ] Filter `AppState.clips` by case-insensitive substring of decrypted plain text
- [ ] For large histories (>200): lazy decrypt only visible rows
- [ ] Performance target: <16ms to filter 1,000 items (pre-decrypted in memory index)

#### 5.6 Right-click context menu per row
- [ ] SwiftUI `.contextMenu { }` on `ClipRowView`
- [ ] Actions: Pin / Unpin · Burn after paste (toggle) · Copy again (puts back on pasteboard) · Delete

#### 5.7 Global shortcut registration
- [ ] `KeyboardShortcuts.onKeyUp(for: .showPanel)` — fires on main thread
- [ ] Default binding: `⌥V` (Session-5 default; was `⌃⇧V`) — stored in `UserDefaults` via `KeyboardShortcuts`
- [ ] Re-bindable in Settings → General tab

---

## 6. M3 — v1.0 ship

**Exit criteria:** Onboarding completes. All settings persist. App auto-launches at login. Notarized .dmg downloadable from GitHub Releases. Zero launch permissions required (macOS 16 grants capture permission on first run via one prompt).

### Tasks

#### 6.1 First-launch onboarding (3 screens)
- [ ] `OnboardingWindowController.swift` — shown if `UserDefaults.hasAcceptedTerms == false`
- Screen 1: Welcome + Terms summary. "I understand" checkbox + link to full TERMS.md. "Continue" button disabled until checked.
- Screen 2: Set shortcut. `KeyboardShortcuts.Recorder` pre-loaded with default `⌥V` (was `⌃⇧V`). Brief explanation of the panel appearing at cursor.
- Screen 3: Privacy posture. Summary of encryption, local-only, paste-window caveat. Toggle: "Hide history while screen recording" (default on). Note: "Source app exclusions off by default — add apps in Settings if needed."
- [ ] On "Finish": set `UserDefaults.hasAcceptedTerms = true`, record version + timestamp
- [ ] Skippable via "Skip" button (records skip, does not require consent checkbox — user can re-read terms in Settings → About)

#### 6.2 Settings window (full implementation)
See DESIGN.md §5 for tab-by-tab spec. Implement all General and Privacy tabs. Advanced tab: implement master pattern-detection toggle and sub-toggles (even if detection logic comes in M5 — the settings UI and persistence should be in place).

- [ ] `SettingsWindowController.swift`
- [ ] `SettingsView.swift` + all tab subviews
- [ ] `Settings.swift` model (UserDefaults-backed, Codable)
- [ ] All settings changes take effect immediately (no Apply button)
- [ ] Window remembers last position (`setFrameAutosaveName`)

#### 6.3 Login item
- [ ] `SMAppService.mainApp.register()` on first launch (default: on)
- [ ] Settings toggle: "Launch at login" calls `register()` / `unregister()` as appropriate
- [ ] Handle `SMAppService.Status.requiresApproval` — guide user to System Settings → Login Items

#### 6.4 Auto-expiry
- [ ] Daily sweep: `NSBackgroundActivityScheduler` with 24-hour interval
- [ ] `HistoryStore.sweepExpired(olderThan:)` — respects `isBurn` already handled; respects `isPinned` (exempt)
- [ ] Expiry window: 1 / 7 / 30 / Never (default: 7 days)

#### 6.5 Clear all
- [ ] Menu bar "Clear All History…" and Settings → Advanced both call `HistoryStore.deleteAll()`
- [ ] Confirmation: `NSAlert` with "Clear" (destructive) / "Cancel"
- [ ] After clear: `AppState.clips = []`

#### 6.6 Notarization & distribution
- [ ] Codesign with Developer ID Application certificate
- [ ] Enable Hardened Runtime in Xcode Signing & Capabilities
- [ ] `xcrun notarytool submit` → wait for approval → `xcrun stapler staple`
- [ ] Create `.dmg` with `create-dmg` or `hdiutil`; staple to the .dmg as well
- [ ] GitHub Release with signed .dmg + SHA-256 checksum in release notes
- [ ] README.md (separate from planning docs): pitch, install instructions, compile-from-source path, link to TERMS.md

#### 6.7 macOS 16 pasteboard permission
- [ ] Detect when running on macOS 16+ and capture permission was denied
- [ ] Degrade gracefully: pause capture, show `NSAlert` explaining the app needs the permission to function, link to System Settings
- [ ] Do not crash or silently fail

---

## 7. M4 — v1.1 privacy layer

**Exit criteria:** F7 (burn-after-paste), F8 (screen-record privacy), F9 (auto-expiry), F10 (source-app filter) all pass their acceptance criteria from PRD §6.

### Tasks

#### 7.1 Burn-after-paste (F7)
- [ ] Per-item `isBurn` flag, set via right-click context menu in the panel
- [ ] After paste: if `isBurn == true`, `HistoryStore.delete(id:)` immediately
- [ ] Tooltip on the burn-flagged icon in the row: "Deleted after one paste. Note: content is briefly visible to other apps during paste (see Terms)."
- [ ] Burns DO NOT prevent the item from being stored initially — burn is a delete-after-paste instruction, not a capture filter

#### 7.2 Screen recording privacy (F8)
- [ ] `ScreenRecordWatcher.swift` — detects active screen recording / sharing
  - Method 1 (macOS 14–15): check `CGDisplayStreamCreate` or `NSScreen.screensHaveSeparateSpaces` heuristic; poll every 2 seconds
  - Method 2 (macOS 15+): `SCShareableContentInfo` — preferred; direct API
  - Sets `AppState.isRecording: Bool`
- [ ] `ClipListView`: when `isRecording == true`, replace list content with a blurred placeholder
  - Placeholder text: "History hidden while screen recording"
  - Panel can still be opened and closed — only content is hidden
- [ ] Menu bar icon: show recording dot when `isRecording == true`
- [ ] Restore to normal within 1 second of recording stopping

#### 7.3 Source-app exclusion list (F10)
- [ ] `AppState.settings.exclusionList: [String]` — bundle IDs
- [ ] `ClipboardMonitor` checks `frontmostApp.bundleIdentifier` against list before storing
- [ ] Settings → Privacy: list view of excluded apps with app names + icons; Add/Remove buttons
- [ ] "Add App…" button: `NSOpenPanel` → read `CFBundleIdentifier` from selected `.app` bundle
- [ ] Pre-populate with nothing (empty default — opt-in)

---

## 8. M5 — v1.2 advanced features

**Exit criteria:** F11 (ClickFix detection), F13 (pattern detection), F12 (pinning), F14 (full keyboard nav) all pass acceptance criteria from PRD §6.

### Tasks

#### 8.1 ClickFix / pastejacking detection (F11 — novel feature)
This is SafeClip's most novel feature. No competitor has it.

**Detection heuristic:**
1. Frontmost app at copy time is a browser (`com.apple.Safari`, `com.google.Chrome`, `org.mozilla.firefox`, `com.microsoft.edgemac`, `company.thebrowser.Browser` [Arc])
2. Plain text matches any of:
   - `curl … | (sudo )?(ba)?sh` — piped execution
   - `sudo ` at the start
   - Base64 blob piped to a shell: `echo [A-Za-z0-9+/=]{20,} | base64 -d | sh`
   - `python -c "import base64…"`
   - `powershell` (in case of cross-platform attack)
3. Text was not already in history (new content from a browser = suspicious)

**UX:**
- Flagged item shows a red warning banner: "⚠️ Clipboard overwritten by a website — looks like a shell command. Do not paste in Terminal."
- User can dismiss the warning and paste anyway (not blocked — just warned)
- Warn on paste (when user selects the item and presses Return): "This item was flagged as a possible pastejacking attack. Paste anyway?"

**Notes:** False positive rate is acceptable — this triggers rarely and the cost of a false positive (an extra click) is much lower than the cost of a missed ClickFix attack.

#### 8.2 Pattern detection (F13 — opt-in)
Patterns to detect (all opt-in, default off):

| Pattern | Regex / Algorithm | Display |
|---------|------------------|---------|
| GitHub token | `/^ghp_[A-Za-z0-9]{36}$/` | "GitHub personal access token" |
| OpenAI key | `/^sk-[A-Za-z0-9]{48}$/` | "OpenAI API key" |
| AWS key | `/^AKIA[A-Z0-9]{16}$/` | "AWS access key" |
| Anthropic key | `/^sk-ant-[A-Za-z0-9-_]{90,}$/` | "Anthropic API key" |
| Generic API key | `/^[A-Za-z0-9_-]{32,64}$/` | "Possible API key" (lower confidence) |
| Credit card | Luhn check on 13–19 digit strings | "Possible credit card number" |
| Private key | `-----BEGIN (RSA|EC|OPENSSH) PRIVATE KEY-----` | "Private key" |

All patterns produce a flag icon in the row (not a blocking warning). If "auto-burn flagged items" is on, flagged items automatically get `isBurn = true`.

#### 8.3 Item pinning (F12)
- [ ] `isPinned` flag on `ClipItem`; toggle via right-click → "Pin" / "Unpin"
- [ ] Keyboard shortcut inside panel: `⌘P` to pin/unpin selected item
- [ ] Pinned items sort to the top of the list, below the search field
- [ ] Pinned items are exempt from auto-expiry
- [ ] `📌` icon prefix in the row

#### 8.4 Full keyboard navigation (F14)
- [ ] `↑` / `↓` — move selection; wrap around at ends
- [ ] `Return` — paste plain text
- [ ] `⌥Return` — paste rich text (with formatting)
- [ ] `Escape` — close panel, no paste
- [ ] `⌘Delete` — delete selected item
- [ ] `⌘P` — pin / unpin selected item
- [ ] Any printable character typed when list is focused → append to search field

---

## 9. Post-v1 horizon

These are explicitly **not in scope** for v1 but are worth tracking so future-Mudit doesn't have to re-research them.

| Feature | Notes | Why deferred |
|---------|-------|--------------|
| **iCloud sync (zero-knowledge)** | Client-side encrypt before upload; server stores only ciphertext. Requires CloudKit entitlement + significant complexity. | Adds attack surface, complexity, and trust concerns. No demand signal yet. |
| ~~**Images / files in history**~~ | ~~Store image previews + raw data.~~ | **Shipped in v0.2.0** (see R13). |
| **Browser extension** | Could mark clipboard writes from web forms as "from browser" more reliably than frontmost-app heuristic. | OS-level monitoring sufficient for v1. Extension adds distribution complexity. |
| **AI features** | Summarise items, group by topic, smart search. | Explicitly anti-scope. SafeClip's identity is "does one thing, no bloat." |
| **Windows / Linux** | NSPasteboard, NSPanel, Keychain are macOS-only throughout. | Would require a rewrite from scratch. |
| **Mac App Store** | Would require App Sandbox. Pasteboard access works sandboxed; login items work sandboxed. But SMAppService works; `NSStatusItem` works. Main cost: sandbox entitlement review for `changeCount` polling. | Possible post-v1 if demand warrants it. Non-sandboxed .dmg is the simpler start. |
| **Paid binary on GitHub** | Research supports $8–12 one-time. Decide before M3. | Pricing decision deferred — free at launch is also valid. |
| ~~**Panel anchored to the text caret, not the mouse**~~ (owner request, 15 June 2026) | **Shipped Session 6 (16 June 2026) — see R16.** Default (no permission): the panel now opens *above* the cursor with a callout arrow pointing at it, so it never lands on the field. Opt-in "Open above the text cursor" toggle (Settings → General) anchors it above the blinking caret via read-only Accessibility caret bounds, behind an in-app explanation sheet shown before the macOS prompt; falls back to mouse anchoring when off/not-granted/no-caret. Still never synthesizes ⌘V. | **Done.** Implemented exactly as planned below. Used the literal `"AXTrustedCheckOptionPrompt"` key (SDK-portable) and bounds of a zero-length range at the selection start for the caret rect; sandbox-gated like OCR (`CaretLocator.isSupported`). |
| **Privacy Mode = blur, not blank** + password-dot polish (owner request, 15 June 2026) | Today screen-record/Privacy Mode replaces the whole list with an "eye.slash" placeholder ([App/Panel/ClipboardPanelView.swift:54](../App/Panel/ClipboardPanelView.swift)). Owner wants content **blurred** (frosted, still shaped) rather than fully hidden — apply a `.blur()`/`.redacted()` per row instead of swapping in the placeholder. **Already shipped:** concealed passwords render as `••••••••••••` monospaced ([ClipboardPanelView.swift:168](../App/Panel/ClipboardPanelView.swift)) with a `lock.fill` icon to the left ([ClipboardPanelView.swift:194](../App/Panel/ClipboardPanelView.swift)) — owner's "circular dots + lock icon" request is done; optional polish = truer password-bullet glyph/weight. | Pure presentation change, no permission, no data-model change. Decide whether blur fully obscures (security) or is light (orientation); likely heavy blur on real concealed/flagged rows, lighter on the rest. |
| **Clipboard history in the menu-bar dropdown** (owner request, 15 June 2026) | `MenuBarController` currently has a deliberate header comment — *"clip history lives in the floating panel, never in this menu"* ([App/MenuBar/MenuBarController.swift:6](../App/MenuBar/MenuBarController.swift)) — so the menu only holds Show Panel / Capture toggle / Privacy / Clear / Prefs. Owner now wants the icon to earn its place by listing recent clips (the menu is built lazily in `menuNeedsUpdate`, so adding a "Recent" section of the top-N decrypted items as clickable `NSMenuItem`s that copy-on-click is straightforward). | Soft reversal of a prior design call, not a hard one. Watch: (a) decrypting N rows on every menu open — keep N small (~10) and lean on the existing in-memory cache; (b) **privacy** — respect `historyHidden`/Privacy Mode and concealed/masked rows so secrets aren't surfaced in a plain menu; (c) keep the floating panel as the primary surface, the menu as a quick-glance secondary. |
| **AI/structure-aware OCR formatting** (owner request, 15 June 2026) | ⌥C OCR (`ScreenOCRService` → Vision `VNRecognizeTextRequest`) dumps recognized lines top-to-bottom, left-to-right, losing tables/columns/layout. Owner wants the pasted text to preserve structure. Two tracks: **(1) non-AI, on-device** — Vision already returns per-observation bounding boxes; cluster `VNRecognizedTextObservation` boxes by x-ranges/rows to reconstruct columns and emit Markdown/TSV tables, join wrapped lines, etc. No model, no permission, ships in the box. **(2) optional local-LLM cleanup** — an Advanced setting where users running a local model (Ollama / LM Studio / MLX at a localhost endpoint) point SafeClip at it to reformat OCR output. Strictly opt-in, off by default, localhost-only — must not break the "no telemetry / local-only / no cloud" promise. Potential real USP: contextual, layout-aware OCR that no clipboard manager ships. | Track (1) is in-scope-shaped and the right first step (deterministic, free, private). Track (2) brushes against the "no AI / no bloat" anti-scope (R-AI row above) — gate it behind Advanced settings as a pure local integration, never a default or a cloud call. |

---

## 10. Technical research log

Decisions and their research backing, so future sessions don't re-derive them.

### R1 — No Accessibility permission *for paste* (refined 15 June 2026)
**Decision (unchanged core):** Do not synthesize ⌘V. The user presses it themselves — SafeClip only writes to `NSPasteboard`. This half is permanent.  
**Research:** ClipBook's blog post confirms pasting without Accessibility is viable — write to `NSPasteboard` and let the user's ⌘V do the rest. The Accessibility grant gives keylogger-level power, so we refuse it *for the paste path*.  
**Trade-off accepted:** One extra keypress per paste.

**Refinement (owner, 15 June 2026):** "zero permissions" was over-stated as an absolute. The real pillar is **zero permissions at launch / by default** — the app starts with nothing and works fully with nothing. *Advanced, opt-in* features may request a single permission each, but only when the user enables them and only behind an in-app explanation sheet (what it reads, what it never does) shown *before* the macOS system prompt. This transparency-first prompting is itself the privacy USP (mirrors how Apple frames its own prompts). Concretely this unblocks **caret-anchored panel** (read-only Accessibility for caret bounds — never keystroke synthesis) and keeps **screen-OCR** permission-free via interactive `screencapture`. The competitive-table claim (§14) stays "zero special permissions **at launch**," which remains literally true.
**Accessibility vs. Screen Recording (for the record):** Accessibility = read/control other apps' UI tree + synthesize input (most powerful grant; what keyloggers + automation tools hold). Screen Recording = capture display pixels (what OCR tools need). Caret-anchoring would use only the read-only caret-bounds sliver of Accessibility; ⌥C OCR avoids Screen Recording entirely by shelling out to `screencapture -i`.

### R2 — Non-sandboxed distribution
**Decision:** Hardened Runtime on; App Sandbox off; distribute as notarized .dmg off GitHub Releases.  
**Research:** Most successful indie menu-bar utilities (Alfred, PopClip, Raycast) are non-sandboxed. App Sandbox complicates `changeCount` polling in some edge cases and adds the entitlement review overhead. Non-sandboxed + notarized + open source is sufficient for trust for the target audience.  
**Gatekeeping:** Gatekeeper and notarization still prevent unsigned/unnotarized binaries from running. The privacy story doesn't depend on sandboxing.

### R3 — GRDB over CoreData / raw SQLite
**Decision:** GRDB.swift for the database layer.  
**Research:** CoreData adds significant overhead and its default file formats are not easily auditable. Raw SQLite is fine but error-prone. GRDB gives a clean Swift API, record types, migrations, and is MIT-licensed with a long track record. `strings` testing on a GRDB file shows only the schema, no content — confirming that our encrypt-before-write approach works.

### R4 — KeyboardShortcuts over CGEvent tap
**Decision:** Sindre Sorhus's `KeyboardShortcuts` package.  
**Research:** `CGEvent.tap(at: .cgSessionEventTap)` requires `com.apple.security.temporary-exception.cs.debugger` or Accessibility in some configurations, and is fragile across macOS versions. `KeyboardShortcuts` uses public APIs only, is well-maintained, and handles the `NSUserDefaultsController` binding for the Settings recorder automatically.

### R5 — AES-256-GCM per-item nonce
**Decision:** Encrypt each clip item independently with a unique random nonce.  
**Research:** Using a single IV/nonce for all encryptions under the same key would allow GCM nonce reuse, which is catastrophically insecure (reveals the keystream XOR). Per-item random nonces from `AES.GCM.Nonce()` (12 bytes, CSPRNG) are safe for 2^32 items under the same key without nonce collision risk.

### R6 — SHA-256 for dedup, not plaintext comparison
**Decision:** Store `content_hash = SHA-256(plaintext)` in the clear; deduplicate by this hash.  
**Research:** Comparing plaintext directly for dedup would require decrypting all rows on every insert — O(n) decrypt per copy. SHA-256 is a one-way function, so storing it in the clear doesn't leak the content. Collision resistance of SHA-256 is sufficient for this non-security-critical use (dedup, not authentication).

### R7 — macOS 16 clipboard API abstraction
**Decision:** Abstract `ClipboardMonitor` behind a protocol with two concrete implementations.  
**Research:** macOS 16 (announced WWDC 2025) adds a new "detect-before-read" pasteboard API that checks data types without triggering the "Paste from Other Apps" permission prompt. Without this API, every `NSPasteboard.general.string(forType:)` call on macOS 16 could prompt the user. Using `#available(macOS 16, *)` at runtime and a protocol-based abstraction lets us test both paths and switch cleanly.

### R9 — `Data` slice indices are a real trap (found by test)
**Finding:** `AES.GCM.SealedBox.ciphertext` is a slice of the combined nonce|ct|tag buffer; concatenating slices preserves `startIndex` (it was 12, not 0), so `blob[0]` traps. `EncryptionService.encrypt` now re-wraps in `Data(_:)` to return canonical zero-based data, and the test asserts `startIndex == 0`.

### R10 — Dedup hash upgraded from SHA-256 to keyed HMAC (deviation from PRD §9, improvement)
**Why:** a plain SHA-256 of a *low-entropy* secret (a human password) stored in cleartext is offline-guessable by anyone holding the database file. HMAC-SHA256 keyed via HKDF from the master key keeps exact-match dedup while making the hash useless without the Keychain key. Matters precisely because SafeClip captures passwords by design.

### R11 — Pasteboard privacy on current macOS (the PRD's "macOS 16" model)
**Reality check during the build (macOS 26.5):** the hypothetical detect-before-read API doesn't exist as speced; the real model is `NSPasteboard.accessBehavior` (macOS 15.4+) plus a one-time system prompt on first background read. Implementation: single polling monitor behind the `ClipboardMonitoring` protocol seam; explicit-deny is detected via `accessBehavior` → capture pauses with a menu-bar warning and guidance alert (F5's degrade-gracefully criterion). In the live smoke test on 26.5, capture worked without a prompt for the locally dev-signed build; the deny path stays handled.

### R12 — Screen-record detection is heuristic-only without permissions (limitation accepted)
**Reality:** every robust "is the screen being recorded/shared" API requires holding the Screen Recording permission ourselves — violating the zero-permission pledge. Shipped: detection of the macOS capture UI (`screencaptureui`) + a one-click **manual Privacy Mode** in the menu bar for conferencing scenarios. F8's "Zoom blurs within 1s" acceptance is **not fully met** and is documented in Settings copy and README. Revisit if users prefer granting the permission for full coverage.

### R14 — Dual-channel distribution: one repo, two targets (Session 4)
**Ask was "GitHub variant in a different folder"; shipped shape is two xcodegen targets** sharing 100% of sources — a copied folder would diverge immediately and double every future change. `SafeClip` = GitHub (non-sandboxed, Developer ID, notarized dmg). `SafeClip-MAS` = App Store (App Sandbox + `user-selected.read-write` for the powerbox panels). Verified: both targets build zero-warning; the MAS build boots sandboxed and creates its encrypted store inside its container. Same bundle ID across channels (same app, one installed at a time); histories live in different locations per channel (container vs ~/Library/Application Support). MAS submission blockers: Apple Developer account, Apple Distribution signing, **app icon** (none exists yet). Full channel comparison: docs/DISTRIBUTION.md.

### R13 — v0.2.0: images, file copies, Liquid Glass (owner-revised scope, June 10 2026)
**What changed:** PRD §13's "no images/files in v1" non-goal was revised by owner decision. Schema v2 adds `kind` (`text`/`image`/`file_list`) + encrypted thumbnail columns; migration tested against a frozen v1 database.
**Images:** stored encrypted, PNG-normalized (deterministic dedup; dedup hashes the *payload bytes*, since the "Image W×H" placeholder would collide distinct images), 10 MB cap, 96px encrypted thumbnail for the row preview. Pasting writes an `NSImage` (PNG+TIFF reps for receiver compatibility); the plain/rich modifier is ignored for images.
**Files:** paths stored (newline-joined, encrypted), not contents; pasting writes real file URLs plus the path text for plain-text fields. File-URL detection runs *before* the string check because Finder also puts the file name on the pasteboard as text.
**Known trade-off:** mixed string+image pasteboards prefer the string (right for spreadsheet cells; a browser "Copy Image" that includes a URL string captures the URL instead of the image).
**Metadata in clear (by design):** `kind` and `rich_type` (`public.png`) are cleartext like `char_count` — they reveal *that* a row is an image, never content. Verified live: no PNG magic bytes anywhere in the database file.
**Liquid Glass:** the panel chrome is `NSGlassEffectView` (cornerRadius 18) on macOS 26+, `.regularMaterial` below; onboarding primary buttons use `.glassProminent` with `.borderedProminent` fallback. Settings/menus get the system treatment automatically from the SDK 26 build.

### R15 — Session 5: screen-region OCR, shortcut remap, classifier fix, stale-bundle lesson
**Screen-region OCR (⌥C):** owner reframed "OCR" from background image-indexing (built earlier, removed — it silently updated a hidden field with no UI, so it read as broken) to an explicit *capture action*. `ScreenOCRService` shells out to `/usr/sbin/screencapture -i -x -t png <temp>` (the native crosshair, system-driven so the app needs **no** Screen Recording permission of its own), OCRs the temp file with Vision (`VNRecognizeTextRequest`, on-device), writes the text to `NSPasteboard`, and deletes the image — it is **never** added to history. The recognized text rides the normal monitor into history like any copy. A non-activating menu-bar toast (`NSPanel`, `orderFrontRegardless`) confirms without stealing focus, so the user can ⌘V where they already are. **Sandbox note:** `Process` is forbidden under App Sandbox → self-reports `.unavailable` via `APP_SANDBOX_CONTAINER_ID`; GitHub channel only (fine while MAS is deferred).
**Shortcut remap:** panel ⌃⇧V → **⌥V**, OCR → **⌥C**; both in Settings → General. One-time `shortcutsV2Migrated` flag calls `KeyboardShortcuts.reset(...)` so existing installs adopt the new defaults instead of keeping the stored ⌃⇧V.
**Classifier false-positive fix:** the low-confidence "Possible API key" heuristic flagged any 32–64-char `[A-Za-z0-9_-]` token with a letter+digit — hitting git SHAs, UUIDs, hashes. Tightened to **≥40 chars + mixed upper/lower/digit + Shannon entropy ≥3.2**; lowercase-hex SHAs/UUIDs now pass clean. Added **Reset All Flags** (`HistoryStore.resetAllFlags()`, Settings → Advanced) to un-mask rows mislabeled before the fix. (Pattern detection is still opt-in/off by default, so this only ever bit users who enabled it.)
**Debug login-item default OFF:** a Debug build registering itself via `SMAppService` is what resurrected stale DerivedData bundles. `launchAtLogin` now defaults `false` under `#if DEBUG`, `true` in Release.
**Operational lesson:** `xcodebuild -derivedDataPath build …` had dropped stale `.app` copies in the repo's `build/` dir; Spotlight/launchd then launched the **sandboxed MAS copy** for ⌥C (where `screencapture` is blocked), causing an endless permission/quit-reopen loop. Fix recipe: kill `SafeClip`, `rm -rf build ~/Library/Developer/Xcode/DerivedData/SafeClip-*`, `tccutil reset All com.mudit.safeclip`, clean-build, launch only the DerivedData `Debug/SafeClip.app`.

### R16 — Session 6: caret-anchored panel + callout arrow (the §9 owner request, built)
**Default, no permission (the part that fixes the actual complaint):** `FloatingPanelController` no longer drops the panel below-and-left of the mouse where it could cover the target field. The window is now the rounded body **plus a small callout arrow**; `show()` resolves an anchor, then `layout(for:)` centres the body on it and prefers placing it **above** the anchor (arrow points down at it), flipping below only when there's no room above. So even with zero permissions the panel stays out of the way and visibly points at where it anchored.
**Opt-in caret anchoring (read-only Accessibility):** new `caretAnchoring` setting (default OFF) + "Open above the text cursor" toggle in Settings → General. When on **and** trusted, `CaretLocator.caretRect()` reads `kAXFocusedUIElement` → `kAXSelectedTextRange` → bounds of a **zero-length** range at the selection start (`kAXBoundsForRange`), converts Quartz top-left coords → AppKit bottom-left via the primary-display height, and the panel anchors above the caret. Any failure (off / not granted / field exposes no caret bounds, e.g. some web views) silently falls back to mouse anchoring.
**Transparency-first prompt (R1):** flipping the toggle ON shows an in-app NSAlert explaining *exactly* what's read ("only the on-screen location of the blinking cursor — never keystrokes, never the text in the field, never synthesizes ⌘V") **before** `requestTrust()` triggers the macOS Accessibility prompt. Cancelling leaves it OFF. This is the privacy USP made literal.
**Key portability:** used the literal `"AXTrustedCheckOptionPrompt"` dictionary key instead of the `kAXTrustedCheckOptionPrompt` global, which imports as `Unmanaged<CFString>` on some SDKs (same class of issue as the Sendable-portability fix). Avoids `.takeUnretainedValue()` churn.
**Arrow rendering:** the beak is a tiny SwiftUI `Shape` (`PanelArrow`) filled with `.regularMaterial`, hosted in its own `NSHostingView` sibling to the body inside a transparent container view — not baked into the body, because the macOS-26 `NSGlassEffectView` wraps the whole body as a rounded rect and can't be made triangular. Body sits at the container top (arrow at bottom, pointing down) when above the anchor, or the reverse when below; arrow x is clamped onto the flat edge between the 18-pt corners.
**Sandbox:** AX control of other apps is blocked under the App Sandbox, so `CaretLocator.isSupported` mirrors `ScreenOCRService` (`APP_SANDBOX_CONTAINER_ID`) — GitHub channel only; the MAS build disables the toggle with an explanatory footer. **Still never synthesizes ⌘V** (the permanent half of R1 is untouched). No Info.plist/entitlement change needed (Accessibility has no usage-description key). Both targets build zero-warning; 43 core tests green. Interactive QA (does it actually land above the caret in real apps) pending a human.

**Session-6 QA round (16 June 2026) — three fixes from owner's first hands-on test:**
1. **Caret detection is spotty across apps — root cause is the *source app*, not SafeClip.** `kAXBoundsForRange` only works where the focused app exposes it: native AppKit / WebKit text fields answer (Perplexity, Instagram, Safari inputs → exact caret); Chromium/Electron web views often don't expose per-range bounds, and Electron apps (Claude for Desktop, WhatsApp) may not surface an a11y tree at all without the `AXManualAccessibility` write-trick — which we deliberately *don't* use, to keep the pledge read-only. So those fall back to mouse anchoring (correct by design, just not caret-exact). Mitigation shipped: `CaretLocator` now probes three ranges in order — zero-length caret, the char *after*, the char *before* — recovering some WebKit/contenteditable cases that only answer a non-empty range. The honest limit (Electron ⇒ mouse fallback) is documented, not hidden.
2. **Panel chrome rebuilt as one unified callout.** The Session-6 first cut drew the body (Liquid Glass / material) and the beak as two separate AppKit subviews offset inside a transparent container — which read as a detached triangle + a seam + "two buttons" at the bottom (the body's two rounded bottom corners flanking the gap). Replaced with a single SwiftUI `CalloutShape` (rounded body + beak merged into one `Path`) used as both the `glassEffect(.regular, in:)` (macOS 26+) / `.regularMaterial` background **and** the content clip — body and beak are now one continuous surface, no gap, no material mismatch. `FloatingPanelController` now hosts one `NSHostingView` for the whole window and just updates its `PanelArrowSpec` (edge + x) per show. Dropped `NSGlassEffectView` in favour of SwiftUI `glassEffect` (still Liquid Glass on 26+). *Visual QA still pending a human — built blind.*
3. **"Everything is in password mode on reopen" is not a bug — over-eager `ConcealedType` from source apps.** Live DB (200 rows) showed 52 concealed, **all** from `com.anthropic.claudefordesktop` (43) and `net.whatsapp.WhatsApp` (9) — both tag many clipboard copies with `org.nspasteboard.ConcealedType`, the same flag password managers use, so SafeClip masks them exactly as designed. Fix: masked rows now **reveal on hover** (`ClipRowView.hovering`) — the list stays unreadable at a glance but any row can be checked on demand, without auto-revealing the most-recent item. The existing global "Mask password previews" toggle (Settings → Privacy) and the source-app exclusion list remain the heavier hammers. Open question for owner: should SafeClip stop trusting `ConcealedType` from non-password-manager apps (e.g. a per-source allowlist)?

**Session-6 QA round 2 (16 June 2026) — owner answered the open questions:**
- **Electron caret support — use the `AXManualAccessibility` lever (owner wants it).** `CaretLocator.prewarmFrontmostApp()` sets `AXManualAccessibility = true` on the frontmost app, switching on Chromium/Electron's accessibility tree (Claude, Arc, Wispr Flow, …) so the caret becomes readable; no-op on native apps. This is the **one write** SafeClip makes via AX — it enables *reading* only (no input synthesis, no keystroke/text reads), and the consent sheet + footer now disclose it. Because the tree builds asynchronously, `AppDelegate` also pre-warms on `NSWorkspace.didActivateApplicationNotification` (gated on the `caretAnchoring` setting) so the **first** ⌥V after switching to an Electron app already anchors. (We use `AXManualAccessibility`, *not* `AXEnhancedUserInterface`, which has AppKit side-effects.) The "appears below the caret" report is the same mouse-fallback symptom for web content; this addresses Chromium/Electron — Safari/WebKit web content still leans on the 3-probe fallback.
- **Concealed guardrail (owner: "un-conceal Wispr Flow").** Key insight: Wispr Flow is a dictation tool that **pastes into the focused app**, so SafeClip records the *frontmost* app (Claude/WhatsApp — now 71/9 in the live DB) as the source, not Wispr; the concealed flag rides Wispr's clipboard write. So the guardrail keys on the **recorded source**. New `ignoreConcealedFrom: [String]` setting; `AppState.handleCapture` skips concealment for those sources; `AppState.stopConcealing(source:)` adds the app **and** un-masks existing rows via the new `HistoryStore.unconcealSource(_:)` (clears `flag_reason='concealed'` for that `source_bundle` only — covered by a new test, **44 tests** now). Surfaced two ways: right-click a masked row → "Always Show Copies from [App]", and Settings → Privacy → "Apps not treated as passwords" (add/remove). Real password-manager copies (1Password, etc.) are attributed to the manager, so they stay masked.

**Session-6 QA round 3 (16 June 2026) — "same issues as before"; stopped guessing, instrumented.** Two changes hadn't visibly landed, so this round is diagnose-first:
- **DEBUG diagnostics.** `CaretLocator.caretRect` now logs (DEBUG only, visible in the Xcode console) exactly where it drops out — `NOT trusted` / `no focused element` / `no selected-text-range (role=…)` / `no caret bounds (role=…) — mouse fallback` / `OK … quartz=… appKit=…`. `FloatingPanelController` logs the anchor source + final frame. `ClipboardMonitor` logs each capture's `frontmost` / `source(convention)` / `concealed` / types. This turns the blind loop into data: owner reproduces in Claude and reads back the lines. **Leading hypothesis for "still at cursor / below the caret": a dev rebuild invalidated the Accessibility TCC grant**, so `isTrusted` is false and *everything* falls back to mouse (which is below the real caret). Added an "Open Accessibility Settings…" button + a sharper "grant it to **this build**; rebuilding can reset the grant" caption.
- **Electron support is now an explicit, disclosed toggle.** Split the `AXManualAccessibility` enable out of the caret toggle into `assistChromiumApps` (default ON, nested under "Open above the text cursor"). Disclosed in **TERMS §3a** (new) and the **onboarding** shortcut page. Gated everywhere (caretRect param + the activation pre-warm).
- **Wispr attribution, not a per-app hack.** `ClipboardMonitor` now prefers the `org.nspasteboard.source` convention (the app that *wrote* the content) over the frontmost app, so Wispr Flow can be recognized as the writer regardless of which app is focused. One-time migration (`wisprUnconcealMigrated`) seeds `com.electron.wispr-flow` into `ignoreConcealedFrom`. **Open: whether Wispr actually sets `org.nspasteboard.source` — the new capture log will confirm; if it doesn't, attribution stays frontmost and we need another signal.**

**Session-6 QA round 5 (16 June 2026) — owner's console logs resolved all three open threads.**
- **Geometry: confirmed fixed.** Owner: "opening at the right place in normal apps"; the `SafeClip caret: OK … appKit=(343,562)` / `placeAbove=true frame=…582…` Xcode lines show correct above-anchor placement (incl. a multi-monitor rig: primary 3200×1800, laptop at origin (912,−982) — conversion + placement both correct there).
- **Claude root cause = no `AXBoundsForRange` on Chromium.** Log: `role=AXTextArea` with a selected range but `no caret bounds from AXBoundsForRange`. So `AXManualAccessibility` worked (the tree + focused text area are visible) — Chromium/Blink just doesn't implement the CFRange bounds API; it exposes caret geometry via the **text-marker** API VoiceOver uses. Added `CaretLocator.boundsViaSelectedTextMarker` — `AXSelectedTextMarkerRange` → `AXBoundsForTextMarkerRange` (undocumented but VoiceOver-stable; marker range is an opaque CFTypeRef handed straight back as the param), walking up to 6 ancestors since the markers may live on the AXWebArea not the focused control. Tried after the CFRange probes fail. **Unverified on Electron from here — owner's next `SafeClip caret:` line ("OK via text-marker" vs still failing) confirms.**
- **Wispr is unidentifiable on the clipboard — proven by the capture log.** `SafeClip capture: frontmost=com.anthropic.claudefordesktop source(convention)=(none) concealed=YES types=…ConcealedType,public.utf8-plain-text` — Wispr's dictated insert is **byte-for-byte identical to a password-manager copy** (plain text + ConcealedType, no `org.nspasteboard.source`, no app signature). So nothing can single out "Wispr", and the round-4 convention-attribution + Wispr pre-seed can't work — **removed the dead pre-seed migration.** The deterministic, safe fix is the existing per-source guardrail keyed on the *frontmost* app: un-conceal the apps you **dictate into** (Claude, WhatsApp) via right-click → "Always Show Copies from [App]" / Settings → Privacy. Password managers stay masked because you **copy from** them (they're frontmost then), so they're never in the list. (`org.nspasteboard.source` preference kept — harmless, helps if any app ever declares it.)
- **Fixed a layout-recursion runtime log** ("not legal to call -layoutSubtreeIfNeeded …") by switching the per-show resize to `setFrame(_:display:false)` (panel isn't on screen yet; show() orders it front after).

**Session-6 QA round 4 (16 June 2026) — found the "too low" root cause empirically.** Owner reported the panel appears "too low wherever the cursor or caret is", *including with the mouse anchor (no permission)* — which ruled out trust/Electron and pointed at the shared geometry path. A spawned diagnosis workflow was killed by an account session limit, so this was done with a **standalone Swift harness** replicating `layout(for:)` + `convertFromQuartz` exactly. It proved it: the panel was a **fixed 451 px tall ≈ half the 944 px visible height**, so "fits above" only succeeded for anchors in the bottom ~half; any caret/cursor in the upper half had no room above → fell **below** the anchor = "too low." Not a coordinate/sign bug (the conversion math checks out). **Fix: adaptive height.** `FloatingPanelController.layout(for:)` now measures the room above vs below the anchor, prefers above whenever ≥ `minBodyHeight` (240) fits, sizes the body to the available space (capped at 442, list scrolls), and only drops below when the anchor is genuinely near the screen top. `ClipboardPanelView` was made size-agnostic (fills the window, reserves the beak strip via padding) so the window can be resized per show. Harness re-run confirms above for carets down through the upper-mid of the screen (e.g. cocoaTop 662 → above with a 270 px body). Both targets build zero-warning, 44 tests pass. **"Still wrong on Claude" is the separate Electron/trust matter** — the adaptive fix makes Claude's mouse-fallback open *above* the cursor now, but true caret anchoring there still needs Accessibility granted + Claude's a11y tree responding to `AXManualAccessibility` (the DEBUG `SafeClip caret:` log pins which). Visual QA of the resizing panel still pending a human.

### R17 — Session 13: panel scroll/click root-caused to OS-level input misrouting; hit the permission-free ceiling
**Context:** Sessions 9–12 tried non-activating panels, activating panels, native `NSScrollView`, local+global monitor combos — each round reported "fixed" then the owner found it still broken. Session 13's job was to stop guessing and get a real measurement.

**Method — built a real automated test harness instead of relying on manual QA:** `FloatingPanelController.runSelfTest(iterations:)`, gated behind `SAFECLIP_SELFTEST=<N>` (never baked into the checked-in scheme, since it moves the real cursor and posts real clicks — set via `launchctl setenv SAFECLIP_SELFTEST 10` for a one-off run). Critically, it posts genuine `CGEvent`s through `.cghidEventTap`, not direct method calls — the pre-existing `SCROLLDIAG` self-check called `scrollView.scrollWheel(with:)` directly in-process, which only proves the method *can* be called, and reported success 100% of the time even when real trackpad input failed for the owner. **Lesson for any future diagnostic: exercise the real delivery path or the check will lie.**

**Finding — root cause is certain, not a guess:** instrumenting `forwardScroll` showed scroll failures were 0% an `NSScrollView` problem (`fwd_no_move=0` — once an event reaches us, it always scrolls) and 0% a "lost" event (`missed_seen_nowhere=0`). 100% of failures were real events the window server routed to some *other* destination instead of SafeClip's local `NSEvent` monitor, even while `NSApp.isActive`/`panel.isKeyWindow` read `true`. This is genuine OS-level misrouting of input away from an `.accessory` (`LSUIElement`) app's window, not a bug in our SwiftUI/AppKit code.

**Two fixes shipped that reduce the symptom but don't eliminate it:**
1. `globalScrollMonitor` — a global `NSEvent` monitor for `.scrollWheel` catches events the local monitor misses and manually forwards them. Verified: scroll went 3/10 → 10/10 in the harness, twice. **But global monitors can only observe, never consume/block an event (OS restriction, not fixable in our code)** — so whatever the OS actually routed the event to also processes it. Owner confirmed live: the window behind the panel (e.g. Claude Desktop) still scrolls ~25% of the time.
2. `outsideClickMonitor` (the "click outside closes panel" feature, added the same session) was found to be *catching the same misrouted clicks* and closing the panel before the row's tap could fire — `click_self_closed=10/10` in the harness. Fixed to check `panel.frame.contains(...)` first and replay in-frame clicks via `panel.sendEvent(event)` instead of hiding. Unlike the scroll fix, this one was **not** cleanly re-verified — the owner's live re-test after the fix still saw the panel close on some off-target clicks.

**Tried and reverted:** temporarily switching `NSApp.setActivationPolicy(.regular)` while the panel is shown (theory: `.accessory` apps aren't a reliable input-routing target even when "active"). Did not fix the leak, and introduced new instability — while testing it, Xcode itself rebuilt/relaunched SafeClip repeatedly with nobody clicking Run. Root cause of that: while `.regular` was active, the harness's own synthetic `CGEvent` clicks (being real system-level events) were themselves misrouted to whatever was genuinely frontmost — Xcode, during dev testing — accidentally clicking its Run button. Reverted fully; do not retry without treating this as a real risk.

**The architectural ceiling, and the decision it forces (tracked as D7):** `NSEvent` local/global monitors cannot both catch *and* block a misrouted event — that combination requires a `CGEventTap` created in `.defaultTap` mode (not `.listenOnly`), which requires Accessibility/Input Monitoring permission. R1 already establishes the precedent of opt-in Accessibility grants for advanced features (caret-anchoring, snippet auto-expand) behind an in-app consent sheet — but scroll and click are *core* panel behavior, not opt-in, so gating them behind Accessibility would mean either prompting by default (a real change to the "zero permissions at launch" pillar) or leaving scroll/click semi-broken for anyone who declines. Not decided this session.

### R8 — Screen recording detection method
**Decision:** Use `SCShareableContentInfo` on macOS 15+ (preferred); fall back to `CGDisplayStream` heuristic on macOS 14.  
**Research:** There is no public "is someone screen recording right now" API as a simple boolean. The closest available on macOS 15+ is checking `SCShareableContentInfo` for active sharing sessions. The `CGDisplayStream` approach (checking if any stream is active) can produce false positives for apps using Metal display streaming internally. Accept this limitation for v1; document it.

---

## 11. Open decisions tracker

These require a decision before the tagged milestone.

| # | Decision | Needed by | Options | Notes |
|---|----------|-----------|---------|-------|
| ~~D1~~ | ~~GitHub username / repo URL~~ | — | — | **Resolved:** `github.com/Mudit01100001/safeclip`; TERMS updated |
| ~~D2~~ | ~~Bundle ID~~ | — | — | **Resolved:** `com.mudit.safeclip`, signed with team `YHK4D97KC4` |
| D3 | **App name trademark check** | release | "SafeClip" (working title) | Check macOS App Store + USPTO before committing |
| ~~D4~~ | ~~Paid vs. free binary~~ | — | — | **Resolved (Session 5): paid `.dmg` on Mudit's website via a payment gateway; MIT source stays public.** Open: price + which gateway |
| D5 | **Launch timing** | release | Align with macOS 16 GA (fall 2026) | Aim for maximum narrative tailwind |
| ~~D6~~ | ~~**Developer ID certificate**~~ | — | — | **Resolved 15 Jul:** cert created, notarytool credentials stored, first real notarized `.dmg` (0.2.1) produced successfully. Two release-script bugs found and fixed along the way (`build`→`archive`/`exportArchive` to drop the get-task-allow entitlement; explicit re-sign pass for Sparkle's nested helper binaries). |
| D7 | **Accessibility permission for core panel scroll/click reliability** | next scroll/click fix attempt | (a) Request Accessibility by default to enable a `CGEventTap` that can consume misrouted input; (b) accept scroll (~25% leak to the app behind) and click (can still close panel without pasting) as "mostly works" indefinitely | Session 13: root-caused both to genuine OS-level input misrouting to the `.accessory` window; `NSEvent` global monitors can observe but never consume, so this is the architectural ceiling, not a bug to keep patching. See R17. |

---

## 12. Closed decisions (do not re-litigate)

| Decision | What was decided | Reason |
|----------|-----------------|--------|
| Sandbox stance | ~~Non-sandboxed, notarized .dmg, off-MAS~~ **Revised Session 4: dual-channel.** GitHub target stays non-sandboxed; a second `SafeClip-MAS` target (App Sandbox) shares all sources for App Store distribution. See R14 + docs/DISTRIBUTION.md. | Owner wants both channels; one repo + two targets avoids codebase divergence. |
| Accessibility permission | Never request it | Would allow keystroke injection = same power as a keylogger. Core design pillar. |
| Synthesized ⌘V | No — user presses it | Requires Accessibility. One extra keypress accepted. |
| "Burn after paste" scope | Per-item opt-in, NOT global default | History persistence is the whole point of a clipboard manager |
| Default paste mode | Plain text (strip formatting) | Rich text stored and available via ⌥Return |
| Source-app filter default | OFF (empty exclusion list) | Mudit wants passwords captured; users who don't can add 1Password themselves |
| Pattern detection default | OFF | Reduces false positives; users opt in |
| Cloud sync / AI / browser extension | Not in v1 | Scope creep; trust concerns; complexity |
| Open source license | MIT (source-available) | HN users won't trust a closed-source clipboard manager; source stays public for audit/build even though the binary is paid |
| Distribution | ~~GitHub Releases (.dmg) + source~~ **Revised Session 5: paid notarized `.dmg` on Mudit's own website (payment gateway); MIT source public for build/audit; MAS deferred until website revenue funds the dev license.** | Bootstrap funding for the Apple Developer license; no telemetry possible; source remains the trust anchor |
| Database | GRDB.swift (SQLite) | Clean Swift API, auditable, MIT |
| Global hotkey library | KeyboardShortcuts (Sindre Sorhus) | Public APIs only, well-maintained, MIT |

---

## 13. Risk register

| Risk | Likelihood | Impact | Mitigation | Owner |
|------|-----------|--------|------------|-------|
| macOS 16 pasteboard API breaks capture | Med | High | Abstract behind protocol; test on 15.4 preview now; `#available` gate | M1 |
| Nonce reuse in AES-GCM | Low | Critical | Per-item `AES.GCM.Nonce()` (CSPRNG); unit test catches wrong-key | M1 |
| GCM nonce storage corruption | Low | High | Nonce stored as separate BLOB column; GRDB write is atomic | M1 |
| Panel steals focus accidentally | Med | Med | `.nonactivatingPanel` style mask; test with Xcode + text editor side by side | M2 |
| Panel appears off-screen (multi-monitor / notch) | Med | Med | Clamp to `visibleFrame` of correct `NSScreen` | M2 |
| Keychain ACL broken after re-sign | Low | High | Same Developer ID across versions preserves ACL; document in README | M3 |
| notarization rejected | Med | Med | Follow Hardened Runtime checklist; no dynamic code loading | M3 |
| Screen recording detection false positives | Med | Low | Document limitation; blur is non-destructive (data not deleted, just hidden) | M4 |
| ClickFix regex false positives | Med | Low | Warn, don't block; user can dismiss and paste anyway | M5 |
| Single-maintainer perception | Med | Low | Open source = forkable; document architecture thoroughly (this file) | Ongoing |

---

## 14. Competitive gap analysis

This table is why the project exists. No competitor covers all columns. SafeClip's v1 covers the first five; v1.2 adds the last two.

| Feature | Maccy | Paste | CleanClip | CopyClip 2 | Raycast | **SafeClip** |
|---------|:-----:|:-----:|:---------:|:----------:|:-------:|:------------:|
| Cursor-anchored floating panel | ❌ | ❌ | ✅ (`⌘;`) | ❌ | ❌ | ✅ |
| Plain-text paste as default | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ |
| Encrypted history store | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Screen-share privacy | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (v1.1) |
| ClickFix / pastejacking detection | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (v1.2) |
| Open source | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Zero special permissions at launch (advanced features opt in per-permission) | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| One-time pricing (no subscription) | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ (planned) |

**Uncontested gaps SafeClip fills:** encrypted store + screen-share privacy + ClickFix detection. None of the above ship any of these three.

**Closest single competitor by feature overlap:** CleanClip (cursor panel, one-time price) — but no encryption, no open source, no screen-share privacy.
