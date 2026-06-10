# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Use GitHub's private vulnerability reporting: **Security → Report a vulnerability** on this repository. You'll get a response within 7 days.

## Scope

SafeClip's security promises (and their limits) are spelled out in [TERMS.md](TERMS.md) §3 and the threat model in [PRD.md](PRD.md) §8. Reports are especially welcome for:

- Plaintext clipboard content reaching disk (database, logs, crash dumps, temp files)
- The Keychain master key being readable by another process or user
- Nonce reuse or other cryptographic misuse in `SafeClipCore`
- The capture pipeline storing content from excluded apps or transient/concealed pasteboards when it shouldn't
- Bypass of the burn-after-paste deletion or `secure_delete` behaviour

Out of scope (disclosed limitations, not bugs):

- Content readable from `NSPasteboard` during a paste (the "paste window")
- Universal Clipboard syncing the live clipboard to the user's other devices
- Heuristic misses in pattern/ClickFix detection (best-effort by design)

## Supported versions

The latest release only.
