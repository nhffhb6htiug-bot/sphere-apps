-- STAGING ONLY: reviewed workflow tables and chat permissions. No external services.
alter table public.profiles add column suspended boolean not null default false;
create or replace function public.sp_core_whoami() returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',id,'role',role,'suspended',suspended) from public.profiles where id=auth.uid()
$$;
create table public.sp_chat_clears(user_id uuid not null references public.profiles(id) on delete cascade,other_id uuid not null references public.profiles(id) on delete cascade,cleared_at timestamptz not null default now(),primary key(user_id,other_id));
create table public.sp_project_work(job_id uuid primary key references public.sp_jobs(id),client_id uuid not null references public.profiles(id),editor_id uuid not null references public.profiles(id),phase text not null default 'active',started_at timestamptz not null default now(),hours integer not null default 24,due_at timestamptz not null default now()+interval '24 hours',original_due_at timestamptz not null default now()+interval '24 hours',grace_hours integer not null default 4,extended_hours integer not null default 0,pending_extension_hours integer,preview_link text,preview_note text,preview_at timestamptz,preview_approved_at timestamptz,preview_on_time boolean,is_late boolean not null default false,late_since timestamptz,completed_at timestamptz,updated_at timestamptz not null default now());
create table public.sp_project_files(id uuid primary key default gen_random_uuid(),job_id uuid not null references public.sp_jobs(id),uploaded_by uuid not null references public.profiles(id),kind text not null check(kind in ('preview','client_file')),source text not null check(source in ('upload','link')),storage_path text unique,external_url text,file_name text,mime text,size_bytes bigint,duration_sec numeric,version integer not null,status text not null default 'uploading',note text,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(job_id,kind,version));
create table public.sp_project_extensions(id uuid primary key default gen_random_uuid(),job_id uuid not null references public.sp_jobs(id),requested_by uuid not null references public.profiles(id),hours integer not null check(hours between 1 and 72),reason text,status text not null default 'pending',created_at timestamptz not null default now(),decided_at timestamptz,decided_by uuid);
create unique index staging_one_extension on public.sp_project_extensions(job_id) where status='pending';
create table public.sp_revisions(id uuid primary key default gen_random_uuid(),job_id uuid not null references public.sp_jobs(id),number integer not null,requested_by uuid not null references public.profiles(id),notes text not null,preview_version integer,is_paid boolean not null default false,fee numeric not null default 0,status text not null,old_due_at timestamptz,new_due_at timestamptz,delivered_version integer,created_at timestamptz not null default now(),opened_at timestamptz,delivered_at timestamptz,unique(job_id,number));
create unique index staging_one_revision on public.sp_revisions(job_id) where status in ('open','awaiting_payment');
create table public.sp_change_requests(id uuid primary key default gen_random_uuid(),job_id uuid not null references public.sp_jobs(id),requested_by uuid not null references public.profiles(id),details text not null,extra_price numeric not null check(extra_price>=0),extra_hours integer not null check(extra_hours between 0 and 72),link text,file_ids uuid[] not null default '{}',status text not null default 'pending',editor_note text,created_at timestamptz not null default now(),decided_at timestamptz,applied_at timestamptz);
create unique index staging_one_change on public.sp_change_requests(job_id) where status in ('pending','accepted_awaiting_payment');
create table public.sp_project_events(id bigint generated always as identity primary key,job_id uuid not null references public.sp_jobs(id),at timestamptz not null default now(),actor_id uuid,kind text not null,title text not null,details text);
create table public.sp_disputes(id uuid primary key default gen_random_uuid(),job_id uuid not null references public.sp_jobs(id),kind text not null default 'dispute',opened_by uuid not null references public.profiles(id),category text not null,details text not null,status text not null default 'open',decision_note text,decided_by uuid,decided_at timestamptz,created_at timestamptz not null default now());
create unique index staging_one_case on public.sp_disputes(job_id) where status='open';
create table public.sp_final_files(job_id uuid primary key references public.sp_jobs(id),preview_file_id uuid not null references public.sp_project_files(id),preview_version integer not null,final_link text not null,note text,submitted_by uuid not null references public.profiles(id),submitted_at timestamptz not null default now());
create table public.sp_refunds(id uuid primary key default gen_random_uuid(),job_id uuid not null references public.sp_jobs(id),dispute_id uuid references public.sp_disputes(id),amount numeric not null default 0 check(amount>=0),kind text not null default 'simulation',status text not null default 'disabled',reason text,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.sp_payments(id uuid primary key default gen_random_uuid(),job_id uuid not null references public.sp_jobs(id),client_id uuid not null,editor_id uuid,amount numeric not null default 0 check(amount>=0),currency text not null default 'INR',status text not null default 'disabled',provider text not null default 'simulation',created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.sp_extra_payments(id uuid primary key default gen_random_uuid(),job_id uuid not null references public.sp_jobs(id),client_id uuid not null,editor_id uuid,kind text not null,ref_id uuid,amount numeric not null default 0 check(amount>=0),status text not null default 'disabled',created_at timestamptz not null default now());
create table public.sp_settlements(job_id uuid primary key references public.sp_jobs(id),editor_id uuid not null,editor_base numeric not null default 0,bonus_awarded numeric not null default 0,late_deduction numeric not null default 0,net_adjustment numeric not null default 0,status text not null default 'simulation',computed_at timestamptz not null default now());
create table public.sp_project_ratings(id uuid primary key default gen_random_uuid(),job_id uuid not null unique references public.sp_jobs(id),editor_id uuid not null,client_id uuid not null,score integer not null check(score between -3 and 3),feedback text,created_at timestamptz not null default now());
create table public.sp_phone_verifications(user_id uuid primary key references public.profiles(id),created_at timestamptz not null default now());
create table public.sp_admin_audit(id bigint generated always as identity primary key,at timestamptz not null default now(),actor_id uuid,action text not null,target_type text,target_id text,job_id uuid,user_id uuid,old_status text,new_status text,reason text,details jsonb);
create table public.sp_editor_verification_outreach(editor_id uuid primary key references public.profiles(id),messaged_at timestamptz not null default now(),messaged_by uuid);
create table public.sp_detail_requests(id uuid primary key default gen_random_uuid(),editor_id uuid not null references public.profiles(id),note text,status text not null default 'pending',created_at timestamptz not null default now(),done_at timestamptz,done_by uuid);
create table public.sp_admin_hidden_jobs(job_id uuid primary key references public.sp_jobs(id),created_at timestamptz not null default now());
do $$ declare t text; begin
 foreach t in array array['sp_chat_clears','sp_project_work','sp_project_files','sp_project_extensions','sp_revisions','sp_change_requests','sp_project_events','sp_disputes','sp_final_files','sp_refunds','sp_payments','sp_extra_payments','sp_settlements','sp_project_ratings','sp_phone_verifications','sp_admin_audit','sp_editor_verification_outreach','sp_detail_requests','sp_admin_hidden_jobs'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on table public.%I from public,anon,authenticated',t);
 end loop;
end $$;
grant usage on schema sphere_staging_private to authenticated;
create function sphere_staging_private.active_user() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and not suspended)
$$;
create function sphere_staging_private.admin_user() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and role='ADMIN' and not suspended)
$$;
create function sphere_staging_private.party(p_job uuid) returns boolean language sql stable security definer set search_path='' as $$
 select sphere_staging_private.active_user() and exists(select 1 from public.sp_jobs j where j.id=p_job and auth.uid() in (j.client_id,j.assigned_editor))
$$;
create function sphere_staging_private.chat_allowed(peer uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and peer<>auth.uid() and sphere_staging_private.active_user()
 and exists(select 1 from public.profiles where id=peer and not suspended)
 and exists(select 1 from public.sp_jobs j where (j.client_id=auth.uid() and j.assigned_editor=peer) or (j.assigned_editor=auth.uid() and j.client_id=peer))
 and not exists(select 1 from public.sp_blocks b where (b.blocker_id=auth.uid() and b.blocked_id=peer) or (b.blocked_id=auth.uid() and b.blocker_id=peer))
$$;
revoke all on function sphere_staging_private.active_user(),sphere_staging_private.admin_user(),sphere_staging_private.party(uuid),sphere_staging_private.chat_allowed(uuid) from public,anon;
grant execute on function sphere_staging_private.active_user(),sphere_staging_private.admin_user(),sphere_staging_private.party(uuid),sphere_staging_private.chat_allowed(uuid) to authenticated;
do $$ declare t text; begin
 foreach t in array array['sp_project_work','sp_project_files','sp_project_extensions','sp_revisions','sp_change_requests','sp_project_events','sp_disputes','sp_refunds','sp_payments','sp_extra_payments','sp_settlements','sp_project_ratings'] loop
 execute format('grant select on public.%I to authenticated',t);
 execute format('create policy staging_party_read on public.%I for select to authenticated using(sphere_staging_private.party(job_id))',t);
 end loop;
end $$;
create policy staging_admin_dispute_read on public.sp_disputes for select to authenticated using(sphere_staging_private.admin_user());
create policy staging_admin_portfolio_read on public.sp_portfolio for select to authenticated using(sphere_staging_private.admin_user());
grant select,insert(user_id,other_id),update(cleared_at) on public.sp_chat_clears to authenticated;
create policy staging_clear_owner on public.sp_chat_clears for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid() and sphere_staging_private.active_user());
-- Keep existing messages readable by parties; prohibit new messages after block or suspension.
grant insert(id,sender_id,receiver_id,text,media_path,media_type,media_name,job_id,reply_to),update(delivered_at,read_at) on public.sp_messages to authenticated;
create policy staging_message_insert on public.sp_messages for insert to authenticated with check(sender_id=auth.uid() and sphere_staging_private.chat_allowed(receiver_id) and (job_id is null or sphere_staging_private.party(job_id)));
create policy staging_message_receipts on public.sp_messages for update to authenticated using(receiver_id=auth.uid() and sphere_staging_private.active_user()) with check(receiver_id=auth.uid() and sphere_staging_private.active_user());
create function sphere_staging_private.guard_message() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.sender_id is distinct from auth.uid() or not sphere_staging_private.chat_allowed(new.receiver_id) then raise exception 'chat not permitted'; end if;
 if new.job_id is not null and not exists(select 1 from public.sp_jobs j where j.id=new.job_id and ((j.client_id=new.sender_id and j.assigned_editor=new.receiver_id) or (j.assigned_editor=new.sender_id and j.client_id=new.receiver_id))) then raise exception 'wrong project'; end if;
 if new.reply_to is not null and not exists(select 1 from public.sp_messages m where m.id=new.reply_to and ((m.sender_id=new.sender_id and m.receiver_id=new.receiver_id) or (m.sender_id=new.receiver_id and m.receiver_id=new.sender_id))) then raise exception 'invalid reply'; end if;
 -- Conservative staging filter; not full production moderation. Reject contact/link text, no real external contact.
 if new.text ~* '(https?://|www\.|@|[0-9][0-9 .()+-]{6,}[0-9])' then raise exception 'staging contact filter'; end if;
 if new.media_path is not null then
  if new.media_path not like (new.sender_id::text||'/chat/%') or not exists(select 1 from storage.objects o where o.bucket_id='sphere-chat' and o.name=new.media_path) then raise exception 'media missing or wrong owner'; end if;
 end if;
 if trim(new.text)='' and new.media_path is null then raise exception 'empty message'; end if;
 new.mod_status='approved';new.mod_reason=null;return new;
end $$;
revoke all on function sphere_staging_private.guard_message() from public,anon,authenticated;
create trigger staging_message_guard before insert on public.sp_messages for each row execute function sphere_staging_private.guard_message();
create function sphere_staging_private.seen(peer uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select case when sphere_staging_private.chat_allowed(peer) and exists(select 1 from public.sp_presence where user_id=auth.uid() and show_last_seen) and exists(select 1 from public.sp_messages m where (m.sender_id=auth.uid() and m.receiver_id=peer) or (m.receiver_id=auth.uid() and m.sender_id=peer))
 then coalesce((select jsonb_build_object('visible',show_last_seen,'last_seen_at',case when show_last_seen then last_seen_at end) from public.sp_presence where user_id=peer),jsonb_build_object('visible',false,'last_seen_at',null)) else jsonb_build_object('visible',false,'last_seen_at',null) end
$$;
revoke all on function sphere_staging_private.seen(uuid) from public,anon;
grant execute on function sphere_staging_private.seen(uuid) to authenticated;
create or replace function public.sp_last_seen(p_other uuid) returns jsonb language sql stable security invoker set search_path='' as $$ select sphere_staging_private.seen(p_other) $$;
create policy staging_chat_peer_media on storage.objects for select to authenticated using(bucket_id='sphere-chat' and exists(select 1 from public.sp_messages m where m.media_path=name and auth.uid() in (m.sender_id,m.receiver_id) and sphere_staging_private.chat_allowed(case when m.sender_id=auth.uid() then m.receiver_id else m.sender_id end)));
create policy staging_proof_admin on storage.objects for select to authenticated using(bucket_id='sphere-editor-proof' and sphere_staging_private.admin_user());
alter publication supabase_realtime add table public.sp_messages,public.sp_notifications;
