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
| 11 | Revisions + change requests: 3 free revisions, ₹50 from the 4th (all to the editor), change requests with price / time / files, accept / reject, deadline + price history, Razorpay or UPI for extras | 2.11.0 | `011_revisions_changes.sql` + Edge Function `sphere-extra-payment` |
| 10 | Project files + watermarked preview: private project bucket, uploads with progress, links for 1 GB+ files, SPHERE watermark burned in on the editor's device, in-app player with moving watermark, preview versions | 2.10.0 | `010_project_files.sql` |
| 9 | Chat + AI moderation: project chat, UPI / bank / card / IFSC hidden, suspicious messages held, AI check (sphere-moderate), admin review queue | 2.9.0 | `009_chat_moderation.sql` + Edge Function `sphere-moderate` |
| 8 | Project workflow + deadlines: work clock after payment, 24 h per delivery day, 4 h grace, late detection, live countdown, preview link, ask / give more time, timeline, notifications | 2.8.0 | `008_project_workflow.sql` |
| 7 | Editor selection + payment: project card for both sides, price lock, payment screen, payment records (pending/paid/failed/refunded), duplicate protection, private split | 2.7.0 | `007_payments.sql` |
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

## Part 7 — test checklist (Razorpay test mode)
1. Supabase: run `007_payments.sql` → then `checks/payments_check.sql` → all ✅.
2. Upload `index.html.html` → Settings shows **Sphere v2.7.0**.
3. Client chooses a bid (Part 6) → project page shows **Project SPH-…**, the editor, price, delivery days.
4. Client taps **Accept & Lock This Amount** → goes to **Payment** → total to pay (no Sphere fee shown).
5. Pay with Razorpay test card **4111 1111 1111 1111** (any future date, any CVV) or test UPI **success@razorpay** → "Payment successful" → project "Editor is working", chip **Paid ✅**.
6. Try test UPI **failure@razorpay** on another project → "Payment failed" → payment screen shows the failure → retry works.
7. Open Payment again on the paid project → "Payment received", no pay button.
8. Editor sees the same project: "You receive …", payment chip, "start working".

## Part 8 — test checklist
1. Supabase: run `008_project_workflow.sql` → then `checks/project_workflow_check.sql` → all ✅ (line 4 says if the 10-minute check is on).
2. Upload `index.html.html` → Settings shows **Sphere v2.8.0**.
3. Pay a project (Part 7) → editor and client both get "project started"; project page shows the **countdown**.
4. Editor → **Need more time?** → +12 h + reason → client gets a notification and sees **Give the time / No**.
5. Client → **Give the time** → new deadline shows; timeline has both lines.
6. Client → **Give the editor more time** → +6 h → deadline moves again.
7. Editor → **Send preview to client** with a Drive link → client sees **Preview ready** + link; an Instagram link is refused.
8. Quick late test (SQL Editor): `update public.sp_project_work set due_at = now() - interval '5 hours' where phase = 'active';` then open the app → project shows **Late**, both get "Project is late"; client can give more time.
9. My Projects / editor Home show the ⏳ / ⚠️ / 🔴 / 👀 chips.

## Part 9 — test checklist
1. Supabase: run `009_chat_moderation.sql` → then `checks/chat_moderation_check.sql` → all ✅.
2. (Optional, for AI) Deploy the Edge Function `sphere-moderate` — see `supabase/functions/sphere-moderate/README.md`.
3. Upload `index.html.html` → Settings shows **Sphere v2.9.0**.
4. Paid project → **💬 Project chat with Editor** → header shows the project → send "Please add captions" → delivered.
5. Send `9876543210`, `rahul@okaxis`, `acc 123456789012` → shown as 📵.
6. Send "WhatsApp pe aa jao" → sender sees "being checked"; the other phone sees "⏳ This message is being checked by Sphere".
7. Admin Panel → **🛡️ Messages to review** → the original text + AI chip → **Remove** → the bubble becomes "🚫 Message removed", sender gets a warning. Try **Deliver** on another → the real text appears on both phones.
8. With `sphere-moderate` deployed: "export it for WhatsApp status also" is delivered automatically within seconds.

## Part 10 — test checklist (use Chrome on a computer or Android for the editor)
1. Supabase: run `010_project_files.sql` → then `checks/project_files_check.sql` → all ✅.
2. Upload `index.html.html` → Settings shows **Sphere v2.10.0**.
3. Client on a paid project → **📎 Project files** → **Upload files** (a photo + a small video) → progress bar → listed; editor gets a notification and can **Open** them.
4. Client → **🔗 Big files** → paste a Google Drive folder link → listed as a link; an Instagram link is refused.
5. Editor → **🎬 Choose video & add watermark** → pick a 20–60 s video → "Adding the SPHERE watermark… %" → "Uploading… %" → Preview v1 sent.
6. Client → **▶ Watch preview v1** → the video plays inside Sphere with a big moving SPHERE (burned in + on top), no download button.
7. Editor sends another preview → client sees **Preview v2** and can switch between versions.
8. Log in as a third account and open the project link → refused; the files cannot be opened.

## Part 11 — test checklist
1. Supabase: run `011_revisions_changes.sql` → then `checks/revisions_check.sql` → all ✅.
2. (Optional, for Razorpay) deploy `sphere-extra-payment` — see `supabase/functions/sphere-extra-payment/README.md`.
3. Upload `index.html.html` → Settings shows **Sphere v2.11.0**.
4. Paid project with a preview → client writes changes → **Ask for revision #1 (free)** → editor sees the notes + new deadline → editor sends the next preview → revision shows **Delivered as preview v2**.
5. Repeat until 3 free are used → the button says **Ask for revision #4 — ₹50** → after asking, **Pay ₹50** (Razorpay test, or "Pay by UPI instead" + transaction ID → Admin Panel → 💳 Extra payments → Received) → revision #4 starts.
6. Client → **📝 Ask for a change** → details + ₹400 + 24 h + a link + a file → editor **Accept** → client pays → *Accepted changes* shows on the job; project card shows original vs revised deadline; History keeps old deadline / old extra total.
7. Another change → editor **Reject** with a note → client is told.
