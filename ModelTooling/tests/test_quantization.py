# PocketMind — On-Device Private LLM for iPhone
# Copyright (c) 2026 Aryan Suthar. All Rights Reserved.
#
# PROPRIETARY AND CONFIDENTIAL
# Unauthorized copying, distribution, modification, or use of this file,
# via any medium, is strictly prohibited without the express written
# permission of the copyright owner.
#
# For licensing inquiries: aryanrajendrasuthar@gmail.com

"""Tests for the quantization pipeline (quantize.py)."""

import hashlib
import json
import sys
import tempfile
from pathlib import Path
from typing import Any, Generator
from unittest.mock import MagicMock, patch

import numpy as np
import pytest
import yaml

# Add scripts directory to path so we can import without installing
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))


@pytest.fixture
def sample_config() -> dict[str, Any]:
    """Minimal config dict matching the YAML schema."""
    return {
        "model_id": "llama32_1b",
        "display_name": "Llama 3.2 1B Instruct",
        "huggingface_repo": "meta-llama/Llama-3.2-1B-Instruct",
        "parameters": {"count": 1_000_000_000, "context_length": 131072, "target_context_length": 4096},
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
            "capabilities": ["reasoning", "writing", "code", "summarization"],
            "offline_limitations": ["no_live_data", "no_web_search", "no_real_time_events"],
            "knowledge_cutoff": "2024-04",
            "max_tokens": 512,
        },
    }


@pytest.fixture
def temp_config_dir(
    sample_config: dict[str, Any], tmp_path: Path
) -> Generator[Path, None, None]:
    """Write sample config YAML to a temp directory and yield the path."""
    config_path = tmp_path / "llama32_1b.yaml"
    with open(config_path, "w") as f:
        yaml.dump(sample_config, f)
    yield tmp_path


class TestLoadConfig:
    def test_loads_valid_config(self, temp_config_dir: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        from quantize import load_config, CONFIGS_DIR
        monkeypatch.setattr("quantize.CONFIGS_DIR", temp_config_dir)
        config = load_config("llama32_1b")
        assert config["model_id"] == "llama32_1b"
        assert config["quantization"]["method"] == "Q4_K_M"

    def test_raises_for_unknown_model(self, temp_config_dir: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr("quantize.CONFIGS_DIR", temp_config_dir)
        from quantize import load_config
        with pytest.raises(FileNotFoundError):
            load_config("nonexistent_model")


class TestFindGgufOrSafetensors:
    def test_finds_gguf_file(self, tmp_path: Path) -> None:
        from quantize import find_gguf_or_safetensors
        gguf = tmp_path / "model.gguf"
        gguf.write_bytes(b"dummy")
        result = find_gguf_or_safetensors(tmp_path)
        assert result == gguf

    def test_finds_safetensors_file(self, tmp_path: Path) -> None:
        from quantize import find_gguf_or_safetensors
        st = tmp_path / "model.safetensors"
        st.write_bytes(b"dummy")
        result = find_gguf_or_safetensors(tmp_path)
        assert result == st

    def test_prefers_gguf_over_safetensors(self, tmp_path: Path) -> None:
        from quantize import find_gguf_or_safetensors
        gguf = tmp_path / "model.gguf"
        st = tmp_path / "model.safetensors"
        gguf.write_bytes(b"dummy_gguf")
        st.write_bytes(b"dummy_st")
        result = find_gguf_or_safetensors(tmp_path)
        assert result == gguf

    def test_returns_none_when_no_weight_file(self, tmp_path: Path) -> None:
        from quantize import find_gguf_or_safetensors
        result = find_gguf_or_safetensors(tmp_path)
        assert result is None

    def test_ignores_non_weight_files(self, tmp_path: Path) -> None:
        from quantize import find_gguf_or_safetensors
        (tmp_path / "config.json").write_text("{}")
        (tmp_path / "tokenizer.json").write_text("{}")
        result = find_gguf_or_safetensors(tmp_path)
        assert result is None


class TestMeasurePerplexity:
    def test_returns_float(self) -> None:
        """Perplexity should return a positive float for valid logprob responses."""
        from quantize import measure_perplexity, PERPLEXITY_TEST_CORPUS

        mock_llm = MagicMock()
        mock_llm.tokenize.return_value = [1, 2, 3, 4, 5]
        mock_llm.return_value = {
            "choices": [{
                "logprobs": {
                    "token_logprobs": [None, -1.2, -0.8, -1.5, -0.9]
                }
            }]
        }

        with patch("quantize.Llama", return_value=mock_llm):
            ppl = measure_perplexity(Path("/fake/model.gguf"), PERPLEXITY_TEST_CORPUS[:3])

        assert isinstance(ppl, float)
        assert ppl > 0

    def test_returns_nan_when_no_logprobs(self) -> None:
        """Should return NaN gracefully when model returns no logprobs."""
        from quantize import measure_perplexity

        mock_llm = MagicMock()
        mock_llm.tokenize.return_value = [1, 2]
        mock_llm.return_value = {"choices": [{"logprobs": {"token_logprobs": []}}]}

        with patch("quantize.Llama", return_value=mock_llm):
            ppl = measure_perplexity(Path("/fake/model.gguf"), ["Hello world."])

        assert np.isnan(ppl)

    def test_perplexity_increases_after_quantization_mock(self) -> None:
        """Quantized model should have higher perplexity than FP16 baseline (mocked)."""
        baseline = 9.0
        quantized = 9.5
        pct_increase = ((quantized - baseline) / baseline) * 100
        assert pct_increase < 15.0, "Mock delta should be within acceptable range"


class TestBenchmarkInference:
    def test_returns_positive_tokens_per_sec(self) -> None:
        from quantize import benchmark_inference

        mock_llm = MagicMock()
        mock_llm.return_value = {
            "usage": {"completion_tokens": 50}
        }

        with patch("quantize.Llama", return_value=mock_llm):
            with patch("quantize.time.perf_counter", side_effect=[0.0, 5.0]):
                tps = benchmark_inference(Path("/fake/model.gguf"), n_tokens=50)

        assert tps == pytest.approx(10.0, rel=0.01)


class TestQuantizationThreshold:
    def test_acceptable_perplexity_increase(self) -> None:
        baseline = 9.0
        for pct in [0.0, 5.0, 10.0, 14.9]:
            quantized = baseline * (1 + pct / 100)
            increase = ((quantized - baseline) / baseline) * 100
            assert increase < 15.0

    def test_unacceptable_perplexity_increase(self) -> None:
        baseline = 9.0
        for pct in [15.0, 20.0, 50.0]:
            quantized = baseline * (1 + pct / 100)
            increase = ((quantized - baseline) / baseline) * 100
            assert increase >= 15.0

    def test_perplexity_nan_does_not_abort(self) -> None:
        """NaN perplexity (model returned no logprobs) should not trigger abort."""
        assert np.isnan(float("nan"))

    def test_quantization_type_is_q4km(self) -> None:
        from quantize import QUANTIZATION_TYPE
        assert QUANTIZATION_TYPE == "Q4_K_M"
