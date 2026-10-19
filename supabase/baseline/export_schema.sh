#!/usr/bin/env bash
# Export the production SCHEMA ONLY (no data rows) to supabase/baseline/schema.sql.
# Run on your own computer. Needs pg_dump 17 (same major version as the Supabase database).
#   1. Supabase → Project Settings → Database → Connection string → "Session pooler" (copy it)
#   2. export SPHERE_DB_URL='<that connection string with your database password>'
#   3. bash supabase/baseline/export_schema.sh
# The password stays in your terminal; it is never written to the file. Never commit the URL.
set -euo pipefail
: "${SPHERE_DB_URL:?set SPHERE_DB_URL first (see the comments above)}"
cd "$(dirname "$0")"
pg_dump "$SPHERE_DB_URL" --schema-only --no-owner \
  --schema=public --schema=sphere_private --schema=storage \
  --exclude-schema=sphere_backup -f schema.sql
# safety checks: no data, no obvious secrets
if grep -qiE '^copy |^insert into ' schema.sql; then echo "STOP: data rows found — do not commit"; exit 1; fi
if grep -qE 'sb_secret_|rzp_live_[A-Za-z0-9]{8}|github_pat_|-----BEGIN [A-Z ]*PRIVATE KEY' schema.sql; then echo "STOP: secret-like text found — do not commit"; exit 1; fi
echo "schema.sql written ($(wc -l < schema.sql) lines) — review it, then commit"
