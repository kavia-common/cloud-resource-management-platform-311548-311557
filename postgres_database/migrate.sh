#!/usr/bin/env bash
set -euo pipefail

# Runs SQL migrations in ./migrations in lexical order and records them in public.schema_migrations.
# This is intentionally lightweight and compatible with the current postgres_database/startup.sh.
#
# IMPORTANT:
# - This script reads connection info from db_connection.txt (created by startup.sh).
# - Migrations are tracked by filename + checksum to prevent accidental drift.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_CONN_FILE="${ROOT_DIR}/db_connection.txt"
MIGRATIONS_DIR="${ROOT_DIR}/migrations"

if [[ ! -f "${DB_CONN_FILE}" ]]; then
  echo "ERROR: db_connection.txt not found at ${DB_CONN_FILE}"
  echo "Run startup.sh first to initialize PostgreSQL and create db_connection.txt."
  exit 1
fi

if [[ ! -d "${MIGRATIONS_DIR}" ]]; then
  echo "No migrations directory found at ${MIGRATIONS_DIR}. Nothing to do."
  exit 0
fi

# db_connection.txt contains a full command like: psql postgresql://user:pass@host:port/db
CONN_STR="$(sed -e 's/^psql[[:space:]]*//' "${DB_CONN_FILE}")"
if [[ -z "${CONN_STR}" ]]; then
  echo "ERROR: Could not parse connection string from db_connection.txt"
  exit 1
fi

PSQL=(psql "${CONN_STR}" -v ON_ERROR_STOP=1)

echo "Ensuring migrations bookkeeping table exists..."
"${PSQL[@]}" -c "
CREATE TABLE IF NOT EXISTS public.schema_migrations (
  filename TEXT PRIMARY KEY,
  checksum TEXT NOT NULL,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
"

shopt -s nullglob
mapfile -t migration_files < <(ls -1 "${MIGRATIONS_DIR}"/*.sql 2>/dev/null | sort || true)

if [[ ${#migration_files[@]} -eq 0 ]]; then
  echo "No migration files found in ${MIGRATIONS_DIR}."
  exit 0
fi

echo "Found ${#migration_files[@]} migration(s). Applying if needed..."

for file in "${migration_files[@]}"; do
  filename="$(basename "${file}")"
  checksum="$(sha256sum "${file}" | awk '{print $1}')"

  existing_checksum="$("${PSQL[@]}" -tAc "SELECT checksum FROM public.schema_migrations WHERE filename='${filename}'" || true)"
  existing_checksum="$(echo "${existing_checksum}" | tr -d '[:space:]')"

  if [[ -n "${existing_checksum}" ]]; then
    if [[ "${existing_checksum}" != "${checksum}" ]]; then
      echo "ERROR: Migration checksum mismatch for ${filename}"
      echo "  applied: ${existing_checksum}"
      echo "  current: ${checksum}"
      echo "Refusing to continue. Create a new migration instead of editing an applied one."
      exit 1
    fi
    echo "✓ Skipping already-applied migration: ${filename}"
    continue
  fi

  echo "→ Applying migration: ${filename}"
  "${PSQL[@]}" -f "${file}"
  "${PSQL[@]}" -c "INSERT INTO public.schema_migrations (filename, checksum) VALUES ('${filename}', '${checksum}');"
  echo "✓ Applied migration: ${filename}"
done

echo "Migrations complete."
