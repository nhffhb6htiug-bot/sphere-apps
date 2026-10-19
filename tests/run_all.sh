#!/usr/bin/env bash
# Sphere — minimal automated tests (local only; no production data, no real payments).
# Needs: PostgreSQL 14+ (psql + a local server), Node.js 18+, Python 3 + Playwright (Chromium).
set -u
cd "$(dirname "$0")/.."
FAILED=0
echo "== 1. database: contact privacy + chat blocking (migrations 031 + 032 on an isolated fixture)"
DB=sphere_test_$$
createdb "$DB" || exit 2
if psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f tests/db/fixture.sql \
   && psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/migrations/031_block_enforced.sql \
   && psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/migrations/032_block_contact.sql \
   && psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f tests/db/test_blocking.sql 2>&1 | grep -E "PASS|FAIL|ERROR"; then :; else FAILED=1; fi
psql -X -q -d "$DB" -c "select 1" >/dev/null 2>&1 && dropdb "$DB"
echo "== 2. unit: payment signature checks (real code from supabase/functions)"
node tests/unit/payment_signature.test.mjs || FAILED=1
echo "== 3. browser: Premium badge (real app, mocked server answer)"
python3 tests/browser/premium_badge_test.py || FAILED=1
[ $FAILED -eq 0 ] && echo "ALL TEST GROUPS PASSED" || { echo "SOME TESTS FAILED"; exit 1; }
