# PocketMind — On-Device Private LLM for iPhone
# Copyright (c) 2026 Aryan Suthar. All Rights Reserved.
#
# PROPRIETARY AND CONFIDENTIAL
# Unauthorized copying, distribution, modification, or use of this file,
# via any medium, is strictly prohibited without the express written
# permission of the copyright owner.
#
# For licensing inquiries: aryanrajendrasuthar@gmail.com

"""
Validate the CoreML model output quality against the original HuggingFace model.

Runs 50 standard prompts through both models and computes ROUGE-L score.
Fails the pipeline if ROUGE-L drop exceeds 0.10.
"""

import argparse
import json
import logging
import sys
import time
from pathlib import Path
from typing import Any

import coremltools as ct
import numpy as np
import yaml
from rouge_score import rouge_scorer
from transformers import AutoModelForCausalLM, AutoTokenizer, PreTrainedTokenizerBase
import torch
from tqdm import tqdm

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

RAW_DIR = Path.home() / ".pocketmind" / "models" / "raw"
COREML_DIR = Path.home() / ".pocketmind" / "models" / "coreml"
CONFIGS_DIR = Path(__file__).parent.parent / "configs"

MIN_ROUGE_L = 0.90  # fail if CoreML ROUGE-L drops below 90% of baseline

STANDARD_PROMPTS = [
    "What is the capital of France?",
    "Explain the water cycle in simple terms.",
    "Write a haiku about autumn leaves.",
    "What is 17 multiplied by 13?",
    "Describe the process of photosynthesis.",
    "What are the primary colors?",
    "Explain recursion with a simple example.",
    "What is the Pythagorean theorem?",
    "Name three programming languages and their primary uses.",
    "What is the speed of light?",
    "Describe what a binary search tree is.",
    "What causes thunder during a storm?",
    "Explain what DNA stands for and its purpose.",
    "What is the difference between HTTP and HTTPS?",
    "Write a short poem about the moon.",
    "What is Newton's first law of motion?",
    "Explain what machine learning is in one paragraph.",
    "What is the largest planet in our solar system?",
    "Describe the structure of an atom.",
    "What is the difference between RAM and ROM?",
    "Explain what a compiler does.",
    "What is the boiling point of water in Celsius?",
    "Name the four seasons and their characteristics.",
    "What is the difference between a virus and a bacterium?",
    "Explain what blockchain technology is.",
    "What is the Fibonacci sequence?",
    "Describe what an API is.",
    "What is the greenhouse effect?",
    "Explain the concept of supply and demand.",
    "What is the difference between syntax and semantics in programming?",
    "Name three famous painters and their most notable works.",
    "What is the formula for the area of a circle?",
    "Explain what encryption is and why it matters.",
    "What is the difference between a list and a tuple in Python?",
    "Describe what the mitochondria does in a cell.",
    "What is a hash function?",
    "Explain what quantum computing is in simple terms.",
    "What causes the seasons on Earth?",
    "What is the difference between RAM and storage?",
    "Explain what a neural network is.",
    "What is the difference between AI and machine learning?",
    "Describe what version control is and why it is used.",
    "What is the time complexity of binary search?",
    "Explain what a deadlock is in computer science.",
    "What is the difference between TCP and UDP?",
    "Describe what containerization is (Docker).",
    "What is the CAP theorem?",
    "Explain what a REST API is.",
    "What is the difference between synchronous and asynchronous code?",
    "What is the purpose of a foreign key in a database?",
]


def load_config(model_id: str) -> dict[str, Any]:
    """Load YAML config for the given model ID."""
    config_path = CONFIGS_DIR / f"{model_id}.yaml"
    if not config_path.exists():
        raise FileNotFoundError(f"No config found for model '{model_id}'.")
    with open(config_path, "r") as f:
        return yaml.safe_load(f)  # type: ignore[no-any-return]


def generate_hf(
    model: Any,
    tokenizer: PreTrainedTokenizerBase,
    prompt: str,
    max_new_tokens: int = 100,
) -> str:
    """Generate a response using the HuggingFace model."""
    inputs = tokenizer(prompt, return_tensors="pt")
    with torch.no_grad():
        outputs = model.generate(
            **inputs,
            max_new_tokens=max_new_tokens,
            do_sample=False,
            temperature=1.0,
            pad_token_id=tokenizer.eos_token_id,
        )
    response_ids = outputs[0][inputs["input_ids"].shape[1]:]
    return tokenizer.decode(response_ids, skip_special_tokens=True).strip()


def generate_coreml(
    coreml_model: ct.models.MLModel,
    tokenizer: PreTrainedTokenizerBase,
    prompt: str,
    target_ctx: int,
    max_new_tokens: int = 100,
) -> str:
    """
    Generate a response using the CoreML model (greedy decoding).

    Runs max_new_tokens autoregressive steps.
    """
    tokens = tokenizer.encode(prompt)
    generated: list[int] = list(tokens)
    eos_id = tokenizer.eos_token_id

    for _ in range(max_new_tokens):
        seq_len = min(len(generated), target_ctx)
        input_ids = np.zeros((1, target_ctx), dtype=np.int32)
        attention_mask = np.zeros((1, target_ctx), dtype=np.int32)
        input_ids[0, :seq_len] = generated[-seq_len:]
        attention_mask[0, :seq_len] = 1

        predictions = coreml_model.predict(
            {"input_ids": input_ids, "attention_mask": attention_mask}
        )
        logits_key = list(predictions.keys())[0]
        logits = predictions[logits_key]
        next_token = int(np.argmax(logits[0, seq_len - 1]))
        generated.append(next_token)

        if next_token == eos_id:
            break

    response_ids = generated[len(tokens):]
    return tokenizer.decode(response_ids, skip_special_tokens=True).strip()


def compute_rouge_l(reference: str, hypothesis: str) -> float:
    """Compute ROUGE-L F1 score between two strings."""
    scorer = rouge_scorer.RougeScorer(["rougeL"], use_stemmer=True)
    scores = scorer.score(reference, hypothesis)
    return float(scores["rougeL"].fmeasure)


def validate(model_id: str, benchmark: bool = False) -> None:
    """
    Run validation pipeline.

    1. Load HF model and CoreML model
    2. Run 50 prompts through both
    3. Compute ROUGE-L between outputs
    4. Fail if average ROUGE-L drop > 0.10

    Args:
        model_id: Model ID from configs/
        benchmark: If True, also measure latency metrics
    """
    config = load_config(model_id)
    raw_dir = RAW_DIR / model_id
    output_name = config["coreml"]["output_name"]
    coreml_path = COREML_DIR / f"{output_name}.mlpackage"
    target_ctx = config["parameters"]["target_context_length"]

    if not raw_dir.exists():
        logger.error("Raw model not found: %s", raw_dir)
        sys.exit(1)

    if not coreml_path.exists():
        logger.error("CoreML model not found: %s", coreml_path)
        sys.exit(1)

    logger.info("Loading HuggingFace model from %s...", raw_dir)
    tokenizer = AutoTokenizer.from_pretrained(str(raw_dir))
    hf_model = AutoModelForCausalLM.from_pretrained(
        str(raw_dir),
        torch_dtype=torch.float32,
        low_cpu_mem_usage=True,
    ).eval()

    logger.info("Loading CoreML model from %s...", coreml_path)
    coreml_model = ct.models.MLModel(str(coreml_path))

    rouge_scores: list[float] = []
    results: list[dict[str, Any]] = []
    first_token_times: list[float] = []
    hallucination_flags: list[str] = []

    logger.info("Running %d validation prompts...", len(STANDARD_PROMPTS))

    for i, prompt in enumerate(tqdm(STANDARD_PROMPTS, desc="Validating")):
        reference = generate_hf(hf_model, tokenizer, prompt, max_new_tokens=100)

        t_start = time.perf_counter()
        hypothesis = generate_coreml(
            coreml_model, tokenizer, prompt, target_ctx, max_new_tokens=100
        )
        t_elapsed = time.perf_counter() - t_start
        first_token_times.append(t_elapsed)

        score = compute_rouge_l(reference, hypothesis)
        rouge_scores.append(score)

        # Flag truncated or empty outputs as potential hallucinations
        if not hypothesis or len(hypothesis) < 5:
            hallucination_flags.append(
                f"Prompt {i}: empty or very short output. Prompt: '{prompt[:60]}'"
            )

        results.append({
            "prompt": prompt,
            "reference": reference,
            "hypothesis": hypothesis,
            "rouge_l": round(score, 4),
            "latency_sec": round(t_elapsed, 3),
        })

    avg_rouge_l = float(np.mean(rouge_scores))
    min_rouge_l = float(np.min(rouge_scores))
    logger.info("Average ROUGE-L: %.4f", avg_rouge_l)
    logger.info("Minimum ROUGE-L: %.4f (worst prompt)", min_rouge_l)

    if hallucination_flags:
        logger.warning("Potential truncated outputs detected:")
        for flag in hallucination_flags:
            logger.warning("  %s", flag)

    # Save detailed results
    results_path = COREML_DIR / f"{output_name}_validation_results.json"
    with open(results_path, "w") as f:
        json.dump(
            {
                "model_id": model_id,
                "avg_rouge_l": avg_rouge_l,
                "min_rouge_l": min_rouge_l,
                "hallucination_flags": hallucination_flags,
                "prompts": results,
            },
            f,
            indent=2,
        )
    logger.info("Detailed results saved: %s", results_path)

    if benchmark:
        avg_latency = float(np.mean(first_token_times))
        p95_latency = float(np.percentile(first_token_times, 95))
        logger.info("Avg latency per output: %.3fs | P95: %.3fs", avg_latency, p95_latency)

    if avg_rouge_l < MIN_ROUGE_L:
        logger.error(
            "ROUGE-L (%.4f) is below minimum threshold (%.2f). "
            "CoreML model quality is unacceptable. "
            "Check conversion logs and consider using a higher quantization level.",
            avg_rouge_l,
            MIN_ROUGE_L,
        )
        sys.exit(1)

    logger.info("Validation passed. ROUGE-L %.4f ≥ %.2f ✓", avg_rouge_l, MIN_ROUGE_L)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate PocketMind CoreML model output quality against HuggingFace baseline."
    )
    parser.add_argument(
        "--model",
        required=True,
        choices=["llama32_1b", "llama32_3b", "phi3_mini"],
        help="Model ID corresponding to a config in configs/.",
    )
    parser.add_argument(
        "--benchmark",
        action="store_true",
        help="Also report latency metrics.",
    )
    args = parser.parse_args()
    validate(model_id=args.model, benchmark=args.benchmark)


if __name__ == "__main__":
    main()
