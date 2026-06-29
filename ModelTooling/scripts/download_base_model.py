# PocketMind — On-Device Private LLM for iPhone
# Copyright (c) 2026 Aryan Suthar. All Rights Reserved.
#
# PROPRIETARY AND CONFIDENTIAL
# Unauthorized copying, distribution, modification, or use of this file,
# via any medium, is strictly prohibited without the express written
# permission of the copyright owner.
#
# For licensing inquiries: aryanrajendrasuthar@gmail.com

"""Download a base model from HuggingFace with SHA-256 checksum verification."""

import argparse
import hashlib
import logging
import os
import sys
from pathlib import Path
from typing import Optional

import yaml
from huggingface_hub import hf_hub_download, snapshot_download
from huggingface_hub.utils import EntryNotFoundError, RepositoryNotFoundError
from tqdm import tqdm

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

CACHE_DIR = Path.home() / ".pocketmind" / "models" / "raw"
CONFIGS_DIR = Path(__file__).parent.parent / "configs"
CHECKSUM_FILE = "checksums.sha256"


def load_config(model_id: str) -> dict:  # type: ignore[type-arg]
    """Load YAML config for the given model ID."""
    config_path = CONFIGS_DIR / f"{model_id}.yaml"
    if not config_path.exists():
        raise FileNotFoundError(
            f"No config found for model '{model_id}'. "
            f"Expected: {config_path}"
        )
    with open(config_path, "r") as f:
        return yaml.safe_load(f)  # type: ignore[no-any-return]


def compute_sha256(file_path: Path, chunk_size: int = 1 << 20) -> str:
    """Compute SHA-256 hash of a file, reading in chunks to avoid OOM."""
    sha256 = hashlib.sha256()
    file_size = file_path.stat().st_size
    with open(file_path, "rb") as f:
        with tqdm(
            total=file_size,
            unit="B",
            unit_scale=True,
            desc=f"Verifying {file_path.name}",
            leave=False,
        ) as pbar:
            for chunk in iter(lambda: f.read(chunk_size), b""):
                sha256.update(chunk)
                pbar.update(len(chunk))
    return sha256.hexdigest()


def load_published_checksums(repo_id: str, output_dir: Path) -> dict[str, str]:
    """
    Download the published SHA-256 checksum file from HuggingFace.

    Returns a dict mapping filename → expected_sha256.
    If no checksum file is published, returns an empty dict and logs a warning.
    """
    try:
        checksum_path = hf_hub_download(
            repo_id=repo_id,
            filename=CHECKSUM_FILE,
            local_dir=output_dir,
        )
        checksums: dict[str, str] = {}
        with open(checksum_path, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split()
                if len(parts) == 2:
                    sha256_hex, filename = parts
                    checksums[filename] = sha256_hex
        logger.info("Loaded %d checksums from %s", len(checksums), CHECKSUM_FILE)
        return checksums
    except EntryNotFoundError:
        logger.warning(
            "No '%s' file found in repo '%s'. "
            "Skipping checksum verification.",
            CHECKSUM_FILE,
            repo_id,
        )
        return {}


def verify_file(file_path: Path, expected_checksums: dict[str, str]) -> bool:
    """
    Verify a file's SHA-256 against expected_checksums.

    Returns True if verified or if no checksum is available (logs warning).
    Returns False if checksum mismatch.
    """
    filename = file_path.name
    if filename not in expected_checksums:
        logger.warning("No checksum available for '%s'. Skipping verification.", filename)
        return True

    logger.info("Verifying SHA-256 for '%s'...", filename)
    actual = compute_sha256(file_path)
    expected = expected_checksums[filename]

    if actual != expected:
        logger.error(
            "SHA-256 MISMATCH for '%s'!\n  Expected: %s\n  Actual:   %s",
            filename,
            expected,
            actual,
        )
        return False

    logger.info("SHA-256 verified for '%s'. ✓", filename)
    return True


def download_model(
    model_id: str,
    token: Optional[str] = None,
    force: bool = False,
) -> Path:
    """
    Download model from HuggingFace and verify checksums.

    Args:
        model_id: One of the model IDs defined in configs/ (e.g. 'llama32_1b').
        token: HuggingFace access token for gated models.
        force: Re-download even if output directory already exists.

    Returns:
        Path to the downloaded model directory.
    """
    config = load_config(model_id)
    repo_id: str = config["huggingface_repo"]
    output_dir = CACHE_DIR / model_id

    if output_dir.exists() and not force:
        logger.info(
            "Model '%s' already downloaded at '%s'. Use --force to re-download.",
            model_id,
            output_dir,
        )
        return output_dir

    output_dir.mkdir(parents=True, exist_ok=True)
    logger.info("Downloading '%s' from HuggingFace repo '%s'...", model_id, repo_id)
    logger.info("Destination: %s", output_dir)

    try:
        snapshot_download(
            repo_id=repo_id,
            local_dir=str(output_dir),
            token=token,
            ignore_patterns=["*.msgpack", "flax_model*", "tf_model*", "rust_model*"],
        )
    except RepositoryNotFoundError:
        logger.error(
            "Repository '%s' not found. "
            "Check the repo ID in configs/%s.yaml and ensure you have access. "
            "For gated models, provide --token.",
            repo_id,
            model_id,
        )
        sys.exit(1)

    logger.info("Download complete. Verifying file integrity...")

    expected_checksums = load_published_checksums(repo_id, output_dir)

    all_verified = True
    for file_path in sorted(output_dir.rglob("*")):
        if not file_path.is_file():
            continue
        # Only verify model weight files — skip metadata
        if file_path.suffix in {".safetensors", ".bin", ".gguf", ".pt"}:
            if not verify_file(file_path, expected_checksums):
                all_verified = False

    if not all_verified:
        logger.error(
            "Checksum verification failed for one or more files in '%s'. "
            "The download may be corrupted. Delete '%s' and retry.",
            output_dir,
            output_dir,
        )
        sys.exit(1)

    logger.info("All files verified. Model '%s' ready at: %s", model_id, output_dir)
    return output_dir


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Download a PocketMind base model from HuggingFace."
    )
    parser.add_argument(
        "--model",
        required=True,
        choices=["llama32_1b", "llama32_3b", "phi3_mini"],
        help="Model ID corresponding to a config in configs/.",
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("HF_TOKEN"),
        help="HuggingFace access token. Defaults to HF_TOKEN env var.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-download even if the model directory already exists.",
    )
    args = parser.parse_args()

    download_model(
        model_id=args.model,
        token=args.token,
        force=args.force,
    )


if __name__ == "__main__":
    main()
