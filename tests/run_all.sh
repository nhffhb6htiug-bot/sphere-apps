#!/usr/bin/env bash
# Sphere — automated tests (local only; no production data, no real payments).
# Needs: PostgreSQL 14+ (createdb/psql + local server), Node.js 18+, Python 3 + Playwright (Chromium).
# Any FAIL / ERROR line or non-zero exit in any group makes the whole run fail (exit 1).
set -u
cd "$(dirname "$0")/.."
FAILED=0
check_out(){ # $1 = group name, $2 = output; fail on FAIL/ERROR lines
  echo "$2" | grep -E "PASS|FAIL|ERROR|TOTAL"
  if echo "$2" | grep -qE "FAIL|ERROR"; then echo "!! $1 FAILED"; FAILED=1; fi
}
run_sql_group(){ # $1 = name, rest = sql files in order
  local name="$1"; shift; local db="sphere_t_${name}_$$" out rc
  createdb "$db" || { echo "!! cannot create test database"; exit 2; }
  out=$(for f in "$@"; do psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f "$f" 2>&1 || echo "ERROR in $f"; done)
  check_out "$name" "$out"
  dropdb "$db" >/dev/null 2>&1
}
echo "== 1. database: contact privacy + chat blocking (migrations 031 + 032)"
run_sql_group blocking tests/db/fixture.sql supabase/migrations/031_block_enforced.sql supabase/migrations/032_block_contact.sql tests/db/test_blocking.sql
echo "== 2. database: Premium status + webhook duplicates"
run_sql_group premium tests/db/test_premium_webhook.sql
echo "== 3. database: fee one-pending rules (migration 033)"
run_sql_group fees tests/db/test_fee_pending.sql
echo "== 3b. database: chat replies + private last seen (migration 034)"
run_sql_group chat034 tests/db/fixture_034.sql supabase/migrations/034_chat_reply_last_seen.sql tests/db/test_034_chat.sql
echo "== 3c. database: delete for me (migration 035)"
run_sql_group chat035 tests/db/fixture_034.sql supabase/migrations/034_chat_reply_last_seen.sql supabase/migrations/035_chat_delete_for_me.sql tests/db/test_035_delete_for_me.sql
echo "== 4. unit: payment signature checks (real code from supabase/functions)"
out=$(node tests/unit/payment_signature.test.mjs 2>&1); rc=$?; check_out unit "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 4b. unit: service worker notification click"
out=$(node tests/unit/sw_notification_click.test.mjs 2>&1); rc=$?; check_out sw "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 5. browser: Premium badge"
out=$(python3 tests/browser/premium_badge_test.py 2>&1); rc=$?; check_out badge "$out"; [ $rc -eq 0 ] || FAILED=1
if [ -f tests/browser/chat_online_test.py ]; then
  echo "== 6. browser: chat online status + header buttons"
  out=$(python3 tests/browser/chat_online_test.py 2>&1); rc=$?; check_out online "$out"; [ $rc -eq 0 ] || FAILED=1
fi
echo "== 7. browser: instant tabs (cached copy) + Liquid Glass"
out=$(python3 tests/browser/instant_tabs_test.py 2>&1); rc=$?; check_out tabs "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 8. browser: chat upgrade (keyboard, reply, emoji, photos, viewer, typing, last seen)"
out=$(python3 tests/browser/chat_upgrade_test.py 2>&1); rc=$?; check_out chat "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 9. browser: message alerts, tones, preferences, notification links"
out=$(python3 tests/browser/message_alerts_test.py 2>&1); rc=$?; check_out alerts "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 10. browser: v2.22.10 (Send button, delete for me, bell, auto-read, permission prompt, last seen)"
out=$(python3 tests/browser/chat_fixes_2210_test.py 2>&1); rc=$?; check_out fixes2210 "$out"; [ $rc -eq 0 ] || FAILED=1
[ $FAILED -eq 0 ] && echo "ALL TEST GROUPS PASSED" || { echo "SOME TESTS FAILED"; exit 1; }
