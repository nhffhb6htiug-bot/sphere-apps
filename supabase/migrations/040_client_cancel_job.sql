-- =====================================================================
-- SPHERE — CLIENT CAN CANCEL A PROJECT BEFORE PAYING (owner request, 21 Oct 2026)
-- Only the client who posted it, only while it is Open / Agreeing on price / Payment needed, and only if no
-- payment was made. After payment the dispute / refund process applies. Editors involved get a notification.
-- Safe to run again. Deletes NO data (the job stays, with status 'cancelled').
-- =====================================================================
begin;
create or replace function public.sp_client_cancel_job(p_job uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); j record; n int := 0;
begin
  if me is null then raise exception 'Please log in.'; end if;
  select id, client_id, status, title, category, assigned_editor, razorpay_payment_id into j from public.sp_jobs where id = p_job for update;
  if not found then raise exception 'Project not found.'; end if;
  if j.client_id is distinct from me then raise exception 'This is not your project.'; end if;
  if j.status = 'cancelled' then return jsonb_build_object('ok', true, 'already', true); end if;
  if j.status not in ('open', 'negotiating', 'payment-pending') or j.razorpay_payment_id is not null then
    raise exception 'This project can no longer be cancelled — the work or payment has started. If something is wrong, open a dispute from the project.';
  end if;
  update public.sp_jobs set status = 'cancelled' where id = p_job;
  insert into public.sp_notifications (user_id, title, body, category, job_id)
  select distinct x.e, 'Project cancelled', 'The client cancelled "' || coalesce(nullif(j.title, ''), j.category, 'a project') || '".', 'general', p_job
  from (select j.assigned_editor as e union select a.editor_id from public.sp_applications a where a.job_id = p_job) x
  where x.e is not null and x.e <> me;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'notified', n);
end $$;
revoke all on function public.sp_client_cancel_job(uuid) from public, anon;
grant execute on function public.sp_client_cancel_job(uuid) to authenticated;
insert into public.sp_schema_versions (version, name) values ('040', 'Client can cancel a project before paying')
on conflict (version) do update set applied_at = now();
commit;
