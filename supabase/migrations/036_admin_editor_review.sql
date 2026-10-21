-- =====================================================================
-- SPHERE — ADMIN: who verified / rejected each editor + a private admin note about the editor
-- Safe to run again. Deletes NO data.
-- • sp_editor_admin_notes: a short note (max 500 characters) about an editor. Only admins can read or
--   write it, through the functions below; the editor never sees it.
-- • sp_admin_editor_review(ids): for admins — verified editors (or the given editors) with who verified
--   them and when, the last 5 approve / reject decisions (admin name, time, reason) and the note.
-- • sp_admin_set_editor_note(editor, note, pin): admin + Admin PIN; every change is in the audit log.
-- =====================================================================
begin;
create table if not exists public.sp_editor_admin_notes (
  editor_id uuid primary key references public.profiles(id) on delete cascade,
  note text not null check (char_length(note) between 1 and 500),
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.sp_editor_admin_notes enable row level security;
revoke all on public.sp_editor_admin_notes from anon, authenticated;

create or replace function public.sp_admin_editor_review(p_ids uuid[] default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.sp_admin_only();
  return coalesce((select jsonb_agg(x order by (x->>'verified_at') desc nulls last, x->>'name') from (
    select jsonb_build_object(
      'id', p.id, 'name', p.full_name, 'is_verified', coalesce(p.is_verified, false), 'status', p.verification_status,
      'verified_at', p.verified_at,
      'verified_by_name', (select a.full_name from public.profiles a where a.id = p.verified_by),
      'note', n.note, 'note_by', (select a.full_name from public.profiles a where a.id = n.updated_by), 'note_at', n.updated_at,
      'history', coalesce((select jsonb_agg(jsonb_build_object('at', h.at, 'by', h.by_name, 'decision', h.new_status, 'reason', h.reason) order by h.at desc)
                  from (select au.at, au.new_status, au.reason, (select a.full_name from public.profiles a where a.id = au.actor_id) as by_name
                          from public.sp_admin_audit au
                         where au.target_type = 'user' and au.action = 'verification' and au.target_id = p.id::text
                         order by au.at desc limit 5) h), '[]'::jsonb)) as x
    from public.profiles p
    left join public.sp_editor_admin_notes n on n.editor_id = p.id
    where upper(btrim(p.role)) = 'EDITOR'
      and ((p_ids is null and coalesce(p.is_verified, false)) or p.id = any(p_ids))
  ) s), '[]'::jsonb);
end $$;

create or replace function public.sp_admin_set_editor_note(p_editor uuid, p_note text, p_pin text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v text := left(btrim(coalesce(p_note, '')), 500);
begin
  perform public.sp_admin_only();
  perform public.sp_admin_check_pin(p_pin);
  if not exists (select 1 from public.profiles where id = p_editor and upper(btrim(role)) = 'EDITOR') then raise exception 'Editor not found'; end if;
  if v = '' then
    delete from public.sp_editor_admin_notes where editor_id = p_editor;
  else
    insert into public.sp_editor_admin_notes (editor_id, note, updated_by, updated_at) values (p_editor, v, auth.uid(), now())
    on conflict (editor_id) do update set note = excluded.note, updated_by = excluded.updated_by, updated_at = now();
  end if;
  perform public.sp_audit_write('editor_note', 'user', p_editor::text, null, p_editor, null, null, left(v, 200), jsonb_build_object('cleared', v = ''));
  return jsonb_build_object('note', nullif(v, ''), 'at', now());
end $$;

revoke all on function public.sp_admin_editor_review(uuid[]), public.sp_admin_set_editor_note(uuid, text, text) from public, anon;
grant execute on function public.sp_admin_editor_review(uuid[]), public.sp_admin_set_editor_note(uuid, text, text) to authenticated;
insert into public.sp_schema_versions (version, name) values ('036', 'Admin: who verified / rejected each editor + private admin note')
on conflict (version) do update set applied_at = now();
commit;
