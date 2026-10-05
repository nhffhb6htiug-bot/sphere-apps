# Sphere — Database (Supabase)

> Built from the app code. For the exact live structure, run `supabase/checks/schema_snapshot.sql`
> and replace the "Tables" section with its output.

## Tables

| Table | Used for | Key columns (from the app) |
|---|---|---|
| `profiles` | Every user | `id`, `role` (CLIENT/EDITOR/ADMIN), `full_name`, `email`, `phone`, `avatar_url`, `categories[]`, `languages[]`, `skills[]`, `experience_years`, `price_range`, `sample_video_url`, `portfolio_url`, `is_verified`, `verification_code`, `verification_note`, `razorpay_account_id` |
| `sp_public_profiles` (view) | Public editor directory without phone/email | same as profiles minus private fields |
| `sp_jobs` | Jobs / projects | `client_id`, `category`, `description`, `budget`, `deadline`, `language`, `files_link`, `raw_files`, `status`, `assigned_editor`, `proposed_amount`, `proposed_by`, `locked_amount`, `payment_status`, `delivery_link`, `editor_amount`, `platform_fee`, `payout_status`, `razorpay_transfer_id` |
| `sp_applications` | Bids | `job_id`, `editor_id`, `message`, `bid_amount`, `status` (unique per job+editor) |
| `sp_messages` | Chat | `sender_id`, `receiver_id`, `text`, `media_path`, `media_type`, `duration_sec`, `delivered_at`, `read_at`, `created_at` |
| `sp_chat_clears` | "Clear chat" per person | `user_id`, `other_id`, `cleared_at` |
| `sp_blocks` | Blocked users | |
| `sp_portfolio` | Editor portfolio items | `editor_id`, `title`, `image_path`, `video_url` |
| `sp_ratings` | Reviews | `job_id`, `editor_id`, `client_id`, `stars`, `review` |
| `sp_reports` | Reports / complaints | `job_id`, `reporter_id`, `against_id`, `chat_user_id`, `reason`, `details`, `status`, `admin_note`, `resolved_at` |
| `sp_notifications` | In-app notifications | `user_id`, `title`, `body` |
| `sp_saved` | Saved editors | `user_id`, `editor_id` |
| `sp_settings` | Admin values | `key`, `value` — `platform_fee_percent`, `verify_fee`, `revision_fee`, `free_revisions`, `pro_fee`, `strike_limit`, `mod_skip_admins` |
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
| `sp_core_role`, `sp_core_has_role` | Anyone logged in | Role helpers |
| `sp_mod_mask`, `sp_mod_numeric_only`, `sp_mod_re` | Internal | Contact protection |

## Triggers

| Trigger | On | What |
|---|---|---|
| `sp_core_profile_guard` | `profiles` | Keeps roles in capitals; blocks self-made admins and self-given ✔ ticks |
| `zz_sp_mod_guard` | `sp_messages`, `sp_jobs`, `sp_applications`, `profiles`, `sp_portfolio`, `sp_ratings`, `sp_notifications` | Hides phone numbers, emails, links, @IDs; records strikes; blocks suspended users |

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
| `002_foundation.sql` | Part 1 |
