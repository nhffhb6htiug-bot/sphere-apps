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
echo "== 3d. database: admin editor review + private note (migration 036)"
run_sql_group admin036 tests/db/fixture_036.sql supabase/migrations/036_admin_editor_review.sql tests/db/test_036_admin_review.sql
echo "== 3e. database: phone push devices, delivery trigger, retry (migration 037; pg_net replaced by a stub)"
db37=sphere_t_push_$$; createdb "$db37" || exit 2
out=$( { cat tests/db/fixture_037.sql; sed '/create extension if not exists pg_net;/d' supabase/migrations/037_web_push.sql; cat tests/db/test_037_push.sql; } | psql -X -q -v ON_ERROR_STOP=1 -d "$db37" -f - 2>&1 || echo "ERROR in 037 group")
check_out push037 "$out"; dropdb "$db37" >/dev/null 2>&1
echo "== 3f. database: open bidding (migration 038)"
run_sql_group bids038 tests/db/fixture_038.sql supabase/migrations/038_open_bidding.sql tests/db/test_038_open_bidding.sql
echo "== 3g. database: one role per account, admin-only switch (migration 039)"
run_sql_group roles039 tests/db/fixture_039.sql supabase/migrations/039_admin_only_roles.sql tests/db/test_039_roles.sql
echo "== 3h. database: client cancels before paying (migration 040)"
run_sql_group cancel040 tests/db/fixture_040.sql supabase/migrations/040_client_cancel_job.sql tests/db/test_040_cancel.sql
echo "== 3i. database: phone OTP prepared (migration 042)"
run_sql_group otp042 tests/db/fixture_042.sql supabase/migrations/042_otp_login.sql tests/db/test_042_otp.sql
echo "== 4. unit: payment signature checks (real code from supabase/functions)"
out=$(node tests/unit/payment_signature.test.mjs 2>&1); rc=$?; check_out unit "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 4b. unit: service worker notification click"
out=$(node tests/unit/sw_notification_click.test.mjs 2>&1); rc=$?; check_out sw "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 4c. unit: Web Push encryption (RFC 8291 test vector) + VAPID"
out=$(node tests/unit/webpush_rfc.test.mjs 2>&1); rc=$?; check_out webpush "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 4d. unit: sphere-push delivery core (fake database + fake push service)"
out=$(node tests/unit/push_core.test.mjs 2>&1); rc=$?; check_out pushcore "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 4e. unit: service worker push handler"
out=$(node tests/unit/sw_push.test.mjs 2>&1); rc=$?; check_out swpush "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 4f. unit: sphere-otp hook (signature, WhatsApp → SMS, limits, no OTP in logs)"
out=$(node tests/unit/otp_core.test.mjs 2>&1); rc=$?; check_out otpcore "$out"; [ $rc -eq 0 ] || FAILED=1
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
echo "== 11. browser: admin verification — who verified, notes, unverify"
out=$(python3 tests/browser/admin_editor_review_test.py 2>&1); rc=$?; check_out admin2211 "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 12. browser: phone push in the app (register, no doubles, logout, test button)"
out=$(python3 tests/browser/push_app_test.py 2>&1); rc=$?; check_out pushapp "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 13. browser: Home recent projects without expired jobs"
out=$(python3 tests/browser/home_recent_test.py 2>&1); rc=$?; check_out home "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 14. browser: open bidding — verified / not verified on bids"
out=$(python3 tests/browser/open_bidding_test.py 2>&1); rc=$?; check_out openbid "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 15. browser: roles — no self switching, admin Make Client / Editor"
out=$(python3 tests/browser/roles_test.py 2>&1); rc=$?; check_out roles "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 16. browser: Help & Support, cancel before paying, minimise, Premium / Verified pills"
out=$(python3 tests/browser/home_cancel_badges_test.py 2>&1); rc=$?; check_out home2217 "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 17. browser: phone's own permission prompt + real notification icons"
out=$(python3 tests/browser/native_prompt_test.py 2>&1 | grep -v DeprecationWarning); rc=${PIPESTATUS[0]}; check_out native "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 18. browser: editor Home without the status card"
out=$(python3 tests/browser/editor_home_test.py 2>&1); rc=$?; check_out edhome "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 19. browser: Get Premium position, minimise empty card, Verified PC, Mobile/PC, ₹29 first"
out=$(python3 tests/browser/premium_pc_verify_test.py 2>&1); rc=$?; check_out v2220 "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 20. browser: phone OTP login (off / on)"
out=$(python3 tests/browser/otp_login_test.py 2>&1); rc=$?; check_out otplogin "$out"; [ $rc -eq 0 ] || FAILED=1
echo "== 21. browser: Admin Panel keeps its place, centred tabs, word wrapping"
out=$(python3 tests/browser/admin_scroll_test.py 2>&1); rc=$?; check_out adminscroll "$out"; [ $rc -eq 0 ] || FAILED=1
[ $FAILED -eq 0 ] && echo "ALL TEST GROUPS PASSED" || { echo "SOME TESTS FAILED"; exit 1; }
