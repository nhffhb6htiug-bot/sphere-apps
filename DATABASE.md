# Sphere — Database (Supabase)

> Built from the app code. For the exact live structure, run `supabase/checks/schema_snapshot.sql`
> and replace the "Tables" section with its output.

## Tables

| Table | Used for | Key columns (from the app) |
|---|---|---|
| `profiles` | Every user | `id`, `role` (CLIENT/EDITOR/ADMIN), `full_name`, `email`, `phone`, `avatar_url`, `categories[]`, `languages[]`, `skills[]`, `experience_years`, `price_range`, `sample_video_url`, `portfolio_url`, `is_verified`, `verification_code`, `verification_note`, `razorpay_account_id`, **Part 4:** `bio`, `availability` (available/busy/away), `verification_status` (not_applied/pending/approved/rejected), `verification_fee_status` (unpaid/submitted/confirmed), `verification_fee_ref`, `verification_fee_at`, `verification_reviewed_at` |
| `sp_public_profiles` (view) | Public editor directory without phone/email | same as profiles minus private fields |
| `sp_editor_public_extra` (view) | Public bio + availability of editors (Part 4) | `id`, `bio`, `availability` |
| `sp_jobs` | Jobs / projects | `client_id`, `category`, `description`, `budget`, `deadline`, `language`, `files_link`, `raw_files`, `status`, `assigned_editor`, `proposed_amount`, `proposed_by`, `locked_amount`, `payment_status`, `delivery_link`, `editor_amount`, `platform_fee`, `payout_status`, `razorpay_transfer_id`, **Part 5:** `title`, `video_length`, `video_format`, `style_notes`, `reference_links`, `revisions_expected`, `ai_assisted` |
| `sp_payments` | One payment record per project — Part 7 | `job_id` (unique), `client_id`, `editor_id`, `amount`, `status` (pending/paid/failed/refunded), `order_id`, `payment_id`, `attempts`, `failure_reason`, `duplicate_refs`, `paid_at`, `refunded_at` |
| `sp_payment_splits` | Sphere's internal split — admins only (Part 7) | `job_id`, `editor_base`, `platform_fee_percent`, `platform_fee`, `bonus_pool`, `editor_payout` |
| `sp_job_drafts` | Unfinished job posts (private to the client, max 20) — Part 5 | `id`, `client_id`, `data` (the form), `updated_at` |
| `sp_applications` | Bids | `job_id`, `editor_id`, `message`, `bid_amount`, `status` (pending / selected / rejected), **Part 6:** `delivery_days`, `updated_at` — one per job+editor (`sp_app_job_editor_uq`) |
| `sp_messages` | Chat | `sender_id`, `receiver_id`, `text`, `media_path`, `media_type`, `duration_sec`, `delivered_at`, `read_at`, `created_at` |
| `sp_chat_clears` | "Clear chat" per person | `user_id`, `other_id`, `cleared_at` |
| `sp_blocks` | Blocked users | |
| `sp_portfolio` | Editor portfolio items | `editor_id`, `title`, `image_path`, `video_url` |
| `sp_ratings` | Reviews | `job_id`, `editor_id`, `client_id`, `stars`, `review` |
| `sp_reports` | Reports / complaints | `job_id`, `reporter_id`, `against_id`, `chat_user_id`, `reason`, `details`, `status`, `admin_note`, `resolved_at` |
| `sp_notifications` | In-app notifications | `user_id`, `title`, `body` |
| `sp_saved` | Saved editors | `user_id`, `editor_id` |
| `sp_settings` | Admin values | `key`, `value` — `platform_fee_percent`, `verify_fee`, `revision_fee`, `free_revisions`, `pro_fee`, `strike_limit`, `mod_skip_admins`, `free_works`, `bids_verified_only` |
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
| `sp_pay_sync_job` | `sp_jobs` (after insert/update) | Keeps `sp_payments` + split in step with the project (Part 7) |
| `sp_bid_guard` | `sp_applications` | Bidding rules on insert; editors change only their own pending bid; clients only the status (Part 6) |
| `sp_core_role_guard` | `sp_applications` (insert), `sp_portfolio`, `sp_ratings` (insert) | Only editors bid / have a portfolio; only the job's client reviews its editor (Part 2) |
| `zz_sp_mod_guard` | `sp_messages`, `sp_jobs`, `sp_applications`, `profiles` (name, price, bio), `sp_portfolio`, `sp_ratings`, `sp_notifications` | Hides phone numbers, emails, links, @IDs; records strikes; blocks suspended users |

## Storage buckets
`sphere-raw` (client footage, max 5 files × 50 MB), `sphere-media` (avatars, portfolio), `sphere-chat` (chat photos, videos, voice notes).

## Edge Functions (code not in GitHub yet — see `supabase/functions/README.md`)
`sphere-ai`, `create-razorpay-order`, `verify-razorpay-payment`, `release-payout`, `refund-payment`.

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
