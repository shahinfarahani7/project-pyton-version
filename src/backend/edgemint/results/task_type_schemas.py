from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Any


@lru_cache
def load_output_schemas(root: Path | None = None) -> dict[str, dict[str, Any]]:
    repo_root = root or Path(__file__).resolve().parents[4]
    catalog_dir = repo_root / "dsl" / "catalog" / "task-types"
    schemas: dict[str, dict[str, Any]] = {}
    if not catalog_dir.is_dir():
        return schemas
    import yaml

    for path in sorted(catalog_dir.glob("*.yaml")):
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        task_code = str(document["spec"]["code"])
        output_schema = document["spec"].get("outputSchema")
        if isinstance(output_schema, dict):
            schemas[task_code] = output_schema
    return schemas


def output_schema_for(task_type: str) -> dict[str, Any] | None:
    return load_output_schemas().get(task_type)
