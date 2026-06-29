# PocketMind

**Private, offline AI that runs entirely on your iPhone.**

PocketMind is an on-device large language model app for iOS. Every inference happens locally — your prompts, responses, and conversation history never leave your device.

---

## Privacy Guarantee

- No internet connection required for inference
- No user data collected or transmitted
- All conversations encrypted on-device with SQLCipher + Secure Enclave key derivation
- App Store Privacy Labels: Data Not Collected

---

## Supported Devices & Models

| Model | Parameters | INT4 Size | Min Device |
|---|---|---|---|
| Llama 3.2 1B Instruct | 1B | ~0.6 GB | iPhone 12 (A14) |
| Llama 3.2 3B Instruct | 3B | ~1.8 GB | iPhone 14 (A15) |
| Phi-3 Mini 3.8B Instruct | 3.8B | ~2.3 GB | iPhone 15 Pro (A17) |

Model selection during onboarding is automatic — PocketMind detects available RAM and recommends the right model for your device.

---

## Architecture Overview

```
User Input
    │
    ▼
CapabilityBoundaryClassifier   ← filters live-data queries before inference
    │
    ▼
InferenceEngine (actor)        ← CoreML model, streaming AsyncStream<InferenceToken>
    │
    ▼
MemoryManager (actor)          ← KV cache, sliding window, memory pressure handling
    │
    ▼
PrivacyVault (actor)           ← SQLCipher encrypted conversation store
    │
    ▼
SwiftUI Chat View              ← streaming token display
```

All components run on-device. No network calls during inference.

---

## Prerequisites

- **macOS 14+** with **Xcode 16+** for iOS development
- **Python 3.11** for model tooling pipeline
- **llama.cpp** for GGUF quantization
- **coremltools 7.2+** for CoreML conversion
- **HuggingFace account** (free) for model downloads

---

## Local Development Setup

### 1. Clone the repository

```bash
git clone https://github.com/aryanrajendrasuthar/PocketMind-LLM.git
cd PocketMind-LLM
```

### 2. Run the model pipeline (Sprint 1)

```bash
cd ModelTooling
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Download base model (Llama 3.2 1B by default)
python scripts/download_base_model.py --model llama32_1b

# Quantize to INT4 Q4_K_M
python scripts/quantize.py --model llama32_1b

# Convert to CoreML
python scripts/convert_to_coreml.py --model llama32_1b

# Validate output quality
python scripts/validate_model.py --model llama32_1b

# Export model manifest
python scripts/export_metadata.py --model llama32_1b
```

### 3. Run model tooling tests

```bash
cd ModelTooling
pytest tests/ -v
```

### 4. Open the iOS project

```bash
open PocketMind/PocketMind.xcodeproj
```

Build and run on an iPhone 12 or newer (iOS 17+) or the iOS Simulator.

### 5. Run iOS unit tests

```bash
xcodebuild test \
  -scheme PocketMind \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

---

## Running Tests

| Test Suite | Command |
|---|---|
| Python model tooling | `cd ModelTooling && pytest tests/ -v` |
| iOS unit tests | `xcodebuild test -scheme PocketMind -destination 'platform=iOS Simulator,name=iPhone 15 Pro'` |
| SwiftLint | `swiftlint` |
| Static analysis | `xcodebuild analyze -scheme PocketMind` |

---

## Documentation

| Document | Description |
|---|---|
| [Architecture](docs/architecture.md) | Full system design and data flow |
| [Model Optimization](docs/model-optimization.md) | Quantization, pruning, distillation guide |
| [CoreML Conversion](docs/coreml-conversion.md) | Step-by-step conversion pipeline |
| [Privacy Architecture](docs/privacy-architecture.md) | On-device privacy guarantees |
| [Memory Management](docs/memory-management.md) | Layer swapping and KV cache design |
| [Offline Limitations](docs/offline-limitations.md) | What the model can and cannot do offline |
| [Deployment](docs/deployment.md) | App Store submission checklist |
| [Security Policy](SECURITY.md) | Vulnerability disclosure policy |
| [Changelog](CHANGELOG.md) | Version history |

---

## License

Proprietary — All Rights Reserved © 2026 Aryan Suthar.

See [LICENSE](LICENSE) for full terms. Unauthorized use, copying, or distribution is strictly prohibited.

For licensing inquiries: aryanrajendrasuthar@gmail.com
