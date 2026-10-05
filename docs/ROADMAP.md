# Sphere — Roadmap

Workflow: Client → AI collects requirements → Job → Editors bid → Client selects → Payment → Editor works →
Watermarked preview → Revisions → Approval → Payment release / Dispute → Rating & performance.

Budget: ₹0 (free tiers). One part at a time: build → test → fix → next.

| Part | Name | Status | Needs |
|---|---|---|---|
| — | Contact protection (number block, strikes, suspicious users) | ✅ Done (built before the roadmap) | — |
| 1 | Foundation: structure, config, roles, settings, system status, docs | 🔨 This release (v2.1.0) | — |
| 2 | Hidden names (Editor #A12 / Client #C45) | ⏳ | Part 1 |
| 3 | AI job intake (Sphere AI builds the job card) | ⏳ | `sphere-ai` function code |
| 4 | Bidding + selection + price model | ⏳ | Parts 2, 3 · decide Sphere share |
| 5 | Upfront payment + work room + watermarked preview | ⏳ | Part 4 |
| 6 | Revisions (3 free, 4th ₹50) + approval + payout + bonus | ⏳ | Part 5 · decide ₹50 owner, bonus rule |
| 7 | Disputes (AI summary) + ratings + Editor Levels + Order Again | ⏳ | Part 6 |
| 8 | ₹29 verification + ₹199 Pro + sponsored slots | ⏳ | Part 7 · decide Pro benefits |
| 9 | Android app catch-up + go live (Razorpay live keys) | ⏳ | Parts 2–8 |

## Part 1 — test checklist
1. Supabase → SQL Editor: run `supabase/migrations/002_foundation.sql` → "Success".
2. Run `supabase/checks/foundation_check.sql` → every line ends with ✅.
3. Website → Settings → bottom shows **Sphere v2.1.0**.
4. Admin Panel → **🛠️ System status** → Database Connected ✅, users by role, installed parts 001 + 002.
5. Old features still work: login (email + Google), post a job, bid, chat, admin verify editor.
6. Security: a normal account cannot make itself admin or verified (checked by the guard trigger).
