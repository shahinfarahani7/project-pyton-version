#!/usr/bin/env python3
"""Regenerate typed clients from canonical contracts (Protobuf + OpenAPI)."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROTO_DIR = ROOT / "contracts" / "proto"
OPENAPI_DIR = ROOT / "contracts" / "openapi"
GENERATED = ROOT / "generated"


def _run(cmd: list[str], *, cwd: Path | None = None) -> None:
    result = subprocess.run(cmd, cwd=cwd or ROOT, check=False, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(cmd)}")


def copy_protobuf_sources() -> int:
    target = GENERATED / "protobuf"
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True)
    count = 0
    for proto in sorted(PROTO_DIR.glob("*.proto")):
        shutil.copy2(proto, target / proto.name)
        count += 1
    manifest = {
        "source": "contracts/proto",
        "files": sorted(p.name for p in PROTO_DIR.glob("*.proto")),
        "package": "edgemint.v1",
    }
    (target / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return count


def generate_protobuf_clients() -> None:
    for subdir in ("python", "dart", "typescript"):
        path = GENERATED / subdir
        if path.exists():
            shutil.rmtree(path)
        path.mkdir(parents=True)

    buf = shutil.which("buf")
    if buf:
        try:
            _run([buf, "generate"], cwd=PROTO_DIR)
            return
        except RuntimeError:
            print("buf generate unavailable; falling back to grpcio-tools", file=sys.stderr)

    # Fallback: grpcio-tools for Python when buf CLI or remote plugins are unavailable.
    python_out = GENERATED / "python"
    protos = sorted(PROTO_DIR.glob("*.proto"))
    _run(
        [
            sys.executable,
            "-m",
            "grpc_tools.protoc",
            f"--proto_path={PROTO_DIR}",
            f"--python_out={python_out}",
            f"--grpc_python_out={python_out}",
            *[str(p) for p in protos],
        ]
    )
    init_py = python_out / "__init__.py"
    init_py.write_text('"""Generated Protobuf message types."""\n', encoding="utf-8")

    dart_pkg = GENERATED / "dart" / "lib" / "generated"
    dart_pkg.mkdir(parents=True, exist_ok=True)
    (dart_pkg / "README.md").write_text(
        "# Dart protobuf stubs\n\nRun `buf generate` from contracts/proto when buf CLI is available.\n",
        encoding="utf-8",
    )
    ts_pkg = GENERATED / "typescript" / "proto"
    ts_pkg.mkdir(parents=True, exist_ok=True)
    (ts_pkg / "README.md").write_text(
        "# TypeScript protobuf stubs\n\nRun `buf generate` from contracts/proto when buf CLI is available.\n",
        encoding="utf-8",
    )


def _ts_type(schema: dict, schemas: dict) -> str:
    if "$ref" in schema:
        ref = schema["$ref"].split("/")[-1]
        return ref
    if "allOf" in schema:
        return " & ".join(_ts_type(part, schemas) for part in schema["allOf"])
    schema_type = schema.get("type")
    if schema_type == "string":
        return "string"
    if schema_type == "integer":
        return "number"
    if schema_type == "number":
        return "number"
    if schema_type == "boolean":
        return "boolean"
    if schema_type == "array":
        return f"{_ts_type(schema.get('items', {}), schemas)}[]"
    if schema_type == "object":
        props = schema.get("properties", {})
        if not props:
            return "Record<string, unknown>"
        fields = "; ".join(
            f"{name}{'?' if name not in schema.get('required', []) else ''}: {_ts_type(prop, schemas)}"
            for name, prop in props.items()
        )
        return f"{{ {fields} }}"
    return "unknown"


def generate_openapi_typescript() -> int:
    out_dir = GENERATED / "typescript" / "openapi"
    out_dir.mkdir(parents=True, exist_ok=True)
    count = 0
    for spec_path in sorted(OPENAPI_DIR.glob("*.yaml")):
        import yaml

        spec = yaml.safe_load(spec_path.read_text(encoding="utf-8"))
        schemas = spec.get("components", {}).get("schemas", {})
        api_name = spec_path.stem.replace("edgemint-", "").replace("-", "_")
        lines = [
            "// Auto-generated from canonical OpenAPI. Do not edit manually.",
            f"// Source: contracts/openapi/{spec_path.name}",
            "",
        ]
        for name, schema in sorted(schemas.items()):
            if not isinstance(schema, dict):
                continue
            ts_name = name.replace("-", "_")
            if schema.get("type") == "object" or "properties" in schema or "allOf" in schema:
                lines.append(f"export type {ts_name} = {_ts_type(schema, schemas)};")
            elif schema.get("type") == "string" and "enum" in schema:
                values = " | ".join(f'"{v}"' for v in schema["enum"])
                lines.append(f"export type {ts_name} = {values};")
            else:
                lines.append(f"export type {ts_name} = {_ts_type(schema, schemas)};")
            count += 1
        (out_dir / f"{api_name}.ts").write_text("\n".join(lines) + "\n", encoding="utf-8")

    index_lines = [
        "// Auto-generated OpenAPI type barrel.",
        *[f'export * from "./openapi/{p.stem}";' for p in sorted((out_dir).glob("*.ts"))],
        "",
    ]
    (GENERATED / "typescript" / "index.ts").write_text("\n".join(index_lines), encoding="utf-8")
    return count


def main() -> None:
    GENERATED.mkdir(exist_ok=True)
    proto_count = copy_protobuf_sources()
    generate_protobuf_clients()
    schema_count = generate_openapi_typescript()
    print(
        json.dumps(
            {
                "status": "generated",
                "protobufSources": proto_count,
                "openapiSchemas": schema_count,
                "outputs": [
                    "generated/protobuf",
                    "generated/python",
                    "generated/dart",
                    "generated/typescript",
                ],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
