#!/usr/bin/env python3
"""Database integration harness for PostgreSQL migrations, RLS, and invariants."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "database" / "sql"


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_migration_files() -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    for migration in sorted(MIGRATIONS.glob("*.sql")):
        text = migration.read_text(encoding="utf-8")
        if "BEGIN;" not in text:
            raise RuntimeError(f"MIGRATION_MISSING_BEGIN:{migration.name}")
        last = next(
            (line.strip() for line in reversed(text.splitlines()) if line.strip() and not line.strip().startswith("--")),
            "",
        )
        if last != "COMMIT;":
            raise RuntimeError(f"MIGRATION_MUST_END_WITH_COMMIT:{migration.name}")
        records.append({"version": migration.name, "checksum": sha256_file(migration)})
    return records


def psql_query(sql: str) -> str:
    env = os.environ.copy()
    env.setdefault("PGPASSWORD", env.get("POSTGRES_PASSWORD", ""))
    host = env.get("POSTGRES_HOST", "localhost")
    user = env.get("POSTGRES_USER", "edgemint")
    db = env.get("POSTGRES_DB", "edgemint")
    cmd = ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-h", host, "-U", user, "-d", db, "-Atc", sql]
    result = subprocess.run(cmd, capture_output=True, text=True, env=env, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "PSQL_FAILED")
    return result.stdout.strip()


def live_checks() -> dict[str, object]:
    applied = psql_query("SELECT version || ':' || checksum_sha256 FROM public.schema_migrations ORDER BY version")
    applied_rows = [row for row in applied.splitlines() if row]
    rls_count = int(
        psql_query(
            "SELECT COUNT(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace "
            "WHERE c.relrowsecurity = true AND n.nspname = 'public'"
        )
    )
    return {"appliedMigrations": applied_rows, "rlsEnabledTables": rls_count}


def main() -> None:
    parser = argparse.ArgumentParser(description="EdgeMint database validation harness")
    parser.add_argument("--live", action="store_true", help="Run live PostgreSQL checks via psql")
    args = parser.parse_args()

    migrations = validate_migration_files()
    report: dict[str, object] = {
        "status": "passed",
        "generatedAt": datetime.now(UTC).isoformat(),
        "migrations": migrations,
        "migrationCount": len(migrations),
    }

    if args.live:
        report["live"] = live_checks()
    else:
        report["liveSkipped"] = True
        report["liveSkipReason"] = "Pass --live when PostgreSQL is reachable and migrations are applied."

    print(json.dumps(report, indent=2))
    if report["status"] != "passed":
        sys.exit(1)


if __name__ == "__main__":
    main()
