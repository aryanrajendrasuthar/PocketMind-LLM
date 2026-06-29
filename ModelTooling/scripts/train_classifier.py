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
Train and export the lightweight CapabilityBoundaryClassifier CoreML model.

This script produces a binary NLClassifier that distinguishes:
  - "fully_offline"       — the model can answer from training knowledge
  - "requires_live_data"  — the query needs real-time information

The output is a compiled .mlmodelc bundle that the iOS app loads via NLModel.
Target size: < 5 MB. Target accuracy: > 85% on a held-out test set.

Usage:
    python scripts/train_classifier.py [--output-dir PATH]
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Optional

import coremltools as ct
import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, classification_report
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

OUTPUT_DIR = Path.home() / ".pocketmind" / "classifier"
SCRIPTS_DIR = Path(__file__).parent

# ─── Training data ─────────────────────────────────────────────────────────────
# Each entry: (text, label)
# Labels: "fully_offline" | "requires_live_data"

TRAINING_DATA: list[tuple[str, str]] = [
    # ── requires_live_data ────────────────────────────────────────────────────
    ("What is the stock price of Apple today?", "requires_live_data"),
    ("What is Bitcoin worth right now?", "requires_live_data"),
    ("What is the current price of Ethereum?", "requires_live_data"),
    ("What is the weather like in New York today?", "requires_live_data"),
    ("Will it rain tomorrow in Los Angeles?", "requires_live_data"),
    ("What is today's weather forecast?", "requires_live_data"),
    ("What happened in the news today?", "requires_live_data"),
    ("What are the latest headlines?", "requires_live_data"),
    ("Who won the Super Bowl last night?", "requires_live_data"),
    ("What are the NFL scores today?", "requires_live_data"),
    ("What is the current interest rate?", "requires_live_data"),
    ("What is the current mortgage rate?", "requires_live_data"),
    ("Is the stock market up today?", "requires_live_data"),
    ("What time does Target close today?", "requires_live_data"),
    ("Is McDonald's open right now?", "requires_live_data"),
    ("What is the address of the nearest Starbucks?", "requires_live_data"),
    ("What's the phone number for the Apple Store?", "requires_live_data"),
    ("What crypto should I buy right now?", "requires_live_data"),
    ("What is the current exchange rate for EUR to USD?", "requires_live_data"),
    ("Who is currently leading the polls?", "requires_live_data"),
    ("What are the election results?", "requires_live_data"),
    ("What is the live score of the game?", "requires_live_data"),
    ("What movies are playing tonight?", "requires_live_data"),
    ("What is the current temperature outside?", "requires_live_data"),
    ("Is it going to snow this weekend?", "requires_live_data"),
    ("What is the Dow Jones at right now?", "requires_live_data"),
    ("What are the latest COVID stats?", "requires_live_data"),
    ("What just happened in the news?", "requires_live_data"),
    ("Tell me today's top stories", "requires_live_data"),
    ("What is the latest iPhone model price?", "requires_live_data"),
    ("What is Bitcoin trading at?", "requires_live_data"),
    ("Show me current stock prices", "requires_live_data"),
    ("What is the weather forecast for this week?", "requires_live_data"),
    ("Who won the game last night?", "requires_live_data"),
    ("What is the NASDAQ at today?", "requires_live_data"),
    ("Give me today's news summary", "requires_live_data"),
    ("What is the current prime rate?", "requires_live_data"),
    ("Are flights delayed at LAX today?", "requires_live_data"),
    ("What's the traffic like right now?", "requires_live_data"),
    ("Is the Fed raising rates today?", "requires_live_data"),
    ("What happened in the election?", "requires_live_data"),
    ("Latest NBA scores?", "requires_live_data"),
    ("What is today's Wordle answer?", "requires_live_data"),
    ("Check today's gas prices near me", "requires_live_data"),
    ("What is the current USD to JPY exchange rate?", "requires_live_data"),
    ("What is the S&P 500 today?", "requires_live_data"),
    ("What concerts are happening tonight?", "requires_live_data"),
    ("Who is currently president?", "requires_live_data"),
    ("What are today's sports scores?", "requires_live_data"),
    ("What is happening in the world today?", "requires_live_data"),

    # ── fully_offline ─────────────────────────────────────────────────────────
    ("Explain recursion in programming with an example", "fully_offline"),
    ("What is the capital of France?", "fully_offline"),
    ("Write a haiku about autumn leaves", "fully_offline"),
    ("What is 17 multiplied by 13?", "fully_offline"),
    ("Explain the water cycle", "fully_offline"),
    ("Write a Python function to binary search a list", "fully_offline"),
    ("What is Newton's first law of motion?", "fully_offline"),
    ("Summarize the French Revolution", "fully_offline"),
    ("What is machine learning?", "fully_offline"),
    ("Explain what a binary search tree is", "fully_offline"),
    ("How do I cook pasta al dente?", "fully_offline"),
    ("What are the planets in our solar system?", "fully_offline"),
    ("Write an email apologizing to a client", "fully_offline"),
    ("Explain blockchain technology", "fully_offline"),
    ("What is the Pythagorean theorem?", "fully_offline"),
    ("What is the difference between TCP and UDP?", "fully_offline"),
    ("Explain what DNA is", "fully_offline"),
    ("What is the speed of light?", "fully_offline"),
    ("How does photosynthesis work?", "fully_offline"),
    ("What is a hash map?", "fully_offline"),
    ("Write a short poem about the ocean", "fully_offline"),
    ("Explain quantum computing in simple terms", "fully_offline"),
    ("What is the difference between RAM and ROM?", "fully_offline"),
    ("How does a compiler work?", "fully_offline"),
    ("What are the primary colors?", "fully_offline"),
    ("Explain the concept of object-oriented programming", "fully_offline"),
    ("What is the history of the Roman Empire?", "fully_offline"),
    ("How do I sort a list in Python?", "fully_offline"),
    ("What is Ohm's law?", "fully_offline"),
    ("Explain the difference between mitosis and meiosis", "fully_offline"),
    ("Write a cover letter for a software engineer position", "fully_offline"),
    ("What is the time complexity of quicksort?", "fully_offline"),
    ("Explain what a RESTful API is", "fully_offline"),
    ("What is the Fibonacci sequence?", "fully_offline"),
    ("How does HTTPS work?", "fully_offline"),
    ("What is the greenhouse effect?", "fully_offline"),
    ("Explain supply and demand", "fully_offline"),
    ("What is a deadlock in operating systems?", "fully_offline"),
    ("Write a regex to match email addresses", "fully_offline"),
    ("Explain what encryption is", "fully_offline"),
    ("What is the capital of Japan?", "fully_offline"),
    ("How do black holes form?", "fully_offline"),
    ("Explain the current state of machine learning research", "fully_offline"),
    ("What is the theory of evolution?", "fully_offline"),
    ("Describe the current best practices for API design", "fully_offline"),
    ("What is the history of artificial intelligence?", "fully_offline"),
    ("Write a function that reverses a string in Swift", "fully_offline"),
    ("What is the difference between a virus and a bacterium?", "fully_offline"),
    ("Explain what containerization means in software", "fully_offline"),
    ("What is dark matter?", "fully_offline"),
]


def build_pipeline() -> Pipeline:
    """TF-IDF + Logistic Regression pipeline optimized for short text classification."""
    return Pipeline([
        (
            "tfidf",
            TfidfVectorizer(
                ngram_range=(1, 3),
                max_features=8000,
                sublinear_tf=True,
                strip_accents="unicode",
                analyzer="word",
                token_pattern=r"\b\w+\b",
                min_df=1,
            ),
        ),
        (
            "clf",
            LogisticRegression(
                C=2.0,
                max_iter=1000,
                solver="lbfgs",
                class_weight="balanced",
                random_state=42,
            ),
        ),
    ])


def train(output_dir: Optional[Path] = None) -> Path:
    """
    Train, evaluate, and export the capability classifier.

    Returns the path to the compiled .mlmodelc bundle.
    """
    output_dir = output_dir or OUTPUT_DIR
    output_dir.mkdir(parents=True, exist_ok=True)

    texts = [item[0] for item in TRAINING_DATA]
    labels = [item[1] for item in TRAINING_DATA]

    x_train, x_test, y_train, y_test = train_test_split(
        texts, labels, test_size=0.2, random_state=42, stratify=labels
    )

    logger.info("Training on %d samples, evaluating on %d...", len(x_train), len(x_test))

    pipeline = build_pipeline()
    pipeline.fit(x_train, y_train)

    y_pred = pipeline.predict(x_test)
    accuracy = accuracy_score(y_test, y_pred)
    logger.info("Test accuracy: %.1f%%", accuracy * 100)
    logger.info("\n%s", classification_report(y_test, y_pred))

    if accuracy < 0.80:
        logger.error(
            "Classifier accuracy (%.1f%%) is below the 80%% minimum. "
            "Add more training examples and retrain.",
            accuracy * 100,
        )
        sys.exit(1)

    # ── Export to CoreML ──────────────────────────────────────────────────────
    logger.info("Exporting to CoreML NLClassifier...")

    # Build the vocabulary from the fitted vectorizer
    vectorizer = pipeline.named_steps["tfidf"]
    clf = pipeline.named_steps["clf"]

    # Collect per-class coefficients and feature names for CoreML NLClassifier
    feature_names: list[str] = vectorizer.get_feature_names_out().tolist()
    classes: list[str] = clf.classes_.tolist()

    # Serialize model parameters to a JSON sidecar (loaded by the iOS app as fallback)
    sidecar = {
        "classes": classes,
        "accuracy": accuracy,
        "n_features": len(feature_names),
    }
    sidecar_path = output_dir / "classifier_meta.json"
    with open(sidecar_path, "w") as f:
        json.dump(sidecar, f, indent=2)
    logger.info("Metadata written: %s", sidecar_path)

    # Convert to CoreML using coremltools sklearn converter
    try:
        from coremltools.converters import sklearn as sklearn_converter

        coreml_model = sklearn_converter.convert(
            pipeline,
            input_features=[("text", str)],
            output_feature_names="label",
        )
        coreml_model.short_description = "PocketMind capability boundary classifier"
        coreml_model.author = "Aryan Suthar"
        coreml_model.version = "1.0.0"
        coreml_model.user_defined_metadata["accuracy"] = f"{accuracy:.4f}"
        coreml_model.user_defined_metadata["n_training_samples"] = str(len(x_train))

        mlmodel_path = output_dir / "CapabilityClassifier.mlmodel"
        coreml_model.save(str(mlmodel_path))
        logger.info("Saved: %s (%.1f KB)", mlmodel_path, mlmodel_path.stat().st_size / 1024)

    except Exception as exc:
        logger.warning(
            "coremltools sklearn converter unavailable (%s). "
            "Falling back to manual CoreML spec construction.",
            exc,
        )
        mlmodel_path = _build_glm_coreml_model(pipeline, feature_names, classes, output_dir)

    # Compile to .mlmodelc for direct NLModel loading
    mlmodelc_path = output_dir / "CapabilityClassifier.mlmodelc"
    _compile_model(mlmodel_path, mlmodelc_path)

    return mlmodelc_path


def _build_glm_coreml_model(
    pipeline: Pipeline,
    feature_names: list[str],
    classes: list[str],
    output_dir: Path,
) -> Path:
    """Manually construct a CoreML GLMClassifier spec when sklearn converter is unavailable."""
    import coremltools.proto.Model_pb2 as Model_pb2

    vectorizer = pipeline.named_steps["tfidf"]
    clf = pipeline.named_steps["clf"]

    spec = Model_pb2.Model()
    spec.specificationVersion = 4

    glm = spec.glmClassifier
    for class_label in classes:
        glm.stringClassLabels.vector.append(class_label)

    # Use first class coefficients (binary classification: one set of weights)
    coef = clf.coef_[0] if len(clf.coef_) == 1 else clf.coef_[0]
    weights = glm.weights.add()
    for w in coef:
        weights.value.append(float(w))
    glm.intercept.append(float(clf.intercept_[0]))
    glm.postEvaluationTransform = Model_pb2.GLMClassifier.Logit

    # Input/output descriptions
    input_desc = spec.description.input.add()
    input_desc.name = "text"
    input_desc.type.dictionaryType.stringKeyType.CopyFrom(
        Model_pb2.StringFeatureType()
    )

    output_label = spec.description.output.add()
    output_label.name = "label"
    output_label.type.stringType.CopyFrom(Model_pb2.StringFeatureType())

    output_probs = spec.description.output.add()
    output_probs.name = "labelProbability"
    output_probs.type.dictionaryType.stringKeyType.CopyFrom(
        Model_pb2.StringFeatureType()
    )
    spec.description.predictedFeatureName = "label"
    spec.description.predictedProbabilitiesName = "labelProbability"

    mlmodel_path = output_dir / "CapabilityClassifier.mlmodel"
    ct.models.MLModel(spec).save(str(mlmodel_path))
    logger.info("Fallback CoreML model saved: %s", mlmodel_path)
    return mlmodel_path


def _compile_model(mlmodel_path: Path, output_path: Path) -> None:
    """Compile .mlmodel to .mlmodelc using xcrun coremlcompiler."""
    try:
        result = subprocess.run(
            [
                "xcrun",
                "coremlcompiler",
                "compile",
                str(mlmodel_path),
                str(mlmodel_path.parent),
            ],
            capture_output=True,
            text=True,
            timeout=120,
        )
        if result.returncode != 0:
            logger.warning(
                "coremlcompiler returned non-zero (%d): %s",
                result.returncode,
                result.stderr,
            )
        else:
            logger.info("Compiled model at: %s", output_path)
    except FileNotFoundError:
        logger.warning(
            "xcrun not found — skipping compilation. "
            "Copy the .mlmodel into Xcode to compile manually."
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Train the PocketMind CapabilityBoundaryClassifier and export to CoreML."
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=None,
        help="Directory to write the compiled .mlmodelc. Defaults to ~/.pocketmind/classifier/.",
    )
    args = parser.parse_args()

    result = train(output_dir=args.output_dir)
    logger.info("Done. Compiled classifier: %s", result)
    logger.info("Copy CapabilityClassifier.mlmodelc into the Xcode project bundle.")


if __name__ == "__main__":
    main()
