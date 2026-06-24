# SafeClip — CLAUDE.md
_Last updated: 24 June 2026 (Session 8 — **QA-fix rounds + closed-source pivot; 2 known bugs open**)._

> This file auto-loads at the start of every Claude Code session opened in this folder. It is the single source of truth for "what is this and what's next." Detailed product spec lives in [PRD.md](PRD.md).

---

## 🚦 SESSION HANDOFF — read first

**Status: BUILT + OCR shipped.** All milestone code (M0–M5) plus v0.2.0 (images/files), Session-5 OCR, and the Session-7 warm-up bundle are implemented, build with **zero warnings** under Swift 6 strict concurrency, **55 core tests pass**, and the automated security smoke test passes live (encrypted rows on disk, keychain key, dedup, relaunch persistence). Repo: [github.com/Mudit01100001/safeclip](https://github.com/Mudit01100001/safeclip).

**Session 7 — competitive reckoning (24 Jun):** competitor **Supaste** leveled up (OCR, notch shelf, categories, inline snippets) and research surfaced **Maus** as the real threat — it owns "opens at your cursor / multi-monitor," so **caret-anchoring is no longer a unique wedge**. The only *uncontested* differentiators are all **safety** (encryption, plain-text default, screen-share blur, ClickFix warnings) — and clipboard threats just went mainstream (ClickFix +500% YoY, Apple Terminal paste-warnings in macOS 26.4, macOS 16 clipboard-privacy prompt). **Decision: the product/website lead with SAFETY for the general user; caret-anchoring is supporting.** A full 12-feature backlog ranked by implementation complexity lives in **private notes** (`~/.claude/plans/…supaste…md`) — deliberately **not** committed here (publish the code, not the playbook). Website scaffolding is a separate session.

**Session 8 — QA-fix rounds + closed-source pivot (24 Jun):** repo set **PRIVATE**; product is now **closed-source + paid** ("first in a series of QoL apps"). Built across three QA rounds: backlog #5–#8 (categories, multipaste, menu-bar history, image-OCR search), then fixes/polish — ClickFix-vs-concealed priority fix, dynamic file icons (real `NSWorkspace` doc/folder icons + extension-visible names), numeric quick-paste modifier picker, collapsible settings descriptions (`ExpandableText`), blur-not-blank, caret-proximity anchoring (slider + live preview, default 500pt), screenshot protection (`sharingType=.none` on panel+toast), "Appeared in images" search section, **em dashes removed from all copy**, and in-app open-source scrub (AboutView/Info.plist; README/LICENSE deferred to website session). 55 tests, both targets zero-warning. **⚠️ TWO KNOWN BUGS open (see next-session note):** (1) **panel scroll** — wheel/trackpad scroll dead in the floating panel (root cause: `.nonactivatingPanel` doesn't receive scrollWheel; recommended fix = make the panel activating + restore prior-app focus on hide). (2) **custom magnifier eyedropper** — `ScreenColorPicker.swift` is built but **disabled/unwired** (its borderless overlay can't become key → locked the user out of window-switching); ⌥P reverted to the safe system `NSColorSampler`. Next session: fix scroll, then build the magnifier eyedropper with the owner's custom Illustrator icon (teardrop frame + transparent centre circle = the magnified window). Full carry-over in memory `project_safeclip_next_session.md`.

**Default shortcuts (remapped Session 5):** **⌥V** opens the floating panel; **⌥C** captures a screen region → OCR → text on the clipboard. Both rebindable in Settings → General. A one-time migration (`shortcutsV2Migrated` default) resets the old ⌃⇧V binding to the new defaults on first launch of a Session-5+ build.

**What remains (needs Mudit, not code):**
1. **Interactive QA** — press ⌥V and exercise the panel by hand (automated tests can't drive the UI): search, arrows, ⌥Return rich paste, context menu, settings tabs, onboarding flow (delete the `com.mudit.safeclip` defaults domain to re-trigger it). For ⌥C OCR, the first use shows the system **Screen Recording** consent → allow once, then quit & reopen. **New (Session 6):** confirm the panel now opens *above* the cursor with a callout arrow pointing at it (default, no permission); then in Settings → General toggle **"Open above the text cursor"** → the in-app explanation sheet appears, Continue triggers the macOS **Accessibility** prompt (allow once), and the panel should then anchor above the blinking caret in a text field with the arrow at the caret. Denying/leaving it off falls back to mouse anchoring. **Session-6 QA rounds (16 Jun, ROADMAP R16 addenda):** (a) caret-exactness is **source-app dependent** — native/WebKit fields (Perplexity, Instagram, Safari inputs) anchor exactly; Chromium/Electron (Claude Desktop, Arc, Wispr Flow) expose no a11y tree by default. Owner greenlit using the `AXManualAccessibility` lever: `CaretLocator.prewarmFrontmostApp()` switches on the focused Chromium/Electron app's a11y tree (the one AX *write* SafeClip makes — enables reading only, disclosed in the consent sheet); `AppDelegate` pre-warms it on app-activation so the first ⌥V works. Safari/WebKit *web content* still leans on the 3-probe fallback. (b) Panel chrome rebuilt as one SwiftUI `CalloutShape` (`PanelChrome.swift`, `glassEffect` on 26+) — owner confirmed it looks good. (c) Concealed masking: many copies show as `••••` because **Wispr Flow (dictation) pastes into the focused app, recorded as Claude/WhatsApp**, which (plus those apps themselves) tag copies `org.nspasteboard.ConcealedType` (live DB: all concealed rows from those two). Fixes: masked rows **reveal on hover**; new **`ignoreConcealedFrom`** per-source guardrail — right-click a masked row → "Always Show Copies from [App]" (also un-masks existing rows via `HistoryStore.unconcealSource`), or Settings → Privacy → "Apps not treated as passwords". Real password managers stay masked (attributed to themselves).
2. **macOS clipboard prompt** — on some machines the first background capture shows a one-time "paste from other apps" system prompt → choose *Always Allow*. The deny path is handled (capture pauses + menu-bar warning).
3. **Notarized release** — needs a paid Apple Developer account + "Developer ID Application" cert, then `Scripts/release.sh` does build→sign→notarize→staple→dmg. Until then, local builds sign with the Apple Development cert (team `YHK4D97KC4`).
4. Open product calls: app name trademark check, website pricing.

**Distribution (revised Session 5 — paid website binary):** sell the **non-sandboxed `SafeClip` build** (Developer ID, notarized `.dmg`) as a **paid download from Mudit's own website** behind a payment gateway. The binary is **not** offered free on GitHub Releases; the MIT source stays public for the build-from-source / audit path. **Mac App Store is deferred** — earn website revenue → fund the Apple Developer license → then ship the `SafeClip-MAS` (sandboxed) target. Until then MAS is dormant; do **not** let sandbox limits block features (screen-OCR shells out to `/usr/sbin/screencapture`, which the sandbox forbids — fine for now). One repo, two targets, shared sources — do NOT fork into separate folders. Channel detail: [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

### What this project is
A **privacy-first macOS clipboard manager**. The differentiators — none of which any mainstream competitor (Maccy, Paste, CleanClip, CopyClip, Raycast) currently ships:
1. **Encrypted history store** — AES-256-GCM, key in macOS Keychain.
2. **Floating panel at the cursor** — like the emoji picker (⌃⌘Space), triggered by a global shortcut. Not a menu-bar dropdown.
3. **Plain-text paste by default** — rich formatting captured but stripped on paste; `⌥Return` keeps formatting.
4. **Screen-recording privacy** — history blurred while screen sharing (unbuilt elsewhere; Maccy #1017 open since Jan 2025).
5. **ClickFix / pastejacking detection** — warn when the clipboard was overwritten by a webpage with a shell command (novel; ClickFix was >50% of macOS malware-loader activity in 2025).
6. **Screen-region OCR (⌥C)** — drag a region like ⌘⇧4; the text in it is recognized on-device (Vision) and copied to the clipboard. The screenshot is OCR'd from a temp file then deleted — never stored. Interactive `screencapture -i` keeps the app itself free of Screen Recording permission.

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
- ~~v0.2.0 (Session 3)~~ ✅ **images + file copies in history** (encrypted payloads + thumbnails, schema v2 migration) and **Liquid Glass** panel chrome on macOS 26+ (material fallback ≤25). See ROADMAP R13.
- ~~Session 5~~ ✅ **screen-region OCR (⌥C)** via `ScreenOCRService` (interactive `screencapture` → Vision → clipboard, image deleted, never stored) + non-activating menu-bar confirmation toast; **shortcut remap** ⌃⇧V→⌥V with one-time migration; **classifier fix** — tightened the low-confidence "possible API key" heuristic (≥40 chars, mixed upper/lower/digit, Shannon entropy ≥3.2) so hex hashes/UUIDs/SHAs stop false-flagging, plus a **Reset All Flags** action (Settings → Advanced) to un-mask already-mislabeled rows. The earlier auto-OCR-on-image-copy was removed (silent/no UI). 43 tests.
- ~~Session 6~~ ✅ **caret-anchored panel + callout arrow** (ROADMAP R16). Default (no permission): the panel now opens *above* the cursor with an arrow pointing at it, so it never lands on the field you're pasting into. New **opt-in** "Open above the text cursor" toggle (Settings → General) anchors it above the blinking caret instead, via the **read-only** Accessibility caret bounds (`CaretLocator`: `kAXFocusedUIElement`→`kAXSelectedTextRange`→`kAXBoundsForRange`) — an in-app explanation sheet shows *before* the macOS prompt (R1 transparency-first), and it gracefully falls back to mouse anchoring when off/not-granted/no-caret. **Still never synthesizes ⌘V.** Sandbox-gated like OCR (`CaretLocator.isSupported` → GitHub channel only; MAS disables the toggle). Zero warnings, 43 tests.
- ~~Session 7~~ ✅ **warm-up feature bundle** (first slice of the safety-led backlog). (1) **ClickFix detection ON by default** (`AppSettings.clickFixDetection` now `true` + one-time `clickFixDefaultOnMigrated` flag enables it for existing installs). (2) **Numeric quick-paste** `⌃⌘1…⌃⌘9`, `⌃⌘0` — places the top-10 history items on the clipboard for the user's own ⌘V (no synthesized paste; pillar-safe), with a menu-bar confirmation toast and per-slot rebind/clear in Settings → General. Pastejacking-flagged items aren't placed silently (toast directs to the panel). (3) **Color swatches + SVG badge** — `ClipColor` parser (hex/rgb/rgba, whole-string) + `isLikelySVGMarkup` in `SafeClipCore` (9 new tests); the panel row renders a 24pt swatch for color clips and a code glyph for SVG markup. *Note: this is the display-only slice of "SVG kind" — no capture-pipeline/rendered-preview SVG yet.* (4) **Blur-not-blank** — while screen-recording/Privacy Mode the panel now shows the list **blurred** (radius 10) + non-interactive with an "Hidden while screen recording" pill, instead of the old blank placeholder. Both targets build zero-warning, 52 tests. **Interactive QA pending** (see below).
- ~~Session 7 (cont.)~~ ✅ **medium tier of the backlog (#5–#8).** (5) **Categories / collections** — encrypted per-clip `category` (schema v3 + `HistoryStore.setCategory`), a filter-chip bar in the panel, and a context-menu submenu (assign / New Category… via NSAlert / remove). Filtering is in-memory in `PanelViewModel.recomputeFilter`. (6) **Multipaste** — ⌘-click builds an ordered selection (numbered badges + count bar); Return places the clips combined (newline-joined) as one payload for a single ⌘V (`AppState.pasteCombined` → `PasteService.placePlainText`; pillar-safe, warns once if any item is ClickFix-flagged). (7) **Menu-bar history** — the status-item menu now lists the top 8 recent clips (icons, masked concealed values, suppressed while history hidden); clicking places for ⌘V, ClickFix items route to the panel. (8) **Search-within-images** — copied images are OCR'd on-device (`OCRService`) into an encrypted `ocr_text` column (schema v4) that the panel search matches; new "Search text inside images (OCR)" toggle (default on) in Settings → General. Both targets zero-warning, **55 tests** (added category + OCR round-trip/encryption tests). **Remaining backlog (private notes): #9 saved snippets (Tier-A), #10 structure-aware OCR, #11 auto-expand snippets (AX-gated), #12 E2E sync (architectural) — each warrants a focused session. Interactive QA pending.**

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
| `SafeClipCore/` | SPM package: crypto, Keychain, GRDB store, security scanner. **43 tests** — `swift test --package-path SafeClipCore`. |
| `App/` | App sources: `main.swift` (AppKit entry), AppDelegate, AppState, Services/ (incl. `OCRService`, `ScreenOCRService`), MenuBar/, Panel/, Settings/, Onboarding/. |
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
| Login item | `SMAppService` (Debug default OFF, Release ON — see caveats) |
| OCR | Vision `VNRecognizeTextRequest` (on-device) + interactive `screencapture -i` for region select |
| Dist | Paid notarized `.dmg` on Mudit's website (payment gateway); MIT source public for build/audit; MAS deferred |

---

## Build / run
```bash
xcodegen                                                      # only after editing project.yml
xcodebuild -project SafeClip.xcodeproj -scheme SafeClip -configuration Debug build      # GitHub variant
xcodebuild -project SafeClip.xcodeproj -scheme SafeClip-MAS -configuration Debug build  # App Store variant (sandboxed)
open SafeClip.xcodeproj                                       # or work in Xcode
swift test --package-path SafeClipCore                        # core test suite (43 tests)
Scripts/smoke_test.sh                                         # live security assertions (wipes local history!)
```
**Run the RIGHT build (Session-5 lesson):** only ever launch via Xcode ⌘R or `open` the DerivedData `Debug/SafeClip.app`. Do **not** `xcodebuild -derivedDataPath build …` into the repo — that drops stale `.app` copies in `build/` that Spotlight/launchd then launch instead of your latest build (the sandboxed MAS copy was hijacking ⌥C). Debug builds now default `launchAtLogin` **OFF** so a dev build can't register itself as a login item and resurrect itself. To wipe a tangle: kill `SafeClip`, `rm -rf build ~/Library/Developer/Xcode/DerivedData/SafeClip-*`, `tccutil reset All com.mudit.safeclip`, then clean-build.
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
- **Keep scope minimal.** No AI, no sync v1, no browser extension. (PRD §13.) Images/files were added in v0.2.0 by owner decision — encrypted like text, paths-not-contents for files. Screen-region OCR added Session 5 — on-device Vision only, the screenshot is never persisted.
- **Screen-OCR is non-sandboxed-only.** `ScreenOCRService` spawns `/usr/sbin/screencapture`, which the App Sandbox forbids; it self-reports `.unavailable` (env `APP_SANDBOX_CONTAINER_ID`) and shows a toast in a sandboxed build. Fine while MAS is deferred.

---

## Open questions (PRD §19)
- **App name** — "SafeClip" is a working title; check trademark + macOS app-name collisions.
- ~~**Paid vs. free**~~ **Decided (Session 5): paid notarized `.dmg` sold on Mudit's own website via a payment gateway; MIT source stays public for build/audit.** Open: exact price, which gateway.
- ~~**Sandbox stance** — decide at M0.~~ **Decided: non-sandboxed .dmg is the shipping build; MAS deferred until website revenue funds the Apple Developer license.**
- **macOS 16 launch timing** — aim release near macOS 16 GA (fall 2026) for the privacy-narrative tailwind.

---

## Context: how this project started
Mudit uses CopyClip and wanted a clipboard manager that (a) pastes plain text via a special trigger, (b) shows history in a cursor-anchored popup like the emoji viewer, and (c) protects sensitive data (passwords) rather than hoarding everything in plaintext. Research confirmed the exact combination doesn't exist and the encryption + screen-share + hijack-detection gaps are uncontested. This is a separate project from the De-Sludging Project (different folder, different repo) — they share nothing.
