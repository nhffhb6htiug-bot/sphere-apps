-- STAGING FOUNDATION ONLY. Never run against production.
-- Hand-authored schema based on production column metadata; no data or secret copied.
create schema sphere_staging_private;
revoke all on schema sphere_staging_private from public,anon,authenticated;
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 role text not null check(role in ('CLIENT','EDITOR','ADMIN')),
 full_name text not null check(char_length(full_name) between 1 and 100),
 phone text not null default '', email text, skills text[] default '{}',categories text[] default '{}',
 experience_years integer check(experience_years between 0 and 50),price_range text,
 sample_video_url text,verification_code text,is_verified boolean not null default false,created_at timestamptz not null default now(),
 portfolio_url text,avatar_url text,verified_by uuid,verified_at timestamptz,verification_note text,
 languages text[] default '{}',bio text check(char_length(bio)<=300),
 availability text not null default 'available' check(availability in ('available','busy','away')),
 verification_status text default 'not_applied' check(verification_status in ('not_applied','pending','rejected','approved')),
 verification_fee_status text default 'unpaid',edit_device text check(edit_device in ('mobile','pc','both')),
 proof_video_url text,proof_video_at timestamptz,proof_screenshot_path text,proof_screenshot_at timestamptz,
 phone_verified_at timestamptz
);
create table public.sp_settings(key text primary key,value text not null,updated_at timestamptz not null default now(),updated_by uuid);
insert into public.sp_settings(key,value) values
 ('otp_login','0'),('wa_verify_required','0'),('wa_verify_number',''),
 ('platform_fee_percent','5'),('free_revisions','3'),('revision_fee','50'),
 ('revision_hours','24'),('late_fee_per_hour','10'),('final_review_hours','10'),
 ('bonus_early_hours','5'),('preview_max_minutes','10'),('file_max_mb','50');
create table public.sp_jobs(
 id uuid primary key default gen_random_uuid(),client_id uuid not null references profiles(id),
 category text not null,description text,budget numeric check(budget>=0),deadline date,files_link text,
 status text not null default 'open' check(status in ('open','negotiating','payment-pending','in-progress','delivered','approved','closed','refunded')),
 assigned_editor uuid references profiles(id),proposed_amount numeric,proposed_by uuid,locked_amount numeric,
 payment_status text default 'unpaid',delivery_link text,created_at timestamptz not null default now(),
 editor_amount numeric,platform_fee numeric,payout_status text,raw_files jsonb not null default '[]' check(jsonb_typeof(raw_files)='array'),
 language text,title text,video_length text,video_format text,style_notes text,reference_links text,revisions_expected integer,
 ai_assisted boolean not null default false,extra_requirements text,extra_amount numeric not null default 0,
 review_state text not null default '',final_submitted_at timestamptz,decision_due_at timestamptz,released_at timestamptz,
 admin_flag text not null default 'normal',admin_note text,audience text not null default 'all'
);
create table public.sp_job_drafts(id uuid primary key default gen_random_uuid(),client_id uuid not null references profiles(id) on delete cascade,data jsonb not null check(jsonb_typeof(data)='object'),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.sp_portfolio(id uuid primary key default gen_random_uuid(),editor_id uuid not null references profiles(id) on delete cascade,title text not null check(char_length(title) between 1 and 80),image_path text,video_url text,created_at timestamptz not null default now(),category text not null);
create table public.sp_ratings(id uuid primary key default gen_random_uuid(),editor_id uuid not null references profiles(id),stars integer not null check(stars between 1 and 5));
create table public.sp_blocks(blocker_id uuid not null references profiles(id) on delete cascade,blocked_id uuid not null references profiles(id) on delete cascade,created_at timestamptz not null default now(),primary key(blocker_id,blocked_id),check(blocker_id<>blocked_id));
create table public.sp_presence(user_id uuid primary key references profiles(id) on delete cascade,last_seen_at timestamptz,show_last_seen boolean not null default false);
create table public.sp_messages(id uuid primary key default gen_random_uuid(),sender_id uuid not null references profiles(id),receiver_id uuid not null references profiles(id),text text not null check(char_length(text)<=2000),created_at timestamptz not null default now(),delivered_at timestamptz,read_at timestamptz,media_path text,media_type text,media_name text,duration_sec integer,job_id uuid references sp_jobs(id),mod_status text default 'pending',mod_reason text,reply_to uuid references sp_messages(id),check(sender_id<>receiver_id));
create table public.sp_notifications(id uuid primary key default gen_random_uuid(),user_id uuid not null references profiles(id),title text not null,body text,is_read boolean not null default false,created_at timestamptz not null default now(),read_at timestamptz,category text,job_id uuid references sp_jobs(id),link jsonb,audience text not null default 'all',important boolean not null default false,sender_id uuid,dedupe_key text,push_status text not null default 'disabled',email_status text not null default 'disabled');
create table public.sp_reports(id uuid primary key default gen_random_uuid(),job_id uuid references sp_jobs(id),reporter_id uuid not null references profiles(id),against_id uuid references profiles(id),reason text not null,details text,status text not null default 'open',admin_note text,created_at timestamptz not null default now(),resolved_at timestamptz,chat_user_id uuid);
create table public.sp_applications(id uuid primary key default gen_random_uuid(),job_id uuid not null references sp_jobs(id),editor_id uuid not null references profiles(id),message text,bid_amount numeric,status text not null default 'pending',created_at timestamptz not null default now(),delivery_days integer,updated_at timestamptz,unique(job_id,editor_id));
create table public.sp_saved(user_id uuid not null references profiles(id) on delete cascade,editor_id uuid not null references profiles(id) on delete cascade,created_at timestamptz not null default now(),primary key(user_id,editor_id));
-- Safe directory projection. Physical table maintained by reviewed trigger, not a privileged view.
create table public.sp_public_profiles(id uuid primary key references profiles(id) on delete cascade,role text not null,full_name text not null,categories text[],languages text[],skills text[],experience_years integer,price_range text,sample_video_url text,portfolio_url text,is_verified boolean not null,avatar_url text,bio text,availability text,edit_device text);
do $$ declare t text; begin
 foreach t in array array['profiles','sp_settings','sp_jobs','sp_job_drafts','sp_portfolio','sp_ratings','sp_blocks','sp_presence','sp_messages','sp_notifications','sp_reports','sp_applications','sp_saved','sp_public_profiles'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on table public.%I from public,anon,authenticated',t);
 end loop;
end $$;
grant select on profiles to authenticated;
grant insert(id,role,full_name,phone,email) on profiles to authenticated;
grant update(full_name,phone,email,skills,categories,experience_years,price_range,sample_video_url,portfolio_url,avatar_url,languages,bio,availability,edit_device,verification_status) on profiles to authenticated;
create policy staging_profile_read on profiles for select to authenticated using(id=(select auth.uid()));
create policy staging_profile_insert on profiles for insert to authenticated with check(id=(select auth.uid()) and role in ('CLIENT','EDITOR') and not is_verified and verification_status='not_applied');
create policy staging_profile_update on profiles for update to authenticated using(id=(select auth.uid())) with check(id=(select auth.uid()));
create function sphere_staging_private.guard_profile() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if current_user in ('authenticated','anon') then
   if new.role<>old.role or new.is_verified<>old.is_verified then raise exception 'privileged field'; end if;
   if new.verification_status is distinct from old.verification_status and not (old.role='EDITOR' and not old.is_verified and old.verification_status in ('not_applied','rejected') and new.verification_status='pending') then raise exception 'invalid verification transition'; end if;
 end if; return new;
end $$;
revoke all on function sphere_staging_private.guard_profile() from public,anon,authenticated;
create trigger staging_profile_guard before update on profiles for each row execute function sphere_staging_private.guard_profile();
create function sphere_staging_private.sync_directory() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.role='EDITOR' and new.is_verified then
 insert into public.sp_public_profiles(id,role,full_name,categories,languages,skills,experience_years,price_range,sample_video_url,portfolio_url,is_verified,avatar_url,bio,availability,edit_device)
 values(new.id,new.role,new.full_name,new.categories,new.languages,new.skills,new.experience_years,new.price_range,new.sample_video_url,new.portfolio_url,new.is_verified,new.avatar_url,new.bio,new.availability,new.edit_device)
 on conflict(id) do update set full_name=excluded.full_name,categories=excluded.categories,languages=excluded.languages,skills=excluded.skills,experience_years=excluded.experience_years,price_range=excluded.price_range,sample_video_url=excluded.sample_video_url,portfolio_url=excluded.portfolio_url,is_verified=excluded.is_verified,avatar_url=excluded.avatar_url,bio=excluded.bio,availability=excluded.availability,edit_device=excluded.edit_device;
 else delete from public.sp_public_profiles where id=new.id; end if; return new;
end $$;
revoke all on function sphere_staging_private.sync_directory() from public,anon,authenticated;
create trigger staging_directory after insert or update on profiles for each row execute function sphere_staging_private.sync_directory();
grant select on sp_public_profiles,sp_ratings to authenticated;
create policy staging_directory_read on sp_public_profiles for select to authenticated using(true);
create policy staging_rating_read on sp_ratings for select to authenticated using(true);
grant select on sp_settings to anon,authenticated;
create policy staging_settings_read on sp_settings for select to anon,authenticated using(true);
grant select on sp_jobs to authenticated;
grant insert(id,client_id,category,description,budget,deadline,files_link,raw_files,language,title,video_length,video_format,style_notes,reference_links,revisions_expected,ai_assisted,audience,status,assigned_editor) on sp_jobs to authenticated;
create policy staging_job_read on sp_jobs for select to authenticated using(client_id=(select auth.uid()) or assigned_editor=(select auth.uid()));
create policy staging_job_insert on sp_jobs for insert to authenticated with check(client_id=(select auth.uid()) and exists(select 1 from profiles p where p.id=(select auth.uid()) and p.role='CLIENT') and ((status='open' and assigned_editor is null) or (status='negotiating' and assigned_editor in(select id from sp_public_profiles))) and payment_status='unpaid' and delivery_link is null);
grant select,insert,delete on sp_job_drafts to authenticated; grant update(data,updated_at) on sp_job_drafts to authenticated;
create policy staging_draft_owner on sp_job_drafts for all to authenticated using(client_id=(select auth.uid())) with check(client_id=(select auth.uid()) and exists(select 1 from profiles p where p.id=(select auth.uid()) and p.role='CLIENT'));
grant select,delete on sp_portfolio to authenticated; grant insert(id,editor_id,title,image_path,video_url,category) on sp_portfolio to authenticated;
create policy staging_portfolio_read on sp_portfolio for select to authenticated using(editor_id=(select auth.uid()) or editor_id in(select id from sp_public_profiles));
create policy staging_portfolio_insert on sp_portfolio for insert to authenticated with check(editor_id=(select auth.uid()) and exists(select 1 from profiles p where p.id=(select auth.uid()) and p.role='EDITOR') and (image_path is null or image_path like ((select auth.uid())::text||'/portfolio/%')) and (video_url is null or video_url like 'https://%'));
create policy staging_portfolio_delete on sp_portfolio for delete to authenticated using(editor_id=(select auth.uid()));
create function sphere_staging_private.portfolio_cap() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.editor_id is distinct from auth.uid() then raise exception 'owner mismatch'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.editor_id::text,0));
 if (select count(*) from public.sp_portfolio where editor_id=new.editor_id)>=12 then raise exception 'portfolio limit'; end if;
 return new;
end $$;
revoke all on function sphere_staging_private.portfolio_cap() from public,anon,authenticated;
create trigger staging_portfolio_cap before insert on sp_portfolio for each row execute function sphere_staging_private.portfolio_cap();
grant select,delete on sp_blocks to authenticated; grant insert(blocker_id,blocked_id) on sp_blocks to authenticated;
create policy staging_block_read on sp_blocks for select to authenticated using(blocker_id=(select auth.uid()) or blocked_id=(select auth.uid()));
create policy staging_block_insert on sp_blocks for insert to authenticated with check(blocker_id=(select auth.uid()));
create policy staging_block_delete on sp_blocks for delete to authenticated using(blocker_id=(select auth.uid()));
grant select on sp_presence to authenticated; grant insert(user_id,last_seen_at,show_last_seen),update(last_seen_at,show_last_seen) on sp_presence to authenticated;
create policy staging_presence_owner on sp_presence for all to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
grant select on sp_messages to authenticated;
create policy staging_message_read on sp_messages for select to authenticated using(sender_id=(select auth.uid()) or receiver_id=(select auth.uid()));
-- Message writes stay denied pending moderation and reply/party guard review.
grant select on sp_notifications to authenticated; grant update(is_read,read_at) on sp_notifications to authenticated;
create policy staging_notice_read on sp_notifications for select to authenticated using(user_id=(select auth.uid()));
create policy staging_notice_update on sp_notifications for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
grant select on sp_reports to authenticated;grant insert(job_id,reporter_id,against_id,reason,details,chat_user_id) on sp_reports to authenticated;
create policy staging_report_read on sp_reports for select to authenticated using(reporter_id=(select auth.uid()));
create policy staging_report_insert on sp_reports for insert to authenticated with check(reporter_id=(select auth.uid()));
grant select on sp_applications to authenticated;
create policy staging_bid_read on sp_applications for select to authenticated using(editor_id=(select auth.uid()) or job_id in(select id from sp_jobs where client_id=(select auth.uid())));
grant select,insert,delete on sp_saved to authenticated;
create policy staging_saved_owner on sp_saved for all to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create function public.sp_core_whoami() returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',id,'role',role,'suspended',false) from public.profiles where id=auth.uid()
$$;
create function public.sp_phone_verify_status() returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('required',false,'verified',false) where auth.uid() is not null
$$;
create function public.sp_seen_ping() returns void language sql security invoker set search_path='' as $$
 insert into public.sp_presence(user_id,last_seen_at) values(auth.uid(),now()) on conflict(user_id) do update set last_seen_at=excluded.last_seen_at
$$;
create function public.sp_my_show_last_seen() returns boolean language sql stable security invoker set search_path='' as $$
 select coalesce((select show_last_seen from public.sp_presence where user_id=auth.uid()),false)
$$;
create function public.sp_set_show_last_seen(p_show boolean) returns void language sql security invoker set search_path='' as $$
 insert into public.sp_presence(user_id,show_last_seen) values(auth.uid(),p_show) on conflict(user_id) do update set show_last_seen=excluded.show_last_seen
$$;
create function public.sp_last_seen(p_other uuid) returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('visible',false,'last_seen_at',null)
$$;
revoke all on function public.sp_core_whoami(),public.sp_phone_verify_status(),public.sp_seen_ping(),public.sp_my_show_last_seen(),public.sp_set_show_last_seen(boolean),public.sp_last_seen(uuid) from public,anon;
grant execute on function public.sp_core_whoami(),public.sp_phone_verify_status(),public.sp_seen_ping(),public.sp_my_show_last_seen(),public.sp_set_show_last_seen(boolean),public.sp_last_seen(uuid) to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('sphere-raw','sphere-raw',false,52428800,array['image/jpeg','image/png','image/webp','video/mp4','video/webm','video/quicktime']),
 ('sphere-chat','sphere-chat',false,52428800,array['image/jpeg','image/png','image/webp','video/mp4','video/webm','video/quicktime']),
 ('sphere-project','sphere-project',false,52428800,array['image/jpeg','image/png','image/webp','video/mp4','video/webm','video/quicktime']),
 ('sphere-editor-proof','sphere-editor-proof',false,10485760,array['image/jpeg','image/png','image/webp']),
 ('sphere-media','sphere-media',true,10485760,array['image/jpeg','image/png','image/webp']);
-- Owner-only upload/read for selected synthetic media. No project delivery bucket access yet.
create policy staging_storage_read on storage.objects for select to authenticated using(bucket_id in ('sphere-raw','sphere-chat','sphere-editor-proof','sphere-media') and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy staging_storage_insert on storage.objects for insert to authenticated with check(bucket_id in ('sphere-raw','sphere-chat','sphere-editor-proof','sphere-media') and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy staging_raw_delete on storage.objects for delete to authenticated using(bucket_id='sphere-raw' and (storage.foldername(name))[1]=(select auth.uid())::text);
