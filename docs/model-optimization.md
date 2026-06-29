# Model Optimization Guide

## Why INT4 Quantization?

On-device inference requires model weights to fit in device RAM alongside the OS and app. Full-precision (FP32) is completely impractical; FP16 is still too large for consumer iPhones. INT4 quantization achieves a 4× size reduction vs FP16 with minimal quality loss.

### Size vs Quality Tradeoff

| Format | Llama 3.2 1B | Phi-3 Mini 3.8B | Notes |
|---|---|---|---|
| FP32 | ~4 GB | ~15 GB | Out of question for iPhone |
| FP16 | ~2 GB | ~7.6 GB | Barely fits iPhone 15 Pro Max |
| INT8 | ~1 GB | ~3.8 GB | Decent quality, still large |
| INT4 Q4_K_M | ~0.6 GB | ~2.3 GB | **Target** — best quality/size in 4-bit |
| INT4 Q4_0 | ~0.55 GB | ~2.1 GB | Slightly smaller, lower quality |

**Q4_K_M** uses a mixed quantization scheme: most weights in 4-bit, key tensors in higher precision. This delivers better perplexity than pure Q4_0 at only marginal size cost.

---

## Perplexity Comparison (WikiText-2)

These are reference figures from published benchmarks. Run `validate_model.py` to generate project-specific numbers.

| Model | FP16 PPL | INT8 PPL | INT4 Q4_K_M PPL | Delta vs FP16 |
|---|---|---|---|---|
| Llama 3.2 1B | 8.91 | 9.02 | 9.34 | +4.8% |
| Llama 3.2 3B | 6.81 | 6.89 | 7.12 | +4.5% |
| Phi-3 Mini 3.8B | 6.21 | 6.28 | 6.49 | +4.5% |

Pipeline aborts if perplexity increase exceeds **15%** vs FP16 baseline.

---

## CoreML Conversion

See [coreml-conversion.md](coreml-conversion.md) for the full step-by-step guide.

Key decisions:
- `compute_units=ct.ComputeUnit.ALL` — lets CoreML route ops to CPU, GPU, or ANE at runtime
- `minimum_deployment_target=ct.target.iOS17` — required for `MLProgram` format
- `convert_to="mlprogram"` — newer format, better ANE support than `neuralnetwork`
- `compute_precision=ct.precision.FLOAT16` — activations in FP16, weights stored INT4

---

## ANE vs GPU vs CPU Op Routing

CoreML automatically assigns operations to the best compute unit. Understanding the routing helps debug performance regressions:

| Operation Type | Preferred Unit | Notes |
|---|---|---|
| Matrix multiply (large) | ANE | Transformer attention and FFN layers |
| Embedding lookup | CPU | ANE doesn't accelerate sparse lookups well |
| Softmax | ANE / GPU | Route depends on tensor shape |
| RoPE positional encoding | GPU | Complex math, ANE less efficient |
| LayerNorm | ANE | Small tensors; ANE wins |
| Sampling (top-p) | CPU | Low parallelism, CPU is fine |

Use Instruments → Core ML Instrument to inspect per-op routing on device.

---

## Benchmark Results

Target metrics (A16 Bionic, iPhone 14 Pro):

| Model | Time to First Token | Sustained Throughput | Peak Memory |
|---|---|---|---|
| Llama 3.2 1B INT4 | < 1.5s | ≥ 12 tok/s | ~800 MB |
| Llama 3.2 3B INT4 | < 2.5s | ≥ 7 tok/s | ~2.2 GB |
| Phi-3 Mini INT4 | < 3.0s | ≥ 5 tok/s | ~2.8 GB |

Minimum acceptable: **time-to-first-token < 3s, throughput ≥ 5 tok/s** on A16+.

Run `validate_model.py` with `--benchmark` flag after conversion to populate actual numbers.
