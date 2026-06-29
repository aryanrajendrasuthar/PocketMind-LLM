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
Integration smoke tests for the model pipeline scripts.

These tests verify that:
- Each script module is importable with no side-effects on import.
- Config loading works end-to-end for all three model configs.
- Key constants and functions exist with the expected signatures.
- Utility functions (SHA-256, ROUGE-L, manifest structure) produce
  correct output without requiring a real GPU or network call.
"""

import hashlib
import importlib
import json
import os
import tempfile
from pathlib import Path
from typing import Any

import pytest

# ─── Helpers ──────────────────────────────────────────────────────────────────

SCRIPTS_DIR = Path(__file__).parent.parent / "scripts"
CONFIGS_DIR = Path(__file__).parent.parent / "configs"


def import_script(name: str) -> Any:
    """Import a script module by filename (without .py)."""
    import sys
    if str(SCRIPTS_DIR) not in sys.path:
        sys.path.insert(0, str(SCRIPTS_DIR))
    return importlib.import_module(name)


# ─── Config loading ───────────────────────────────────────────────────────────

class TestConfigLoading:
    """All three YAML model configs must load cleanly with required fields."""

    REQUIRED_FIELDS = [
        "model_id", "quantization_type", "coreml", "hardware",
        "performance", "manifest",
    ]
    CONFIGS = ["llama32_1b.yaml", "llama32_3b.yaml", "phi3_mini.yaml"]

    @pytest.mark.parametrize("config_file", CONFIGS)
    def test_config_has_required_fields(self, config_file: str) -> None:
        import yaml  # type: ignore[import]
        config_path = CONFIGS_DIR / config_file
        assert config_path.exists(), f"Config not found: {config_path}"
        with open(config_path) as f:
            config = yaml.safe_load(f)
        for field in self.REQUIRED_FIELDS:
            assert field in config, f"'{field}' missing from {config_file}"

    @pytest.mark.parametrize("config_file", CONFIGS)
    def test_model_id_is_non_empty_string(self, config_file: str) -> None:
        import yaml  # type: ignore[import]
        with open(CONFIGS_DIR / config_file) as f:
            config = yaml.safe_load(f)
        assert isinstance(config["model_id"], str)
        assert len(config["model_id"]) > 0

    @pytest.mark.parametrize("config_file", CONFIGS)
    def test_quantization_type_is_q4km(self, config_file: str) -> None:
        import yaml  # type: ignore[import]
        with open(CONFIGS_DIR / config_file) as f:
            config = yaml.safe_load(f)
        assert config["quantization_type"] == "Q4_K_M"


# ─── download_base_model ──────────────────────────────────────────────────────

class TestDownloadScript:
    def test_module_importable(self) -> None:
        mod = import_script("download_base_model")
        assert mod is not None

    def test_compute_sha256_returns_hex_string(self) -> None:
        mod = import_script("download_base_model")
        with tempfile.NamedTemporaryFile(delete=False, suffix=".bin") as f:
            f.write(b"pocketmind-test-content")
            path = f.name
        try:
            result = mod.compute_sha256(path)
            assert isinstance(result, str)
            assert len(result) == 64  # SHA-256 hex digest is always 64 chars
            assert all(c in "0123456789abcdef" for c in result)
        finally:
            os.unlink(path)

    def test_compute_sha256_deterministic(self) -> None:
        mod = import_script("download_base_model")
        with tempfile.NamedTemporaryFile(delete=False, suffix=".bin") as f:
            f.write(b"determinism-check")
            path = f.name
        try:
            assert mod.compute_sha256(path) == mod.compute_sha256(path)
        finally:
            os.unlink(path)

    def test_compute_sha256_different_for_different_content(self) -> None:
        mod = import_script("download_base_model")
        with tempfile.NamedTemporaryFile(delete=False) as f1, \
             tempfile.NamedTemporaryFile(delete=False) as f2:
            f1.write(b"content-a")
            f2.write(b"content-b")
            path1, path2 = f1.name, f2.name
        try:
            assert mod.compute_sha256(path1) != mod.compute_sha256(path2)
        finally:
            os.unlink(path1)
            os.unlink(path2)

    def test_load_published_checksums_returns_dict_for_missing_file(self) -> None:
        mod = import_script("download_base_model")
        result = mod.load_published_checksums("/nonexistent/path/checksums.sha256")
        assert isinstance(result, dict)


# ─── quantize ─────────────────────────────────────────────────────────────────

class TestQuantizeScript:
    def test_module_importable(self) -> None:
        mod = import_script("quantize")
        assert mod is not None

    def test_quantization_type_constant_is_q4km(self) -> None:
        mod = import_script("quantize")
        assert mod.QUANTIZATION_TYPE == "Q4_K_M"

    def test_max_perplexity_increase_is_15(self) -> None:
        mod = import_script("quantize")
        assert mod.MAX_PERPLEXITY_INCREASE_PCT == 15.0

    def test_perplexity_threshold_acceptable(self) -> None:
        mod = import_script("quantize")
        assert mod.perplexity_increase_acceptable(10.0, 11.0) is True

    def test_perplexity_threshold_unacceptable(self) -> None:
        mod = import_script("quantize")
        assert mod.perplexity_increase_acceptable(10.0, 12.0) is False

    def test_perplexity_threshold_exactly_at_limit_is_acceptable(self) -> None:
        mod = import_script("quantize")
        # 10.0 → 11.5 is exactly +15%
        assert mod.perplexity_increase_acceptable(10.0, 11.5) is True

    def test_find_gguf_or_safetensors_returns_none_for_empty_dir(self) -> None:
        mod = import_script("quantize")
        with tempfile.TemporaryDirectory() as d:
            result = mod.find_gguf_or_safetensors(d)
            assert result is None


# ─── convert_to_coreml ────────────────────────────────────────────────────────

class TestConvertScript:
    def test_module_importable(self) -> None:
        mod = import_script("convert_to_coreml")
        assert mod is not None

    def test_compute_rouge_l_identical_strings(self) -> None:
        mod = import_script("convert_to_coreml")
        score = mod.compute_rouge_l("the quick brown fox", "the quick brown fox")
        assert abs(score - 1.0) < 1e-6

    def test_compute_rouge_l_empty_strings(self) -> None:
        mod = import_script("convert_to_coreml")
        score = mod.compute_rouge_l("", "")
        assert score == 0.0

    def test_compute_rouge_l_different_strings(self) -> None:
        mod = import_script("convert_to_coreml")
        score = mod.compute_rouge_l("the cat sat", "a dog ran")
        assert 0.0 <= score < 1.0

    def test_compute_rouge_l_partial_overlap(self) -> None:
        mod = import_script("convert_to_coreml")
        score = mod.compute_rouge_l("the quick brown fox", "the quick red fox")
        assert 0.5 < score < 1.0


# ─── validate_model ───────────────────────────────────────────────────────────

class TestValidateScript:
    def test_module_importable(self) -> None:
        mod = import_script("validate_model")
        assert mod is not None

    def test_min_rouge_l_threshold_is_090(self) -> None:
        mod = import_script("validate_model")
        assert mod.MIN_ROUGE_L == 0.90

    def test_standard_prompts_count_is_50(self) -> None:
        mod = import_script("validate_model")
        assert len(mod.STANDARD_PROMPTS) == 50

    def test_all_standard_prompts_are_non_empty(self) -> None:
        mod = import_script("validate_model")
        for prompt in mod.STANDARD_PROMPTS:
            assert isinstance(prompt, str)
            assert len(prompt.strip()) > 0


# ─── export_metadata ──────────────────────────────────────────────────────────

class TestExportMetadataScript:
    def test_module_importable(self) -> None:
        mod = import_script("export_metadata")
        assert mod is not None

    def test_compute_sha256_of_directory_is_deterministic(self) -> None:
        mod = import_script("export_metadata")
        with tempfile.TemporaryDirectory() as d:
            # Write two files to ensure directory hashing is sorted
            Path(d, "b.bin").write_bytes(b"second")
            Path(d, "a.bin").write_bytes(b"first")
            hash1 = mod.compute_sha256_of_directory(d)
            hash2 = mod.compute_sha256_of_directory(d)
            assert hash1 == hash2
            assert len(hash1) == 64

    def test_compute_sha256_of_directory_changes_with_content(self) -> None:
        mod = import_script("export_metadata")
        with tempfile.TemporaryDirectory() as d:
            Path(d, "model.bin").write_bytes(b"original content")
            hash1 = mod.compute_sha256_of_directory(d)
            Path(d, "model.bin").write_bytes(b"changed content")
            hash2 = mod.compute_sha256_of_directory(d)
            assert hash1 != hash2

    def test_compute_directory_size_sums_file_sizes(self) -> None:
        mod = import_script("export_metadata")
        with tempfile.TemporaryDirectory() as d:
            Path(d, "file1.bin").write_bytes(b"a" * 1000)
            Path(d, "file2.bin").write_bytes(b"b" * 2000)
            size = mod.compute_directory_size(d)
            assert size == 3000

    def test_manifest_structure_has_all_required_keys(self) -> None:
        mod = import_script("export_metadata")
        required = [
            "model_id", "display_name", "version", "quantization",
            "file_size_bytes", "sha256", "min_ios", "min_ram_gb",
            "min_device", "min_chip", "recommended_devices",
            "context_length", "max_tokens", "knowledge_cutoff",
            "capabilities", "offline_limitations",
        ]
        # Build a minimal mock manifest and verify all keys are present in the template
        template = mod.build_manifest_template()
        for key in required:
            assert key in template, f"Key '{key}' missing from manifest template"

    def test_recommended_devices_a14_returns_iphone12(self) -> None:
        mod = import_script("export_metadata")
        devices = mod.recommended_devices("A14 Bionic")
        assert any("12" in d for d in devices)

    def test_recommended_devices_a17_returns_iphone15pro(self) -> None:
        mod = import_script("export_metadata")
        devices = mod.recommended_devices("A17 Pro")
        assert any("15 Pro" in d for d in devices)


# ─── train_classifier ─────────────────────────────────────────────────────────

class TestTrainClassifierScript:
    def test_module_importable(self) -> None:
        mod = import_script("train_classifier")
        assert mod is not None

    def test_training_examples_count_is_100(self) -> None:
        mod = import_script("train_classifier")
        assert len(mod.TRAINING_EXAMPLES) == 100

    def test_training_examples_have_two_classes(self) -> None:
        mod = import_script("train_classifier")
        labels = {label for _, label in mod.TRAINING_EXAMPLES}
        assert labels == {"live_data", "offline"}

    def test_training_examples_balanced(self) -> None:
        mod = import_script("train_classifier")
        live = sum(1 for _, l in mod.TRAINING_EXAMPLES if l == "live_data")
        offline = sum(1 for _, l in mod.TRAINING_EXAMPLES if l == "offline")
        assert live == offline == 50

    def test_minimum_accuracy_constant_is_80(self) -> None:
        mod = import_script("train_classifier")
        assert mod.MIN_ACCURACY == 0.80
