# SafeClip — Product Requirements Document

_Working title. Last updated: June 2026. Status: pre-build (planning)._

---

## Table of Contents

1. [Vision](#1-vision)
2. [Problem & Evidence](#2-problem--evidence)
3. [Competitive Landscape](#3-competitive-landscape)
4. [Target Users & Personas](#4-target-users--personas)
5. [User Stories](#5-user-stories)
6. [Feature Specification](#6-feature-specification)
7. [UX & Interaction Design](#7-ux--interaction-design)
8. [Security Architecture](#8-security-architecture)
9. [Data Model](#9-data-model)
10. [Settings / Preferences](#10-settings--preferences)
11. [Technical Requirements](#11-technical-requirements)
12. [Edge Cases & Failure Modes](#12-edge-cases--failure-modes)
13. [Non-Goals](#13-non-goals)
14. [Release Plan & Milestones](#14-release-plan--milestones)
15. [Risks & Mitigations](#15-risks--mitigations)
16. [Testing Strategy](#16-testing-strategy)
17. [Distribution & Licensing](#17-distribution--licensing)
18. [Success Metrics](#18-success-metrics)
19. [Open Questions](#19-open-questions)
20. [Glossary](#20-glossary)
21. [Research Appendix](#21-research-appendix-sources)

---

## 1. Vision

A macOS clipboard manager that is **private by design**. History is encrypted on disk, the live system clipboard exposure is minimised, and the UI floats near your cursor — not buried in the menu bar. The app does one thing well, requires no special permissions to run, and is open source so every privacy claim is independently verifiable.

**One-line pitch:** _The clipboard manager that doesn't betray you — encrypted history, plain-text paste, and a picker that appears right where you're typing._

**Design principles:**
1. **Minimum permissions.** The app runs with zero special permissions at launch. No Accessibility, no Full Disk Access.
2. **Honest about limits.** Where macOS makes a guarantee impossible (the paste window), we disclose it plainly rather than over-promising.
3. **Verifiable trust.** Open source. The no-exfiltration claim is checkable by reading the code.
4. **Do one thing well.** A clipboard manager, not a productivity suite. No AI, no bloat.

---

## 2. Problem & Evidence

Every mainstream macOS clipboard manager stores history as **plaintext on disk** (independent analysis flags most as plain SQLite with no encryption — see [ClipGate audit](https://clipgate.github.io/blog/macos-clipboard-history-what-leaks/)). This creates concrete exposure:

| Exposure | Detail | Evidence |
|----------|--------|----------|
| **Silent clipboard reads** | Until macOS 16, any running app can read `NSPasteboard` at any time with no permission prompt — functionally a keylogger for clipboard content. | [MacRumors / 9to5Mac, May 2025](https://9to5mac.com/2025/05/12/macos-16-clipboard-privacy-protection/) |
| **Password-manager leakage** | The single most-requested feature on Maccy's tracker for years. Users wrote "flaky wrapper scripts that turn Maccy on and off" around 1Password. | [Maccy Issue #79 (2020)](https://github.com/p0deje/Maccy/issues/79) |
| **Disk / backup forensics** | Plaintext history is captured in Time Machine snapshots and any disk image. | ClipGate audit (above) |
| **Screen-share exposure** | No mainstream app hides clipboard history during screen recording / Zoom. | [Maccy Issue #1017 (Jan 2025, unresolved)](https://github.com/p0deje/Maccy/issues/1017) |
| **Clipboard hijacking (ClickFix)** | Malicious sites overwrite the clipboard with shell commands, then social-engineer a paste into Terminal. **>50% of macOS malware loader activity in 2025.** | [Virus Bulletin VB2025](https://www.virusbulletin.com/conference/vb2025/abstracts/clickfix-exploiting-clipboard-multi-stage-payload-delivery-across-os-platforms/), [Malwarebytes](https://www.malwarebytes.com/blog/news/2026/03/new-macos-security-feature-will-alert-users-about-possible-clickfix-attacks) |
| **Rich-text junk** | Pasting carries fonts/colours/HTML into plain-text fields. Users want a forced plain-text paste *and* the option to keep formatting. | [Alfred forum request](https://www.alfredforum.com/topic/9480-rich-text-support-for-clipboard-history-plus-paste-as-plaintext-hotkey/) |

**Trust requirement:** HN commenters on clipboard managers stated plainly they will not use a closed-source one: _"I absolutely need open source for this, I wouldn't be able to trust it otherwise."_ ([HN thread](https://news.ycombinator.com/item?id=31867121))

**The uncontested gaps:** No mainstream macOS clipboard manager (a) encrypts its history store, (b) warns on clipboard hijacking, or (c) hides history during screen recording. SafeClip targets all three.

---

## 3. Competitive Landscape

| App | Price | Cursor-float UI | Auto-strip on copy | Encrypted store | Screen-share privacy | Hijack detection | Open source |
|-----|-------|:---:|:---:|:---:|:---:|:---:|:---:|
| **Maccy** | Free / ~$10 MAS | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| **Paste** | $30/yr | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **CleanClip** | $20 once | ✅ (`⌘;`) | ❌ (paste-time) | ❌ | ❌ | ❌ | ❌ |
| **CopyClip 2** | Free / paid | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Raycast** | Free / $8/mo | ❌ (launcher) | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Pasta** | Paid | ❌ (panel) | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Pure Paste** | Free | n/a (no UI) | ✅ | n/a | ❌ | ❌ | ❌ |
| **QuietClip** | $8.99 once | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **SafeClip** | TBD ($8–12 once) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

**Positioning:** There is a clear gap between free/open-source (Maccy) and $20–30 paid apps. None combine cursor-float UI + auto-strip + encryption. SafeClip occupies the privacy-first slot at a one-time $8–12 price. Subscription resistance is well documented for utilities this simple.

**Closest single competitors:** CleanClip (cursor-float, but no encryption, closed source) and Pure Paste (auto-strip, but no history UI). Neither overlaps SafeClip's full feature set.

---

## 4. Target Users & Personas

**Primary — "Dev who copies secrets all day."**
Copies API keys, tokens, snippets, and passwords dozens of times an hour. Uses a password manager. Wants history but is uneasy that everything is captured in plaintext. Will read the source before trusting it. Values the per-item "burn after paste" and the encrypted store.

**Secondary — "Consultant on back-to-back calls."**
Screen-shares constantly. Has been burned by clipboard history flashing on screen during a paste. Wants history auto-hidden whenever recording is active. Non-technical about security but understands "it hides during Zoom."

**Tertiary — "Writer who hates formatting."**
Copies from the browser, Notion, and Word into plain-text editors. Wants the formatting gone by default but occasionally needs to keep it. Lives in the plain-text-default + `⌥Return` rich-paste behaviour.

---

## 5. User Stories

**Core loop**
- As a user, I press a shortcut and a list of my recent copies appears **at my cursor**, so I don't move my eyes to the menu bar.
- As a user, I type to filter the list, so I find the right item in two or three keystrokes.
- As a user, I press Return on an item and it lands in my text field **as plain text**, so I never paste unwanted formatting.
- As a user, I press `⌥Return` on an item and it pastes **with original formatting**, so I'm not locked out of rich paste when I need it.

**Privacy**
- As a security-conscious user, I want my history encrypted on disk, so a stolen laptop or backup doesn't leak my clipboard.
- As a user copying a password, I want to mark it "burn after paste", so it's gone from history the moment I use it.
- As a consultant, I want history hidden while screen recording, so I never flash a secret on a call.
- As a developer, I want a warning when the clipboard was overwritten by a webpage with a shell command, so I don't fall for a ClickFix attack.

**Control**
- As a user, I want to exclude specific apps (1Password) from capture, so their copies are never stored at all.
- As a user, I want old items to auto-expire, so my history doesn't accumulate forever.
- As a user, I want to clear all history instantly, so I can wipe everything before handing over my screen.

---

## 6. Feature Specification

Each feature lists **acceptance criteria** so "done" is unambiguous.

### P0 — Must ship (v1.0)

**F1 — Encrypted history store**
All items stored as AES-256-GCM ciphertext. Key generated once at first launch, stored in macOS Keychain, ACL-locked to the app's code signature.
- ✅ `strings history.db` returns no recognisable clipboard content.
- ✅ Deleting and reinstalling the app (without deleting the Keychain item) re-opens existing history; deleting the Keychain item renders history permanently unreadable.
- ✅ Another user account / another app cannot read the key (verified via `security` CLI).

**F2 — Floating panel at cursor**
Global, user-configurable shortcut (default `⌃⇧V`) opens an `NSPanel` at `NSEvent.mouseLocation`. Non-activating — does not steal focus from the active app.
- ✅ Panel appears within 100ms of the shortcut.
- ✅ Panel position clamps to the visible screen frame (no off-screen / under-notch rendering on multi-monitor).
- ✅ The active app's text cursor stays active; pressing Escape returns focus untouched.

**F3 — Plain-text default paste, rich-text on modifier**
Both representations captured. Return pastes plain text; `⌥Return` pastes original rich text.
- ✅ Copying a formatted table from Numbers and pressing Return pastes a clean tab-separated string; `⌥Return` pastes the table structure.
- ✅ No font/colour/HTML metadata survives a plain-text paste.

**F4 — Search**
Inline search field filters history in real time.
- ✅ Typing filters within one frame (<16ms) for a 1,000-item history.
- ✅ Search matches item content, case-insensitive.

**F5 — macOS 16 pasteboard compliance**
Uses the `detect`-before-read API so capture does not trigger a permission prompt per item.
- ✅ On macOS 16, normal capture generates zero "Paste from Other Apps" prompts after the initial grant.
- ✅ On macOS 14–15, falls back to `changeCount` polling cleanly.

**F6 — Clear all / instant wipe**
One action clears the entire history store (encrypted rows deleted, not just hidden).
- ✅ After "Clear All", `history.db` contains zero item rows.

### P1 — v1.1

**F7 — Delete after use (per-item "burn after paste")**
Right-click an item → "Burn after paste". Item is deleted from history immediately after it is pasted once. **Per-item, not the global default.**
- ✅ A burn-flagged item disappears from history after one paste.
- ✅ Tooltip discloses the best-effort limitation (see §8).

**F8 — Screen recording privacy**
Detects active screen recording / sharing; blurs or hides panel content; restores when recording stops.
- ✅ Starting a QuickTime/Zoom screen recording blurs the panel within 1s.
- ✅ Stopping recording restores normal display.

**F9 — Auto-expiry**
Items older than N days (default 7, configurable) auto-deleted on a daily sweep.
- ✅ An item with `created_at` older than the window is gone after the next sweep.
- ✅ Pinned items (F12) are exempt.

**F10 — Source app filter (opt-in, OFF by default)**
User-managed list of bundle IDs whose copies are never stored.
- ✅ A copy from an excluded app creates no history row.
- ✅ Default list is empty; nothing is excluded unless the user adds it.

### P2 — Backlog

**F11 — Pastejacking / ClickFix detection** _(novel — no competitor has this)_
Heuristic: clipboard overwritten while a browser is frontmost AND content matches shell-command patterns (`curl … | sh`, `sudo`, base64 blobs piped to a shell). Show a red warning banner on the item.
- ✅ A simulated ClickFix string surfaces a warning banner before paste.

**F12 — Item pinning** — pinned items survive auto-expiry and sort to the top.
**F13 — Pattern detection (opt-in, OFF by default)** — Luhn (cards), API-key prefixes (`ghp_`, `sk-`, `AKIA`), private-key headers. Flagged with a warning icon; optionally auto-burn.
**F14 — Full keyboard navigation** — arrows to move, Return / `⌥Return` to paste, Escape to dismiss, `⌘Delete` to remove an item.
**F15 — iCloud sync (zero-knowledge)** — client-side encryption before upload; server stores only ciphertext. Explicitly **not in v1**.

---

## 7. UX & Interaction Design

### First-launch onboarding (3 screens, skippable)
1. **Welcome + Terms.** Short plain-language summary of [TERMS.md](TERMS.md) with a "I understand" checkbox (records consent locally — see §17). Links to full terms and source code.
2. **Set your shortcut.** Default `⌃⇧V` pre-filled; user can rebind. Explains the panel appears at the cursor.
3. **Privacy posture.** Explains: history is encrypted; nothing leaves the device; the paste-window caveat in one sentence. Optional toggles for screen-record privacy (on) and source-app exclusion (off).

### The floating panel (primary surface)
```
┌─────────────────────────────────┐
│ 🔍 Search…                       │  ← focused on open; type to filter
├─────────────────────────────────┤
│ ▸ meeting notes for thursday     │  ← selected (arrow-key highlight)
│   https://example.com/long/url   │
│   ghp_••••••••••  ⚠️ sensitive   │  ← pattern-flagged (if enabled)
│   def parse(x): return x.strip() │
│   📌 my standard email signature │  ← pinned
├─────────────────────────────────┤
│ ↩ paste · ⌥↩ keep format · ⎋ close│  ← hint bar
└─────────────────────────────────┘
```
- Opens at cursor, search field focused.
- Arrow keys move selection; Return pastes plain; `⌥Return` pastes rich.
- Right-click item → Pin · Burn after paste · Delete · Copy again.
- Escape dismisses and returns focus to the previous app with no side effects.
- **Empty state:** "No clipboard history yet. Copy something and it'll appear here." 
- **Recording-active state:** content area blurred with a small "Hidden while screen recording" label.

### Menu-bar item (secondary)
Minimal `NSStatusItem`: Open panel · Clear all history · Pause capture · Preferences · Quit. Capture state (active/paused) shown by icon.

### Keyboard shortcuts
| Action | Shortcut |
|--------|----------|
| Open panel | `⌃⇧V` (configurable) |
| Paste plain | `Return` |
| Paste with formatting | `⌥Return` |
| Move selection | `↑` / `↓` |
| Delete selected item | `⌘Delete` |
| Pin / unpin | `⌘P` |
| Dismiss | `Escape` |
| Pause/resume capture | from menu bar |

---

## 8. Security Architecture

```
Copy event
  ↓ NSPasteboard.changeCount polled (~200ms)  [macOS 14–15]
  ↓ OR detect-before-read pasteboard API       [macOS 16+]
  ↓
Capture both representations (plain string + rich data)
  ↓
[If source app in exclusion list] → DISCARD, no row written
  ↓
[Optional pattern scan] → flag / optionally auto-burn
  ↓
AES-256-GCM encrypt (key from Keychain, per-item nonce)
  ↓
Write ciphertext row → SQLite (~/Library/Application Support/SafeClip/history.db)

Paste event
  ↓ User selects item in floating panel
  ↓ Decrypt item (key from Keychain)
  ↓ Write chosen representation to NSPasteboard
  ↓ User presses ⌘V in active app   ← NO Accessibility permission required
  ↓ [If burn-after-paste] wipe row from store
```

**Key design decisions (and the research that drives them):**

1. **No synthesized ⌘V → no Accessibility permission.** Injecting keystrokes requires Accessibility (`CGEvent.post`) or AppleScript — the same power a malicious automator wants. We avoid it: SafeClip writes to the pasteboard and the user presses ⌘V. One extra keypress buys a dramatically smaller attack surface and a zero-permission launch. (Pattern used by ClipBook/Paste.)

2. **Keychain key ACL-locked to code signature.** `kSecAttrAccessControl` requires the app's signature to read the key. Mitigates documented **key-redefinition attacks**. Note Accessibility does **not** grant Keychain access — they are separate TCC gates — so even an Accessibility-holding app can't read our key without a separate exploit.

3. **The paste window is disclosed, not hidden.** When pasting, plaintext briefly lives on `NSPasteboard` (typically <1s) until the receiving app reads it. No public API can paste-and-atomically-clear. Therefore **"delete after use" is a best-effort UX property, not a cryptographic guarantee** — stated in the tooltip, onboarding, and [TERMS.md](TERMS.md).

4. **Encryption protects the store, not the live clipboard.** Disclosed plainly: SafeClip encrypts its own history; it cannot protect the system clipboard that all of macOS shares (incl. Universal Clipboard, which syncs to all same-Apple-ID devices instantly).

**Known patched CVEs informing the threat model** (all require local access; all mitigated by current macOS + correct entitlements):
- [CVE-2024-54490](https://ogma.in/understanding-cve-2024-54490-keychain-vulnerability-in-macos-and-its-mitigation) — Keychain access via missing hardened-runtime entitlement (fixed 15.2). → We ship Hardened Runtime.
- [CVE-2025-24204](https://www.helpnetsecurity.com/2025/09/04/macos-gcore-vulnerability-cve-2025-24204/) — `gcore` could read any process memory. → Out of our control; defence-in-depth only.
- [CVE-2025-31191](https://www.microsoft.com/en-us/security/blog/2025/05/01/analyzing-cve-2025-31191-a-macos-security-scoped-bookmarks-based-sandbox-escape/) — security-scoped-bookmark sandbox escape. → We don't rely on that mechanism.

---

## 9. Data Model

**SQLite (GRDB), single file, all content columns encrypted before write.**

```sql
CREATE TABLE clips (
  id            TEXT PRIMARY KEY,        -- UUID
  ciphertext    BLOB NOT NULL,           -- AES-256-GCM(plain text)
  nonce         BLOB NOT NULL,           -- per-item GCM nonce
  rich_cipher   BLOB,                    -- AES-256-GCM(rich data), nullable
  rich_nonce    BLOB,
  rich_type     TEXT,                    -- UTI of the rich representation (e.g. public.rtf)
  content_hash  TEXT NOT NULL,           -- SHA-256 of plain text, for dedup (not reversible)
  char_count    INTEGER NOT NULL,        -- for display ("1,240 chars") without decrypting
  source_bundle TEXT,                    -- frontmost app bundle id at copy time
  is_pinned     INTEGER NOT NULL DEFAULT 0,
  is_burn       INTEGER NOT NULL DEFAULT 0,
  is_flagged    INTEGER NOT NULL DEFAULT 0,  -- pattern detection hit
  flag_reason   TEXT,                    -- 'api_key' | 'card' | 'private_key' | 'clickfix'
  created_at    INTEGER NOT NULL,        -- unix epoch
  last_used_at  INTEGER
);

CREATE INDEX idx_clips_created ON clips(created_at);
CREATE UNIQUE INDEX idx_clips_hash ON clips(content_hash);  -- dedup identical copies
```

**Notes:**
- **Dedup by `content_hash`** so re-copying the same text bumps `last_used_at` instead of creating duplicates. Hash is SHA-256 (one-way) — storing it is not a plaintext leak.
- **`char_count` stored in clear** so the list can show size without decrypting every row on open (decrypt is lazy, per visible item).
- **Search** decrypts lazily over the candidate set; for large histories, consider an in-memory decrypted index built on unlock (never written to disk). v1 can brute-decrypt — 1,000 items is trivially fast.

---

## 10. Settings / Preferences

| Setting | Default | Notes |
|---------|---------|-------|
| Global shortcut | `⌃⇧V` | Rebindable via `KeyboardShortcuts` recorder |
| History limit | 200 items | Or unlimited; oldest pruned beyond limit |
| Auto-expiry window | 7 days | 1 / 7 / 30 / never |
| Strip formatting by default | On | Off = default paste keeps formatting |
| Screen-recording privacy | On | Blur panel while recording |
| Source-app exclusion list | Empty | User adds bundle IDs |
| Pattern detection | Off | Opt-in; sub-toggles per pattern type |
| Auto-burn flagged items | Off | Only meaningful if pattern detection on |
| Launch at login | On | `SMAppService` |
| Pause capture | — | Menu-bar toggle, not persisted |
| Clear all history | — | Destructive action, confirm dialog |

---

## 11. Technical Requirements

| Requirement | Detail |
|-------------|--------|
| Language | Swift 6 (strict concurrency) |
| UI framework | SwiftUI (panel + settings), AppKit (`NSPanel`, `NSStatusItem`) |
| Minimum macOS | 14.0 (Sonoma) |
| Target macOS | 15+ and macOS 16 (pasteboard privacy API) |
| Encryption | CryptoKit — `AES.GCM`, 256-bit, per-item nonce |
| Key storage | Security framework — `SecItemAdd` / `SecItemCopyMatching`, `kSecAttrAccessControl` |
| History store | SQLite via `GRDB.swift` |
| Hotkey | `KeyboardShortcuts` (Sindre Sorhus) — public APIs only |
| Cursor position | `NSEvent.mouseLocation` (public AppKit) |
| Panel | `NSPanel`, `.nonactivatingPanel`, `isFloatingPanel = true` |
| Login item | `SMAppService` |
| Distribution | MIT source on GitHub + notarized `.dmg`/`.zip` on Releases |
| Sandboxing | Hardened Runtime ON. App Sandbox: evaluate — pasteboard read works sandboxed; menu-bar utilities often ship non-sandboxed outside MAS. Decide before notarization. |
| Permissions at launch | **None.** macOS 16 prompts "Paste from Other Apps" once. |
| Dependencies | `GRDB.swift` (MIT), `KeyboardShortcuts` (MIT) — both pinned, both auditable |

---

## 12. Edge Cases & Failure Modes

| Case | Handling |
|------|----------|
| Keychain key missing/corrupt on launch | Offer to regenerate (wipes unreadable history) with a clear warning; never silently lose data without consent. |
| Multi-monitor / notch | Clamp panel origin to visible `NSScreen.visibleFrame`. |
| Huge clipboard item (e.g. 50MB image as text) | Cap stored plain text at a sane limit (e.g. 1MB); store a truncation marker; never store images in v1. |
| Non-text clipboard (files, images) | v1 captures plain-text representation only; ignore pure-image/file copies (document this). |
| Rapid successive copies | Debounce on `changeCount`; dedup by hash. |
| App copies then immediately clears (password managers) | We may capture before the manager clears. Mitigated by exclusion list (opt-in) and burn-after-paste. Disclosed in TERMS. |
| Pasteboard write race during paste | Accept best-effort window; document in TERMS §3. |
| FileVault off | App still encrypts its store; recommend FileVault in onboarding. |
| macOS 16 permission denied | App degrades to "paused" with a clear prompt explaining capture needs the grant. |

---

## 13. Non-Goals

- **No cloud backend in v1.** Local-only. No telemetry. No crash reporting that includes clipboard content.
- **No rich-text preview in the panel.** Formatted items stored, but the panel renders plain text only.
- **No images / files in history (v1).** Text only. Revisit later.
- **No Windows / Linux.** macOS-only; Keychain + AppKit throughout.
- **No browser extension.** OS-level monitoring is sufficient.
- **No AI features.** No summarisation, grouping, or "smart" anything. Scope stays minimal.
- **No synthesized keystroke paste.** Deliberate — see §8.

---

## 14. Release Plan & Milestones

| Milestone | Scope | Exit criteria |
|-----------|-------|---------------|
| **M0 — Skeleton** | Xcode project, menu-bar app shell, dependencies wired, builds clean | `⌘B` zero warnings; app launches to a menu-bar icon |
| **M1 — Capture + store** | Clipboard monitor, AES+Keychain, encrypted SQLite, dedup | Copies persist as ciphertext; `strings` shows nothing |
| **M2 — Panel** | Floating panel at cursor, list, search, plain/rich paste | F2–F4 acceptance criteria pass |
| **M3 — v1.0 polish** | Onboarding + Terms consent, settings, clear-all, login item, notarization | Ships as notarized build; zero launch permissions |
| **M4 — v1.1 privacy** | Burn-after-paste, screen-record privacy, auto-expiry, source-app filter | F7–F10 pass |
| **M5 — v1.2 novel** | ClickFix detection, pattern detection, pinning, full keyboard nav | F11–F14 pass |

**Positioning note:** aim M3 to land near macOS 16 GA (likely fall 2026) to ride the "built for the new clipboard privacy model" narrative.

---

## 15. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| macOS 16 pasteboard API changes break capture | Med | High | Build against the 15.4 developer preview now; abstract capture behind a protocol with `changeCount` + `detect` implementations |
| Users expect persistent history, dislike any ephemerality | Med | Med | Delete-after-use is per-item, never the global default; history persists by default |
| Forced plain-text breaks table/doc workflows | Med | Med | Store rich text too; `⌥Return` rich paste; default-strip is a toggle |
| "Encrypted" over-promises given paste window | Low | High | Plain disclosure in onboarding + TERMS; never claim zero-knowledge against the OS |
| Closed-source distrust | Low | Med | MIT, public repo, reproducible-ish notarized builds, compile-from-source path |
| Notarization / sandbox friction | Med | Low | Decide sandbox stance early (M0); menu-bar utilities commonly ship non-sandboxed off-MAS |
| Single-maintainer abandonment perception | Med | Low | Open source means forkable; document architecture in CLAUDE.md |

---

## 16. Testing Strategy

- **Unit:** encryption round-trip (encrypt→decrypt equality, wrong-key fails), dedup hashing, pattern-detection regexes (Luhn true/false positives, key prefixes), expiry sweep logic.
- **Security:** `strings history.db` finds no plaintext; `security find-generic-password` from another context cannot read the key; verify ACL binding; confirm no plaintext in Time Machine snapshot.
- **Integration:** copy→capture→panel→paste round-trip; plain vs `⌥Return` rich paste into TextEdit (rich) and Terminal (plain); exclusion-list app produces no row; burn item disappears post-paste.
- **UX:** panel position across 1–3 monitors incl. notched display; <100ms open; Escape restores focus; recording-active blur.
- **macOS matrix:** 14, 15, and the 16 preview. Capture path verified on each.

---

## 17. Distribution & Licensing

- **License:** MIT ([LICENSE](LICENSE)). Full source public.
- **Terms consent:** [TERMS.md](TERMS.md) shown at first launch; "I understand" recorded as a local flag (`hasAcceptedTerms` + version + timestamp in `UserDefaults`). No server, so consent is local-only by design; each release bundles its terms and continued use of a version constitutes acceptance (stated in TERMS §9). README links Terms before any download.
- **Binaries:** notarized `.dmg` on GitHub Releases. README states binaries are notarized (malware-checked, not an endorsement) and offers a compile-from-source path for high-trust users.
- **Repo hygiene:** README (with the §2 gaps + §3 table as the pitch), SECURITY.md (private advisory process), the PRD, and CLAUDE.md for contributors/agents.
- **Placeholder:** replace `YOUR_USERNAME` in TERMS.md (×2) when the GitHub repo is created.

---

## 18. Success Metrics (v1)

**Engineering**
- Build passes clean, zero warnings, strict Swift concurrency.
- `strings history.db` returns no recognisable clipboard content.
- Keychain key unreadable by another process (verified via `security` CLI).
- Panel opens <100ms after shortcut.
- Zero permission prompts during normal capture on macOS 16 after initial grant.
- Launches with **zero** special permissions (no Accessibility, no Full Disk Access).

**Product (post-launch, if instrumented privately / via opt-in only)**
- GitHub stars / forks as a trust proxy.
- Issue themes: are the §2 gaps resonating?
- Conversion on the paid binary vs. compile-from-source split.

---

## 19. Open Questions

- **App name.** "SafeClip" is a working title. Check trademark + macOS app-name collisions before committing. Candidates to weigh: clarity ("Clip"-something signals the category) vs. distinctiveness.
- **Paid vs. free.** Research supports $8–12 one-time on Releases while fully open source. Decide before M3.
- **Sandbox stance.** App Sandbox (required for Mac App Store) vs. non-sandboxed (common for menu-bar utilities, simpler pasteboard access). Affects distribution channel. Decide at M0.
- **macOS 16 launch timing.** Track WWDC 2026; align M3 with GA for the privacy-narrative tailwind.
- **Images/files in history.** Out of v1 — revisit based on demand.

---

## 20. Glossary

| Term | Meaning |
|------|---------|
| **`NSPasteboard`** | macOS system clipboard API. Shared by all apps. |
| **`changeCount`** | Integer that increments on every clipboard change; polled to detect copies (macOS ≤15). |
| **`detect` API** | macOS 16 method to inspect clipboard data *types* without reading content or triggering the permission prompt. |
| **Keychain** | macOS secure credential store; backed by the Secure Enclave on modern Macs. |
| **TCC** | Transparency, Consent & Control — macOS permission system (Accessibility, etc.). Keychain access is a *separate* gate from Accessibility. |
| **Paste window** | The brief interval where plaintext sits on `NSPasteboard` during a paste, readable by other apps. |
| **ClickFix / pastejacking** | Attack where a webpage overwrites the clipboard with a malicious command, then tricks the user into pasting it. |
| **Universal Clipboard** | Apple Continuity feature syncing the clipboard across same-Apple-ID devices. |
| **Burn after paste** | Per-item flag: delete from history immediately after one paste. |

---

## 21. Research Appendix (Sources)

Security & platform:
- [macOS 16 clipboard privacy — 9to5Mac](https://9to5mac.com/2025/05/12/macos-16-clipboard-privacy-protection/) · [MacRumors](https://www.macrumors.com/2025/05/12/apple-mac-apps-clipboard-change/) · [Michael Tsai roundup](https://mjtsai.com/blog/2025/05/12/pasteboard-privacy-preview-in-macos-15-4/) · [LapCat: privacy tradeoffs](https://lapcatsoftware.com/articles/2025/5/3.html)
- CVEs: [CVE-2024-54490](https://ogma.in/understanding-cve-2024-54490-keychain-vulnerability-in-macos-and-its-mitigation) · [CVE-2025-24204](https://www.helpnetsecurity.com/2025/09/04/macos-gcore-vulnerability-cve-2025-24204/) · [CVE-2025-31191](https://www.microsoft.com/en-us/security/blog/2025/05/01/analyzing-cve-2025-31191-a-macos-security-scoped-bookmarks-based-sandbox-escape/) · [key redefinition](https://github.com/yo-yo-yo-jbo/macos_key_redefinition/)
- Attacks: [ClickFix VB2025](https://www.virusbulletin.com/conference/vb2025/abstracts/clickfix-exploiting-clipboard-multi-stage-payload-delivery-across-os-platforms/) · [Malwarebytes ClickFix](https://www.malwarebytes.com/blog/news/2026/03/new-macos-security-feature-will-alert-users-about-possible-clickfix-attacks) · [pastejacking](https://securityaffairs.com/47665/hacking/pastejack-attack.html)

Market & user demand:
- [Maccy #79 — ignore password managers](https://github.com/p0deje/Maccy/issues/79) · [Maccy #1017 — screen-record privacy](https://github.com/p0deje/Maccy/issues/1017) · [HN — keyboard-centric clipboard](https://news.ycombinator.com/item?id=40648404) · [HN — Maccy / open-source trust](https://news.ycombinator.com/item?id=31867121) · [Privacy Guides discussion](https://discuss.privacyguides.net/t/macos-clipboard-manager/22131) · [Alfred — rich+plain paste](https://www.alfredforum.com/topic/9480-rich-text-support-for-clipboard-history-plus-paste-as-plaintext-hotkey/) · [ClipGate — what leaks](https://clipgate.github.io/blog/macos-clipboard-history-what-leaks/)

Pricing & competitors:
- [Maccy](https://github.com/p0deje/Maccy) · [Paste](https://pasteapp.io/pricing) · [CleanClip](https://pricing.cleanclip.cc/) · [Raycast](https://www.raycast.com/pricing) · [Pure Paste](https://sindresorhus.com/pure-paste) · [paste-back without Accessibility — ClipBook](https://clipbook.app/blog/paste-to-other-applications/)

API references:
- [NSEvent.mouseLocation](https://developer.apple.com/documentation/appkit/nsevent/1533380-mouselocation) · [NSPanel](https://developer.apple.com/documentation/appkit/nspanel) · [nspasteboard.org — transient data conventions](http://nspasteboard.org/)
