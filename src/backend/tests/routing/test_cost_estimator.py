from __future__ import annotations

from dataclasses import replace

from edgemint.pricing.quotes import CreateQuoteRequest, QuoteService, TaskConfiguration
from edgemint.routing.cost_estimator import EnvelopeTaskCostEstimator, TaskCostEstimatorInputs
from edgemint.routing.envelope_registry import envelope_for_task_type


def test_envelope_registry_loads_document_ocr() -> None:
    envelope = envelope_for_task_type("document.ocr")
    assert envelope is not None
    assert envelope.runtime_class == "paddle_ocr"
    assert envelope.cpu_units == 25


def test_envelope_estimator_scales_with_pages() -> None:
    estimator = EnvelopeTaskCostEstimator()
    one_page = estimator.estimate(
        TaskCostEstimatorInputs(
            taskType="document.ocr",
            inputBytes=500_000,
            estimatedInputTokens=0,
            pageCount=1,
            imageWidth=0,
            imageHeight=0,
            chunkCountEstimate=1,
            runtimeClass="paddle_ocr",
            modelVersionId="paddleocr-mobile",
        )
    )
    five_pages = estimator.estimate(
        TaskCostEstimatorInputs(
            taskType="document.ocr",
            inputBytes=2_500_000,
            estimatedInputTokens=0,
            pageCount=5,
            imageWidth=0,
            imageHeight=0,
            chunkCountEstimate=1,
            runtimeClass="paddle_ocr",
            modelVersionId="paddleocr-mobile",
        )
    )
    assert five_pages.predictedDurationMs > one_page.predictedDurationMs
    assert five_pages.expectedCostMicros > one_page.expectedCostMicros
    assert five_pages.stressedCostMicros >= five_pages.expectedCostMicros


def test_verification_tier_increases_expected_cost() -> None:
    estimator = EnvelopeTaskCostEstimator()
    base_inputs = TaskCostEstimatorInputs(
        taskType="text.summarize",
        inputBytes=12_000,
        estimatedInputTokens=3000,
        pageCount=0,
        imageWidth=0,
        imageHeight=0,
        chunkCountEstimate=3,
        runtimeClass="mediapipe_llm",
        modelVersionId="qwen2.5-0.5b",
        verificationTier="standard",
    )
    standard = estimator.estimate(base_inputs)
    verified = estimator.estimate(replace(base_inputs, verificationTier="verified"))
    assert verified.expectedCostMicros > standard.expectedCostMicros


def test_quote_service_derives_expected_cost_when_missing() -> None:
    service = QuoteService.default()
    request = CreateQuoteRequest(
        workspaceId="00000000-0000-4000-8000-000000000001",
        taskType="document.ocr",
        input={"pageCount": 2},
        configuration=TaskConfiguration(verificationLevel="standard"),
        quantity=1,
    )
    price_input = service.build_price_input(request)
    assert price_input.expected_cost_micros is not None
    assert price_input.expected_cost_micros > 0
    assert price_input.stressed_cost_micros is not None
    assert price_input.stressed_cost_micros >= price_input.expected_cost_micros
