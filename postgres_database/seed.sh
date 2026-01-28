#!/usr/bin/env bash
set -euo pipefail

# Runs seed SQL files in ./seeds in lexical order and records them in public.seed_runs.
# Seed SQL should be idempotent (use ON CONFLICT DO NOTHING where appropriate).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_CONN_FILE="${ROOT_DIR}/db_connection.txt"
SEEDS_DIR="${ROOT_DIR}/seeds"

if [[ ! -f "${DB_CONN_FILE}" ]]; then
  echo "ERROR: db_connection.txt not found at ${DB_CONN_FILE}"
  echo "Run startup.sh first to initialize PostgreSQL and create db_connection.txt."
  exit 1
fi

if [[ ! -d "${SEEDS_DIR}" ]]; then
  echo "No seeds directory found at ${SEEDS_DIR}. Nothing to do."
  exit 0
fi

CONN_STR="$(sed -e 's/^psql[[:space:]]*//' "${DB_CONN_FILE}")"
if [[ -z "${CONN_STR}" ]]; then
  echo "ERROR: Could not parse connection string from db_connection.txt"
  exit 1
fi

PSQL=(psql "${CONN_STR}" -v ON_ERROR_STOP=1)

echo "Ensuring seed bookkeeping table exists..."
"${PSQL[@]}" -c "
CREATE TABLE IF NOT EXISTS public.seed_runs (
  filename TEXT PRIMARY KEY,
  checksum TEXT NOT NULL,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
"

shopt -s nullglob
mapfile -t seed_files < <(ls -1 "${SEEDS_DIR}"/*.sql 2>/dev/null | sort || true)

if [[ ${#seed_files[@]} -eq 0 ]]; then
  echo "No seed files found in ${SEEDS_DIR}."
  exit 0
fi

echo "Found ${#seed_files[@]} seed file(s). Applying if needed..."

for file in "${seed_files[@]}"; do
  filename="$(basename "${file}")"
  checksum="$(sha256sum "${file}" | awk '{print $1}')"

  existing_checksum="$("${PSQL[@]}" -tAc "SELECT checksum FROM public.seed_runs WHERE filename='${filename}'" || true)"
  existing_checksum="$(echo "${existing_checksum}" | tr -d '[:space:]')"

  if [[ -n "${existing_checksum}" ]]; then
    if [[ "${existing_checksum}" != "${checksum}" ]]; then
      echo "ERROR: Seed checksum mismatch for ${filename}"
      echo "  applied: ${existing_checksum}"
      echo "  current: ${checksum}"
      echo "Refusing to continue. Create a new seed file instead of editing an applied one."
      exit 1
    fi
    echo "✓ Skipping already-applied seed: ${filename}"
    continue
  fi

  echo "→ Applying seed: ${filename}"
  "${PSQL[@]}" -f "${file}"
  "${PSQL[@]}" -c "INSERT INTO public.seed_runs (filename, checksum) VALUES ('${filename}', '${checksum}');"
  echo "✓ Applied seed: ${filename}"
done

echo "Seeding complete."
