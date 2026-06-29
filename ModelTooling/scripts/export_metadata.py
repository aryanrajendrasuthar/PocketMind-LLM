# PocketMind — On-Device Private LLM for iPhone
# Copyright (c) 2026 Aryan Suthar. All Rights Reserved.
#
# PROPRIETARY AND CONFIDENTIAL
# Unauthorized copying, distribution, modification, or use of this file,
# via any medium, is strictly prohibited without the express written
# permission of the copyright owner.
#
# For licensing inquiries: aryanrajendrasuthar@gmail.com

"""Generate model_manifest.json for a converted CoreML model."""

import argparse
import hashlib
import json
import logging
import sys
from pathlib import Path
from typing import Any

import yaml
from tqdm import tqdm

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

COREML_DIR = Path.home() / ".pocketmind" / "models" / "coreml"
CONFIGS_DIR = Path(__file__).parent.parent / "configs"
MANIFEST_DIR = Path.home() / ".pocketmind" / "manifests"


def load_config(model_id: str) -> dict[str, Any]:
    """Load YAML config for the given model ID."""
    config_path = CONFIGS_DIR / f"{model_id}.yaml"
    if not config_path.exists():
        raise FileNotFoundError(f"No config found for model '{model_id}'.")
    with open(config_path, "r") as f:
        return yaml.safe_load(f)  # type: ignore[no-any-return]


def compute_sha256_of_directory(dir_path: Path) -> str:
    """
    Compute a deterministic SHA-256 of all files in a directory.

    Files are sorted by relative path before hashing to ensure reproducibility.
    Used for .mlpackage directories (which are directories, not single files).
    """
    sha256 = hashlib.sha256()
    all_files = sorted(f for f in dir_path.rglob("*") if f.is_file())
    total_size = sum(f.stat().st_size for f in all_files)

    with tqdm(total=total_size, unit="B", unit_scale=True, desc="Computing SHA-256") as pbar:
        for file_path in all_files:
            # Include the relative path in the hash for structural integrity
            sha256.update(str(file_path.relative_to(dir_path)).encode())
            with open(file_path, "rb") as f:
                for chunk in iter(lambda: f.read(1 << 20), b""):
                    sha256.update(chunk)
                    pbar.update(len(chunk))

    return sha256.hexdigest()


def compute_directory_size(dir_path: Path) -> int:
    """Return total size in bytes of all files in a directory."""
    return sum(f.stat().st_size for f in dir_path.rglob("*") if f.is_file())


def recommended_devices(config: dict[str, Any]) -> list[str]:
    """Derive recommended device list based on hardware requirements in config."""
    min_chip = config["hardware"]["min_chip"]
    device_map: dict[str, list[str]] = {
        "A14": [
            "iPhone 12", "iPhone 12 mini", "iPhone 12 Pro", "iPhone 12 Pro Max",
            "iPhone 13", "iPhone 13 mini", "iPhone 13 Pro", "iPhone 13 Pro Max",
            "iPhone 14", "iPhone 14 Plus",
            "iPhone 14 Pro", "iPhone 14 Pro Max",
            "iPhone 15", "iPhone 15 Plus",
            "iPhone 15 Pro", "iPhone 15 Pro Max",
            "iPhone 16", "iPhone 16 Plus",
            "iPhone 16 Pro", "iPhone 16 Pro Max",
        ],
        "A15": [
            "iPhone 13", "iPhone 13 mini", "iPhone 13 Pro", "iPhone 13 Pro Max",
            "iPhone 14", "iPhone 14 Plus",
            "iPhone 14 Pro", "iPhone 14 Pro Max",
            "iPhone 15", "iPhone 15 Plus",
            "iPhone 15 Pro", "iPhone 15 Pro Max",
            "iPhone 16", "iPhone 16 Plus",
            "iPhone 16 Pro", "iPhone 16 Pro Max",
        ],
        "A17": [
            "iPhone 15 Pro", "iPhone 15 Pro Max",
            "iPhone 16 Pro", "iPhone 16 Pro Max",
        ],
    }
    return device_map.get(min_chip, [])


def export_manifest(model_id: str, output_dir: Path | None = None) -> Path:
    """
    Generate model_manifest.json for a converted CoreML model.

    The manifest is consumed by ModelDownloadManager in the iOS app to:
    - Display model info in the onboarding model selection screen
    - Verify SHA-256 after download
    - Enforce minimum device requirements

    Returns the path to the written manifest file.
    """
    config = load_config(model_id)
    output_name = config["coreml"]["output_name"]
    mlpackage_path = COREML_DIR / f"{output_name}.mlpackage"

    if not mlpackage_path.exists():
        logger.error(
            "CoreML model not found: %s\n"
            "Run convert_to_coreml.py --model %s first.",
            mlpackage_path,
            model_id,
        )
        sys.exit(1)

    logger.info("Computing SHA-256 for %s...", mlpackage_path.name)
    sha256 = compute_sha256_of_directory(mlpackage_path)

    file_size_bytes = compute_directory_size(mlpackage_path)
    logger.info("File size: %.2f GB", file_size_bytes / (1024 ** 3))

    manifest_config = config["manifest"]
    hardware_config = config["hardware"]

    manifest: dict[str, Any] = {
        "model_id": f"{output_name}-coreml",
        "display_name": config["display_name"],
        "version": manifest_config["version"],
        "quantization": f"INT4 {config['quantization']['method']}",
        "file_size_bytes": file_size_bytes,
        "sha256": sha256,
        "min_ios": config["coreml"]["minimum_ios"],
        "min_ram_gb": hardware_config["min_ram_gb"],
        "min_device": hardware_config["min_device"],
        "min_chip": hardware_config["min_chip"],
        "recommended_devices": recommended_devices(config),
        "context_length": config["parameters"]["target_context_length"],
        "max_tokens": manifest_config["max_tokens"],
        "knowledge_cutoff": manifest_config["knowledge_cutoff"],
        "capabilities": manifest_config["capabilities"],
        "offline_limitations": manifest_config["offline_limitations"],
        "performance_targets": config["performance_targets"],
    }

    target_dir = output_dir or MANIFEST_DIR
    target_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = target_dir / f"{output_name}_manifest.json"

    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    logger.info("Manifest written: %s", manifest_path)
    logger.info("Model ID: %s", manifest["model_id"])
    logger.info("SHA-256: %s", sha256)
    return manifest_path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Export model_manifest.json for a converted PocketMind CoreML model."
    )
    parser.add_argument(
        "--model",
        required=True,
        choices=["llama32_1b", "llama32_3b", "phi3_mini"],
        help="Model ID corresponding to a config in configs/.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=None,
        help="Directory to write the manifest file. Defaults to ~/.pocketmind/manifests/.",
    )
    args = parser.parse_args()
    export_manifest(model_id=args.model, output_dir=args.output_dir)


if __name__ == "__main__":
    main()
