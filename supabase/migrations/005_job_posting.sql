-- =====================================================================
-- SPHERE — PART 5: JOB CREATION + AI REQUIREMENT COLLECTION
-- Run in: Supabase → SQL Editor → + → paste → Run.  Safe to run again.
-- Needs 002 first. Adds columns + one table; deletes nothing.
--
--   sp_jobs        + title, video_length, video_format, style_notes,
--                    reference_links, revisions_expected, ai_assisted
--   sp_job_drafts  — a client's unfinished job posts (Draft). Only that client
--                    can see them; editors never do. Posting a draft creates a
--                    normal job with status "open".
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) Structured requirements on jobs
-- ---------------------------------------------------------------------
alter table public.sp_jobs add column if not exists title              text;
alter table public.sp_jobs add column if not exists video_length       text;
alter table public.sp_jobs add column if not exists video_format       text;
alter table public.sp_jobs add column if not exists style_notes        text;
alter table public.sp_jobs add column if not exists reference_links    text;
alter table public.sp_jobs add column if not exists revisions_expected int;
alter table public.sp_jobs add column if not exists ai_assisted        boolean not null default false;

alter table public.sp_jobs drop constraint if exists sp_job_title_chk;
alter table public.sp_jobs add  constraint sp_job_title_chk  check (title is null or char_length(title) <= 80);
alter table public.sp_jobs drop constraint if exists sp_job_len_chk;
alter table public.sp_jobs add  constraint sp_job_len_chk    check (video_length is null or char_length(video_length) <= 40);
alter table public.sp_jobs drop constraint if exists sp_job_format_chk;
alter table public.sp_jobs add  constraint sp_job_format_chk check (video_format is null or char_length(video_format) <= 30);
alter table public.sp_jobs drop constraint if exists sp_job_style_chk;
alter table public.sp_jobs add  constraint sp_job_style_chk  check (style_notes is null or char_length(style_notes) <= 1500);
alter table public.sp_jobs drop constraint if exists sp_job_refs_chk;
alter table public.sp_jobs add  constraint sp_job_refs_chk   check (reference_links is null or char_length(reference_links) <= 1000);
alter table public.sp_jobs drop constraint if exists sp_job_revs_chk;
alter table public.sp_jobs add  constraint sp_job_revs_chk   check (revisions_expected is null or revisions_expected between 0 and 10);

-- ---------------------------------------------------------------------
-- 2) Drafts (private to the client)
-- ---------------------------------------------------------------------
create table if not exists public.sp_job_drafts (
  id         uuid primary key default gen_random_uuid(),
  client_id  uuid not null references auth.users(id) on delete cascade default auth.uid(),
  data       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists sp_job_drafts_client_idx on public.sp_job_drafts (client_id, updated_at desc);

alter table public.sp_job_drafts drop constraint if exists sp_job_drafts_size_chk;
alter table public.sp_job_drafts add  constraint sp_job_drafts_size_chk check (pg_column_size(data) <= 20000);

alter table public.sp_job_drafts enable row level security;
drop policy if exists sp_job_drafts_own on public.sp_job_drafts;
create policy sp_job_drafts_own on public.sp_job_drafts for all to authenticated
  using (client_id = auth.uid()) with check (client_id = auth.uid());
revoke all on public.sp_job_drafts from anon;
grant select, insert, update, delete on public.sp_job_drafts to authenticated;

create or replace function public.sp_job_drafts_touch()
returns trigger language plpgsql set search_path = public as $$
declare n int;
begin
  NEW.updated_at := now();
  if TG_OP = 'INSERT' then
    select count(*) into n from public.sp_job_drafts where client_id = NEW.client_id;
    if n >= 20 then raise exception 'You can keep up to 20 drafts. Post or delete an old draft first.'; end if;
  end if;
  return NEW;
end $$;
drop trigger if exists sp_job_drafts_touch on public.sp_job_drafts;
create trigger sp_job_drafts_touch before insert or update on public.sp_job_drafts
  for each row execute function public.sp_job_drafts_touch();

-- ---------------------------------------------------------------------
-- 3a) Contact check: "Instagram reel" / "Insta" are normal words in video jobs,
--     so only "insta id", "insta pe", "DM me" etc. count as warning words now.
--     (Same checker as 001, only the warning-word list changed.)
-- ---------------------------------------------------------------------
do $do$
begin
  if exists (select 1 from pg_proc where proname = 'sp_mod_re') then
    execute $fn$
create or replace function public.sp_mod_mask(p_text text, p_min int default 10, out masked text, out hard boolean, out soft boolean)
language plpgsql immutable set search_path = public as $$
declare
  t text := p_text;
  tok  text := public.sp_mod_re('tok');
  tok6 text := public.sp_mod_re('tok6');
  sep  text := public.sp_mod_re('sep');
  phone_re text;
  email_re  text := '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}';
  email2_re text := '[A-Za-z0-9._-]+([[:space:]]*@[[:space:]]*|[[:space:]]*(\[|\()[[:space:]]*at[[:space:]]*(\]|\))[[:space:]]*|[[:space:]]+at[[:space:]]+)[A-Za-z0-9-]+([[:space:]]*\.[[:space:]]*|[[:space:]]*(\[|\()[[:space:]]*dot[[:space:]]*(\]|\))[[:space:]]*|[[:space:]]+dot[[:space:]]+)(com|in|net|org|co)\M';
  link_re   text := '((https?://|www\.)[^[:space:]]+|([A-Za-z0-9-]+\.)+(com|in|net|org|me|io|co|xyz|app|link|site|online|store|info|ly|ee|gg|tv|page|dev)\M(/[^[:space:]]*)?)';
  allow_re  text := '^(https?://)?(www\.|m\.)?(drive\.google\.com|docs\.google\.com|youtube\.com|youtu\.be|wetransfer\.com|we\.tl|dropbox\.com|mega\.nz|1drv\.ms|onedrive\.live\.com|sphere-live\.onrender\.com)([/?#].*)?$';
  handle_re text := '(^|[^A-Za-z0-9_.@])@[A-Za-z0-9_.]*[A-Za-z][A-Za-z0-9_.]{1,29}';
  soft_re   text := '\m(whats ?app|watsapp|whatsap|wtsp|insta id|insta pe|insta par|insta handle|instagram id|instagram pe|instagram par|instagram handle|dm me|dm karo|telegram|snapchat|g ?pay|google pay|paytm|phone ?pe|call me|call kar|call karo|call karna|number do|number de|number bhej|number bhejo|mera number|mera no|apna number|apna no|contact number|personal number|direct pay|direct payment|outside the app|bahar deal)\M';
  soft_hi   text := '(व्हाट्सएप|व्हाट्सऐप|मेरा नंबर|अपना नंबर)';
  keep text[] := '{}';
  m text;
  i int;
  support text[] := array['7739363798','9468289750','8708712986'];
begin
  hard := false; soft := false;
  if t is null or btrim(t) = '' then masked := t; return; end if;
  phone_re := '(?:(?:\+|00)?91' || sep || '|0' || sep || ')?' || tok6 || '(?:' || sep || tok || '){' || (greatest(p_min, 2) - 1) || '}';

  -- Syahi Films support numbers are always allowed
  for i in 1 .. array_length(support, 1) loop
    t := replace(t, support[i], '‹S' || i || '›');
  end loop;

  -- emails
  if t ~* email_re then t := regexp_replace(t, email_re, '📵', 'gi'); hard := true; end if;
  if t ~* email2_re then t := regexp_replace(t, email2_re, '📵', 'gi'); hard := true; end if;

  -- links: footage / preview sites stay, everything else hidden
  for m in select (regexp_matches(t, link_re, 'gi'))[1] loop
    if m ~* allow_re then
      keep := keep || m;
      t := replace(t, m, '‹L' || array_length(keep, 1) || '›');
    else
      t := replace(t, m, '📵');
      hard := true;
    end if;
  end loop;

  -- @instagram style IDs
  if t ~ handle_re then t := regexp_replace(t, handle_re, '\1📵', 'g'); hard := true; end if;

  -- phone numbers (10 digits starting 6-9, any spacing, digits or words)
  if t ~* phone_re then t := regexp_replace(t, phone_re, '📵', 'gi'); hard := true; end if;

  -- put back allowed links and support numbers
  if array_length(keep, 1) is not null then
    for i in reverse array_length(keep, 1) .. 1 loop
      t := replace(t, '‹L' || i || '›', keep[i]);
    end loop;
  end if;
  for i in 1 .. array_length(support, 1) loop
    t := replace(t, '‹S' || i || '›', support[i]);
  end loop;

  -- warning words (message goes through, strike is recorded)
  if not hard and (t ~* soft_re or t ~ soft_hi) then soft := true; end if;

  masked := t;
end $$;
$fn$;
  end if;
end $do$;

-- ---------------------------------------------------------------------
-- 3b) Contact protection also checks the new text fields (if installed)
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_proc where proname = 'sp_mod_guard') then
    execute 'drop trigger if exists zz_sp_mod_guard on public.sp_jobs';
    execute 'create trigger zz_sp_mod_guard before insert or update of description, title, style_notes, reference_links on public.sp_jobs
             for each row execute function public.sp_mod_guard(''description,title,style_notes,reference_links'', ''job'', ''client_id'')';
  end if;
end $$;

insert into public.sp_schema_versions (version, name)
values ('005', 'Job posting (structured requirements, drafts, AI-assisted)')
on conflict (version) do update set applied_at = now();

commit;

-- Done. You should see "Success. No rows returned".
