# Changelog

All notable changes to PocketMind are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] — 2026-06-28

### Added

**Model Pipeline (Sprint 1)**
- Python toolchain for INT4 Q4_K_M quantization via llama.cpp (`quantize.py`)
- CoreML conversion pipeline targeting iOS 17, ANE+GPU+CPU compute units (`convert_to_coreml.py`)
- SHA-256 checksum verification on all downloaded base model weights (`download_base_model.py`)
- ROUGE-L quality gate (minimum 0.90) on HuggingFace vs. CoreML output (`validate_model.py`)
- `model_manifest.json` export with device requirements and SHA-256 digest (`export_metadata.py`)
- TF-IDF + LogisticRegression capability classifier training pipeline (`train_classifier.py`)
- Model configs for Llama 3.2 1B, Llama 3.2 3B, Phi-3 Mini 3.8B (`ModelTooling/configs/`)
- pytest suites for quantization, CoreML conversion, and classifier training

**iOS Foundation (Sprint 2)**
- Xcode project generated via XcodeGen with `SWIFT_STRICT_CONCURRENCY = complete`
- `SecureEnclaveKeyManager` — EC-P256 Secure Enclave key → ECDH → HKDF-SHA256 → 32-byte database key
- `PrivacyVault` actor — SQLCipher-encrypted conversation storage, WAL mode, 256k PBKDF2 iterations
- `PrivacyInfo.xcprivacy` — `NSPrivacyTracking = false`, zero tracking domains, Data Not Collected label
- All conversation data and model files excluded from iCloud backup (`isExcludedFromBackup = true`)
- SwiftLint configuration with `force_cast`, `force_try`, `force_unwrapping` rules enabled

**Core Inference (Sprint 3)**
- `Tokenizer` — BPE tokenizer loading from HuggingFace `tokenizer.json` with SentencePiece `▁` convention
- `InferenceEngine` actor — async CoreML model loading, `AsyncStream<InferenceToken>` generation
- Temperature scaling → softmax → top-p nucleus sampling
- `MemoryManager` actor — proactive RAM polling, `UIApplication.didReceiveMemoryWarningNotification` handler
- KV cache sliding window — drops oldest message pairs to stay within context budget
- `task_vm_info_data_t` Mach call for accurate per-process memory measurement

**Capability Classifier (Sprint 4)**
- `QueryCapability` — three-case enum: `.fullyOffline`, `.requiresLiveData`, `.requiresSearch`
- `ClassifierRules` — six domain categories (Finance, Weather, News, Sports, Business hours, Rates)
- `CapabilityBoundaryClassifier` — two-stage: keyword rule engine + CoreML `NLModel` (confidence ≥ 0.75)
- `offlineSafeModifiers` guard prevents false positives on academic phrasing ("explain the current state of…")
- Word-boundary-aware matching preventing substring collisions

**UI (Sprint 5)**
- `ModelInfo` — typed model metadata with hardware compatibility checks by available RAM
- `ModelDownloadManager` — background `URLSessionDownloadTask`, SHA-256 verification, certificate pinning, cellular guard
- `VoiceInputService` — on-device `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`
- Four-step onboarding: Welcome → Model Selection (RAM-aware auto-recommend) → Download → Complete
- `ChatViewModel` — integrates Classifier + InferenceEngine + MemoryManager + PrivacyVault
- Input sanitization: control-character stripping, 4,000-character hard cap against prompt injection
- `ChatView` — streaming `ScrollView` with auto-scroll, voice input bar, stop/send toggle
- `MessageBubbleView` — user/assistant bubbles, code block rendering, per-response performance metadata
- `TypingIndicatorView` — staggered animated three-dot indicator
- `CapabilityBoundaryView` — sheet explaining live-data limitations, proceed/dismiss actions
- `SettingsView` — temperature, top-p, max-tokens sliders; cellular download toggle; colour scheme picker; delete all

**Hardening (Sprint 6)**
- `NetworkMonitor` — `NWPathMonitor` singleton replacing development stub; wired into `AppDelegate`
- Eliminated all force-unwraps in production code; `as! SecKey` guarded with `CFGetTypeID` check
- URL construction uses `appendingPathComponent` API (no interpolated force-unwrap)
- Added `ModelInfoTests`, `ModelDownloadManagerTests`, `ChatViewModelTests` test suites
- GitHub Actions CI: SwiftLint strict → xcodebuild → xcodebuild test → TruffleHog (iOS)
- GitHub Actions CI: flake8 → mypy strict → pytest (Python)
- Weekly security scan: CodeQL (Swift + Python), TruffleHog full history, pip-audit

### Security
- Zero network calls during inference — model runs entirely on-device
- Certificate pinning on model CDN (SPKI SHA-256 hash via `Info.plist` key `PinnedCDNPublicKeyHash`)
- All keychain items: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- App Transport Security: `NSAllowsArbitraryLoads = false`

---

## [Unreleased]

_Pending TestFlight beta and App Store submission._
