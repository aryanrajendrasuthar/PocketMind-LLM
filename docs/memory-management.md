# Memory Management

## Overview

On-device LLM inference is memory-intensive. PocketMind uses two complementary strategies:

1. **Lazy model loading** — the CoreML model is not loaded at app launch; it loads on first inference request and can be unloaded under memory pressure.
2. **KV cache sliding window** — the conversation context window is capped at 4096 tokens; older messages are dropped when the limit is approached.

---

## Lazy Model Loading

`InferenceEngine` is a Swift actor. The `MLModel` object is `nil` until the first call to `generate()`.

```swift
actor InferenceEngine {
    private var model: MLModel?

    func generate(prompt: String, ...) -> AsyncStream<InferenceToken> {
        AsyncStream { continuation in
            Task(priority: .userInitiated) {
                if !isLoaded() {
                    try await loadModel()
                }
                // run inference
            }
        }
    }

    func loadModel() async throws {
        // Always called from a background priority context — never blocks main thread
        let config = MLModelConfiguration()
        config.computeUnits = .all
        model = try await MLModel.load(contentsOf: modelURL, configuration: config)
    }

    func unloadModel() {
        model = nil
        // ARC releases the MLModel; CoreML frees GPU/ANE buffers
    }
}
```

`MLModel.load(contentsOf:configuration:)` uses the async variant (available iOS 16+) to avoid blocking the calling actor.

---

## Memory Pressure Handling

`MemoryManager` monitors two signals:

### Signal 1: UIApplication Memory Warning

```swift
NotificationCenter.default.addObserver(
    forName: UIApplication.didReceiveMemoryWarningNotification
) { _ in
    Task {
        await inferenceEngine.unloadModel()
        await MainActor.run {
            // post .inferenceUnloaded notification → UI shows banner
        }
    }
}
```

### Signal 2: Proactive RAM Monitoring

`MemoryManager` polls `os_proc_available_memory()` every 5 seconds while inference is active. If available RAM drops below **500 MB**, it preemptively calls `unloadModel()` before iOS issues a memory warning (which could result in a crash).

```swift
func availableMemoryBytes() -> Int64 {
    var taskInfo = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / 4)
    let result = withUnsafeMutablePointer(to: &taskInfo) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Int64(taskInfo.phys_footprint) : 0
}
```

---

## KV Cache Sliding Window

Every message in the conversation is tokenized and its token count stored in `InferenceMetadata.tokensGenerated`. `MemoryManager` sums the total context token count before each inference call.

### Algorithm

```
contextLimit = min(model.contextLength, 4096)
tokenBudget  = contextLimit - 256          // reserve 256 for the next response

if totalTokens > tokenBudget:
    keep: system prompt (always)
    drop: oldest message pairs (user + assistant) until totalTokens ≤ tokenBudget
    post .contextTrimmed notification → UI shows:
        "Older messages removed from context to save memory"
```

The user is always notified. Silent truncation is never allowed.

---

## Background Suspension

On `UIApplication.didEnterBackgroundNotification`, `MemoryManager` calls `unloadModel()`. iOS aggressively terminates background apps that hold large GPU buffers. Proactively releasing the model prevents termination and allows faster resume when the user returns.

The model reloads automatically on the next `generate()` call, which takes 0.5–2 seconds depending on device and model size.
