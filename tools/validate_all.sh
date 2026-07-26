#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python tools/validate_dsl.py
python tools/validate_contracts.py
python tools/validate_contract_examples.py
python tools/validate_cloudevent_examples.py
python tools/validate_traceability.py
python tools/verify_vectors.py
python tools/validate_sql.py
python tools/validate_websocket_architecture.py
python tools/validate_infra.py
python tools/validate_infrastructure_source.py
python tools/validate_reference.py
python tools/validate_samples.py
python tools/validate_release_blockers.py
python tools/validate_docs.py
python tools/compile_dsl.py
python tools/validate_cursor_plan.py
python tools/validate_production_pack.py
python tools/validate_dependency_locks.py
python tools/validate_release_inputs.py
python tools/regenerate_release_evidence_schema.py
python tools/regenerate_release_evidence_template.py
python tools/validate_evidence_contract.py
python tools/regenerate_package_metadata.py
python tools/verify_package.py
