# PocketMind — On-Device Private LLM for iPhone
# Copyright (c) 2026 Aryan Suthar. All Rights Reserved.
#
# PROPRIETARY AND CONFIDENTIAL
# Unauthorized copying, distribution, modification, or use of this file,
# via any medium, is strictly prohibited without the express written
# permission of the copyright owner.
#
# For licensing inquiries: aryanrajendrasuthar@gmail.com

# ─── Config ───────────────────────────────────────────────────────────────────
SCHEME       := PocketMind
WORKSPACE    := PocketMind/PocketMind.xcworkspace
PROJECT      := PocketMind/PocketMind.xcodeproj
SIM          := platform=iOS Simulator,name=iPhone 16 Pro
PYTHON       := python3
PY_DIR       := ModelTooling

.PHONY: help setup lint analyze test uitest build release \
        pipeline pipeline-1b generate-project clean secrets-scan

# ─── Default ──────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  PocketMind — Development Commands"
	@echo ""
	@echo "  iOS:"
	@echo "    make setup           Install dependencies (mint, swiftlint, xcodegen)"
	@echo "    make generate-project  Regenerate Xcode project from project.yml"
	@echo "    make lint            Run SwiftLint (strict)"
	@echo "    make analyze         Run xcodebuild analyze"
	@echo "    make test            Run unit tests on simulator"
	@echo "    make uitest          Run UI tests on simulator"
	@echo "    make build           Debug build for simulator"
	@echo "    make release         Archive Release build"
	@echo ""
	@echo "  Python model pipeline:"
	@echo "    make pipeline-1b     Download → quantize → convert → validate (Llama 1B)"
	@echo "    make py-lint         flake8 + mypy on ModelTooling"
	@echo "    make py-test         pytest on ModelTooling"
	@echo ""
	@echo "  Security:"
	@echo "    make secrets-scan    TruffleHog full history scan"
	@echo ""
	@echo "  General:"
	@echo "    make clean           Remove DerivedData and Python caches"
	@echo ""

# ─── Setup ────────────────────────────────────────────────────────────────────
setup:
	@command -v xcodegen >/dev/null || brew install xcodegen
	@command -v swiftlint >/dev/null || brew install swiftlint
	@command -v trufflehog >/dev/null || brew install trufflehog
	@$(MAKE) generate-project
	@echo "Setup complete."

generate-project:
	cd PocketMind && xcodegen generate

# ─── iOS ──────────────────────────────────────────────────────────────────────
lint:
	cd PocketMind && swiftlint --strict

analyze:
	xcodebuild analyze \
	  -workspace $(WORKSPACE) \
	  -scheme $(SCHEME) \
	  -destination "$(SIM)" \
	  | xcpretty

test:
	xcodebuild test \
	  -workspace $(WORKSPACE) \
	  -scheme $(SCHEME) \
	  -destination "$(SIM)" \
	  -testPlan PocketMindTests \
	  | xcpretty

uitest:
	xcodebuild test \
	  -workspace $(WORKSPACE) \
	  -scheme $(SCHEME) \
	  -destination "$(SIM)" \
	  -testPlan PocketMindUITests \
	  | xcpretty

build:
	xcodebuild build \
	  -workspace $(WORKSPACE) \
	  -scheme $(SCHEME) \
	  -destination "$(SIM)" \
	  -configuration Debug \
	  | xcpretty

release:
	xcodebuild archive \
	  -workspace $(WORKSPACE) \
	  -scheme $(SCHEME) \
	  -configuration Release \
	  -archivePath build/PocketMind.xcarchive \
	  | xcpretty
	@echo "Archive at build/PocketMind.xcarchive — upload via Xcode Organizer."

# ─── Python pipeline ──────────────────────────────────────────────────────────
py-lint:
	cd $(PY_DIR) && $(PYTHON) -m flake8 scripts/ tests/ && $(PYTHON) -m mypy scripts/ --strict

py-test:
	cd $(PY_DIR) && $(PYTHON) -m pytest tests/ -v

pipeline-1b:
	@echo "Running full model pipeline for Llama 3.2 1B…"
	cd $(PY_DIR) && \
	  $(PYTHON) scripts/download_base_model.py --model meta-llama/Llama-3.2-1B-Instruct && \
	  $(PYTHON) scripts/quantize.py --model meta-llama/Llama-3.2-1B-Instruct && \
	  $(PYTHON) scripts/convert_to_coreml.py --config configs/llama32_1b.yaml && \
	  $(PYTHON) scripts/validate_model.py --config configs/llama32_1b.yaml && \
	  $(PYTHON) scripts/export_metadata.py --config configs/llama32_1b.yaml
	@echo "Pipeline complete. Manifest at ModelTooling/output/llama32_1b/model_manifest.json"

# ─── Security ─────────────────────────────────────────────────────────────────
secrets-scan:
	trufflehog git file://. --only-verified --fail

# ─── Clean ────────────────────────────────────────────────────────────────────
clean:
	rm -rf ~/Library/Developer/Xcode/DerivedData/PocketMind-*
	find $(PY_DIR) -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find $(PY_DIR) -type d -name .mypy_cache -exec rm -rf {} + 2>/dev/null || true
	find $(PY_DIR) -type d -name .pytest_cache -exec rm -rf {} + 2>/dev/null || true
	find $(PY_DIR) -name "*.pyc" -delete 2>/dev/null || true
	@echo "Clean complete."
