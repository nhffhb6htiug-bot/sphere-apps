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
| 3 | Client profile + dashboard: home dashboard, My Projects (Active/History/All), friendly status, Edit Profile, client nav, empty states | 2.3.0 | none (app only) |
| 6 | Job discovery + bidding: search/filter jobs, bid with price + delivery days + message, one bid per job, eligibility rules, compare + choose, other bids closed | 2.6.0 | `006_bidding.sql` |
| 5 | Job posting + AI: 3-step Post a Job, AI fills the form from plain words, style/format/length/revisions, review, drafts, requirements on job pages | 2.5.0 | `005_job_posting.sql` |
| 4 | Editor profile + verification: editor dashboard, availability, bio, edit editor profile, My Jobs tabs, rating display, pending/approved/rejected, ₹29 fee with UTR, admin fee check + reject | 2.4.0 | `004_editor_profile.sql` |

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

## Part 3 — test checklist
1. Upload the new `index.html.html` → Settings shows **Sphere v2.3.0**.
2. Client account with **no** projects: Home shows "No projects yet" with *Post a job* / *Browse editors*; Projects tab shows the same.
3. Client account **with** projects: Home shows Hi + Active / Need you / Completed; "Needs your action" lists jobs that need you.
4. Bottom bar says **Projects**; tabs Active / History / All switch and show counts.
5. Open a project → top line shows the status + your next step.
6. Profile → account type, member since, Projects / Completed / Paid via Sphere.
7. Profile → **Edit profile** → change photo, name, mobile → **Save** → Profile shows the new values.
8. Editor account: bottom bar still Home · Chat · Portfolio · Profile; Jobs list unchanged.

## Part 4 — test checklist
1. Supabase: run `003_auth_roles.sql` (if not done), then `004_editor_profile.sql`, then `checks/editor_profile_check.sql` → all ✅.
2. Upload `index.html.html` → Settings shows **Sphere v2.4.0**.
3. Editor Home: status buttons Available / Busy / Away change the chip; rating, Active, Completed show.
4. Profile → **Edit editor profile** → add bio, change skills → Save → Profile shows the bio; ✔ tick stays.
5. Unverified editor → Verification status → enter a UPI transaction ID → "Payment submitted — Sphere is checking".
6. Admin → Pending Verification → that editor shows the UTR → **Fee received** → editor sees "fee received".
7. Admin → **Reject** with a reason → editor sees "Verification not approved" + reason → **Apply again** → back to pending.
8. Admin → **Verify after call** → editor sees Verified ✔ on Home, Profile and the public page.
9. Client opens the editor's page → sees status chip + bio.
10. Editor → Jobs tab → Available / My work / History.

## Part 5 — test checklist
1. Supabase: run `005_job_posting.sql` → then `checks/job_posting_check.sql` → all ✅.
2. Upload `index.html.html` → Settings shows **Sphere v2.5.0**.
3. Client → Post a Job → write "60 sec Instagram reel, trending music, 3 din me, budget 800" → **✨ Fill the form with AI** → form is filled; change anything.
4. **Review job →** check the summary → **Post job** → My Projects shows it with its title.
5. Post another one → **Save as draft** → My Projects → **Drafts** → Continue → Post.
6. Skip the AI and fill the form yourself → still posts.
7. Editor account → open the job → sees length, format, style, references, revisions.
8. Editor page → **Hire Now** → same form → "Send to editor" → the editor gets the direct hire.

## Part 6 — test checklist (needs 1 client + 2 editor accounts)
1. Supabase: run `006_bidding.sql` → then `checks/bidding_check.sql` → all ✅.
2. Upload `index.html.html` → Settings shows **Sphere v2.6.0**.
3. Client posts a job (Part 5).
4. Editor A → Jobs → **Available** → search / filter finds it → open → price + days + message → **Send bid**. Try sending again → it becomes **Update bid**, never a second bid.
5. Editor B bids too (different price / days).
6. An editor set to **Away**, or rejected / not applied, sees "You can't bid" with the reason.
7. Client → project → **View bids & choose an editor** → sort, open **Compare** → **Choose this editor**.
8. Project shows "Agreeing on price" with the chosen bid; Editor A gets "You got selected 🎉"; Editor B's bid shows **Not selected** and B gets a notification.
9. Client tries to choose again → refused.
