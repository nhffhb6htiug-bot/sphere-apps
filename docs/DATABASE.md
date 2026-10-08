# Sphere — Database (Supabase)

> Built from the app code. For the exact live structure, run `supabase/checks/schema_snapshot.sql`
> and replace the "Tables" section with its output.

## Tables

| Table | Used for | Key columns (from the app) |
|---|---|---|
| `profiles` | Every user | `id`, `role` (CLIENT/EDITOR/ADMIN), `full_name`, `email`, `phone`, `avatar_url`, `categories[]`, `languages[]`, `skills[]`, `experience_years`, `price_range`, `sample_video_url`, `portfolio_url`, `is_verified`, `verification_code`, `verification_note`, `razorpay_account_id`, **Part 4:** `bio`, `availability` (available/busy/away), `verification_status` (not_applied/pending/approved/rejected), `verification_fee_status` (unpaid/submitted/confirmed), `verification_fee_ref`, `verification_fee_at`, `verification_reviewed_at` |
| `sp_public_profiles` (view) | Public editor directory without phone/email | same as profiles minus private fields |
| `sp_editor_public_extra` (view) | Public bio + availability of editors (Part 4) | `id`, `bio`, `availability` |
| `sp_jobs` | Jobs / projects | `client_id`, `category`, `description`, `budget`, `deadline`, `language`, `files_link`, `raw_files`, `status`, `assigned_editor`, `proposed_amount`, `proposed_by`, `locked_amount`, `payment_status`, `delivery_link`, `editor_amount`, `platform_fee`, `payout_status`, `razorpay_transfer_id`, **Part 11:** `extra_requirements`, `extra_amount`, **Part 12:** `review_state`, `final_submitted_at`, `decision_due_at`, **Part 13:** `released_at`, **Part 5:** `title`, `video_length`, `video_format`, `style_notes`, `reference_links`, `revisions_expected`, `ai_assisted` |
| `sp_project_work` | Work clock per paid project — Part 8 | `job_id`, `phase` (active/preview/completed/cancelled), `started_at`, `hours`, `due_at`, `grace_hours`, `extended_hours`, `pending_extension_hours`, `preview_link`, `preview_note`, `preview_at`, `preview_on_time`, `is_late`, `late_since`, notice times |
| `sp_project_extensions` | More-time requests (one pending per project) — Part 8 | `job_id`, `requested_by`, `hours`, `reason`, `status` (pending/approved/declined) |
| `sp_project_events` | Project timeline — Part 8 | `job_id`, `at`, `actor_id`, `kind`, `title`, `details` |
| `sp_payments` | One payment record per project — Part 7 | `job_id` (unique), `client_id`, `editor_id`, `amount`, `status` (pending/paid/failed/refunded), `order_id`, `payment_id`, `attempts`, `failure_reason`, `duplicate_refs`, `paid_at`, `refunded_at` |
| `sp_payment_splits` | Sphere's internal split — admins only (Part 7) | `job_id`, `editor_base`, `platform_fee_percent`, `platform_fee`, `bonus_pool`, `editor_payout` |
| `sp_job_drafts` | Unfinished job posts (private to the client, max 20) — Part 5 | `id`, `client_id`, `data` (the form), `updated_at` |
| `sp_applications` | Bids | `job_id`, `editor_id`, `message`, `bid_amount`, `status` (pending / selected / rejected), **Part 6:** `delivery_days`, `updated_at` — one per job+editor (`sp_app_job_editor_uq`) |
| `sp_messages` | Chat | `sender_id`, `receiver_id`, `text`, `media_path`, `media_type`, `duration_sec`, `delivered_at`, `read_at`, `created_at`, **Part 9:** `job_id` (project chat), `mod_status` (ok / held / released / removed), `mod_reason` |
| `sp_project_ratings` | Client rating −3…+3 + feedback, one per project — Part 13 | `job_id` (unique), `editor_id`, `client_id`, `score`, `feedback` |
| `sp_editor_ratings_public` (view) | Rating history for editor pages, no client names — Part 13 | `editor_id`, `score`, `feedback`, `created_at`, `category` |
| `sp_delivery_checks` | Each preview vs the deadline valid then — Part 13 | `job_id`, `kind` (main / followup), `due_at`, `grace_hours`, `delivered_at`, `early_hours`, `late_minutes`, `late_hours` |
| `sp_settlements` | Bonus / deduction calculation per project — admins only (Part 13) | `client_paid`, `editor_base`, `pool`, `sphere_guaranteed`, `bonus_pool`, `part_value`, `c_early`, `c_rating`, `c_revisions`, `c_quality`, `conditions_met`, `late_hours`, `late_deduction`, `bonus_awarded`, `sphere_total`, `net_adjustment`, `status` (provisional / final), `details` |
| `sp_final_files` | Final preview + clean final link; client sees it only after release — Part 12 | `job_id`, `preview_file_id`, `preview_version`, `final_link`, `note`, `submitted_at` |
| `sp_disputes` | Cases for the Sphere team — Part 12 | `kind` (dispute / no_response), `category`, `details`, `status` (open / resolved_release / resolved_refund / resolved_redo / withdrawn), `ai_category`, `ai_summary`, `decision_note`, `decided_by`, `snapshot` |
| `sp_refunds` | Full refunds — Part 12 | `job_id`, `dispute_id`, `amount`, `status` (approved / processing / refunded / failed / rejected), `reason`, `error` |
| `sp_payout_items` | Editor money to send / recover by hand (Parts 12–13) | `job_id`, `editor_id`, `kind` (extras / bonus / deduction), `amount`, `status` (pending / paid) |
| `sp_revisions` | Revisions per project — Part 11 | `number`, `notes`, `is_paid`, `fee`, `status` (awaiting_payment / open / delivered / cancelled), `old_due_at`, `new_due_at`, `preview_version`, `delivered_version` |
| `sp_change_requests` | Change requests — Part 11 | `details`, `extra_price`, `extra_hours`, `link`, `file_ids`, `status` (pending / rejected / accepted_awaiting_payment / applied / cancelled), `editor_note`, `old_due_at`, `new_due_at`, `old_extra_amount`, `new_extra_amount`, `old_requirements` |
| `sp_extra_payments` | Extra money in a project (paid revision, change price) — Part 11 | `kind`, `ref_id`, `amount`, `status` (pending / paid / failed / cancelled), `method` (razorpay / upi), `order_id`, `payment_id`, `utr` |
| `sp_extra_splits` | Editor / Sphere share of each extra — admins only (Part 11) | `extra_id`, `editor_share`, `sphere_share` |
| `sp_project_files` | Files, links and preview versions of a project — Part 10 | `job_id`, `uploaded_by`, `kind` (client_file / preview), `source` (upload / link), `storage_path`, `external_url`, `file_name`, `mime`, `size_bytes`, `duration_sec`, `version`, `status` (uploading / ready / failed / removed), `note` |
| `sp_msg_holds` | Held messages — admins only (Part 9) | `message_id`, `job_id`, `sender_id`, `receiver_id`, `original_text`, `reason`, `status`, `ai_verdict`, `ai_confidence`, `ai_reason`, `reviewed_by` |
| `sp_chat_clears` | "Clear chat" per person | `user_id`, `other_id`, `cleared_at` |
| `sp_blocks` | Blocked users | |
| `sp_portfolio` | Editor portfolio items | `editor_id`, `title`, `image_path`, `video_url` |
| `sp_ratings` | Reviews | `job_id`, `editor_id`, `client_id`, `stars`, `review` |
| `sp_reports` | Reports / complaints | `job_id`, `reporter_id`, `against_id`, `chat_user_id`, `reason`, `details`, `status`, `admin_note`, `resolved_at` |
| `sp_notifications` | In-app notifications | `user_id`, `title`, `body` |
| `sp_saved` | Saved editors | `user_id`, `editor_id` |
| `sp_settings` | Admin values | `key`, `value` — `platform_fee_percent`, `verify_fee`, `revision_fee`, `free_revisions`, `pro_fee`, `strike_limit`, `mod_skip_admins`, `free_works`, `bids_verified_only`, `work_default_hours`, `work_grace_hours`, `work_fixed_hours`, `work_reminder_hours`, `file_max_mb`, `preview_max_minutes`, `revision_hours`, `final_review_hours`, `late_fee_per_hour`, `bonus_early_hours`, `rating_window_days` |
| `sp_mod_flags` | Strikes / suspension per user (admin-only write) | `user_id`, `strike_count`, `is_suspended`, `warned_at` |
| `sp_mod_strikes` | Every hidden/flagged message (admins only) | `user_id`, `source`, `kind`, `original_text`, `cleared` |
| `sp_schema_versions` | Which Sphere parts are installed | `version`, `name`, `applied_at` |

## Database functions (RPC)

| Function | Who | What |
|---|---|---|
| `sp_admin_check_pin`, `sp_admin_pin_status`, `sp_set_admin_pin` | Admin | Admin Panel PIN |
| `sp_make_admin`, `sp_remove_admin` | Admin + PIN | Manage admins |
| `sp_verify_editor`, `sp_unverify_editor` | Admin + PIN | ✔ tick |
| `sp_set_platform_fee` | Admin + PIN | Commission % |
| `sp_mod_admin_action` | Admin + PIN | Warn / suspend / unsuspend / clear strikes |
| `sp_core_status` | Admin | System status card |
| `sp_rating_submit` | Project's client | Rate −3…+3 once → project closed → settlement final (Part 13) |
| `sp_bonus_tick` | Anyone logged in, pg_cron | Settle projects not rated within the window (Part 13) |
| `sp_settlement_mine`, `sp_editor_earnings_summary` | Editor (own) / admin | Earnings with bonus conditions; totals (Part 13) |
| `sp_final_submit` | Project's editor | Final preview + clean link → client decides within 10 h (Part 12) |
| `sp_dispute_open` | Project's client | Not satisfied / editor never delivered → case with snapshot (Part 12) |
| `sp_final_tick` | Anyone logged in, pg_cron | 10 h passed → Sphere team review (Part 12) |
| `sp_case_decide`, `sp_case_ai_note`, `sp_refund_mark`, `sp_refund_eligibility`, `sp_payout_item_paid` | Admin (+ PIN) | Team decisions, AI note, refund status, eligibility, extra payouts (Part 12) |
| `sp_rev_request`, `sp_rev_cancel` | Project's client | Ask for / cancel an unpaid revision (Part 11) |
| `sp_cr_create`, `sp_cr_cancel` / `sp_cr_answer` | Client / editor | Change request: send, cancel / accept or reject (Part 11) |
| `sp_extra_mark_paid` | sphere-extra-payment (server) or admin | Mark an extra paid → revision opens / change applied (Part 11) |
| `sp_extra_submit_utr` / `sp_extra_admin` | Client / admin + PIN | UPI transaction ID / received or not found (Part 11) |
| `sp_files_begin` / `sp_files_finish` | Client (files) / editor (previews) | Reserve an upload path → mark ready or failed; previews update the work clock (Part 10) |
| `sp_files_add_link` | Client / editor | Big-file link or long-preview link (Part 10) |
| `sp_files_remove` | Uploader / admin | Remove a file (previews stay) (Part 10) |
| `sp_chat_review` | Admin + PIN | Deliver / remove a held message (Part 9) |
| `sp_chat_ai_verdict` | sphere-moderate (server) or admin | Save the AI result; server + safe ≥ 0.8 → deliver (Part 9) |
| `sp_work_submit_preview` | Project's editor | Preview link + note → client told (Part 8) |
| `sp_work_request_extension` / `sp_work_answer_extension` | Editor / client | Ask for / answer more time (Part 8) |
| `sp_work_give_time` | Project's client | Give more time without being asked (Part 8) |
| `sp_work_tick` | Anyone logged in, pg_cron | Reminders, deadline passed, late — once each (Part 8) |
| `sp_pay_lock_price` | Client or chosen editor | Accept the other side's price → payment-pending (Part 7) |
| `sp_pay_start`, `sp_pay_record` | Project's client | Before / after Razorpay: ready + not paid; save IDs or failure (Part 7) |
| `sp_bid_eligibility` | Anyone logged in | Can this editor bid (on this job)? + the reason (Part 6) |
| `sp_bid_select` | Job's client | Choose one bid; other bids closed; notifications (Part 6) |
| `sp_bid_editor_stats`, `sp_bid_counts` | Anyone logged in | Jobs done / rating per editor; number of bids per open job (Part 6) |
| `sp_ed_review` | Admin + PIN | Fee received / fee not found / reject with reason / re-open (Part 4) |
| `sp_core_role`, `sp_core_has_role` | Anyone logged in | Role helpers |
| `sp_core_whoami` | Anyone logged in | Own role, ✔ tick, suspended (Part 2) |
| `sp_core_job_parties` | Internal | Who is the client / editor of a job |
| `sp_mod_mask`, `sp_mod_numeric_only`, `sp_mod_re` | Internal | Contact protection |

## Triggers

| Trigger | On | What |
|---|---|---|
| `sp_core_profile_guard` | `profiles` | Keeps roles in capitals; blocks self-made admins and self-given ✔ ticks |
| `sp_ed_profile_sync` | `profiles` (before update) | Keeps verification state in step with the ✔ tick; editors can only apply / re-apply and submit a fee (Part 4) |
| `sp_ed_profile_after` | `profiles` (after update) | Notifies admins when an editor applies or submits the fee (Part 4) |
| `sp_delivery_check_trigger` | `sp_project_work` (preview_at) | Record each delivery vs its valid deadline (Part 13) |
| `sp_bonus_on_release` | `sp_jobs` (status → approved) | Provisional settlement at release (Part 13) |
| `sp_final_job_before` / `sp_final_job_after` | `sp_jobs` (status → approved / refunded) | Unlock the final link, close cases, refunds → refunded, extras payout, notices (Part 12) |
| `sp_final_report_guard` | `sp_reports` (insert) | No complaints after release (Part 12) |
| `sp_rev_on_preview` | `sp_project_work` (phase / preview change) | Next preview delivers the open revision (Part 11) |
| `sp_chat_project_guard` | `sp_messages` (insert) | Project chat only between that project's client and editor (Part 9) |
| `zzz_sp_chat_hold`, `sp_chat_hold_after` | `sp_messages` (insert) | Hold messages with warning words; tell admins (Part 9) |
| `sp_work_job_trigger` | `sp_jobs` (insert, status change) | Timeline lines; starts / completes / cancels the work clock (Part 8) |
| `sp_work_pay_trigger` | `sp_payments` (status change) | Timeline lines for paid / failed payments (Part 8) |
| `sp_pay_sync_job` | `sp_jobs` (after insert/update) | Keeps `sp_payments` + split in step with the project (Part 7) |
| `sp_bid_guard` | `sp_applications` | Bidding rules on insert; editors change only their own pending bid; clients only the status (Part 6) |
| `sp_core_role_guard` | `sp_applications` (insert), `sp_portfolio`, `sp_ratings` (insert) | Only editors bid / have a portfolio; only the job's client reviews its editor (Part 2) |
| `zz_sp_mod_guard` | `sp_messages`, `sp_jobs`, `sp_applications`, `profiles` (name, price, bio), `sp_portfolio`, `sp_ratings`, `sp_notifications` | Hides phone numbers, emails, links, @IDs; records strikes; blocks suspended users |

## Storage buckets
`sphere-project` (**private**, project files + watermarked previews — Part 10), `sphere-raw` (files attached when posting a job, max 5 × 50 MB, public), `sphere-media` (avatars, portfolio), `sphere-chat` (chat photos, videos, voice notes).

## Edge Functions (code not in GitHub yet — see `supabase/functions/README.md`)
`sphere-moderate` (Part 9) and `sphere-extra-payment` (Part 11) — code in `supabase/functions/`, `sphere-ai`, `create-razorpay-order`, `verify-razorpay-payment`, `release-payout`, `refund-payment`.

## Migrations (run in order)

| File | Status |
|---|---|
| `000_backup_before_part1.sql` | ✅ Run 5 Oct 2026 |
| `001_contact_protection.sql` | ✅ Run (re-run the latest copy once — it is safe) |
| `001b_optional_clean_old_messages.sql` | Optional |
| `001_undo_contact_protection.sql` | Emergency only — do **not** run normally |
| `002_foundation.sql` | ✅ Part 1 |
| `003_auth_roles.sql` | Part 2 |
| `004_editor_profile.sql` | Part 4 |
| `005_job_posting.sql` | Part 5 |
| `006_bidding.sql` | Part 6 |
| `007_payments.sql` | Part 7 |
| `008_project_workflow.sql` | Part 8 |
| `009_chat_moderation.sql` | Part 9 |
| `010_project_files.sql` | Part 10 |
| `011_revisions_changes.sql` | Part 11 |
| `012_final_disputes.sql` | Part 12 |
| `013_ratings_bonus.sql` | Part 13 |
