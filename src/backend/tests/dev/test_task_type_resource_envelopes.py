from __future__ import annotations

import json
from pathlib import Path

from edgemint.dev import task_type_catalog


def test_all_catalog_types_have_resource_envelope_ref() -> None:
    catalog = json.loads(
        Path(task_type_catalog._catalog_path()).read_text(encoding="utf-8")
    )
    types = [item for category in catalog["categories"] for item in category["types"]]
    assert len(types) == 56
    refs = {str(item["value"]): item.get("resourceEnvelopeRef") for item in types}
    assert all(ref and str(ref).startswith("TaskResourceEnvelope/") for ref in refs.values())

    meta = task_type_catalog.task_type_meta("text.summarize")
    assert meta["resourceEnvelopeRef"] == "TaskResourceEnvelope/text-summarize@1.0.0"

    listed = task_type_catalog.list_catalog()
    assert listed["total"] == 56
    assert all(item.get("resourceEnvelopeRef") for item in listed["items"])
