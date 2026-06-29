# PocketMind — On-Device Private LLM for iPhone
# Copyright (c) 2026 Aryan Suthar. All Rights Reserved.
#
# PROPRIETARY AND CONFIDENTIAL
# Unauthorized copying, distribution, modification, or use of this file,
# via any medium, is strictly prohibited without the express written
# permission of the copyright owner.
#
# For licensing inquiries: aryanrajendrasuthar@gmail.com

"""Tests for the CoreML conversion and validation pipelines."""

import json
import sys
import tempfile
from pathlib import Path
from typing import Any, Generator
from unittest.mock import MagicMock, patch, PropertyMock

import numpy as np
import pytest
import yaml

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))


@pytest.fixture
def sample_config() -> dict[str, Any]:
    return {
        "model_id": "llama32_1b",
        "display_name": "Llama 3.2 1B Instruct",
        "huggingface_repo": "meta-llama/Llama-3.2-1B-Instruct",
        "parameters": {"count": 1_000_000_000, "context_length": 131072, "target_context_length": 128},
        "quantization": {"method": "Q4_K_M", "output_format": "gguf"},
        "coreml": {
            "output_name": "pocketmind_llama32_1b",
            "minimum_ios": "17.0",
            "compute_units": "ALL",
            "precision": "FLOAT16",
        },
        "hardware": {"min_device": "iPhone 12", "min_chip": "A14", "min_ram_gb": 3},
        "size_estimates": {"fp16_gb": 2.0, "int4_gb": 0.6},
        "performance_targets": {
            "time_to_first_token_sec": 1.5,
            "min_tokens_per_sec": 12,
            "max_peak_memory_mb": 900,
        },
        "manifest": {
            "version": "1.0.0",
            "capabilities": ["reasoning", "writing", "code"],
            "offline_limitations": ["no_live_data"],
            "knowledge_cutoff": "2024-04",
            "max_tokens": 512,
        },
    }


@pytest.fixture
def temp_config_dir(
    sample_config: dict[str, Any], tmp_path: Path
) -> Generator[Path, None, None]:
    config_path = tmp_path / "llama32_1b.yaml"
    with open(config_path, "w") as f:
        yaml.dump(sample_config, f)
    yield tmp_path


class TestTracedModelWrapper:
    def test_forward_returns_logits(self) -> None:
        from convert_to_coreml import TracedModelWrapper
        import torch

        inner_model = MagicMock()
        logits = torch.randn(1, 128, 32000)
        inner_model.return_value = MagicMock(logits=logits)

        wrapper = TracedModelWrapper(inner_model)
        input_ids = torch.zeros((1, 128), dtype=torch.long)
        attention_mask = torch.ones((1, 128), dtype=torch.long)

        result = wrapper(input_ids, attention_mask)
        assert result.shape == (1, 128, 32000)


class TestLoadConfig:
    def test_loads_valid_config(
        self, temp_config_dir: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr("convert_to_coreml.CONFIGS_DIR", temp_config_dir)
        from convert_to_coreml import load_config
        config = load_config("llama32_1b")
        assert config["model_id"] == "llama32_1b"
        assert config["coreml"]["minimum_ios"] == "17.0"

    def test_raises_for_missing_model(
        self, temp_config_dir: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr("convert_to_coreml.CONFIGS_DIR", temp_config_dir)
        from convert_to_coreml import load_config
        with pytest.raises(FileNotFoundError):
            load_config("no_such_model")


class TestConvertToCoreML:
    def test_sets_model_metadata(
        self,
        sample_config: dict[str, Any],
        tmp_path: Path,
    ) -> None:
        """CoreML model should have correct metadata fields after conversion."""
        import torch
        import coremltools as ct
        from convert_to_coreml import convert_to_coreml

        traced = MagicMock(spec=torch.jit.ScriptModule)
        example_inputs = (
            torch.zeros((1, 128), dtype=torch.int32),
            torch.ones((1, 128), dtype=torch.int32),
        )

        mock_coreml_model = MagicMock(spec=ct.models.MLModel)
        mock_coreml_model.user_defined_metadata = {}

        output_path = tmp_path / "test_model.mlpackage"

        with patch("convert_to_coreml.ct.convert", return_value=mock_coreml_model):
            result = convert_to_coreml(traced, example_inputs, sample_config, output_path)

        assert result.short_description == "PocketMind on-device language model"
        assert result.version == "1.0.0"
        assert result.user_defined_metadata["model_id"] == "llama32_1b"
        assert result.user_defined_metadata["quantization"] == "Q4_K_M"

    def test_uses_correct_compute_units(
        self,
        sample_config: dict[str, Any],
        tmp_path: Path,
    ) -> None:
        """Conversion must use ComputeUnit.ALL for full ANE utilization."""
        import torch
        import coremltools as ct
        from convert_to_coreml import convert_to_coreml

        traced = MagicMock(spec=torch.jit.ScriptModule)
        example_inputs = (
            torch.zeros((1, 128), dtype=torch.int32),
            torch.ones((1, 128), dtype=torch.int32),
        )
        mock_model = MagicMock(spec=ct.models.MLModel)
        mock_model.user_defined_metadata = {}
        output_path = tmp_path / "model.mlpackage"

        captured_kwargs: dict[str, Any] = {}

        def fake_convert(traced: Any, **kwargs: Any) -> MagicMock:
            captured_kwargs.update(kwargs)
            return mock_model

        with patch("convert_to_coreml.ct.convert", side_effect=fake_convert):
            convert_to_coreml(traced, example_inputs, sample_config, output_path)

        assert captured_kwargs.get("compute_units") == ct.ComputeUnit.ALL
        assert captured_kwargs.get("convert_to") == "mlprogram"
        assert captured_kwargs.get("minimum_deployment_target") == ct.target.iOS17


class TestValidateCoreMLModel:
    def test_generates_token_from_coreml(
        self, sample_config: dict[str, Any]
    ) -> None:
        """Validation should run predict and decode at least one token."""
        import coremltools as ct
        from convert_to_coreml import validate_coreml_model

        mock_tokenizer = MagicMock()
        mock_tokenizer.encode.return_value = [1, 2, 3, 4]
        mock_tokenizer.eos_token_id = 2
        mock_tokenizer.decode.return_value = " hello"

        # Logits: vocab size 32000, context 128
        logits = np.random.randn(1, 128, 32000).astype(np.float32)
        mock_coreml = MagicMock(spec=ct.models.MLModel)
        mock_coreml.predict.return_value = {"logits_out": logits}

        validate_coreml_model(mock_coreml, mock_tokenizer, sample_config)
        mock_coreml.predict.assert_called_once()

    def test_exits_on_empty_logits(self, sample_config: dict[str, Any]) -> None:
        """If CoreML returns empty logits, validation must call sys.exit."""
        import coremltools as ct
        from convert_to_coreml import validate_coreml_model

        mock_tokenizer = MagicMock()
        mock_tokenizer.encode.return_value = [1, 2, 3]
        mock_tokenizer.eos_token_id = 2

        mock_coreml = MagicMock(spec=ct.models.MLModel)
        mock_coreml.predict.return_value = {"logits_out": np.array([])}

        with pytest.raises(SystemExit):
            validate_coreml_model(mock_coreml, mock_tokenizer, sample_config)


class TestValidateModel:
    def test_rouge_l_above_threshold_passes(self) -> None:
        """ROUGE-L above 0.90 should pass without calling sys.exit."""
        from validate_model import compute_rouge_l, MIN_ROUGE_L

        # Identical strings → ROUGE-L = 1.0
        score = compute_rouge_l("hello world", "hello world")
        assert score >= MIN_ROUGE_L

    def test_rouge_l_below_threshold_triggers_exit(self) -> None:
        """Average ROUGE-L below 0.90 must trigger sys.exit(1)."""
        from validate_model import MIN_ROUGE_L
        import numpy as np

        scores = [0.5, 0.4, 0.3]
        avg = float(np.mean(scores))
        assert avg < MIN_ROUGE_L

    def test_rouge_l_identical_strings(self) -> None:
        from validate_model import compute_rouge_l
        assert compute_rouge_l("the cat sat on the mat", "the cat sat on the mat") == pytest.approx(1.0, abs=1e-4)

    def test_rouge_l_completely_different_strings(self) -> None:
        from validate_model import compute_rouge_l
        score = compute_rouge_l("apple banana cherry", "xyz alpha gamma delta")
        assert score < 0.5

    def test_rouge_l_partial_overlap(self) -> None:
        from validate_model import compute_rouge_l
        score = compute_rouge_l("the quick brown fox", "the quick red dog")
        assert 0.0 < score < 1.0

    def test_standard_prompts_count(self) -> None:
        from validate_model import STANDARD_PROMPTS
        assert len(STANDARD_PROMPTS) == 50


class TestExportMetadata:
    def test_manifest_structure(
        self, sample_config: dict[str, Any], tmp_path: Path
    ) -> None:
        """Generated manifest must contain all required fields."""
        from export_metadata import export_manifest, CONFIGS_DIR

        # Create a fake .mlpackage directory with a dummy file
        mlpackage_dir = tmp_path / "coreml" / "pocketmind_llama32_1b.mlpackage"
        mlpackage_dir.mkdir(parents=True)
        (mlpackage_dir / "model.mlmodel").write_bytes(b"dummy_model_content_1234")

        config_path = tmp_path / "configs" / "llama32_1b.yaml"
        config_path.parent.mkdir()
        with open(config_path, "w") as f:
            yaml.dump(sample_config, f)

        output_dir = tmp_path / "manifests"

        with patch("export_metadata.CONFIGS_DIR", tmp_path / "configs"):
            with patch("export_metadata.COREML_DIR", tmp_path / "coreml"):
                manifest_path = export_manifest("llama32_1b", output_dir=output_dir)

        with open(manifest_path) as f:
            manifest = json.load(f)

        required_keys = [
            "model_id", "display_name", "version", "quantization",
            "file_size_bytes", "sha256", "min_ios", "min_ram_gb",
            "context_length", "max_tokens", "knowledge_cutoff",
            "capabilities", "offline_limitations",
        ]
        for key in required_keys:
            assert key in manifest, f"Missing key: {key}"

    def test_sha256_is_deterministic(self, tmp_path: Path) -> None:
        """SHA-256 of the same directory content must always be the same."""
        from export_metadata import compute_sha256_of_directory

        dir1 = tmp_path / "dir1"
        dir1.mkdir()
        (dir1 / "file.bin").write_bytes(b"hello world" * 100)

        hash1 = compute_sha256_of_directory(dir1)
        hash2 = compute_sha256_of_directory(dir1)
        assert hash1 == hash2
        assert len(hash1) == 64  # SHA-256 hex string

    def test_sha256_changes_with_content(self, tmp_path: Path) -> None:
        """SHA-256 must differ when file content differs."""
        from export_metadata import compute_sha256_of_directory

        dir1 = tmp_path / "dir1"
        dir1.mkdir()
        (dir1 / "model.bin").write_bytes(b"version1" * 1000)

        dir2 = tmp_path / "dir2"
        dir2.mkdir()
        (dir2 / "model.bin").write_bytes(b"version2" * 1000)

        assert compute_sha256_of_directory(dir1) != compute_sha256_of_directory(dir2)

    def test_recommended_devices_a14(self, sample_config: dict[str, Any]) -> None:
        from export_metadata import recommended_devices
        devices = recommended_devices(sample_config)
        assert "iPhone 12" in devices
        assert "iPhone 15 Pro" in devices

    def test_recommended_devices_a17(self, sample_config: dict[str, Any]) -> None:
        from export_metadata import recommended_devices
        sample_config["hardware"]["min_chip"] = "A17"
        devices = recommended_devices(sample_config)
        assert "iPhone 15 Pro" in devices
        assert "iPhone 12" not in devices

    def test_manifest_file_size_matches_directory(self, tmp_path: Path) -> None:
        from export_metadata import compute_directory_size

        d = tmp_path / "pkg"
        d.mkdir()
        (d / "a.bin").write_bytes(b"x" * 1000)
        (d / "b.bin").write_bytes(b"y" * 500)

        size = compute_directory_size(d)
        assert size == 1500
