# Sphere — Roadmap

Workflow: Client → AI collects requirements → Job → Editors bid → Client selects → Payment → Editor works →
Watermarked preview → Revisions → Approval → Payment release / Dispute → Rating & performance.

Budget: ₹0 (free tiers). One part at a time: build → test → fix → next. Parts are numbered in the order Nitesh gives them.

## Done
| Part | Name | Version | Database file |
|---|---|---|---|
| — | Contact protection (number block, strikes, suspicious users) | 2.0 | `001_contact_protection.sql` |
| 1 | Foundation: structure, config, roles helpers, settings, system status, docs | 2.1.0 | `002_foundation.sql` |
| 2 | Auth + user roles: route protection, session end handling, logout cleanup, DB role checks, suspended banner | 2.2.0 | `003_auth_roles.sql` |

## Still to build (order decided by Nitesh)
Hidden names · AI job intake · bidding + selection + price model · upfront payment + work room + watermarked preview ·
revisions (3 free, 4th ₹50) + approval + payout + bonus · disputes (AI summary) + ratings + editor levels + Order Again ·
₹29 verification + ₹199 Pro + sponsored · Android catch-up + go live.

## Part 2 — test checklist
1. Supabase: run `003_auth_roles.sql` → Success; run `checks/auth_roles_check.sql` → all ✅.
2. Settings shows **Sphere v2.2.0**; Admin → System status lists 001, 002, 003.
3. Client account: can post a job and see own job's bids; Admin Panel and bid screen are refused with a message.
4. Editor account: can see work and bid; Post Job is refused until switching to Client mode; Admin Panel refused.
5. Admin account: lands on Admin Panel; can switch to Editor mode and back.
6. Logout → back to welcome; browser Back/reload does not show private screens.
7. Close and reopen the browser → still logged in (session kept).
