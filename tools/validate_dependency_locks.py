from pathlib import Path
import json
import re
import sys

root = Path(__file__).resolve().parents[1]
errors: list[str] = []

for path in [root / "package.json", *root.glob("src/apps/*/package.json")]:
    data = json.loads(path.read_text())
    for group in ("dependencies", "devDependencies", "optionalDependencies"):
        for name, version in data.get(group, {}).items():
            if version in ("latest", "next", "*") or re.search(r"^[~^><=*]", version):
                errors.append(f"{path.relative_to(root)}:{name}:{version}")

pyproject = (root / "src/backend/pyproject.toml").read_text()
lock = (root / "src/backend/requirements-backend.lock").read_text()
if 'requires-python = ">=3.13,<3.14"' not in pyproject:
    errors.append("Python package compatibility range must be >=3.13,<3.14")

expected_runtime = "3.13.14"
for runtime_file in [root / ".python-version", root / "src/backend/.python-version"]:
    if runtime_file.read_text().strip() != expected_runtime:
        errors.append(f"{runtime_file.relative_to(root)} must pin {expected_runtime}")

tool_versions = (root / ".tool-versions").read_text()
if f"python {expected_runtime}" not in tool_versions:
    errors.append(".tool-versions does not pin the canonical Python runtime")

bootstrap = (root / "tools/bootstrap.sh").read_text()
for token in ["required = (3, 13, 14)", "actual == required", "python -m pip check"]:
    if token not in bootstrap:
        errors.append("bootstrap Python/dependency verification missing:" + token)

for line in lock.splitlines():
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        continue
    if stripped.startswith("--hash="):
        continue
    if stripped.startswith("# via"):
        continue
    if "==" not in stripped:
        errors.append("backend dependency is not exactly pinned:" + stripped)

if not (root / "package-lock.json").exists():
    errors.append("package-lock.json is missing")
if not (root / ".tool-versions").exists():
    errors.append(".tool-versions is missing")

requirements = (root / "tools/requirements.lock").read_text()
if requirements.count("--hash=sha256:") < 9:
    errors.append("validator requirements are not fully hash-pinned")

for path in root.rglob("Dockerfile"):
    text = path.read_text()
    if ":latest" in text:
        errors.append(f"{path.relative_to(root)}:mutable latest image")
    for line in text.splitlines():
        if not line.strip().upper().startswith("FROM "):
            continue
        image = line.strip().split()[1]
        if image.startswith("${") and image.endswith("}"):
            continue
        if "@sha256:" not in image:
            errors.append(
                f"{path.relative_to(root)}:FROM image is not digest-pinned or fail-closed variable:{image}"
            )
    if "${PYTHON_RUNTIME_IMAGE:" not in text:
        errors.append(f"{path.relative_to(root)}:mandatory immutable Python runtime image input missing")

compose = (root / "compose.yaml").read_text()
for required in [
    "${POSTGRES_DEV_IMAGE:",
    "${POSTGRES_TOOLS_IMAGE:",
    "${MINIO_IMAGE:",
    "${MAILPIT_IMAGE:",
]:
    if required not in compose:
        errors.append("compose missing fail-closed image input:" + required)

settings = (root / "src/backend/edgemint/building_blocks/settings.py").read_text()
if 'database_url: str | None = None' not in settings:
    errors.append("database URL must not contain a built-in credentialed default")
if "EDGEMINT_DATABASE_URL_REQUIRED" not in settings:
    errors.append("database configuration must fail closed")
if "INSECURE_DEVELOPMENT_TOKENS_FORBIDDEN" not in settings:
    errors.append("production insecure-token guard is missing")

print(
    json.dumps(
        {
            "status": "passed" if not errors else "failed",
            "backendDependencies": sum(1 for line in lock.splitlines() if "==" in line),
            "errors": errors,
        },
        indent=2,
    )
)
sys.exit(1 if errors else 0)
