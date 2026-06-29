# App Store Metadata — PocketMind

## App Name
PocketMind

## Subtitle (30 chars max)
Private AI That Stays On Your iPhone

## Category
Primary: Productivity
Secondary: Utilities

## Description (4000 chars max)

PocketMind brings powerful AI to your iPhone — without sending a single word to the cloud.

Every conversation stays on your device. There are no servers, no accounts, and no internet required after the one-time model download. Your questions, your answers, your ideas — they never leave your phone.

**How it works**
PocketMind runs a quantized large language model directly on your iPhone's Neural Engine and GPU. Using Apple's CoreML framework, it achieves fast, private inference that rivals cloud-based assistants for most everyday tasks.

**What PocketMind can do**
- Answer questions, explain complex topics, and write or edit text
- Help with coding, math, analysis, and brainstorming
- Work completely offline — no Wi-Fi needed after downloading the model
- Respond in seconds using your iPhone's Neural Engine

**Privacy by design**
- Zero data collection — no analytics, no telemetry, no crash reports are sent anywhere
- Conversations are encrypted using a key derived from your Secure Enclave, readable only on your device
- All data is excluded from iCloud backup
- No account or sign-in required

**Choose your model**
PocketMind automatically recommends the best model for your device:
- Llama 3.2 1B — iPhone 12 and newer, fastest responses
- Llama 3.2 3B — iPhone 14 and newer, better quality
- Phi-3 Mini 3.8B — iPhone 15 Pro and newer, highest capability

**Honest about limitations**
PocketMind's knowledge comes from model training data, not the live internet. It will tell you clearly when a question requires up-to-date information (stock prices, weather, breaking news) rather than guessing.

**Technical highlights**
- INT4 quantized models via llama.cpp for minimal storage footprint
- Streaming token output — see responses as they're generated
- Automatic context management — older messages are trimmed gracefully when approaching the context limit
- Memory pressure handling — the model unloads automatically under low-memory conditions and reloads on next use
- Voice input via Apple's on-device Speech framework

PocketMind is for anyone who wants a capable AI assistant that respects their privacy. No subscriptions, no data harvesting, no compromises.

## Keywords (100 chars max, comma-separated)
AI,offline,private,LLM,on-device,assistant,llama,phi,chat,no internet,privacy,secure,neural engine

## Support URL
https://github.com/aryanrajendrasuthar/PocketMind-LLM

## Marketing URL
https://github.com/aryanrajendrasuthar/PocketMind-LLM

## Privacy Policy URL
_(to be hosted — can link to docs/privacy-architecture.md content)_

---

## Age Rating
4+ (no user-generated content shared externally)

## Content Rights
All model weights are governed by their respective open-source licenses (Meta Llama Community License, MIT for Phi-3).
App code is proprietary — Copyright © 2026 Aryan Suthar.

---

## What's New in 1.0 (Release Notes)
PocketMind 1.0 — initial release.

- Private, offline AI running entirely on your iPhone
- Support for Llama 3.2 1B, Llama 3.2 3B, and Phi-3 Mini 3.8B
- Secure Enclave-encrypted conversation history
- Voice input via on-device speech recognition
- Capability classifier — warns you when a question needs live internet data

---

## App Store Privacy Labels

### Data Not Collected
PocketMind does not collect any data from users.

**Tracking:** No
**Linked to you:** None
**Used to track you:** None

### Data Used to Track You
None.

### Data Linked to You
None.

### Data Not Linked to You
None.

---

## TestFlight Notes (Internal)

Build pre-conditions:
- [ ] All unit tests pass on CI
- [ ] Model download tested on physical device (iPhone 12, 14, 15 Pro)
- [ ] Memory warning simulation tested via Xcode (Debug → Simulate Memory Warning)
- [ ] Certificate pinning tested with Charles Proxy (connection must be rejected)
- [ ] Voice input tested with AirPods and built-in mic
- [ ] Dark mode tested on all simulator sizes
- [ ] Onboarding flow tested: fresh install, model already downloaded
- [ ] SwiftLint: zero warnings
- [ ] Instruments: no memory leaks after 10 conversation turns
- [ ] TruffleHog: no secrets in git history
