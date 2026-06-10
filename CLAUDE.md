# SafeClip — CLAUDE.md
_Last updated: 10 June 2026 (Session 3 — **full build, M0–M5 implemented**)._

> This file auto-loads at the start of every Claude Code session opened in this folder. It is the single source of truth for "what is this and what's next." Detailed product spec lives in [PRD.md](PRD.md).

---

## 🚦 SESSION HANDOFF — read first

**Status: BUILT.** All milestone code (M0–M5) is implemented, builds with **zero warnings** under Swift 6 strict concurrency, 34 core tests pass, and the automated security smoke test passes live (encrypted rows on disk, keychain key, dedup, relaunch persistence). Repo: [github.com/Mudit01100001/safeclip](https://github.com/Mudit01100001/safeclip).

**What remains (needs Mudit, not code):**
1. **Interactive QA** — press ⌃⇧V and exercise the panel by hand (automated tests can't drive the UI): search, arrows, ⌥Return rich paste, context menu, settings tabs, onboarding flow (delete the `com.mudit.safeclip` defaults domain to re-trigger it).
2. **macOS clipboard prompt** — on some machines the first background capture shows a one-time "paste from other apps" system prompt → choose *Always Allow*. The deny path is handled (capture pauses + menu-bar warning).
3. **Notarized release** — needs a paid Apple Developer account + "Developer ID Application" cert, then `Scripts/release.sh` does build→sign→notarize→staple→dmg. Until then, local builds sign with the Apple Development cert (team `YHK4D97KC4`).
4. Open product calls: app name trademark check, paid-vs-free (PRD §19).

**Distribution (revised Session 4 — dual-channel):** one repo, **two targets** sharing all sources. `SafeClip` = GitHub channel (non-sandboxed, Hardened Runtime, Developer ID → notarized `.dmg`). `SafeClip-MAS` = Mac App Store channel (App Sandbox; verified booting in its container). Do NOT fork into separate folders. Channel comparison + MAS submission checklist: [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md). MAS blockers: Apple Developer account, Apple Distribution cert, **app icon (none exists yet)**.

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

### ⚡ MILESTONE STATE (all code shipped 10 June 2026)
- ~~M0 scaffold~~ ✅ xcodegen project, SPM deps wired, menu-bar shell, zero-warning build
- ~~M1 capture + encrypted store~~ ✅ AES-256-GCM + Keychain + GRDB, live-verified with `strings`
- ~~M2 floating panel~~ ✅ non-activating cursor panel, search, plain/⌥rich paste, full keyboard nav
- ~~M3 polish~~ ✅ onboarding w/ terms consent, settings (4 tabs), login item, expiry, clear-all — **notarization pending Developer ID cert** (`Scripts/release.sh` ready)
- ~~M4 privacy~~ ✅ burn-after-paste, screen-record heuristic + manual Privacy Mode, exclusion list
- ~~M5 detection~~ ✅ ClickFix warnings, opt-in pattern detection, concealed-password masking, pinning
- ~~v0.2.0 (Session 3)~~ ✅ **images + file copies in history** (encrypted payloads + thumbnails, schema v2 migration, 40 tests) and **Liquid Glass** panel chrome on macOS 26+ (material fallback ≤25). See ROADMAP R13.

Full milestone detail + deltas from plan: [docs/ROADMAP.md](docs/ROADMAP.md).

---

## Files in this folder
| Path | Purpose |
|------|---------|
| [PRD.md](PRD.md) | Full product spec — features (P0/P1/P2 w/ acceptance criteria), UX, security architecture, data model, milestones, risks, testing, research appendix with sources. |
| [TERMS.md](TERMS.md) | Terms of Use / liability disclaimer. Linked from onboarding + README. Discloses the paste-window limit. |
| [README.md](README.md) | Public pitch: gap table, security model (honest version), install + build-from-source. |
| [SECURITY.md](SECURITY.md) | Private-advisory process; in/out of scope. |
| [LICENSE](LICENSE) | MIT. |
| CLAUDE.md | This file. |
| [docs/DESIGN.md](docs/DESIGN.md) | App architecture — the three UI surfaces as one app, SwiftUI/AppKit split, data flow. |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Milestones (now with status), research log, decisions, risk register. |
| `SafeClipCore/` | SPM package: crypto, Keychain, GRDB store, security scanner. **34 tests** — `swift test --package-path SafeClipCore`. |
| `App/` | App sources: `main.swift` (AppKit entry), AppDelegate, AppState, Services/, MenuBar/, Panel/, Settings/, Onboarding/. |
| `project.yml` | XcodeGen spec — regenerate `SafeClip.xcodeproj` with `xcodegen` after editing. |
| `Config/` | Info.plist (`LSUIElement`), entitlements (empty by design — no sandbox, zero permissions). |
| `Scripts/` | `smoke_test.sh` (live security assertions), `release.sh` (sign→notarize→dmg). |
| `.github/workflows/ci.yml` | CI: core tests + zero-warning build gate. |

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

## Build / run
```bash
xcodegen                                                      # only after editing project.yml
xcodebuild -project SafeClip.xcodeproj -scheme SafeClip -configuration Debug build      # GitHub variant
xcodebuild -project SafeClip.xcodeproj -scheme SafeClip-MAS -configuration Debug build  # App Store variant (sandboxed)
open SafeClip.xcodeproj                                       # or work in Xcode
swift test --package-path SafeClipCore                        # core test suite (40 tests)
Scripts/smoke_test.sh                                         # live security assertions (wipes local history!)
```
**Working rule (how Mudit likes to work):** after any change, build and fix all warnings/errors before calling a task done. Zero warnings — CI enforces it.

### Security smoke tests (verified passing 10 June 2026)
```bash
strings ~/Library/Application\ Support/SafeClip/history.db   # must show NO clipboard text ✅
security find-generic-password -s SafeClip                    # key present ✅
```

---

## Critical caveats to keep in mind
- **Migrations vs. code is not a thing here** (no DB server) — but **notarization is**: a code change isn't shippable until the binary is re-signed + notarized. Source push ≠ released build.
- **macOS 16 will change clipboard capture** — abstract capture behind a protocol with two impls (`changeCount` polling for ≤15, `detect`-before-read for 16+). Test on the 15.4 preview now. (PRD §15.)
- **Never claim zero-knowledge against the OS.** The encryption protects the on-disk store, not the live system clipboard (which Universal Clipboard syncs across devices).
- **Keep scope minimal.** No AI, no sync v1, no browser extension. (PRD §13.) Images/files were added in v0.2.0 by owner decision — encrypted like text, paths-not-contents for files.

---

## Open questions (PRD §19)
- **App name** — "SafeClip" is a working title; check trademark + macOS app-name collisions.
- **Paid vs. free** — research supports $8–12 one-time on Releases, free+open-source on GitHub.
- ~~**Sandbox stance** — decide at M0.~~ **Decided: non-sandboxed .dmg, off-MAS.**
- **macOS 16 launch timing** — aim M3 near macOS 16 GA (fall 2026) for the privacy-narrative tailwind.

---

## Context: how this project started
Mudit uses CopyClip and wanted a clipboard manager that (a) pastes plain text via a special trigger, (b) shows history in a cursor-anchored popup like the emoji viewer, and (c) protects sensitive data (passwords) rather than hoarding everything in plaintext. Research confirmed the exact combination doesn't exist and the encryption + screen-share + hijack-detection gaps are uncontested. This is a separate project from the De-Sludging Project (different folder, different repo) — they share nothing.
