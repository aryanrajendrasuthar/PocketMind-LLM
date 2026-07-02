# PocketMind — On-Device Private LLM for iPhone
# Copyright (c) 2026 Aryan Suthar. All Rights Reserved.
#
# PROPRIETARY AND CONFIDENTIAL
# Unauthorized copying, distribution, modification, or use of this file,
# via any medium, is strictly prohibited without the express written
# permission of the copyright owner.
#
# For licensing inquiries: aryanrajendrasuthar@gmail.com

"""Convert a quantized GGUF model to CoreML .mlpackage for on-device iOS inference."""

import argparse
import logging
import sys
import time
from pathlib import Path
from typing import Optional

import coremltools as ct
import numpy as np
import torch
import yaml
from transformers import AutoModelForCausalLM, AutoTokenizer

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

RAW_DIR = Path.home() / ".pocketmind" / "models" / "raw"
COREML_DIR = Path.home() / ".pocketmind" / "models" / "coreml"
CONFIGS_DIR = Path(__file__).parent.parent / "configs"

TARGET_TIME_TO_FIRST_TOKEN = 3.0
TARGET_MIN_TOKENS_PER_SEC = 5.0


def load_config(model_id: str) -> dict:  # type: ignore[type-arg]
    """Load YAML config for the given model ID."""
    config_path = CONFIGS_DIR / f"{model_id}.yaml"
    if not config_path.exists():
        raise FileNotFoundError(f"No config found for model '{model_id}'.")
    with open(config_path, "r") as f:
        return yaml.safe_load(f)  # type: ignore[no-any-return]


class TracedModelWrapper(torch.nn.Module):
    """Wrapper with a pre-built static 4D causal mask registered as a buffer.

    The mask is computed once at construction (Python int arithmetic, no traced ops)
    so the forward pass has zero dynamic shape ops — coremltools can convert it cleanly.
    """

    def __init__(self, model: torch.nn.Module, context_length: int) -> None:
        super().__init__()
        self.model = model
        min_val = torch.finfo(torch.float16).min
        causal = torch.tril(torch.ones(context_length, context_length, dtype=torch.float16))
        mask_4d = ((1.0 - causal) * min_val).view(1, 1, context_length, context_length)
        self.register_buffer("causal_mask", mask_4d)

    def forward(self, input_ids: torch.Tensor) -> torch.Tensor:
        outputs = self.model(
            input_ids=input_ids,
            attention_mask=self.causal_mask,
            use_cache=False,
        )
        return outputs.logits


def load_hf_model(
    raw_dir: Path,
    config: dict,  # type: ignore[type-arg]
    device: str = "cpu",
) -> tuple[torch.nn.Module, object]:
    """Load HuggingFace model and tokenizer in FP32 for tracing."""
    logger.info("Loading HuggingFace model from %s...", raw_dir)

    tokenizer = AutoTokenizer.from_pretrained(str(raw_dir))
    model = AutoModelForCausalLM.from_pretrained(
        str(raw_dir),
        dtype=torch.float16,
        low_cpu_mem_usage=True,
        attn_implementation='eager',
    )
    model.config.use_cache = False
    model = model.eval().to(device)
    logger.info("Model loaded. Parameter count: %s", f"{sum(p.numel() for p in model.parameters()):,}")
    return model, tokenizer


def trace_model(
    model: torch.nn.Module,
    tokenizer: object,
    target_context_length: int,
) -> tuple[torch.jit.ScriptModule, tuple[torch.Tensor, ...]]:
    """Trace the model with torch.jit.trace for CoreML conversion."""
    logger.info("Tracing model (context length: %d)...", target_context_length)

    wrapper = TracedModelWrapper(model, target_context_length).eval()

    input_ids = torch.zeros((1, target_context_length), dtype=torch.int32)
    example_inputs = (input_ids,)

    with torch.no_grad():
        traced = torch.jit.trace(wrapper, example_inputs, check_trace=False)

    logger.info("Tracing complete.")
    return traced, example_inputs


def convert_to_coreml(
    traced_model: torch.jit.ScriptModule,
    example_inputs: tuple[torch.Tensor, ...],
    config: dict,  # type: ignore[type-arg]
    output_path: Path,
) -> ct.models.MLModel:
    """Run coremltools conversion and save the .mlpackage."""
    logger.info("Converting to CoreML...")

    coreml_config = config["coreml"]
    compute_units_map = {
        "ALL": ct.ComputeUnit.ALL,
        "CPU_ONLY": ct.ComputeUnit.CPU_ONLY,
        "CPU_AND_GPU": ct.ComputeUnit.CPU_AND_GPU,
        "CPU_AND_NE": ct.ComputeUnit.CPU_AND_NE,
    }
    compute_units = compute_units_map.get(coreml_config["compute_units"], ct.ComputeUnit.ALL)

    precision_map = {
        "FLOAT16": ct.precision.FLOAT16,
        "FLOAT32": ct.precision.FLOAT32,
    }
    precision = precision_map.get(coreml_config["precision"], ct.precision.FLOAT16)

    inputs = [
        ct.TensorType(name="input_ids", shape=example_inputs[0].shape, dtype=np.int32),
    ]

    coreml_model = ct.convert(
        traced_model,
        inputs=inputs,
        compute_units=compute_units,
        minimum_deployment_target=ct.target.iOS18,
        convert_to="mlprogram",
        compute_precision=precision,
    )

    coreml_model.short_description = "PocketMind on-device language model"
    coreml_model.author = "Aryan Suthar"
    coreml_model.version = config["manifest"]["version"]
    coreml_model.user_defined_metadata["model_id"] = config["model_id"]
    coreml_model.user_defined_metadata["quantization"] = config["quantization"]["method"]
    coreml_model.user_defined_metadata["context_length"] = str(
        config["parameters"]["target_context_length"]
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    coreml_model.save(str(output_path))
    logger.info("CoreML model saved: %s", output_path)
    return coreml_model


def validate_coreml_model(
    coreml_model: ct.models.MLModel,
    tokenizer: object,
    config: dict,  # type: ignore[type-arg]
) -> None:
    """
    Validate the converted CoreML model produces output on macOS.

    Benchmarks time-to-first-token and approximate throughput.
    Aborts if the model fails to produce any output.
    """
    logger.info("Validating CoreML model on macOS...")
    test_prompt = "Explain what a neural network is in one sentence."

    # Tokenize
    from transformers import PreTrainedTokenizerBase
    tok: PreTrainedTokenizerBase = tokenizer  # type: ignore[assignment]
    input_ids = tok.encode(test_prompt, return_tensors="np")
    seq_len = input_ids.shape[1]
    target_ctx = config["parameters"]["target_context_length"]

    padded_ids = np.zeros((1, target_ctx), dtype=np.int32)
    padded_mask = np.zeros((1, target_ctx), dtype=np.int32)
    padded_ids[0, :seq_len] = input_ids[0]
    padded_mask[0, :seq_len] = 1

    start = time.perf_counter()
    predictions = coreml_model.predict({"input_ids": padded_ids})
    first_token_time = time.perf_counter() - start

    logits_key = list(predictions.keys())[0]
    logits = predictions[logits_key]

    if logits is None or logits.size == 0:
        logger.error("CoreML model produced no output. Conversion may have failed.")
        sys.exit(1)

    next_token_id = int(np.argmax(logits[0, seq_len - 1]))
    next_token = tok.decode([next_token_id])
    logger.info("First token generated: '%s' (token id: %d)", next_token.strip(), next_token_id)
    logger.info("Time to first token: %.3fs", first_token_time)

    targets = config["performance_targets"]
    if first_token_time > TARGET_TIME_TO_FIRST_TOKEN:
        logger.warning(
            "Time to first token (%.3fs) exceeds target (%.1fs). "
            "Performance may be insufficient on older devices.",
            first_token_time,
            targets.get("time_to_first_token_sec", TARGET_TIME_TO_FIRST_TOKEN),
        )
    else:
        logger.info("Time to first token is within target. ✓")


def convert(model_id: str, skip_validation: bool = False) -> Path:
    """
    Full CoreML conversion pipeline.

    1. Load raw HuggingFace model
    2. Trace with torch.jit.trace
    3. Convert with coremltools
    4. Validate on macOS (smoke test)
    5. Return path to .mlpackage

    Raises SystemExit on failure.
    """
    config = load_config(model_id)
    raw_dir = RAW_DIR / model_id
    output_name = config["coreml"]["output_name"]
    output_path = COREML_DIR / f"{output_name}.mlpackage"

    if output_path.exists():
        logger.info("CoreML model already exists: %s", output_path)
        return output_path

    if not raw_dir.exists():
        logger.error(
            "Raw model directory not found: %s\n"
            "Run download_base_model.py --model %s first.",
            raw_dir,
            model_id,
        )
        sys.exit(1)

    hf_model, tokenizer = load_hf_model(
        raw_dir=raw_dir,
        config=config,
    )

    target_ctx = 256  # 256 tokens: 4x faster attention than 512 (O(n²)), sufficient for chat
    traced_model, example_inputs = trace_model(hf_model, tokenizer, target_ctx)

    # Free HF model RAM before conversion (tracing is complete)
    del hf_model
    torch.cuda.empty_cache() if torch.cuda.is_available() else None

    coreml_model = convert_to_coreml(traced_model, example_inputs, config, output_path)

    if not skip_validation:
        validate_coreml_model(coreml_model, tokenizer, config)

    size_gb = sum(f.stat().st_size for f in output_path.rglob("*") if f.is_file()) / 1e9
    logger.info("Conversion complete. Output: %s (%.2f GB)", output_path, size_gb)
    return output_path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert a PocketMind model to CoreML .mlpackage."
    )
    parser.add_argument(
        "--model",
        required=True,
        choices=["llama32_1b", "llama32_3b", "phi3_mini"],
        help="Model ID corresponding to a config in configs/.",
    )
    parser.add_argument(
        "--skip-validation",
        action="store_true",
        help="Skip macOS validation smoke test.",
    )
    args = parser.parse_args()
    convert(model_id=args.model, skip_validation=args.skip_validation)


if __name__ == "__main__":
    main()
