# Security Policy

## Supported Versions

| Version | Supported |
|---|---|
| 1.0.x | Yes |

---

## Reporting a Vulnerability

**Do not file a public GitHub issue for security vulnerabilities.**

Report vulnerabilities privately by email:

**Email:** aryanrajendrasuthar@gmail.com  
**Subject line:** `[SECURITY] PocketMind — <brief description>`

### Response Timeline

| Stage | SLA |
|---|---|
| Acknowledgement | Within 48 hours |
| Initial assessment | Within 5 business days |
| Patch for Critical/High | Within 14 days |
| Patch for Medium | Within 30 days |
| Patch for Low | Next scheduled release |

---

## Threat Model

PocketMind is a fully local, offline iOS app. There is no backend, no API server, and no user accounts.

### Primary Attack Surface

| Threat | Mitigation |
|---|---|
| Physical device access (unlocked) | SQLCipher encryption + Secure Enclave key derivation; data inaccessible without device passcode |
| Physical device access (locked) | iOS Data Protection `.complete` on model weights; `.completeUnlessOpen` on conversation data |
| Malicious model file | SHA-256 checksum verified against signed manifest before any model file is used |
| Network interception during model download | HTTPS + certificate pinning on model CDN; download aborted if certificate hash does not match |
| Prompt injection via user input | Input sanitization strips control characters; output stripped of HTML/script tags |
| Supply chain compromise | Dependencies pinned in `requirements.txt` with hashes; weekly `pip-audit` + `swift package audit` in CI |

### Out of Scope

The following are explicitly out of scope for this security policy:

- Issues that require physical device access **with the device passcode already known** — at that point, the attacker controls the device OS
- Theoretical attacks with no demonstrated proof of concept
- Denial-of-service through repeated inference (this is a local resource exhaustion, not a security vulnerability)
- Privacy concerns that do not involve data leaving the device

---

## Security Architecture Summary

- **No network calls during inference** — all LLM processing is local
- **Encrypted conversation storage** — SQLCipher with a key derived from the Secure Enclave
- **iCloud backup excluded** — all user data directories have `isExcludedFromBackup = true`
- **Keychain access** — `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` on all keychain items
- **No hardcoded secrets** — no API keys, tokens, or credentials exist in the codebase
- **Certificate pinning** — model download CDN leaf certificate is pinned
- **Privacy manifest** — `PrivacyInfo.xcprivacy` accurately declares zero data collection

---

## Contact

Aryan Suthar — aryanrajendrasuthar@gmail.com
