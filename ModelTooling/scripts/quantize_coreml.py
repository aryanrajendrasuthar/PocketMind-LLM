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
Post-hoc INT4 weight quantization of an existing CoreML .mlpackage.

Takes the FP16 traced model produced by convert_to_coreml.py and compresses
the weights to 4-bit linear quantization using coremltools.optimize.
The resulting model is ~75% smaller and ANE-compatible.

Usage:
    python quantize_coreml.py --model pocketmind_llama32_1b
"""

import argparse
import logging
import sys
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

COREML_DIR = Path.home() / ".pocketmind" / "models" / "coreml"


def quantize(model_name: str) -> Path:
    try:
        import coremltools as ct
        from coremltools.optimize.coreml import (
            OptimizationConfig,
            OpLinearQuantizerConfig,
            linear_quantize_weights,
        )
    except ImportError as e:
        logger.error("coremltools not found: %s", e)
        sys.exit(1)

    logger.info("coremltools version: %s", ct.__version__)

    input_path = COREML_DIR / f"{model_name}.mlpackage"
    output_path = COREML_DIR / f"{model_name}_int4.mlpackage"

    if not input_path.exists():
        logger.error("Input model not found: %s", input_path)
        logger.error("Run convert_to_coreml.py first.")
        sys.exit(1)

    if output_path.exists():
        logger.info("INT4 model already exists: %s", output_path)
        return output_path

    input_gb = sum(f.stat().st_size for f in input_path.rglob("*") if f.is_file()) / 1e9
    logger.info("Loading FP16 model (%.2f GB): %s", input_gb, input_path)
    model = ct.models.MLModel(str(input_path))

    logger.info("Applying INT4 per-block weight quantization (~75%% size reduction)...")
    logger.info("Requires model converted with minimum_deployment_target=iOS18.")

    config = OptimizationConfig(
        global_config=OpLinearQuantizerConfig(
            mode="linear_symmetric",
            dtype="int4",
            granularity="per_block",
            block_size=32,
        )
    )

    compressed = linear_quantize_weights(model, config=config)

    logger.info("Saving INT4 model to: %s", output_path)
    compressed.save(str(output_path))

    output_gb = sum(f.stat().st_size for f in output_path.rglob("*") if f.is_file()) / 1e9
    logger.info("Done. FP16: %.2f GB → INT4: %.2f GB (%.0f%% reduction)",
                input_gb, output_gb, (1 - output_gb / input_gb) * 100)
    return output_path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="INT4 quantize an existing PocketMind CoreML .mlpackage."
    )
    parser.add_argument(
        "--model",
        default="pocketmind_llama32_1b",
        help="Base name of the .mlpackage in ~/.pocketmind/models/coreml/",
    )
    args = parser.parse_args()
    quantize(args.model)


if __name__ == "__main__":
    main()
