# SafeClip

**The clipboard manager that doesn't betray you** — encrypted history, plain-text paste, and a picker that appears right where you're typing.

Every mainstream macOS clipboard manager stores your history as plaintext on disk, where any disk image, Time Machine backup, or curious process can read it. SafeClip doesn't.

## What makes it different

| | SafeClip | Maccy | Paste | CleanClip | Raycast |
|---|:---:|:---:|:---:|:---:|:---:|
| Encrypted history store (AES-256-GCM) | ✅ | ❌ | ❌ | ❌ | ❌ |
| Panel opens at your cursor | ✅ | ❌ | ❌ | ✅ | ❌ |
| Plain-text paste by default (⌥↩ keeps formatting) | ✅ | ❌ | ❌ | ❌ | ❌ |
| Hides history while screen recording | ✅ | ❌ | ❌ | ❌ | ❌ |
| Pastejacking (ClickFix) warnings | ✅ | ❌ | ❌ | ❌ | ❌ |
| Zero special permissions at launch | ✅ | ✅ | ✅ | ✅ | ❌ |
| Open source | ✅ | ✅ | ❌ | ❌ | ❌ |

## How it works

- Press **⌃⇧V** (configurable) — a floating panel opens **at your mouse cursor**, like the emoji picker. Your app keeps focus.
- Type to search. **Return** pastes plain text; **⌥Return** keeps the original formatting.
- SafeClip puts the item on the clipboard — **you press ⌘V**. That one extra keypress is deliberate: simulating ⌘V would require the Accessibility permission (keystroke-injection power). SafeClip launches with **zero special permissions**.

## Security model — the honest version

**What's protected**
- History is encrypted on disk with AES-256-GCM, a fresh random nonce per item. `strings history.db` shows nothing.
- The key lives in your macOS **Keychain**, never leaves your device, never syncs to iCloud.
- The dedup index is a *keyed* HMAC, not a plain hash — a copied password can't be offline-guessed from the database file.
- Deleted items (burn-after-paste, Clear All) are zeroed in the database file (`secure_delete`), not just unlinked.
- Password-manager copies (marked `org.nspasteboard.ConcealedType`) are flagged, masked in the panel, and optionally burned after one paste. After pasting a sensitive item SafeClip can wipe the system clipboard if nothing replaced it (35s default).
- No servers, no accounts, no telemetry, no analytics. The code is right here.

**What's not protected — read [TERMS.md](TERMS.md) §3**
- **The paste window.** When you paste, the plaintext briefly sits on the macOS system clipboard where other running apps could read it. True of every clipboard manager; no public API avoids it. We disclose it instead of pretending.
- The encryption protects SafeClip's *store*, not the live system clipboard (which Universal Clipboard syncs to your other Apple devices).
- "Burn after paste" is best-effort cleanup, not a cryptographic guarantee.

**Images and files too (v0.2.0)**
- Copied images land in history encrypted (PNG-normalized, up to 10 MB) with an encrypted thumbnail for the panel preview — a screenshot in your history is as unreadable on disk as a password.
- Finder file copies store the file *locations* (not contents); pasting re-references the original files. Both capture kinds can be switched off in Settings.
- On macOS Tahoe the panel wears the system's Liquid Glass material; older macOS gets the classic translucent material.

**Opt-in extras** (off by default — you decide)
- Pattern detection: flags API keys (`ghp_`, `sk-`, `AKIA`…), Luhn-valid card numbers, private key blocks.
- ClickFix detection: warns when a *website* overwrote your clipboard with something that looks like a shell command — the #1 macOS malware-delivery trick of 2025. Warns, never blocks.
- App exclusion list: copies from apps you choose are never stored at all.

## Install

**Download:** grab the notarized `.dmg` from [Releases](https://github.com/Mudit01100001/safeclip/releases). On first capture, macOS may show a one-time clipboard-access prompt — choose *Always Allow*.

**Build from source** (the high-trust path):

```bash
git clone https://github.com/Mudit01100001/safeclip.git
cd safeclip
brew install xcodegen   # if needed
xcodegen
xcodebuild -project SafeClip.xcodeproj -scheme SafeClip -configuration Release build
```

Requires Xcode 16+ / macOS 14+. Run the test suite with `cd SafeClipCore && swift test`.

## Project layout

| Path | What |
|------|------|
| `SafeClipCore/` | Swift package: encryption, Keychain, GRDB store, security scanner — fully unit-tested, no UI |
| `App/` | The app: status item, floating panel, settings, onboarding |
| `docs/DESIGN.md` | How the three UI surfaces work as one app |
| `docs/ROADMAP.md` | Milestones, research log, decisions |
| `PRD.md` | Full product spec |
| `TERMS.md` | Terms of Use — including the disclosed limitations |

Dependencies: [GRDB.swift](https://github.com/groue/GRDB.swift) (MIT) and [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT). Both pinned, both auditable.

## License

MIT — see [LICENSE](LICENSE). Security disclosures: see [SECURITY.md](SECURITY.md).
