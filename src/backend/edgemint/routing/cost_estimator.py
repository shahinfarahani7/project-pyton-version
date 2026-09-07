from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol

from edgemint.pricing.money import apply_bps
from edgemint.pricing.policy import PricePolicy, load_price_policy
from edgemint.routing.envelope_registry import ResourceEnvelopeSpec, envelope_for_task_type


@dataclass(frozen=True, slots=True)
class TaskCostEstimate:
    """Server-derived cost prediction (architecture §13)."""

    predictedDurationMs: int
    predictedPeakMemoryBytes: int
    predictedCpuUnits: int
    predictedEnergyClass: str
    predictedStageCount: int
    predictedInferenceCalls: int
    expectedCostMicros: int
    stressedCostMicros: int


@dataclass(frozen=True, slots=True)
class TaskCostEstimatorInputs:
    taskType: str
    inputBytes: int
    estimatedInputTokens: int
    pageCount: int
    imageWidth: int
    imageHeight: int
    chunkCountEstimate: int
    runtimeClass: str
    modelVersionId: str
    executionPlanId: str | None = None
    calibrationFactorBps: int = 10_000
    verificationTier: str = "standard"
    quantity: int = 1


class TaskCostEstimator(Protocol):
    def estimate(self, inputs: TaskCostEstimatorInputs) -> TaskCostEstimate:
        """Return deterministic resource prediction for routing/quotes."""


_VERIFICATION_COST_STRESS_BPS = {
    "standard": 10_000,
    "verified": 12_000,
    "consensus": 14_000,
    "enterprise": 15_000,
    "human_review": 16_000,
}


@dataclass(frozen=True, slots=True)
class EnvelopeTaskCostEstimator:
    """Envelope-aware estimator with integer verification modifiers."""

    policy: PricePolicy = field(default_factory=load_price_policy)
    stress_bps: int = 12_000

    def estimate(self, inputs: TaskCostEstimatorInputs) -> TaskCostEstimate:
        envelope = envelope_for_task_type(inputs.taskType)
        if envelope is None:
            return _baseline_fallback(inputs, policy=self.policy, stress_bps=self.stress_bps)

        scaled = _scale_envelope(envelope, inputs)
        duration = _apply_bps_int(scaled.duration_ms, inputs.calibrationFactorBps)
        memory = scaled.memory_bytes
        cpu = scaled.cpu_units
        stages = max(1, inputs.chunkCountEstimate or 1)
        inference_calls = max(1, stages if envelope.runtime_class == "mediapipe_llm" else 1)
        base_cost = _execution_cost_micros(
            cpu_units=cpu,
            duration_ms=duration,
            memory_bytes=memory,
            quantity=max(1, inputs.quantity),
        )
        verification_bps = self._verification_bps(inputs.verificationTier)
        expected = apply_bps(base_cost, verification_bps)
        stressed = apply_bps(expected, self.stress_bps)
        return TaskCostEstimate(
            predictedDurationMs=duration,
            predictedPeakMemoryBytes=memory,
            predictedCpuUnits=cpu,
            predictedEnergyClass=_energy_class(cpu, duration),
            predictedStageCount=stages,
            predictedInferenceCalls=inference_calls,
            expectedCostMicros=expected,
            stressedCostMicros=stressed,
        )

    def _verification_bps(self, verification_tier: str) -> int:
        policy_bps = self.policy.multipliers_bps.get("verification", {}).get(verification_tier)
        if policy_bps is not None:
            return int(policy_bps)
        return _VERIFICATION_COST_STRESS_BPS.get(verification_tier, 10_000)


@dataclass(frozen=True, slots=True)
class _ScaledEnvelope:
    duration_ms: int
    memory_bytes: int
    cpu_units: int


def _scale_envelope(envelope: ResourceEnvelopeSpec, inputs: TaskCostEstimatorInputs) -> _ScaledEnvelope:
    page_factor = max(1, inputs.pageCount or 1)
    token_factor = max(1, (max(inputs.estimatedInputTokens, 1) + 999) // 1000)
    byte_factor = max(1, (max(inputs.inputBytes, 1) + (512 * 1024) - 1) // (512 * 1024))

    if envelope.runtime_class == "mediapipe_llm":
        load_factor = max(token_factor, byte_factor)
    elif envelope.runtime_class == "paddle_ocr":
        load_factor = page_factor
    elif envelope.runtime_class in {"image_classifier", "segmentation_runtime"}:
        pixel_factor = max(1, ((inputs.imageWidth or 1024) * (inputs.imageHeight or 1024)) // (1024 * 1024))
        load_factor = max(1, pixel_factor)
    else:
        load_factor = max(page_factor, token_factor, byte_factor)

    duration = envelope.estimated_duration_ms * load_factor
    memory = envelope.memory_reservation_bytes + (load_factor - 1) * (envelope.memory_reservation_bytes // 4)
    cpu = envelope.cpu_units + (load_factor - 1) * max(1, envelope.cpu_units // 5)
    return _ScaledEnvelope(duration_ms=duration, memory_bytes=memory, cpu_units=cpu)


def _execution_cost_micros(
    *,
    cpu_units: int,
    duration_ms: int,
    memory_bytes: int,
    quantity: int,
) -> int:
    cpu_ms = cpu_units * duration_ms * quantity
    memory_mb = memory_bytes // (1024 * 1024)
    return (cpu_ms // 1000) + (memory_mb * 25)


def estimate_execution_cost_micros(inputs: TaskCostEstimatorInputs) -> tuple[int, int]:
    estimate = EnvelopeTaskCostEstimator().estimate(inputs)
    return estimate.expectedCostMicros, estimate.stressedCostMicros


def _apply_bps_int(value: int, bps: int) -> int:
    return max(1, (value * bps) // 10_000)


def _baseline_fallback(
    inputs: TaskCostEstimatorInputs,
    *,
    policy: PricePolicy,
    stress_bps: int,
) -> TaskCostEstimate:
    duration = _apply_bps_int(
        _base_duration_ms(inputs.taskType, inputs.pageCount, inputs.estimatedInputTokens),
        inputs.calibrationFactorBps,
    )
    memory = _base_memory_bytes(inputs.runtimeClass, inputs.estimatedInputTokens)
    cpu = _base_cpu_units(inputs.runtimeClass, inputs.pageCount)
    base_cost = _execution_cost_micros(
        cpu_units=cpu,
        duration_ms=duration,
        memory_bytes=memory,
        quantity=max(1, inputs.quantity),
    )
    estimator = EnvelopeTaskCostEstimator(policy=policy, stress_bps=stress_bps)
    verification_bps = estimator._verification_bps(inputs.verificationTier)
    expected = apply_bps(base_cost, verification_bps)
    stressed = apply_bps(expected, stress_bps)
    stages = max(1, inputs.chunkCountEstimate or 1)
    return TaskCostEstimate(
        predictedDurationMs=duration,
        predictedPeakMemoryBytes=memory,
        predictedCpuUnits=cpu,
        predictedEnergyClass=_energy_class(cpu, duration),
        predictedStageCount=stages,
        predictedInferenceCalls=max(1, stages if inputs.runtimeClass == "mediapipe_llm" else 1),
        expectedCostMicros=expected,
        stressedCostMicros=stressed,
    )


def _base_duration_ms(task_type: str, page_count: int, tokens: int) -> int:
    if task_type.startswith("document.") or task_type.startswith("ocr."):
        return 90_000 + page_count * 30_000
    if task_type == "text.summarize" or task_type.startswith("document.summarize"):
        return 120_000 + tokens * 40
    if task_type.startswith("image.") or task_type.startswith("safety."):
        return 60_000
    return 90_000 + tokens * 20


def _base_memory_bytes(runtime_class: str, tokens: int) -> int:
    if runtime_class == "mediapipe_llm":
        return min(2_147_483_648, 805_306_368 + tokens * 2048)
    if runtime_class == "paddle_ocr":
        return 536_870_912
    if runtime_class == "segmentation_runtime":
        return 805_306_368
    return 536_870_912


def _base_cpu_units(runtime_class: str, page_count: int) -> int:
    if runtime_class == "mediapipe_llm":
        return 40
    if runtime_class == "paddle_ocr":
        return 25 + page_count * 2
    if runtime_class == "image_classifier":
        return 20
    return 25


def _energy_class(cpu_units: int, duration_ms: int) -> str:
    load = cpu_units * duration_ms
    if load >= 8_000_000:
        return "high"
    if load >= 3_000_000:
        return "medium"
    return "low"


# Back-compat alias for RouterService default until all call sites migrate.
BaselineTaskCostEstimator = EnvelopeTaskCostEstimator
