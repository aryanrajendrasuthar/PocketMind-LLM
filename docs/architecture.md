# System Architecture

## Overview

PocketMind processes every request entirely on-device. The architecture is a linear pipeline with a privacy-first boundary check before any inference occurs.

```
┌─────────────────────────────────────────────────────────┐
│                        SwiftUI                          │
│   ChatView / OnboardingView / SettingsView              │
└────────────────────────┬────────────────────────────────┘
                         │ user query
                         ▼
┌─────────────────────────────────────────────────────────┐
│            CapabilityBoundaryClassifier                 │
│  rule-based + CoreML text classifier                    │
│  → .fullyOffline | .requiresLiveData | .requiresSearch  │
└────────────┬──────────────────────────┬─────────────────┘
             │ .fullyOffline            │ .requiresLiveData
             ▼                          ▼
┌────────────────────────┐  ┌──────────────────────────────┐
│    InferenceEngine     │  │   CapabilityBoundaryView     │
│    (Swift actor)       │  │   (inform user, allow skip)  │
│                        │  └──────────────────────────────┘
│  CoreML .mlpackage     │
│  Tokenizer (vocab JSON)│
│  AsyncStream<Token>    │
└────────────┬───────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────┐
│                    MemoryManager                        │
│    (Swift actor)                                        │
│    os_proc_available_memory() monitoring                │
│    KV cache sliding window (4096 token cap)             │
│    UIApplication memory warning → unloadModel()         │
└────────────┬────────────────────────────────────────────┘
             │ save message
             ▼
┌─────────────────────────────────────────────────────────┐
│                     PrivacyVault                        │
│    (Swift actor)                                        │
│    SQLCipher encrypted SQLite                           │
│    Key: Secure Enclave EC-P256 derived secret           │
│    isExcludedFromBackup = true                          │
└─────────────────────────────────────────────────────────┘
```

---

## CoreML Model Loading Flow

```
App launch
    │
    ├─ ModelDownloadManager checks Application Support/models/
    │       │
    │       ├─ Model present + SHA-256 verified → ready
    │       └─ Model absent → trigger OnboardingFlow download
    │
First inference request
    │
    └─ InferenceEngine.generate() called
            │
            ├─ isLoaded() == false → Task(priority: .userInitiated) { loadModel() }
            │       │
            │       └─ MLModel(contentsOf: modelURL, configuration: config)
            │           configuration.computeUnits = .all   (CPU+GPU+ANE)
            │
            └─ run inference → AsyncStream<InferenceToken>
```

---

## Memory Pressure Response Flow

```
UIApplication.didReceiveMemoryWarningNotification
    │
    └─ MemoryManager receives notification
            │
            ├─ calls InferenceEngine.unloadModel()   → model == nil
            ├─ posts .inferenceUnloaded notification
            └─ SwiftUI observes → shows "Freeing memory..." banner

Next inference request
    │
    └─ InferenceEngine.isLoaded() == false
            │
            └─ loadModel() called again automatically
```

---

## Model Download and Verification Flow

```
User selects model in Onboarding
    │
    └─ ModelDownloadManager.startDownload(modelId:)
            │
            ├─ fetch model_manifest.json from CDN
            ├─ validate CDN certificate (pinned leaf cert)
            ├─ URLSessionDownloadTask (background session)
            │       supports resume after interruption
            │
            ├─ Download complete
            │       ├─ compute SHA-256 of downloaded file
            │       ├─ compare against manifest sha256 field
            │       ├─ MATCH → move to Application Support/models/<modelId>/
            │       └─ MISMATCH → delete file, show error, allow retry
            │
            └─ ModelDownloadManager.downloadProgress[@Published] drives UI
```

---

## Data Flow: What Never Leaves the Device

| Data | Storage | Encrypted | Network |
|---|---|---|---|
| User messages | SQLCipher DB | Yes (Secure Enclave key) | Never |
| Model responses | SQLCipher DB | Yes | Never |
| Conversation history | SQLCipher DB | Yes | Never |
| Model weights | Application Support | Yes (iOS Data Protection) | Download only |
| User preferences | UserDefaults | No (non-sensitive) | Never |
| Inference metadata | SQLCipher DB | Yes | Never |
