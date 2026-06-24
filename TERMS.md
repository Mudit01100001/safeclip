# SafeClip — Terms of Use & Disclaimer

_Effective date: on first use of the application._

---

## 1. What SafeClip is

SafeClip is an open-source (MIT-licensed) macOS application that stores a local history of your clipboard contents. All data is stored exclusively on your device. SafeClip has no backend servers, no accounts, no telemetry, and no ability to access or transmit your clipboard data to any third party.

The source code is publicly available at [github.com/Mudit01100001/safeclip](https://github.com/Mudit01100001/safeclip) under the MIT License. You can read, audit, fork, and compile it yourself at no cost. Pre-built, notarized binaries are distributed as a paid download from the SafeClip website; paying for a binary is purely for convenience and support — it grants no additional rights beyond the MIT License (see §6–§7).

SafeClip can also recognize text from a region of your screen on request (the **⌥C** "capture text from screen" shortcut), using Apple's on-device Vision framework. See §3 for what that does with the captured image.

SafeClip can optionally open its panel above the text cursor instead of the mouse pointer. This is **off by default** and requires macOS Accessibility access, which you grant explicitly after an in-app explanation. See §3a for exactly what that access is used for — and what it is never used for.

---

## 2. Your data stays on your device

- SafeClip does not collect, transmit, store remotely, or sell any clipboard data.
- Clipboard history is stored in an encrypted database on your Mac at `~/Library/Application Support/SafeClip/history.db`. The encryption key is stored in your macOS Keychain and never leaves your device.
- No analytics, crash reporting, or usage data of any kind is sent to the developers.

**You are solely responsible for the clipboard history stored on your device.** Protect your Mac with a login password, FileVault encryption, and standard device security practices.

---

## 3. Security limitations — read this

SafeClip takes reasonable steps to protect clipboard history, but you should understand what those steps do and do not guarantee:

**What the encryption protects:**
The history database on disk is AES-256 encrypted. If someone copies the database file, they cannot read your clipboard history without also extracting the Keychain key, which requires physical or administrative access to your unlocked Mac.

**What the encryption does not protect:**

- **The paste window.** When you paste an item, SafeClip writes the plaintext to the macOS system clipboard (`NSPasteboard`) so the receiving app can read it. That plaintext remains on the system clipboard for a brief period (typically under one second) until overwritten. Any application running on your Mac with clipboard access can read it during that window. This is a limitation of the macOS clipboard API and cannot be fully eliminated by any clipboard manager.

- **"Delete after use" is best-effort.** Marking an item "burn after paste" removes it from SafeClip's history database immediately after pasting. It does not — and cannot — guarantee the content was not read from `NSPasteboard` by another process during the paste window described above.

- **Other applications on your Mac.** Until macOS 16, any app running on your Mac can silently read the system clipboard at any time. SafeClip cannot prevent this. SafeClip's encryption protects its own history store; it does not protect the live system clipboard.

- **Physical access.** If someone has physical or remote access to your unlocked Mac, clipboard history may be accessible.

- **Pattern detection is opt-in, not infallible.** If you enable pattern detection for sensitive items (API keys, credit cards, etc.), SafeClip uses heuristics that may miss some patterns or produce false positives. Do not rely on pattern detection as your sole protection for sensitive credentials.

- **Screen-region OCR.** When you use the "capture text from screen" shortcut (⌥C), SafeClip invokes the standard macOS screenshot tool to capture the region you select, writes that screenshot to a temporary file, recognizes its text on-device with Apple's Vision framework, copies the recognized text to your clipboard, and then deletes the temporary screenshot. The image itself is not added to your history. Text recognition is performed entirely on your Mac; the screenshot is not transmitted anywhere. The recognized text becomes a normal clipboard item and is therefore captured into your history like any other copy, and is subject to the same paste-window limitation described above.

---

## 3a. Caret anchoring and Accessibility access (optional)

SafeClip works fully with **no special permissions**. One optional convenience — opening the panel directly above your text cursor instead of the mouse pointer ("Open above the text cursor", Settings → General) — requires macOS **Accessibility** access. It is **off by default**, and turning it on shows an in-app explanation before the macOS permission prompt. Here is precisely what that access does:

- **What SafeClip reads:** only the on-screen rectangle of the focused app's text cursor (insertion point), so it can position the panel above it. It uses the read-only Accessibility queries `kAXFocusedUIElement → kAXSelectedTextRange → kAXBoundsForRange`.
- **What SafeClip never does with it:** it does not read your keystrokes, does not read the text in the field, does not read any other app's content, and never synthesizes input — you always press ⌘V yourself.
- **Chromium/Electron apps.** Apps built on Chromium/Electron (e.g. Claude for Desktop, Arc) do not expose their cursor position until an assistive client asks them to. With the optional "Also find the cursor in Chromium/Electron apps" sub-setting enabled, SafeClip sets the `AXManualAccessibility` attribute on the focused such app to switch on its accessibility information. **This is the only thing SafeClip writes through the Accessibility API, and it only enables reading the cursor position** — it injects no input and reads no text. You can disable this sub-setting to keep SafeClip strictly read-only and limited to native apps.
- **Revoking.** You can revoke Accessibility access at any time in System Settings → Privacy & Security → Accessibility; SafeClip then falls back to anchoring the panel at the mouse pointer.

---

## 4. Passwords and sensitive credentials

SafeClip is not designed to be a secure vault for passwords or credentials. If you copy a password from a password manager:

- SafeClip will capture it unless you have explicitly added that app to the exclusion list (opt-in feature).
- Even with "delete after use" enabled, the brief paste window applies.
- For maximum protection, use your password manager's built-in auto-fill feature instead of copying and pasting passwords manually.

The developers are not liable for any credential exposure that occurs through normal use of the macOS clipboard.

---

## 5. No warranty

SafeClip is provided "as is", without warranty of any kind, express or implied, including but not limited to warranties of merchantability, fitness for a particular purpose, and non-infringement. The full warranty disclaimer is in the [MIT License](LICENSE).

In no event shall the SafeClip contributors be liable for any claim, damages, or other liability arising from the use of the software, including but not limited to data loss, credential exposure, security incidents, or loss of business.

---

## 6. Open source — your rights

SafeClip is licensed under the MIT License. You are free to:

- Use the software for any purpose, personal or commercial.
- Read and audit the full source code.
- Modify and distribute your own version.
- Compile and run it yourself rather than using a pre-built binary.

The only requirement is that you include the original copyright notice and license text in any copy or substantial portion of the software.

---

## 7. Pre-built binaries

Pre-built binaries are distributed as a paid download from the SafeClip website. Building from source (per §6) remains free and is the highest-trust path. If you use a pre-built binary rather than compiling from source:

- Binaries are notarized with Apple's notarisation service, which checks for known malware. Notarisation is not an endorsement and does not guarantee the absence of all vulnerabilities.
- You are trusting that the binary matches the source code in this repository. We encourage users with high security requirements to compile from source.
- Payment is for the convenience of a signed, notarized build and to support development; it does not alter the MIT License terms or create any warranty (see §5).

---

## 8. Third-party dependencies

SafeClip uses the following open-source libraries, each under their own licenses:

- `GRDB.swift` — SQLite database (MIT License)
- `KeyboardShortcuts` — Global hotkey registration (MIT License)

These libraries are not affiliated with SafeClip. They are fetched as pinned Swift Package Manager dependencies; their source code and licenses are available in their respective GitHub repositories.

---

## 9. Changes to these terms

Because SafeClip has no accounts or backend, we cannot notify you of changes to these terms directly. Updated terms will be included in each new release and committed to the repository. Continued use of a new version constitutes acceptance of the terms included with that version.

---

## 10. Contact

This is an open-source project. For questions, security disclosures, or bug reports, please open an issue at [github.com/Mudit01100001/safeclip/issues](https://github.com/Mudit01100001/safeclip/issues).

For security vulnerabilities, please use GitHub's private security advisory feature rather than a public issue.
