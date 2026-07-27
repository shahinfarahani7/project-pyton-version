from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from edgemint.payments.errors import payment_error
from edgemint.payments.service import PaymentProviderService


def evaluate_claim_eligibility(raw_input: dict[str, Any]) -> dict[str, Any]:
    reasons: list[str] = []
    if not raw_input.get("policyEnabled", True):
        reasons.append("CLAIMS_DISABLED")
    if int(raw_input.get("verifiedRewardMicros", 0)) < 100_000_000:
        reasons.append("MINIMUM_NOT_MET")
    if raw_input.get("kycRequired", True) and not raw_input.get("kycApproved"):
        reasons.append("KYC_REQUIRED")
    if raw_input.get("sanctionsScreeningRequired", True) and not raw_input.get("sanctionsClear"):
        reasons.append("SANCTIONS_SCREENING_REQUIRED")
    if raw_input.get("jurisdictionAllowlistRequired", True) and not raw_input.get("jurisdictionAllowed"):
        reasons.append("JURISDICTION_NOT_ALLOWED")
    if raw_input.get("fraudHoldMustBeClear", True) and raw_input.get("fraudHold"):
        reasons.append("FRAUD_HOLD")
    if raw_input.get("destinationVerificationRequired", True) and not raw_input.get("destinationVerified"):
        reasons.append("DESTINATION_NOT_VERIFIED")
    return {"eligible": not reasons, "reasons": reasons}


@dataclass
class ClaimPayoutService:
    payments: PaymentProviderService = field(default_factory=PaymentProviderService)
    submitted_batches: list[dict[str, Any]] = field(default_factory=list)

    def submit_claim_batch(
        self,
        *,
        batch_id: str,
        claims: list[dict[str, Any]],
        idempotency_key: str,
    ) -> dict[str, Any]:
        transfers: list[dict[str, Any]] = []
        for claim in claims:
            eligibility = evaluate_claim_eligibility(claim)
            if not eligibility["eligible"]:
                raise payment_error("KYC_INCOMPLETE", detail=",".join(eligibility["reasons"]))
            transfers.append(
                {
                    "workerId": claim["workerId"],
                    "amountMicroEur": claim["verifiedRewardMicros"],
                }
            )
        result = self.payments.submit_payout_batch(
            batch_id=batch_id,
            transfers=transfers,
            idempotency_key=idempotency_key,
        )
        self.submitted_batches.append(result)
        return result
