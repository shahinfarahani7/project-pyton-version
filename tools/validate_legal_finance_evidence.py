#!/usr/bin/env python3
"""Validate legal, privacy, finance, and commercial approval evidence for WP-240."""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
LEGAL_DIR_NAME = "legal-finance"

REQUIRED_FILES = (
    "summary.json",
    "control-map.json",
    "product-surface-audit.json",
    "signed-approvals.json",
    "customer-worker-terms.json",
    "privacy-dpa.json",
    "payout-tax-kyc.json",
    "model-licenses.json",
    "pricing-reward-treasury.json",
    "insurance-incident.json",
    "consumer-labor-analysis.json",
)

REQUIRED_EXTERNAL_INPUTS = (
    "RELEASE_APPROVAL_MANIFEST",
    "LEGAL_PRIVACY_APPROVAL",
    "FINANCE_TAX_PAYOUT_APPROVAL",
    "MODEL_LICENSE_APPROVAL",
)

GA1_PAYOUT_COUNTRIES = frozenset({"DE", "FR", "NL", "BE", "AT", "IE", "ES", "IT", "PT", "FI"})
GA1_TASK_TYPES = frozenset(
    {
        "document.ocr",
        "document.extract",
        "image.classify",
        "image.detect",
        "vision.analyze",
        "audio.transcribe",
        "text.translate",
        "text.generate",
        "text.embedding",
        "document.verify",
    }
)
GA1_DATA_CLASSES = frozenset({"public", "internal", "confidential", "restricted"})
GA1_MODELS = frozenset({"paddleocr-mobile", "gemma-3n-e2b-int4", "whisper-base-int8"})
GA1_PAYMENT_FLOWS = frozenset(
    {
        "customer_billing",
        "stripe_tax",
        "worker_kyc",
        "worker_payout",
        "ledger_reconciliation",
    }
)
PROHIBITED_SURFACE_CLAIMS = (
    "guaranteedEarnings",
    "hiddenComputation",
    "tokenValuePromise",
    "unsupportedGeography",
)


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _parse_iso8601(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def _task_types_from_pricing() -> set[str]:
    pricing_path = ROOT / "dsl" / "policies" / "pricing" / "public-eur-2026q3-v2.yaml"
    document = yaml.safe_load(pricing_path.read_text(encoding="utf-8"))
    return {rule["taskType"] for rule in document["spec"]["rules"]}


def validate_legal_finance(evidence_root: Path) -> tuple[list[str], dict]:
    errors: list[str] = []
    legal_dir = evidence_root / LEGAL_DIR_NAME

    if not legal_dir.is_dir():
        return [f"legal-finance evidence directory missing: {legal_dir}"], {}

    for name in REQUIRED_FILES:
        if not (legal_dir / name).is_file():
            errors.append(f"missing legal-finance evidence: {name}")

    external_root = evidence_root / "external-inputs"
    for input_name in REQUIRED_EXTERNAL_INPUTS:
        if not (external_root / f"{input_name}.json").is_file():
            errors.append(f"missing external input: {input_name}")

    if errors:
        return errors, {}

    summary = _load_json(legal_dir / "summary.json")
    control_map = _load_json(legal_dir / "control-map.json")
    surface_audit = _load_json(legal_dir / "product-surface-audit.json")
    approvals = _load_json(legal_dir / "signed-approvals.json")

    if summary.get("status") != "passed":
        errors.append("legal-finance summary status is not passed")

    now = datetime.now(timezone.utc)
    countries = control_map.get("countries", {})
    for code in GA1_PAYOUT_COUNTRIES:
        entry = countries.get(code)
        if not entry or not entry.get("approved"):
            errors.append(f"GA1 country missing approved control: {code}")

    pricing_task_types = _task_types_from_pricing()
    if pricing_task_types != GA1_TASK_TYPES:
        errors.append("pricing policy task types diverge from GA1 baseline set")

    task_types = control_map.get("taskTypes", {})
    for task_type in GA1_TASK_TYPES:
        entry = task_types.get(task_type)
        if not entry or not entry.get("approved"):
            errors.append(f"GA1 task type missing approved control: {task_type}")

    data_classes = control_map.get("dataClasses", {})
    for data_class in GA1_DATA_CLASSES:
        entry = data_classes.get(data_class)
        if not entry or not entry.get("approved"):
            errors.append(f"GA1 data class missing approved control: {data_class}")

    models = control_map.get("models", {})
    for model in GA1_MODELS:
        entry = models.get(model)
        if not entry or not entry.get("approved"):
            errors.append(f"GA1 model missing approved control: {model}")
        elif not entry.get("licenseVersion"):
            errors.append(f"GA1 model missing licenseVersion: {model}")

    payment_flows = control_map.get("paymentFlows", {})
    for flow in GA1_PAYMENT_FLOWS:
        entry = payment_flows.get(flow)
        if not entry or not entry.get("approved"):
            errors.append(f"GA1 payment flow missing approved control: {flow}")

    retention = control_map.get("retentionPeriods", {})
    required_retention_keys = ("eventRetentionDays", "deadLetterRetentionDays", "consentEvidenceDays")
    for key in required_retention_keys:
        if key not in retention or not retention[key].get("approved"):
            errors.append(f"retention period missing approved control: {key}")

    for claim in PROHIBITED_SURFACE_CLAIMS:
        if surface_audit.get(claim):
            errors.append(f"prohibited product surface claim detected: {claim}")

    if not surface_audit.get("auditPassed"):
        errors.append("product surface audit did not pass")

    signed = approvals.get("approvals", [])
    if len(signed) < 4:
        errors.append("signed approvals must include legal, privacy, finance, and model license")

    for approval in signed:
        approval_id = approval.get("id", "<unknown>")
        for field in ("function", "approverId", "signedAt", "policyVersion", "signatureSha256", "expiresAt"):
            if not approval.get(field):
                errors.append(f"approval {approval_id} missing field: {field}")
        expires_at = approval.get("expiresAt")
        if expires_at and _parse_iso8601(expires_at) <= now:
            errors.append(f"approval {approval_id} expired")

    result = {
        "status": "passed" if not errors else "failed",
        "legalDir": str(legal_dir.relative_to(ROOT)),
        "countriesApproved": len([c for c in countries.values() if c.get("approved")]),
        "taskTypesApproved": len([t for t in task_types.values() if t.get("approved")]),
        "approvalsSigned": len(signed),
        "errors": errors,
    }
    return errors, result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence_dir", nargs="?", default="evidence/actual")
    args = parser.parse_args()

    evidence_root = Path(args.evidence_dir)
    if not evidence_root.is_absolute():
        evidence_root = ROOT / evidence_root

    errors, result = validate_legal_finance(evidence_root)
    print(json.dumps(result, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
