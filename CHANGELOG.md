# Changelog

All notable changes to PocketMind are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### In Progress
- Sprint 1: Model optimization pipeline (Python tooling)
- Sprint 2: iOS Foundation — Xcode project, PrivacyVault, Secure Enclave integration

---

## [1.0.0] — TBD

### Added
- On-device LLM inference via CoreML — no internet required
- Support for Llama 3.2 1B Instruct (default), Llama 3.2 3B Instruct, Phi-3 Mini 3.8B Instruct
- INT4 Q4_K_M quantization pipeline via llama.cpp
- CoreML conversion pipeline with ANE optimization
- Streaming token output in SwiftUI chat interface
- CapabilityBoundaryClassifier — prevents silent hallucination of live data
- Encrypted conversation history via SQLCipher + Secure Enclave key derivation
- Memory pressure handling — model unloads and reloads automatically
- KV cache sliding window — drops oldest messages to stay within context limit
- Model download manager — background URLSession, SHA-256 verification, certificate pinning
- Onboarding flow — device RAM detection, model recommendation, download, privacy summary
- Settings — model management, privacy controls, inference parameters
- Voice input via Apple Speech framework (on-device, no cloud transcription)
- Full dark/light mode support via system colors
- Privacy manifest (`PrivacyInfo.xcprivacy`) — Data Not Collected
- All conversation data excluded from iCloud backup
