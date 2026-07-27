from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src" / "backend"))

from edgemint.fraud.privacy import RETAINED_RECORD_CLASSES  # noqa: E402
from edgemint.fraud.service import FraudService  # noqa: E402


def contract_checks() -> list[str]:
    errors: list[str] = []
    fraud_src = (ROOT / "src/backend/edgemint/services/fraud.py").read_text(encoding="utf-8")
    for route in [
        '"/internal/fraud/signals:evaluate"',
        '"/internal/fraud/cases:open"',
        '"/internal/fraud/privacy/subjects/{subject_id}:delete"',
        '"/internal/fraud/privacy/dsar:submit"',
    ]:
        if route not in fraud_src:
            errors.append(f"missing fraud route {route}")
    if "sk_live_" in fraud_src:
        errors.append("live stripe key must not appear in fraud service source")
    return errors


def privacy_deletion_checks() -> list[str]:
    errors: list[str] = []
    service = FraudService()
    subject_id = "subj_privacy_int"
    service.minimize_profile(
        subject_id=subject_id,
        payload={"country": "FR", "tier": "T1", "email": "privacy@example.com", "address": "1 Rue Test"},
    )
    service.privacy.device_links[subject_id] = [
        {"accountId": "acc_priv", "deviceId": "dev_priv"},
    ]
    dsar = service.submit_dsar(subject_id=subject_id, request_type="erasure")
    if dsar["status"] != "accepted":
        errors.append("dsar not accepted")

    retained = [
        {"class": "financial_record", "id": "fin_retain", "amountMicroEur": 500000},
        {"class": "audit_record", "id": "aud_retain", "action": "payout"},
        {"class": "profile_snapshot", "id": "snap_1"},
    ]
    deletion = service.delete_subject_data(subject_id=subject_id, retained_records=retained)
    if subject_id in service.privacy.profiles:
        errors.append("profile store not deleted")
    if subject_id in service.privacy.device_links:
        errors.append("device graph not deleted")
    preserved = [item for item in retained if item.get("class") in RETAINED_RECORD_CLASSES]
    if deletion["preservedRecords"] != len(preserved):
        errors.append("financial/audit retention count mismatch")
    if not deletion["deletedStores"]:
        errors.append("deletion log missing deleted stores")
    return errors


def main() -> int:
    errors = contract_checks() + privacy_deletion_checks()
    if errors:
        print("\n".join(errors))
        return 1
    print('{"status":"pass","checks":["contract","privacy_deletion"]}')
    return 0


if __name__ == "__main__":
    sys.exit(main())
