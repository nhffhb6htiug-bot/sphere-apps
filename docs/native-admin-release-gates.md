# Native admin release gates
This branch is a read/preview implementation. No actual verification approval, rejection, suspension, project mutation or financial transaction was performed. New management actions are local dry-runs, deliberately not wired to production mutations. Existing outreach tracking is the only previous separately PIN-confirmed write.

## Contract mapping (not enabled)
- approve: sp_verify_editor(p_editor,p_category,p_pin); backend validates promo video and first-50 screenshot, but check fee eligibility and current pending state atomically before approving.
- reject/reopen: sp_ed_review(p_editor,p_action,p_note,p_pin); existing function updates by id without atomic editor role/current-state guard. Reopen must clear outreach in the same transaction, not a second best-effort request.
- account: sp_admin_user_action(p_user,p_action,p_reason,p_pin); add server rejection of admin/self targets and re-check active operator/session, not just UI.
- project: sp_admin_project_action(p_job,p_action,p_reason,p_hours,p_pin); flag/clear/open_review/add_time/close_unpaid require current server status and audit reason; close/unpaid must check provider order/in-flight state as well as captured status.
- hide/restore: sp_admin_project_visibility(p_job,p_action); existing RPC lacks PIN parameter. Harden server before enabling. Delete is excluded.
- no case decision, role promotion, payment/fee confirmation, release/refund or force verification from this build.

## Verification and privacy
Current admin role RPC checks database role; native additionally checks non-suspended status and session identity. Server functions must also enforce suspension, session revocation and MFA (AAL2) for privileged operations; native guard is not a security boundary. No new permissions or service keys. Existing broad admin RPCs return more fields than the UI needs; replace with server-side projections before release. Screenshot signed URL 90 seconds, app image cache disabled, screen protection and background clear; expiry cannot revoke already downloaded content. Video link opens external allowlisted provider and WhatsApp opens a draft on explicit action; no auto-send.

## Staging acceptance
Use test-only admin, editor and client, no production mutation. Check anon/client/editor access denied, admin revocation while open, wrong PIN/lockout, suspended admin, self/admin-target action denial, approve without proof/fee, reject wrong role, simultaneous state transitions, reopen atomic outreach clear, audit, screenshot wrong-owner path and expiry, project hide/restore and unpaid closure racing checkout. Record build, unit, authenticated RLS and two-device test results. No claim of full parity until these pass.
