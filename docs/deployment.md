# App Store Deployment Guide

Complete pre-submission checklist and step-by-step instructions for building,
profiling, and submitting PocketMind to the App Store.

---

## 1. Pre-Submission Checklist

### Privacy & Data
- [ ] `PrivacyInfo.xcprivacy` is complete — `NSPrivacyTracking = false`, no tracking domains
- [ ] App Store Privacy Labels in App Store Connect match `PrivacyInfo.xcprivacy` ("Data Not Collected")
- [ ] `NSAllowsArbitraryLoads = false` in `Info.plist`
- [ ] All conversation data directories verified with `isExcludedFromBackup = true`
- [ ] Keychain items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- [ ] TruffleHog scan passes — no secrets in git history (`make secrets-scan`)

### Code Quality
- [ ] SwiftLint zero warnings (`make lint`)
- [ ] `xcodebuild analyze` zero issues (`make analyze`)
- [ ] All unit tests pass (`make test`)
- [ ] All UI tests pass (`make uitest`)
- [ ] No force-unwraps in any production Swift file
- [ ] No `print()` calls in any production Swift file
- [ ] `SWIFT_STRICT_CONCURRENCY = complete` in build settings
- [ ] All Swift files have the proprietary license header
- [ ] All Python files have the proprietary license header
- [ ] Python: `make py-lint` (flake8 + mypy strict) exits 0
- [ ] Python: `make py-test` exits 0

### Security
- [ ] `PinnedCDNPublicKeyHash` in `Info.plist` is set to the production CDN leaf SPKI SHA-256
- [ ] Certificate pinning verified with Charles Proxy (connection is rejected when intercepted)
- [ ] Input sanitization strips control characters — verified in `ChatViewModelTests`
- [ ] SHA-256 verification runs on every downloaded model file — verified in `ModelDownloadManagerTests`

### Features
- [ ] `CapabilityBoundaryClassifier` tested with ≥ 30 queries (unit test gate)
- [ ] `PrivacyVault.deleteAllData()` verified to wipe DB + WAL + SHM + UserDefaults
- [ ] Memory pressure test passes: Xcode Debug → Simulate Memory Warning during active inference
- [ ] KV cache trimming: system prompt preserved, oldest turns dropped when context fills
- [ ] Model pipeline end-to-end for Llama 3.2 1B: `make pipeline-1b`
- [ ] CoreML model loads on physical iPhone 12 and produces valid output

### Documentation
- [ ] `README.md` complete
- [ ] `docs/architecture.md` complete
- [ ] `docs/privacy-architecture.md` complete
- [ ] `docs/model-optimization.md` complete
- [ ] `docs/offline-limitations.md` complete
- [ ] `SECURITY.md` complete
- [ ] `CHANGELOG.md` has a finalized 1.0.0 entry

### App Store Metadata
- [ ] App name: "PocketMind"
- [ ] Subtitle: "Private AI That Stays On Your iPhone"
- [ ] Description matches `AppStore/metadata.md`
- [ ] Keywords set (`AppStore/metadata.md`)
- [ ] Screenshots prepared for iPhone 16 Pro Max, iPhone SE (3rd gen)
- [ ] App icon at 1024×1024 (no alpha channel, no rounded corners)
- [ ] Age rating: 4+
- [ ] Primary category: Productivity

---

## 2. Certificate Pinning Setup

Before shipping, pin the production CDN leaf certificate:

```bash
# Extract public key hash from the CDN server
openssl s_client -connect models.pocketmind.app:443 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256 -hex \
  | awk '{print $2}'
```

Paste the resulting 64-character hex string into `PocketMind/Supporting Files/Info.plist`
under the key `PinnedCDNPublicKeyHash`. This key is read at runtime by `ModelDownloadManager`.

> When `PinnedCDNPublicKeyHash` is empty the app accepts any valid TLS certificate.
> Always set it before building a Release/TestFlight build.

**Verifying the pin with Charles Proxy:**
1. Install Charles root certificate on the test device.
2. Enable SSL proxying for `models.pocketmind.app`.
3. Attempt a model download in the app.
4. Expected: download immediately fails with "Certificate pin mismatch" in the console log.
5. If download succeeds — pinning is not working; check `Info.plist`.

---

## 3. Instruments Profiling Targets

Run these sessions on a **physical device** before submission:

### Memory — Allocations instrument
Goal: confirm no persistent growth after 10 conversation turns.
1. Product → Profile → Allocations
2. Complete 10 conversation turns (varied prompt lengths)
3. Tap "New Conversation" to reset context
4. Heap growth after reset must be < 5 MB compared to post-launch baseline

### Memory — Leaks instrument
Goal: zero leaks after inference completes.
1. Product → Profile → Leaks
2. Send 5 messages, wait for generation to complete
3. Tap stop — Leaks must show 0 leaked objects

### CPU — Time Profiler
Goal: first-token latency < 3 s on iPhone 12.
1. Product → Profile → Time Profiler
2. Send a prompt; note wall-clock time to first rendered token
3. Target: ≤ 3 s TTFT on iPhone 12 (A14), ≤ 1.5 s on iPhone 15 Pro (A17)

### Energy — Energy Log
Goal: no `CPU_WAKEUP` storm during idle (between inference calls).
1. Run Energy Log while idle on the chat screen for 60 s
2. CPU wakeups must be < 10/min when not generating

### Memory Pressure Simulation
1. Run on device, start an inference
2. Xcode: Debug → Simulate Memory Warning
3. Expected: inference stops, `memoryFreedBanner` appears in ChatView
4. Send another message — model must reload and produce output

---

## 4. TestFlight Build

```bash
# Archive
make release
# Open Xcode Organizer → Distribute App → TestFlight → Upload
# Or using xcode-install + altool:
xcrun altool --upload-app \
  -f build/PocketMind.xcarchive/Products/Applications/PocketMind.app \
  -t ios \
  -u "$APPLE_ID" \
  -p "$APP_SPECIFIC_PASSWORD"
```

**TestFlight test matrix (minimum):**

| Device       | Chip   | RAM  | Model to test |
|---|---|---|---|
| iPhone 12    | A14    | 4 GB | Llama 3.2 1B  |
| iPhone 14    | A15    | 6 GB | Llama 3.2 3B  |
| iPhone 15 Pro| A17 Pro| 8 GB | Phi-3 Mini    |

---

## 5. App Review Notes

Include in the App Review Information field in App Store Connect:

```
PocketMind requires iOS 17+ and an A14 Bionic chip or newer.

The app does not bundle any model weights. During onboarding the user
downloads a quantized LLM (~0.8–2.3 GB) from our CDN over HTTPS.
After download, the app operates entirely offline — no network calls
are made during inference.

The app does not collect any user data. Conversations are encrypted
on-device using a key derived from the Secure Enclave and never leave
the device.

To review the model download flow, you will need a Wi-Fi connection
during onboarding. Subsequent testing requires no network access.
```

---

## 6. Post-Submission

After App Store approval:

1. Tag the release in git: `git tag -s v1.0.0 -m "1.0.0 — initial release"`
2. Push tag: `git push origin v1.0.0`
3. Update `CHANGELOG.md` `[Unreleased]` section with the next cycle
4. Archive the `.xcarchive` with dSYMs for crash symbolication
