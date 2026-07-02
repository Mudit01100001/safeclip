# SafeClip — Privacy Policy

_Effective date: 2 July 2026 (updated for the update-check feature). Applies to all versions of SafeClip._

---

Short version: **SafeClip collects nothing. Your clipboard data never leaves your device.** The one exception is an optional update check, covered in §1 and §4 below.

---

## 1. Data we collect

None of your personal or clipboard data. SafeClip is a local-only application: no accounts, no usage statistics, no analytics, no crash reports, no telemetry of any kind. Your clipboard content never leaves your Mac.

The one network request SafeClip can make is an **update check**: a request to `safeclip.app` asking "is there a version of SafeClip newer than mine." It contains no clipboard content, no personal data, and no device-identifying profile (SafeClip explicitly disables the update framework's optional system-profile reporting). This check never happens on its own unless you turn on "Automatically check for updates" in Settings → Updates; otherwise it only runs when you click "Check for Updates…" yourself. See §4.

---

## 2. Data SafeClip stores on your device

SafeClip stores your clipboard history in an encrypted database on your Mac:

| What | Where |
|------|-------|
| Clipboard history (text, images, file paths) | `~/Library/Application Support/SafeClip/history.db` |
| Encryption key | Your macOS Keychain — never leaves your device |

**Encryption:** Every item is encrypted individually with AES-256-GCM and a unique random nonce. The database file reveals nothing without the Keychain key.

**Your control:** You can delete all history at any time via Settings → Advanced → Clear All History. Deleted items are zeroed in the database file (`secure_delete`), not just unlinked.

---

## 3. What we do not collect

- Names, email addresses, or contact information
- Device identifiers, IP addresses, or location data
- Usage statistics or behavioural analytics
- Crash reports or error logs sent to any server
- Clipboard contents (your data never leaves your Mac)
- Advertising or marketing identifiers of any kind

---

## 4. Third-party services

SafeClip uses no third-party analytics, advertising, tracking, or cloud services.

**Update checks (opt-in / manual):** SafeClip's only network functionality is checking `safeclip.app/appcast.xml` for a newer version, using the open-source [Sparkle](https://sparkle-project.org) framework. This is off by default and never runs on a schedule unless you enable "Automatically check for updates" in Settings → Updates; you can always trigger a one-off check yourself via "Check for Updates…" in the menu bar. The request carries no clipboard content and no device profile (system-profile reporting is disabled in SafeClip's configuration). If a newer version exists, you're shown release notes and choose whether to install; nothing installs silently. Each release is signed with a private key only Mudit holds, and SafeClip verifies that signature before installing anything it downloads.

Open-source dependencies (none transmit clipboard data; Sparkle is the only one that makes network requests, and only for the update check described above):
- **GRDB.swift** (MIT Licence) — local SQLite database
- **KeyboardShortcuts** (MIT Licence) — global hotkey registration
- **Sparkle** (MIT Licence) — update checking, GitHub-channel build only

---

## 5. Your rights under the DPDP Act 2023

Under India's Digital Personal Data Protection Act 2023 and other applicable law:

- **Right to access** — All data SafeClip holds is on your own device. You can export it via Settings → Advanced → Export History.
- **Right to erasure** — Delete individual items from the panel, or all history via Settings → Advanced → Clear All History.
- **Right to withdraw consent** — Uninstall SafeClip and delete `~/Library/Application Support/SafeClip/` at any time. There is no account to close.
- **Right to grievance redressal** — Contact the Grievance Officer listed in §7 below.

---

## 6. Security measures

| Measure | Detail |
|---------|--------|
| Encryption at rest | AES-256-GCM, per-item nonce |
| Key storage | macOS Keychain, locked to app code signature |
| Dedup index | Keyed HMAC (prevents offline guessing from database) |
| Deletion | `secure_delete` — bytes zeroed on removal |
| Clipboard wipe | Optional: SafeClip can overwrite the system clipboard after pasting a sensitive item (35 s default, configurable) |

For a full account of what the encryption protects and what it does not, see [TERMS.md](TERMS.md) §3.

---

## 7. Grievance Officer

In accordance with India's Digital Personal Data Protection Act 2023:

**Mudit Ahlawat**
Email: m14ahlawat@gmail.com
GitHub: [github.com/Mudit01100001/safeclip/issues](https://github.com/Mudit01100001/safeclip/issues)

Grievances are acknowledged within 72 hours and resolved within 7 working days.

---

## 8. Children's data

SafeClip collects no personal data from anyone, including children.

---

## 9. Data breach notification

In the event of a security incident affecting personal data processed by SafeClip (not currently applicable as we collect none), we will notify affected users and the Data Protection Board of India within 72 hours of becoming aware of the breach.

---

## 10. Changes to this policy

Updated versions are committed to the repository and included in new releases. The effective date at the top of this document reflects the most recent revision. Continued use of a new version constitutes acceptance of the updated policy.

---

## 11. Contact

- GitHub issues: [github.com/Mudit01100001/safeclip/issues](https://github.com/Mudit01100001/safeclip/issues)
- Security disclosures: use GitHub's private security advisory feature, not a public issue
- Grievance Officer email: m14ahlawat@gmail.com
