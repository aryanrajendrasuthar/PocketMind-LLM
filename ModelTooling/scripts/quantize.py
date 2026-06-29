# PocketMind — On-Device Private LLM for iPhone
# Copyright (c) 2026 Aryan Suthar. All Rights Reserved.
#
# PROPRIETARY AND CONFIDENTIAL
# Unauthorized copying, distribution, modification, or use of this file,
# via any medium, is strictly prohibited without the express written
# permission of the copyright owner.
#
# For licensing inquiries: aryanrajendrasuthar@gmail.com

"""Quantize a base model to INT4 Q4_K_M GGUF format via llama-cpp-python."""

import argparse
import logging
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Optional

import numpy as np
import yaml
from llama_cpp import Llama
from tqdm import tqdm

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

RAW_DIR = Path.home() / ".pocketmind" / "models" / "raw"
QUANTIZED_DIR = Path.home() / ".pocketmind" / "models" / "quantized"
CONFIGS_DIR = Path(__file__).parent.parent / "configs"

QUANTIZATION_TYPE = "Q4_K_M"
MAX_PERPLEXITY_INCREASE_PCT = 15.0

PERPLEXITY_TEST_CORPUS = [
    "The quick brown fox jumps over the lazy dog.",
    "To be, or not to be, that is the question.",
    "In the beginning was the Word, and the Word was with God.",
    "It was the best of times, it was the worst of times.",
    "All happy families are alike; each unhappy family is unhappy in its own way.",
    "Call me Ishmael. Some years ago—never mind how long precisely—",
    "It is a truth universally acknowledged, that a single man in possession of a good fortune.",
    "The sky above the port was the color of television, tuned to a dead channel.",
    "Whether I shall turn out to be the hero of my own life, or whether that station.",
    "A screaming comes across the sky. It has happened before, but there is nothing to compare it to.",
]


def load_config(model_id: str) -> dict:  # type: ignore[type-arg]
    """Load YAML config for the given model ID."""
    config_path = CONFIGS_DIR / f"{model_id}.yaml"
    if not config_path.exists():
        raise FileNotFoundError(f"No config found for model '{model_id}'.")
    with open(config_path, "r") as f:
        return yaml.safe_load(f)  # type: ignore[no-any-return]


def find_gguf_or_safetensors(model_dir: Path) -> Optional[Path]:
    """Find the primary model weight file in a downloaded model directory."""
    for ext in [".gguf", ".safetensors"]:
        candidates = sorted(model_dir.glob(f"*{ext}"))
        if candidates:
            # Return largest file (shards: pick the first alphabetically for .safetensors)
            return candidates[0]
    return None


def convert_safetensors_to_gguf(safetensors_dir: Path, output_path: Path) -> Path:
    """
    Convert HuggingFace safetensors weights to FP16 GGUF using llama.cpp convert script.

    Requires llama.cpp to be installed and `convert_hf_to_gguf.py` accessible.
    Falls back to the llama-cpp-python bundled converter if available.
    """
    logger.info("Converting safetensors → FP16 GGUF...")

    # Try llama-cpp-python bundled converter
    import llama_cpp
    llama_cpp_root = Path(llama_cpp.__file__).parent
    converter = llama_cpp_root / "convert_hf_to_gguf.py"

    if not converter.exists():
        raise RuntimeError(
            "llama.cpp converter not found. Install llama-cpp-python with "
            "LLAMA_METAL=1 pip install llama-cpp-python, or convert manually."
        )

    result = subprocess.run(
        [
            sys.executable,
            str(converter),
            str(safetensors_dir),
            "--outfile",
            str(output_path),
            "--outtype",
            "f16",
        ],
        capture_output=True,
        text=True,
        timeout=3600,
    )

    if result.returncode != 0:
        logger.error("Conversion failed:\n%s", result.stderr)
        raise RuntimeError("safetensors → GGUF conversion failed.")

    logger.info("FP16 GGUF created at: %s", output_path)
    return output_path


def quantize_gguf(fp16_gguf: Path, output_path: Path) -> Path:
    """Quantize an FP16 GGUF to Q4_K_M using llama-quantize."""
    logger.info("Quantizing %s → %s (%s)...", fp16_gguf.name, output_path.name, QUANTIZATION_TYPE)

    import llama_cpp
    llama_cpp_root = Path(llama_cpp.__file__).parent
    quantize_bin = llama_cpp_root / "llama-quantize"

    if not quantize_bin.exists():
        # Try alternative names
        for name in ["quantize", "llama_quantize"]:
            candidate = llama_cpp_root / name
            if candidate.exists():
                quantize_bin = candidate
                break
        else:
            raise RuntimeError(
                "llama-quantize binary not found in llama-cpp-python installation. "
                "Build llama-cpp-python from source with quantization support."
            )

    result = subprocess.run(
        [str(quantize_bin), str(fp16_gguf), str(output_path), QUANTIZATION_TYPE],
        capture_output=True,
        text=True,
        timeout=7200,
    )

    if result.returncode != 0:
        logger.error("Quantization failed:\n%s", result.stderr)
        raise RuntimeError(f"GGUF quantization to {QUANTIZATION_TYPE} failed.")

    logger.info("Quantized model saved at: %s", output_path)
    return output_path


def measure_perplexity(gguf_path: Path, test_sentences: list[str]) -> float:
    """
    Approximate perplexity using negative log-likelihood over test sentences.

    This is not the full WikiText-2 perplexity but provides a fast sanity check
    to detect quality regressions from quantization.
    """
    logger.info("Measuring perplexity on %s sentences...", len(test_sentences))

    llm = Llama(
        model_path=str(gguf_path),
        n_ctx=512,
        n_batch=512,
        verbose=False,
        logits_all=True,
    )

    total_nll = 0.0
    total_tokens = 0

    for sentence in tqdm(test_sentences, desc="Perplexity"):
        tokens = llm.tokenize(sentence.encode("utf-8"))
        if len(tokens) < 2:
            continue

        output = llm(sentence, max_tokens=1, echo=True, logprobs=len(tokens))
        if output.get("choices") and output["choices"][0].get("logprobs"):
            token_logprobs = output["choices"][0]["logprobs"].get("token_logprobs", [])
            valid_logprobs = [lp for lp in token_logprobs if lp is not None]
            total_nll += -sum(valid_logprobs)
            total_tokens += len(valid_logprobs)

    if total_tokens == 0:
        logger.warning("Could not measure perplexity — no valid logprobs returned.")
        return float("nan")

    ppl = float(np.exp(total_nll / total_tokens))
    logger.info("Approximate perplexity: %.4f (over %d tokens)", ppl, total_tokens)
    return ppl


def benchmark_inference(gguf_path: Path, n_tokens: int = 100) -> float:
    """Measure tokens/second on the current machine."""
    logger.info("Benchmarking inference speed (%d tokens)...", n_tokens)

    llm = Llama(
        model_path=str(gguf_path),
        n_ctx=512,
        n_batch=512,
        verbose=False,
    )

    prompt = "Explain the concept of recursion in programming in simple terms."
    start = time.perf_counter()
    output = llm(prompt, max_tokens=n_tokens, echo=False)
    elapsed = time.perf_counter() - start

    generated = output["usage"]["completion_tokens"]
    tokens_per_sec = generated / elapsed if elapsed > 0 else 0.0
    logger.info(
        "Speed: %.1f tokens/sec (%d tokens in %.2fs)",
        tokens_per_sec,
        generated,
        elapsed,
    )
    return tokens_per_sec


def quantize(model_id: str, skip_benchmark: bool = False) -> Path:
    """
    Full quantization pipeline for a model.

    1. Locate downloaded raw model
    2. Convert to FP16 GGUF if needed
    3. Quantize to Q4_K_M GGUF
    4. Measure perplexity before and after
    5. Abort if perplexity increase > MAX_PERPLEXITY_INCREASE_PCT
    6. Benchmark inference speed

    Returns path to the quantized .gguf file.
    """
    config = load_config(model_id)
    raw_dir = RAW_DIR / model_id
    QUANTIZED_DIR.mkdir(parents=True, exist_ok=True)

    if not raw_dir.exists():
        logger.error(
            "Raw model directory not found: %s\n"
            "Run download_base_model.py --model %s first.",
            raw_dir,
            model_id,
        )
        sys.exit(1)

    output_gguf = QUANTIZED_DIR / f"{config['coreml']['output_name']}_{QUANTIZATION_TYPE.lower()}.gguf"

    if output_gguf.exists():
        logger.info("Quantized model already exists: %s", output_gguf)
        return output_gguf

    # Locate source weight file
    source_file = find_gguf_or_safetensors(raw_dir)
    if source_file is None:
        logger.error("No .gguf or .safetensors file found in %s", raw_dir)
        sys.exit(1)

    with tempfile.TemporaryDirectory() as tmpdir:
        if source_file.suffix == ".safetensors":
            fp16_gguf = Path(tmpdir) / f"{model_id}_fp16.gguf"
            convert_safetensors_to_gguf(raw_dir, fp16_gguf)
        else:
            fp16_gguf = source_file

        # Measure baseline perplexity (FP16)
        logger.info("--- Baseline (FP16) perplexity ---")
        baseline_ppl = measure_perplexity(fp16_gguf, PERPLEXITY_TEST_CORPUS)

        # Quantize
        quantize_gguf(fp16_gguf, output_gguf)

    # Measure quantized perplexity
    logger.info("--- Quantized (%s) perplexity ---", QUANTIZATION_TYPE)
    quantized_ppl = measure_perplexity(output_gguf, PERPLEXITY_TEST_CORPUS)

    # Check perplexity delta
    if not (np.isnan(baseline_ppl) or np.isnan(quantized_ppl)):
        pct_increase = ((quantized_ppl - baseline_ppl) / baseline_ppl) * 100
        logger.info(
            "Perplexity delta: %.4f → %.4f (+%.2f%%)",
            baseline_ppl,
            quantized_ppl,
            pct_increase,
        )
        if pct_increase > MAX_PERPLEXITY_INCREASE_PCT:
            logger.error(
                "Perplexity increase (%.2f%%) exceeds threshold (%.1f%%). "
                "Quantization quality is unacceptable. Aborting.",
                pct_increase,
                MAX_PERPLEXITY_INCREASE_PCT,
            )
            output_gguf.unlink(missing_ok=True)
            sys.exit(1)

    if not skip_benchmark:
        benchmark_inference(output_gguf)

    size_mb = output_gguf.stat().st_size / (1024 * 1024)
    logger.info(
        "Quantization complete. Output: %s (%.1f MB)",
        output_gguf,
        size_mb,
    )
    return output_gguf


def main() -> None:
    parser = argparse.ArgumentParser(
        description=f"Quantize a PocketMind model to INT4 {QUANTIZATION_TYPE} GGUF."
    )
    parser.add_argument(
        "--model",
        required=True,
        choices=["llama32_1b", "llama32_3b", "phi3_mini"],
        help="Model ID corresponding to a config in configs/.",
    )
    parser.add_argument(
        "--skip-benchmark",
        action="store_true",
        help="Skip the inference speed benchmark.",
    )
    args = parser.parse_args()
    quantize(model_id=args.model, skip_benchmark=args.skip_benchmark)


if __name__ == "__main__":
    main()
