# CoreML Conversion Pipeline

## Overview

The conversion pipeline transforms HuggingFace model weights into an iOS-ready `.mlpackage` that runs on the Apple Neural Engine.

## Prerequisites

```bash
pip install coremltools>=7.2 torch>=2.3.0 transformers>=4.41.0
```

Also requires Xcode command-line tools for on-device validation.

---

## Step-by-Step Pipeline

### Step 1: Download Base Model

```bash
python scripts/download_base_model.py --model llama32_1b
```

Downloads to `~/.pocketmind/models/raw/<model_id>/`.
Verifies SHA-256 against the published HuggingFace model card checksum.

### Step 2: Quantize to INT4 Q4_K_M

```bash
python scripts/quantize.py --model llama32_1b
```

Uses `llama-cpp-python` to produce a `.gguf` file at `~/.pocketmind/models/quantized/`.
Measures perplexity before and after. Aborts if delta exceeds 15%.

### Step 3: Convert to CoreML

```bash
python scripts/convert_to_coreml.py --model llama32_1b
```

Loads the quantized GGUF weights, traces through the model, and runs:

```python
import coremltools as ct

model = ct.convert(
    traced_model,
    compute_units=ct.ComputeUnit.ALL,
    minimum_deployment_target=ct.target.iOS17,
    convert_to="mlprogram",
    compute_precision=ct.precision.FLOAT16,
)

model.short_description = "PocketMind on-device language model"
model.version = "1.0.0"
model.save("~/.pocketmind/models/coreml/<model_id>.mlpackage")
```

### Step 4: Validate

```bash
python scripts/validate_model.py --model llama32_1b
```

Runs 50 standard prompts through both the original and CoreML model.
Computes ROUGE-L score. Fails pipeline if drop exceeds 0.10.

### Step 5: Export Manifest

```bash
python scripts/export_metadata.py --model llama32_1b
```

Produces `model_manifest.json` consumed by `ModelDownloadManager` in the iOS app.

---

## Common Conversion Issues

### ANE Unsupported Op

**Symptom:** `coremltools` warns about ops falling back to CPU.

**Fix:** Check coremltools release notes for newly supported ops. In the interim, add an explicit `compute_units=ct.ComputeUnit.CPU_AND_GPU` for affected layers via `ct.optimize`.

### Numerical Mismatch After Conversion

**Symptom:** `validate_model.py` reports ROUGE-L drop > 0.10.

**Fix:**
1. Increase quantization precision: try Q5_K_M instead of Q4_K_M.
2. Check for fp16 overflow in attention layers — clamp logits before softmax.
3. Verify tokenizer vocab matches between HuggingFace and GGUF conversion.

### Memory Spike During Conversion

**Symptom:** OOM on Mac with < 16 GB RAM during `ct.convert()`.

**Fix:** Run conversion on a Mac with ≥ 16 GB RAM. The 1B model needs ~8 GB peak during tracing.

---

## On-Device Validation

After adding the `.mlpackage` to the Xcode project bundle, verify on a physical device:

```swift
// In a debug build, add a temporary validation route
let config = MLModelConfiguration()
config.computeUnits = .all
let model = try MLModel(contentsOf: modelURL, configuration: config)
// Run a test prompt through InferenceEngine
```

Check Xcode debug gauges: confirm ANE utilization > 0% during inference (non-zero means the model is actually using the Neural Engine).
