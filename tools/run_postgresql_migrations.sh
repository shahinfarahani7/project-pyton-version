#!/usr/bin/env bash
set -euo pipefail

: "${POSTGRES_HOST:?POSTGRES_HOST required}"
: "${POSTGRES_USER:?POSTGRES_USER required}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD required}"
: "${POSTGRES_DB:?POSTGRES_DB required}"

export PGPASSWORD="$POSTGRES_PASSWORD"

psql_base=(
  psql -X -v ON_ERROR_STOP=1
  -h "$POSTGRES_HOST"
  -U "$POSTGRES_USER"
  -d "$POSTGRES_DB"
)

for migration in /migrations/*.sql; do
  version="$(basename "$migration")"
  checksum="$(sha256sum "$migration" | awk '{print $1}')"

  escaped_version="${version//\'/\'\'}"
  has_ledger="$("${psql_base[@]}" -Atc "SELECT CASE WHEN to_regclass('public.schema_migrations') IS NULL THEN '0' ELSE '1' END")"
  existing=""
  if [[ "$has_ledger" == "1" ]]; then
    existing="$("${psql_base[@]}" -Atc \
      "SELECT checksum_sha256 FROM public.schema_migrations WHERE version = '${escaped_version}'")"
  fi

  if [[ -n "$existing" ]]; then
    [[ "$existing" == "$checksum" ]] || {
      echo "MIGRATION_CHECKSUM_MISMATCH:$version" >&2
      exit 1
    }
    continue
  fi

  last_statement="$(grep -Ev '^[[:space:]]*(--.*)?$' "$migration" | tail -n 1 | tr -d '[:space:]')"
  [[ "$last_statement" == "COMMIT;" ]] || {
    echo "MIGRATION_MUST_END_WITH_COMMIT:$version" >&2
    exit 1
  }

  # The migration body and its checksum ledger entry commit atomically. A crash can
  # therefore never leave an applied migration without a recorded checksum.
  {
    # Remove the final COMMIT statement while preserving any trailing comments or
    # blank lines. The checksum ledger INSERT below becomes part of the same
    # transaction as the migration body.
    awk -v file="$migration" '
      { lines[NR] = $0 }
      END {
        idx = NR
        while (idx > 0) {
          stripped = lines[idx]
          sub(/^[[:space:]]+/, "", stripped)
          sub(/[[:space:]]+$/, "", stripped)
          if (stripped != "" && substr(stripped, 1, 2) != "--") {
            break
          }
          idx--
        }
        if (idx == 0 || toupper(lines[idx]) != "COMMIT;") {
          printf "MIGRATION_MUST_END_WITH_COMMIT:%s\n", file > "/dev/stderr"
          exit 1
        }
        for (i = 1; i < idx; i++) {
          print lines[i]
        }
      }
    ' "$migration"
    cat <<SQL
INSERT INTO public.schema_migrations(version, checksum_sha256)
VALUES ('${escaped_version}', '${checksum}');
COMMIT;
SQL
  } | "${psql_base[@]}"
done
