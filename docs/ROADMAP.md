# SafeClip — Design, Operations & Research Roadmap

_Last updated: June 2026. Distribution decided: non-sandboxed, notarized .dmg off GitHub Releases (no Mac App Store)._

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

## 1. Where we are

| Item | Status |
|------|--------|
| Product spec (PRD.md) | Complete |
| Architecture design (docs/DESIGN.md) | Complete |
| Terms of Use (TERMS.md) | Complete (needs YOUR_USERNAME replaced) |
| License (MIT) | Complete |
| Xcode project | **Not started** |
| Any source code | **None** |
| Git repo | **Not initialized** |
| GitHub remote | **Not created** |
| Distribution decision | **Decided: non-sandboxed .dmg, off-MAS** |

**Next action:** initialize git, create GitHub repo, scaffold Xcode project (Milestone M0).

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

**Exit criteria:** Global shortcut `⌃⇧V` opens the panel within 100ms at the cursor. User can search, select with arrows, and press Return to paste plain text into any app without focus being stolen. Panel closes on Escape.

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
- [ ] Default binding: `⌃⇧V` — stored in `UserDefaults` via `KeyboardShortcuts`
- [ ] Re-bindable in Settings → General tab

---

## 6. M3 — v1.0 ship

**Exit criteria:** Onboarding completes. All settings persist. App auto-launches at login. Notarized .dmg downloadable from GitHub Releases. Zero launch permissions required (macOS 16 grants capture permission on first run via one prompt).

### Tasks

#### 6.1 First-launch onboarding (3 screens)
- [ ] `OnboardingWindowController.swift` — shown if `UserDefaults.hasAcceptedTerms == false`
- Screen 1: Welcome + Terms summary. "I understand" checkbox + link to full TERMS.md. "Continue" button disabled until checked.
- Screen 2: Set shortcut. `KeyboardShortcuts.Recorder` pre-loaded with default `⌃⇧V`. Brief explanation of the panel appearing at cursor.
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
| **Images / files in history** | Store image previews + raw data. UI needs thumbnail grid. | Text-only in v1 keeps scope tiny. |
| **Browser extension** | Could mark clipboard writes from web forms as "from browser" more reliably than frontmost-app heuristic. | OS-level monitoring sufficient for v1. Extension adds distribution complexity. |
| **AI features** | Summarise items, group by topic, smart search. | Explicitly anti-scope. SafeClip's identity is "does one thing, no bloat." |
| **Windows / Linux** | NSPasteboard, NSPanel, Keychain are macOS-only throughout. | Would require a rewrite from scratch. |
| **Mac App Store** | Would require App Sandbox. Pasteboard access works sandboxed; login items work sandboxed. But SMAppService works; `NSStatusItem` works. Main cost: sandbox entitlement review for `changeCount` polling. | Possible post-v1 if demand warrants it. Non-sandboxed .dmg is the simpler start. |
| **Paid binary on GitHub** | Research supports $8–12 one-time. Decide before M3. | Pricing decision deferred — free at launch is also valid. |

---

## 10. Technical research log

Decisions and their research backing, so future sessions don't re-derive them.

### R1 — No Accessibility permission
**Decision:** Do not synthesize ⌘V. User presses it themselves.  
**Research:** ClipBook's blog post confirms pasting without Accessibility is viable — write to `NSPasteboard` and let the user's ⌘V do the rest. Accessibility grant gives the same power level as a keylogger; it would undermine the privacy story. Users notice the "Accessibility" permission request in Security settings and distrust apps that have it.  
**Trade-off accepted:** One extra keypress per paste.

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

### R8 — Screen recording detection method
**Decision:** Use `SCShareableContentInfo` on macOS 15+ (preferred); fall back to `CGDisplayStream` heuristic on macOS 14.  
**Research:** There is no public "is someone screen recording right now" API as a simple boolean. The closest available on macOS 15+ is checking `SCShareableContentInfo` for active sharing sessions. The `CGDisplayStream` approach (checking if any stream is active) can produce false positives for apps using Metal display streaming internally. Accept this limitation for v1; document it.

---

## 11. Open decisions tracker

These require a decision before the tagged milestone.

| # | Decision | Needed by | Options | Notes |
|---|----------|-----------|---------|-------|
| D1 | **GitHub username / repo URL** | M0 | — | Replace `YOUR_USERNAME` in TERMS.md ×2 |
| D2 | **Bundle ID** | M0 | `com.mudit.safeclip` or `com.yourname.safeclip` | Used in code signature; hard to change later |
| D3 | **App name trademark check** | M3 | "SafeClip" (working title) | Check macOS App Store + USPTO before committing |
| D4 | **Paid vs. free binary** | M3 | $8–12 one-time on GitHub Releases / free | Research favours $8–12; free is also fine for traction |
| D5 | **macOS 16 launch timing** | M3 | Align with macOS 16 GA (fall 2026) | Aim for maximum narrative tailwind |
| D6 | **Developer ID certificate** | M3 | Personal ($99/yr Apple Developer Program) | Required for notarization |

---

## 12. Closed decisions (do not re-litigate)

| Decision | What was decided | Reason |
|----------|-----------------|--------|
| Sandbox stance | Non-sandboxed, notarized .dmg, off-MAS | Simpler; no MAS target. Hardened Runtime on for notarization. |
| Accessibility permission | Never request it | Would allow keystroke injection = same power as a keylogger. Core design pillar. |
| Synthesized ⌘V | No — user presses it | Requires Accessibility. One extra keypress accepted. |
| "Burn after paste" scope | Per-item opt-in, NOT global default | History persistence is the whole point of a clipboard manager |
| Default paste mode | Plain text (strip formatting) | Rich text stored and available via ⌥Return |
| Source-app filter default | OFF (empty exclusion list) | Mudit wants passwords captured; users who don't can add 1Password themselves |
| Pattern detection default | OFF | Reduces false positives; users opt in |
| Cloud sync / AI / browser extension | Not in v1 | Scope creep; trust concerns; complexity |
| Open source license | MIT | HN users won't trust a closed-source clipboard manager |
| Distribution | GitHub Releases (.dmg) + source | No telemetry possible; source is the trust anchor |
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
| Zero special permissions at launch | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| One-time pricing (no subscription) | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ (planned) |

**Uncontested gaps SafeClip fills:** encrypted store + screen-share privacy + ClickFix detection. None of the above ship any of these three.

**Closest single competitor by feature overlap:** CleanClip (cursor panel, one-time price) — but no encryption, no open source, no screen-share privacy.
