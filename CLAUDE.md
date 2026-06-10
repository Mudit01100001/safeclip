# SafeClip — CLAUDE.md
_Last updated: 6 June 2026 (Session 2 — design docs + sandbox decision)._

> This file auto-loads at the start of every Claude Code session opened in this folder. It is the single source of truth for "what is this and what's next." Detailed product spec lives in [PRD.md](PRD.md).

---

## 🚦 SESSION HANDOFF — read first

**Status: PRE-BUILD.** Planning and design docs complete; no code exists yet. The next session's job is to scaffold the Xcode project (Milestone M0).

**Sandbox decision made (Session 2):** Non-sandboxed, Hardened Runtime on, notarized `.dmg` distributed off GitHub Releases. No Mac App Store target.

### What this project is
A **privacy-first macOS clipboard manager**. The differentiators — none of which any mainstream competitor (Maccy, Paste, CleanClip, CopyClip, Raycast) currently ships:
1. **Encrypted history store** — AES-256-GCM, key in macOS Keychain.
2. **Floating panel at the cursor** — like the emoji picker (⌃⌘Space), triggered by a global shortcut. Not a menu-bar dropdown.
3. **Plain-text paste by default** — rich formatting captured but stripped on paste; `⌥Return` keeps formatting.
4. **Screen-recording privacy** — history blurred while screen sharing (unbuilt elsewhere; Maccy #1017 open since Jan 2025).
5. **ClickFix / pastejacking detection** — warn when the clipboard was overwritten by a webpage with a shell command (novel; ClickFix was >50% of macOS malware-loader activity in 2025).

### What was decided this session (do NOT re-litigate without reason)
- **No synthesized ⌘V → no Accessibility permission.** App writes to the pasteboard; the *user* presses ⌘V. One extra keypress, but the app launches with **zero special permissions**. This is a core design pillar.
- **"Delete after use" is a per-item action ("burn after paste"), NOT the global default.** History persists by default — that's the whole point of a clipboard manager. Burn is opt-in per item.
- **Plain-text is the default paste, but rich text is also stored** so `⌥Return` can paste formatting. Forcing plain-text-only breaks tables/docs.
- **Source-app filtering (skip 1Password etc.) and pattern detection are opt-in, OFF by default** — the user copies passwords often and wants them captured.
- **The "paste window" is a real, unfixable limitation** — plaintext sits on `NSPasteboard` for <1s during paste. We **disclose** it honestly (TERMS §3); we never claim "delete after use" is cryptographic.
- **Local-only, open source (MIT).** No backend, no telemetry. HN users won't trust a closed-source clipboard manager.

### ⚡ IMMEDIATE NEXT STEPS (next session = Milestone M0)
1. `git init` in this folder (not yet a repo). Create the GitHub repo `safeclip` and replace `YOUR_USERNAME` in [TERMS.md](TERMS.md) (×2).
2. Scaffold an Xcode project: menu-bar (`NSStatusItem`) app shell, Swift 6, min macOS 14.
3. Wire dependencies via SPM: `GRDB.swift` (SQLite), `KeyboardShortcuts` (global hotkey).
4. ~~Decide the **sandbox stance**~~ **DECIDED: non-sandboxed, notarized .dmg off GitHub Releases.** No MAS target.
5. Get a clean build (zero warnings) launching to a menu-bar icon = M0 exit criteria.

Then M1 (capture + encrypted store), M2 (floating panel), M3 (v1.0 polish + notarize). Full milestone table: PRD §14.

---

## Files in this folder
| File | Purpose |
|------|---------|
| [PRD.md](PRD.md) | Full product spec — features (P0/P1/P2 w/ acceptance criteria), UX, security architecture, data model, milestones, risks, testing, research appendix with sources. |
| [TERMS.md](TERMS.md) | Terms of Use / liability disclaimer. Shown at first launch + in README. Discloses the paste-window limit. ⚠️ Has `YOUR_USERNAME` placeholder ×2. |
| [LICENSE](LICENSE) | MIT. |
| CLAUDE.md | This file. |
| [docs/DESIGN.md](docs/DESIGN.md) | App architecture — how the three UI surfaces (menu bar, floating panel, settings window) work as one app. SwiftUI/AppKit split, data flow, file layout. |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Full milestone roadmap with per-task checklists, technical research log, closed/open decisions, risk register, competitive gap table. |

_No source code yet._

---

## Tech stack (locked — see PRD §11)
| Layer | Choice |
|-------|--------|
| Language | Swift 6 (strict concurrency) |
| UI | SwiftUI (panel + settings) + AppKit (`NSPanel`, `NSStatusItem`) |
| Min / target OS | macOS 14 (Sonoma) / macOS 16 pasteboard-privacy API |
| Encryption | CryptoKit `AES.GCM` 256-bit, per-item nonce |
| Key storage | Security framework Keychain, `kSecAttrAccessControl` locked to code signature |
| DB | SQLite via `GRDB.swift` (MIT) |
| Hotkey | `KeyboardShortcuts` by Sindre Sorhus (MIT), public APIs only |
| Cursor pos | `NSEvent.mouseLocation` |
| Panel | `NSPanel`, `.nonactivatingPanel`, `isFloatingPanel = true`, clamp to `visibleFrame` |
| Login item | `SMAppService` |
| Dist | MIT source on GitHub + notarized `.dmg` on Releases |

---

## Build / run (once the project exists — placeholders for now)
```bash
# Build (M0+):
xcodebuild -scheme SafeClip -configuration Debug build
# Open in Xcode:
open SafeClip.xcodeproj
```
**Working rule (carry over from how Mudit likes to work):** after any change, build and fix all warnings/errors before calling a task done. Don't consider it done until the build passes clean.

### Security smoke tests (run after M1)
```bash
strings ~/Library/Application\ Support/SafeClip/history.db   # must show NO clipboard text
security find-generic-password -s SafeClip                    # key present, ACL-locked
```

---

## Critical caveats to keep in mind
- **Migrations vs. code is not a thing here** (no DB server) — but **notarization is**: a code change isn't shippable until the binary is re-signed + notarized. Source push ≠ released build.
- **macOS 16 will change clipboard capture** — abstract capture behind a protocol with two impls (`changeCount` polling for ≤15, `detect`-before-read for 16+). Test on the 15.4 preview now. (PRD §15.)
- **Never claim zero-knowledge against the OS.** The encryption protects the on-disk store, not the live system clipboard (which Universal Clipboard syncs across devices).
- **Keep scope minimal.** No images/files in history v1, no AI, no sync v1, no browser extension. (PRD §13.)

---

## Open questions (PRD §19)
- **App name** — "SafeClip" is a working title; check trademark + macOS app-name collisions.
- **Paid vs. free** — research supports $8–12 one-time on Releases, free+open-source on GitHub.
- ~~**Sandbox stance** — decide at M0.~~ **Decided: non-sandboxed .dmg, off-MAS.**
- **macOS 16 launch timing** — aim M3 near macOS 16 GA (fall 2026) for the privacy-narrative tailwind.

---

## Context: how this project started
Mudit uses CopyClip and wanted a clipboard manager that (a) pastes plain text via a special trigger, (b) shows history in a cursor-anchored popup like the emoji viewer, and (c) protects sensitive data (passwords) rather than hoarding everything in plaintext. Research confirmed the exact combination doesn't exist and the encryption + screen-share + hijack-detection gaps are uncontested. This is a separate project from the De-Sludging Project (different folder, different repo) — they share nothing.
