# Privacy Architecture

## Core Guarantee

**No user data ever leaves the device.** This is an architectural guarantee, not a policy promise. There is no server to send data to; inference runs entirely on-device via CoreML.

---

## Data Stored On-Device

| Data Type | Storage Location | Encryption | iOS Data Protection Class |
|---|---|---|---|
| Conversation messages | SQLCipher DB | SQLCipher (Secure Enclave key) | `.completeUnlessOpen` |
| Conversation metadata | SQLCipher DB | SQLCipher | `.completeUnlessOpen` |
| Inference metadata (tok/s, timing) | SQLCipher DB | SQLCipher | `.completeUnlessOpen` |
| Model weights (.mlpackage) | Application Support/models/ | iOS filesystem encryption | `.complete` |
| User preferences (theme, temp) | UserDefaults | No (non-sensitive) | N/A |
| Model download progress | In-memory only | N/A | N/A |

---

## Data Never Collected

- User prompts
- Model responses
- Usage analytics
- Device identifiers
- Crash reports containing any user content

(Crash reporting, if enabled by the user, captures only stack traces — never prompt content or responses.)

---

## Secure Enclave Key Derivation

The SQLCipher database encryption key is derived at runtime:

```
1. Generate EC-P256 key pair in Secure Enclave
   kSecAttrTokenID = kSecAttrTokenIDSecureEnclave
   kSecAttrAccessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

2. Export the public key

3. Perform ECDH with a static app-side EC key
   → shared secret (32 bytes)

4. KDF: HKDF-SHA256(shared_secret, salt="pocketmind.dbkey", info="v1")
   → 32-byte SQLCipher key

5. Open SQLCipher DB with derived key
   → key is never written to disk, exists only in memory while app is foregrounded
```

The Secure Enclave key cannot be extracted from the device — it is hardware-bound. On a different device (or after a factory reset), the key is gone and the DB cannot be decrypted.

---

## Backup Exclusion

All directories containing user data have `isExcludedFromBackup = true` set via:

```swift
var url = URL(fileURLWithPath: dbDirectory)
var resourceValues = URLResourceValues()
resourceValues.isExcludedFromBackup = true
try url.setResourceValues(resourceValues)
```

This prevents conversation data from appearing in iCloud Backup or local iTunes/Finder backups.

---

## Keychain Items

All keychain items (Secure Enclave key reference, any preferences stored in keychain) use:

```swift
kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
```

This ensures keychain items:
- Are inaccessible when the device is locked
- Cannot be migrated to another device (no iCloud Keychain sync)
- Are destroyed on device factory reset

---

## App Transport Security

`Info.plist` configuration:
- `NSAllowsArbitraryLoads = false` (enforced)
- Permitted outbound connections: model download CDN only (certificate pinned)
- No analytics endpoints, no telemetry, no crash reporting URLs unless user opts in

---

## App Store Privacy Labels

Under Apple's privacy nutrition label, PocketMind declares:

**Data Not Collected** across all categories, because:
- No data is transmitted to any server
- No third-party SDKs with tracking are included
- Conversations remain on-device under user control exclusively

This declaration must be re-verified before every App Store submission. Check `PrivacyInfo.xcprivacy` is current.
