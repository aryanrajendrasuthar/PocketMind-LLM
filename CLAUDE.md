# CLAUDE.md — PocketMind: On-Device LLM for iPhone

> **Development Instruction File**
> Root-level project configuration for all development sessions.

---

## Project Identity

| Field | Value |
|---|---|
| **Product name** | PocketMind |
| **Tagline** | Private, offline AI that runs entirely on your iPhone |
| **Version** | 1.0.0 |
| **Owner** | Aryan Suthar |
| **License** | Proprietary — All Rights Reserved © 2026 Aryan Suthar |
| **Repository** | `github.com/aryanrajendrasuthar/PocketMind-LLM` |
| **Primary language (iOS app)** | Swift 5.10 |
| **Primary language (model tooling)** | Python 3.11 |
| **Target platforms** | iOS 17+ (iPhone 12 and newer) |
| **Minimum device** | A14 Bionic chip (Neural Engine required) |
| **Xcode version** | 16+ |

---

## License Header

Prepend every Swift source file (`.swift`) with:

```swift
//
// PocketMind — On-Device Private LLM for iPhone
// Copyright (c) 2026 Aryan Suthar. All Rights Reserved.
//
// PROPRIETARY AND CONFIDENTIAL
// Unauthorized copying, distribution, modification, or use of this file,
// via any medium, is strictly prohibited without the express written
// permission of the copyright owner.
//
// For licensing inquiries: aryanrajendrasuthar@gmail.com
//
```

Prepend every Python source file (`.py`) with:

```python
# PocketMind — On-Device Private LLM for iPhone
# Copyright (c) 2026 Aryan Suthar. All Rights Reserved.
#
# PROPRIETARY AND CONFIDENTIAL
# Unauthorized copying, distribution, modification, or use of this file,
# via any medium, is strictly prohibited without the express written
# permission of the copyright owner.
#
# For licensing inquiries: aryanrajendrasuthar@gmail.com
```

---

## Build Order / Sprint Plan

### Sprint 1 — Model Pipeline (Week 1–2)
1. Set up `ModelTooling/` Python environment and `requirements.txt`
2. Implement `download_base_model.py` with checksum verification
3. Implement `quantize.py` (Q4_K_M via llama.cpp)
4. Implement `convert_to_coreml.py` with CoreML Tools
5. Implement `validate_model.py` with ROUGE-L scoring
6. Implement `export_metadata.py` with `model_manifest.json` output
7. Run full pipeline for Llama 3.2 1B and verify output
8. Write pytest tests for quantization and conversion scripts

### Sprint 2 — iOS Foundation (Week 3–4)
iOS Xcode project, PrivacyVault, Secure Enclave key derivation.

### Sprint 3 — Core Inference (Week 5–6)
Tokenizer, InferenceEngine actor, MemoryManager actor, KV cache.

### Sprint 4 — Capability Classifier (Week 7)
CapabilityBoundaryClassifier — rule-based + CoreML text classifier.

### Sprint 5 — UI (Week 8–10)
Onboarding, ChatView, CapabilityBoundaryView, SettingsView.

### Sprint 6 — Polish & Hardening (Week 11–12)
Certificate pinning, input sanitization, Instruments profiling, App Store submission.

---

## Code Quality Rules

- Swift strict concurrency enabled: `SWIFT_STRICT_CONCURRENCY = complete`
- Zero force-unwraps in production code
- Zero `print()` calls in production — use `os_log`
- All actors must use structured concurrency, no `DispatchQueue`
- Model names, paths, bundle identifiers: constants in `Constants.swift`
- SwiftLint rules: `force_cast`, `force_try`, `force_unwrapping`, `implicitly_unwrapped_optional`
- Every public function must have a doc comment (`///`)
- Python: flake8 zero errors, mypy strict, pytest for all scripts
