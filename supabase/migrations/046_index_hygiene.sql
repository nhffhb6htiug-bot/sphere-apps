-- SPHERE 046 — performance hygiene (advisors 0001 / 0009). No data or rules change.
begin;
drop index if exists public.sp_app_job_editor_uq;        -- same as sp_applications_job_id_editor_id_key (unique constraint, kept)
drop index if exists public.sp_msgs_pair_created_idx;    -- same as sp_messages_pair_idx
drop index if exists public.sp_notif_user_idx;           -- same as sp_notifications_user_idx
create index if not exists sp_blocks_blocked_idx on public.sp_blocks (blocked_id);
create index if not exists sp_chat_clears_other_idx on public.sp_chat_clears (other_id);
create index if not exists sp_contact_grants_fee_idx on public.sp_contact_grants (fee_id);
create index if not exists sp_contact_grants_target_idx on public.sp_contact_grants (target_id);
create index if not exists sp_detail_requests_editor_idx on public.sp_detail_requests (editor_id);
create index if not exists sp_editor_admin_notes_by_idx on public.sp_editor_admin_notes (updated_by);
create index if not exists sp_fee_payments_target_idx on public.sp_fee_payments (target_user);
create index if not exists sp_messages_reply_to_idx on public.sp_messages (reply_to);
create index if not exists sp_msg_hidden_message_idx on public.sp_msg_hidden (message_id);
create index if not exists sp_ratings_client_idx on public.sp_ratings (client_id);
create index if not exists sp_reports_against_idx on public.sp_reports (against_id);
create index if not exists sp_reports_job_idx on public.sp_reports (job_id);
create index if not exists sp_reports_reporter_idx on public.sp_reports (reporter_id);
create index if not exists sp_saved_editor_idx on public.sp_saved (editor_id);
insert into public.sp_schema_versions (version, name) values ('046', 'Index hygiene: 3 duplicate indexes removed, 14 foreign-key indexes added') on conflict (version) do update set applied_at = now();
commit;
