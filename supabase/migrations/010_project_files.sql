-- =====================================================================
-- SPHERE — PART 10: FILE UPLOAD + WATERMARKED PREVIEW
-- Run in: Supabase → SQL Editor → + → paste → Run.  Safe to run again.
-- Needs 001, 002, 008 first. Adds a private bucket, a table, rules; deletes nothing.
--
--   Storage bucket  sphere-project  (PRIVATE, 50 MB per file — free plan limit)
--     <job id>/client/<file id>.<ext>   files the client shares
--     <job id>/preview/<file id>.<ext>  watermarked previews from the editor
--   Only the project's client, its editor and admins can open these files,
--   and only files reserved through sp_files_begin can be uploaded.
--   sp_project_files  every file / link / preview version of a project
--   Bigger files (over 50 MB, e.g. 1 GB+ raw footage): a Drive / Dropbox /
--   WeTransfer / OneDrive link, visible only to the two people in the project.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) Settings + private bucket
-- ---------------------------------------------------------------------
insert into public.sp_settings (key, value) select 'file_max_mb', '50'          where not exists (select 1 from public.sp_settings where key = 'file_max_mb');
insert into public.sp_settings (key, value) select 'preview_max_minutes', '10'  where not exists (select 1 from public.sp_settings where key = 'preview_max_minutes');

insert into storage.buckets (id, name, public, file_size_limit)
values ('sphere-project', 'sphere-project', false, 52428800)
on conflict (id) do update set public = false;

-- ---------------------------------------------------------------------
-- 2) Files of a project
-- ---------------------------------------------------------------------
create table if not exists public.sp_project_files (
  id            uuid primary key default gen_random_uuid(),
  job_id        uuid not null,
  uploaded_by   uuid not null,
  kind          text not null,                 -- client_file | preview
  source        text not null,                 -- upload | link
  storage_path  text,
  external_url  text,
  file_name     text,
  mime          text,
  size_bytes    bigint,
  duration_sec  numeric(10,2),
  version       int,                           -- preview v1, v2, …
  status        text not null default 'uploading',   -- uploading | ready | failed | removed
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
alter table public.sp_project_files drop constraint if exists sp_files_chk;
alter table public.sp_project_files add  constraint sp_files_chk check (
  kind in ('client_file', 'preview') and source in ('upload', 'link')
  and status in ('uploading', 'ready', 'failed', 'removed')
  and (file_name is null or char_length(file_name) <= 120) and (note is null or char_length(note) <= 500)
  and (external_url is null or char_length(external_url) <= 500));
create unique index if not exists sp_files_path_uq on public.sp_project_files (storage_path) where storage_path is not null;
create unique index if not exists sp_files_preview_ver_uq on public.sp_project_files (job_id, version) where kind = 'preview';
create index if not exists sp_files_job_idx on public.sp_project_files (job_id, created_at);

-- is the logged-in user the client or editor of this project (or an admin)?
create or replace function public.sp_files_party(p_job text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sp_jobs j where j.id::text = p_job
                   and (j.client_id = auth.uid() or j.assigned_editor = auth.uid()))
         or public.sp_core_has_role('ADMIN');
$$;
revoke all on function public.sp_files_party(text) from public, anon;
grant execute on function public.sp_files_party(text) to authenticated;

alter table public.sp_project_files enable row level security;
drop policy if exists sp_files_read on public.sp_project_files;
create policy sp_files_read on public.sp_project_files for select to authenticated using (public.sp_files_party(job_id::text));
revoke insert, update, delete on public.sp_project_files from anon, authenticated;
grant select on public.sp_project_files to authenticated;

-- may the logged-in user upload exactly this object? (it must be reserved by sp_files_begin)
create or replace function public.sp_files_upload_ok(p_name text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sp_project_files f
                  where f.storage_path = p_name and f.uploaded_by = auth.uid() and f.status = 'uploading'
                    and f.created_at > now() - interval '6 hours');
$$;
revoke all on function public.sp_files_upload_ok(text) from public, anon;
grant execute on function public.sp_files_upload_ok(text) to authenticated;

-- ---------------------------------------------------------------------
-- 3) Storage rules for the private bucket
-- ---------------------------------------------------------------------
drop policy if exists sp_project_files_read   on storage.objects;
drop policy if exists sp_project_files_insert on storage.objects;
drop policy if exists sp_project_files_delete on storage.objects;
create policy sp_project_files_read on storage.objects for select to authenticated
  using (bucket_id = 'sphere-project' and public.sp_files_party((storage.foldername(name))[1]));
create policy sp_project_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'sphere-project' and public.sp_files_upload_ok(name));
create policy sp_project_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'sphere-project' and owner = auth.uid());

-- ---------------------------------------------------------------------
-- 4) Helpers
-- ---------------------------------------------------------------------
-- a preview (upload or link) is ready → same effect as Part 8 "Send preview"
create or replace function public.sp_files_mark_preview(p_job uuid, p_label text, p_note text, p_by uuid, p_version int)
returns boolean language plpgsql security definer set search_path = public as $$
declare j record; w record; grace_end timestamptz; first boolean; on_time boolean;
begin
  select * into j from public.sp_jobs where id = p_job;
  perform public.sp_work_start(p_job, false);
  select * into w from public.sp_project_work where job_id = p_job for update;
  grace_end := w.due_at + make_interval(hours => w.grace_hours);
  first := w.preview_at is null;
  on_time := now() <= grace_end;
  update public.sp_project_work
     set preview_link = p_label, preview_note = p_note, preview_at = now(), phase = 'preview',
         preview_on_time = case when first then on_time else preview_on_time end,
         pending_extension_hours = null, updated_at = now()
   where job_id = p_job and phase in ('active', 'preview');
  update public.sp_project_extensions set status = 'declined', decided_at = now() where job_id = p_job and status = 'pending';
  perform public.sp_work_event(p_job, p_by, case when first then 'preview' else 'preview_updated' end,
    'Preview v' || p_version || ' ready' || case when first and not on_time then ' (late)' else '' end, p_note);
  perform public.sp_work_notify(j.client_id, 'Preview v' || p_version || ' ready 👀',
    'Watch the watermarked preview of "' || public.sp_work_label(p_job) || '" inside Sphere.');
  return on_time;
end $$;
revoke all on function public.sp_files_mark_preview(uuid, text, text, uuid, int) from public, anon, authenticated;

-- who may add what to a project, and when
create or replace function public.sp_files_check(p_job uuid, p_kind text)
returns public.sp_jobs language plpgsql stable security definer set search_path = public as $$
declare j record;
begin
  select * into j from public.sp_jobs where id = p_job;
  if j.id is null then raise exception 'Project not found.'; end if;
  if p_kind = 'client_file' then
    if auth.uid() is distinct from j.client_id then raise exception 'Only the client of this project can add files here.'; end if;
    if j.status in ('closed', 'refunded') then raise exception 'This project is finished.'; end if;
  elsif p_kind = 'preview' then
    if auth.uid() is distinct from j.assigned_editor then raise exception 'Only the editor of this project can send a preview.'; end if;
    if j.status is distinct from 'in-progress' then raise exception 'Previews can be sent while the project is in progress.'; end if;
  else
    raise exception 'Unknown file type.';
  end if;
  return j;
end $$;

-- ---------------------------------------------------------------------
-- 5) Actions
-- ---------------------------------------------------------------------
-- reserve an upload → returns the storage path to upload to
create or replace function public.sp_files_begin(p_job uuid, p_kind text, p_name text, p_mime text, p_size bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  j record; fid uuid := gen_random_uuid(); ext text; path text; ver int;
  max_bytes bigint := public.sp_setting_int('file_max_mb', 50)::bigint * 1048576;
  nm text := left(regexp_replace(coalesce(p_name, 'file'), '[^A-Za-z0-9 ._()-]', '_', 'g'), 120);
begin
  j := public.sp_files_check(p_job, p_kind);
  if coalesce(p_size, 0) <= 0 then raise exception 'The file is empty.'; end if;
  if p_size > least(max_bytes, 52428800) then
    raise exception 'This file is bigger than % MB. Share it as a Google Drive / Dropbox / WeTransfer link instead.', least(max_bytes, 52428800) / 1048576;
  end if;
  if p_kind = 'preview' and coalesce(p_mime, '') !~* '^video/' then raise exception 'The preview must be a video.'; end if;
  if (select count(*) from public.sp_project_files where job_id = p_job and status = 'uploading' and uploaded_by = auth.uid()
        and created_at > now() - interval '6 hours') >= 10 then
    raise exception 'Too many uploads at once. Wait for the current ones to finish.';
  end if;
  ext := lower(coalesce(nullif(substring(nm from '\.([A-Za-z0-9]{1,5})$'), ''), case when p_kind = 'preview' then 'webm' else 'bin' end));
  path := p_job::text || '/' || case when p_kind = 'preview' then 'preview' else 'client' end || '/' || fid::text || '.' || ext;
  if p_kind = 'preview' then
    select coalesce(max(version), 0) + 1 into ver from public.sp_project_files where job_id = p_job and kind = 'preview';
  end if;
  insert into public.sp_project_files (id, job_id, uploaded_by, kind, source, storage_path, file_name, mime, size_bytes, version, status)
  values (fid, p_job, auth.uid(), p_kind, 'upload', path, nm, left(p_mime, 80), p_size, ver, 'uploading');
  return jsonb_build_object('id', fid, 'path', path, 'bucket', 'sphere-project', 'version', ver);
end $$;

-- upload finished (or failed)
create or replace function public.sp_files_finish(p_id uuid, p_ok boolean, p_duration numeric, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare f record; obj record; j record; on_time boolean; v_note text;
begin
  select * into f from public.sp_project_files where id = p_id for update;
  if f.id is null or f.uploaded_by is distinct from auth.uid() then raise exception 'Not your upload.'; end if;
  if f.status <> 'uploading' then return jsonb_build_object('status', f.status); end if;
  if not p_ok then
    update public.sp_project_files set status = 'failed', updated_at = now() where id = f.id;
    return jsonb_build_object('status', 'failed');
  end if;
  select * into obj from storage.objects where bucket_id = 'sphere-project' and name = f.storage_path;
  if obj.name is null then raise exception 'The upload did not reach the server. Please try again.'; end if;
  v_note := nullif(left((select (public.sp_mod_mask(btrim(coalesce(p_note, '')))).masked), 500), '');
  update public.sp_project_files
     set status = 'ready', note = v_note, updated_at = now(),
         duration_sec = case when p_duration > 0 then p_duration end,
         size_bytes = coalesce(nullif(obj.metadata->>'size', '')::bigint, size_bytes)
   where id = f.id;
  select * into j from public.sp_jobs where id = f.job_id;
  if f.kind = 'preview' then
    on_time := public.sp_files_mark_preview(f.job_id, 'sphere-file:' || f.id, v_note, auth.uid(), f.version);
    return jsonb_build_object('status', 'ready', 'version', f.version, 'on_time', on_time);
  end if;
  perform public.sp_work_event(f.job_id, auth.uid(), 'file_added', 'Client added a file', f.file_name);
  perform public.sp_work_notify(j.assigned_editor, 'New project file 📎', 'The client added "' || f.file_name || '" to "' || public.sp_work_label(f.job_id) || '".');
  return jsonb_build_object('status', 'ready');
end $$;

-- a link for big files (client) or a long preview (editor)
create or replace function public.sp_files_add_link(p_job uuid, p_kind text, p_url text, p_name text, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; url text := btrim(coalesce(p_url, '')); v_nm text; v_note text; ver int; fid uuid; on_time boolean;
begin
  j := public.sp_files_check(p_job, p_kind);
  if url !~* '^https://\S+$' or char_length(url) > 500 then raise exception 'Paste the full link (it starts with https://).'; end if;
  if (select (public.sp_mod_mask(url)).hard) then
    raise exception 'Use a Google Drive, YouTube (unlisted), Dropbox, WeTransfer, OneDrive or Mega link.';
  end if;
  v_nm := nullif(left((select (public.sp_mod_mask(btrim(coalesce(p_name, '')))).masked), 120), '');
  v_note := nullif(left((select (public.sp_mod_mask(btrim(coalesce(p_note, '')))).masked), 500), '');
  if p_kind = 'preview' then
    select coalesce(max(version), 0) + 1 into ver from public.sp_project_files where job_id = p_job and kind = 'preview';
  end if;
  insert into public.sp_project_files (job_id, uploaded_by, kind, source, external_url, file_name, version, status, note)
  values (p_job, auth.uid(), p_kind, 'link', url, coalesce(v_nm, case when p_kind = 'preview' then 'Preview link' else 'Shared link' end), ver, 'ready', v_note)
  returning id into fid;
  if p_kind = 'preview' then
    on_time := public.sp_files_mark_preview(p_job, url, v_note, auth.uid(), ver);
    return jsonb_build_object('id', fid, 'version', ver, 'on_time', on_time);
  end if;
  perform public.sp_work_event(p_job, auth.uid(), 'file_added', 'Client shared a link', coalesce(v_nm, 'Shared link'));
  perform public.sp_work_notify(j.assigned_editor, 'New project files 📎', 'The client shared a link for "' || public.sp_work_label(p_job) || '".');
  return jsonb_build_object('id', fid);
end $$;

-- remove a file from the list (the app then deletes the stored object)
create or replace function public.sp_files_remove(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare f record;
begin
  select * into f from public.sp_project_files where id = p_id for update;
  if f.id is null then raise exception 'Not found.'; end if;
  if f.uploaded_by is distinct from auth.uid() and not public.sp_core_has_role('ADMIN') then raise exception 'Only the person who added this file can remove it.'; end if;
  if f.kind = 'preview' and f.status = 'ready' then raise exception 'Previews stay in the project history.'; end if;
  update public.sp_project_files set status = 'removed', updated_at = now() where id = f.id;
  perform public.sp_work_event(f.job_id, auth.uid(), 'file_removed', 'File removed', f.file_name);
  return jsonb_build_object('path', f.storage_path);
end $$;

revoke all on function public.sp_files_begin(uuid, text, text, text, bigint), public.sp_files_finish(uuid, boolean, numeric, text),
              public.sp_files_add_link(uuid, text, text, text, text), public.sp_files_remove(uuid), public.sp_files_check(uuid, text) from public, anon;
grant execute on function public.sp_files_begin(uuid, text, text, text, bigint), public.sp_files_finish(uuid, boolean, numeric, text),
              public.sp_files_add_link(uuid, text, text, text, text), public.sp_files_remove(uuid) to authenticated;

insert into public.sp_schema_versions (version, name)
values ('010', 'Project files + watermarked previews (private bucket, versions, links for big files)')
on conflict (version) do update set applied_at = now();

commit;

-- Done. You should see "Success. No rows returned".
