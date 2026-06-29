# App Store Deployment Checklist

## Pre-Submission Checklist

### Privacy & Data
- [ ] `PrivacyInfo.xcprivacy` is complete and accurate — "Data Not Collected" for all categories
- [ ] App Store Privacy Labels match `PrivacyInfo.xcprivacy`
- [ ] `NSAllowsArbitraryLoads = false` in `Info.plist`
- [ ] All conversation data directories have `isExcludedFromBackup = true`
- [ ] Keychain items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- [ ] No API keys, tokens, or credentials in the codebase (TruffleHog scan passes)

### Code Quality
- [ ] SwiftLint: zero warnings (`swiftlint --strict`)
- [ ] `xcodebuild analyze`: zero issues
- [ ] All unit tests passing (`xcodebuild test` exits 0)
- [ ] No force-unwraps in any production Swift file
- [ ] No `print()` calls in any production Swift file
- [ ] `SWIFT_STRICT_CONCURRENCY = complete` in build settings
- [ ] All Swift files have the proprietary license header
- [ ] All Python files have the proprietary license header

### Security
- [ ] Certificate pinning implemented for model download CDN
- [ ] Input sanitization strips control characters from user messages
- [ ] Model output stripped of HTML/script tags before display
- [ ] SHA-256 verification runs on every downloaded model file

### Features
- [ ] `CapabilityBoundaryClassifier` tested with ≥ 30 queries
- [ ] `PrivacyVault` `deleteAllData()` verified to wipe all data
- [ ] Memory pressure test passes (model unloads on warning, reloads on next query)
- [ ] KV cache trimming works correctly — oldest messages dropped, system prompt preserved
- [ ] Model pipeline runs end-to-end for Llama 3.2 1B
- [ ] CoreML model loads on physical device and produces valid output

### Documentation
- [ ] `README.md` complete
- [ ] `docs/architecture.md` complete
- [ ] `docs/privacy-architecture.md` complete
- [ ] `docs/model-optimization.md` complete
- [ ] `docs/offline-limitations.md` complete
- [ ] `SECURITY.md` complete
- [ ] `CHANGELOG.md` has a 1.0.0 entry

### App Store Metadata
- [ ] App name: "PocketMind"
- [ ] Subtitle: "Private, Offline AI Assistant"
- [ ] Description written (no mention of internet connectivity required)
- [ ] Screenshots prepared for iPhone 15 Pro Max, iPhone SE (3rd gen), iPad Pro
- [ ] App icon at all required resolutions (1024×1024 base)
- [ ] Age rating: 4+ (no user-generated content shared with others)
- [ ] Category: Productivity

### TestFlight
- [ ] Internal TestFlight build submitted and tested on: iPhone 12, iPhone 14, iPhone 15 Pro
- [ ] All three models verified working on appropriate devices
- [ ] Memory pressure scenario tested on iPhone 12 (lowest supported RAM)
- [ ] Onboarding flow tested from clean install (no existing data)

## App Review Notes

Include in App Review notes:
- This app requires iOS 17+ and an A14 Bionic chip or newer
- The app bundles no model weights — the user downloads the model during onboarding
- No network access is required after model download completes
- The app does not collect any user data
