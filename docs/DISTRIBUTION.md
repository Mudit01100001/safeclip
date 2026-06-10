# SafeClip — Distribution Channels

_One repo, one codebase, two targets. Created Session 4 (June 2026) when the
"no Mac App Store" decision was revised to dual-channel. Do **not** fork the
project into separate folders per channel — the variants share every source
file and would silently diverge._

## The two targets

| | `SafeClip` (GitHub) | `SafeClip-MAS` (App Store) |
|---|---|---|
| Sandbox | None (by design) | **App Sandbox** (MAS requirement) |
| Entitlements | `Config/SafeClip.entitlements` (empty) | `Config/SafeClip-MAS.entitlements` (sandbox + user-selected files) |
| Hardened Runtime | On (notarization requires it) | On (harmless) |
| Release signing | **Developer ID Application** + notarization | **Apple Distribution** + provisioning profile |
| Ships as | Notarized `.dmg` on GitHub Releases (`Scripts/release.sh`) | App Store Connect upload (Xcode Organizer / Transporter) |
| History location | `~/Library/Application Support/SafeClip/` | `~/Library/Containers/com.mudit.safeclip/Data/Library/Application Support/SafeClip/` |
| Bundle ID | `com.mudit.safeclip` | `com.mudit.safeclip` (same app, one channel installed at a time) |

Build either locally:

```bash
xcodebuild -project SafeClip.xcodeproj -scheme SafeClip     build   # GitHub variant
xcodebuild -project SafeClip.xcodeproj -scheme SafeClip-MAS build   # App Store variant
```

## What the sandbox does and doesn't change

Everything SafeClip does survives the sandbox — verified by building and
booting the MAS target:

- ✅ Pasteboard polling, reading, and writing (incl. images and file URLs)
- ✅ Global hotkey (Carbon `RegisterEventHotKey` via KeyboardShortcuts)
- ✅ Keychain master key
- ✅ `SMAppService` login item, `NSWorkspace.frontmostApplication` (ClickFix)
- ✅ Exclusion-list app picker and history export (powerbox panels, covered by
  the `user-selected.read-write` entitlement)

What actually differs:

- **Separate history stores.** The sandboxed build lives in its container, so
  switching channels starts with an empty history (the Keychain key is shared,
  so old databases remain decryptable if manually moved into the container).
- **File-copy paste-back nuance.** SafeClip never opens captured files itself
  (paths-not-contents by design), so capture and paste-back work sandboxed.
  The *receiving* app's own permissions govern whether it can use a pasted
  file URL — same as any sandboxed source app.

## App Store submission checklist (the parts no script can do)

1. Paid Apple Developer account; create the app record in App Store Connect
   for `com.mudit.safeclip`.
2. **App icon** — required for MAS validation; the repo currently ships no
   asset catalog (menu-bar template symbols only). Blocking.
3. Apple Distribution certificate + Mac App Store provisioning profile;
   archive the `SafeClip-MAS` scheme in Xcode → Organizer → upload.
4. Privacy nutrition label: "Data Not Collected" (truthfully — no network).
5. Review notes: explain the clipboard-manager category precedent (Maccy et
   al. are on MAS), the one-time pasteboard consent prompt, and that paste
   requires the user's own ⌘V (no Accessibility).
6. TERMS.md §7 mentions GitHub binaries — App Store builds are governed by
   Apple's standard EULA as well; revisit wording before MAS launch.

## GitHub release (unchanged)

`Scripts/release.sh` — needs `DEVELOPER_ID` + `NOTARY_PROFILE` env vars; does
build → sign → notarize → staple → dmg + checksum.
