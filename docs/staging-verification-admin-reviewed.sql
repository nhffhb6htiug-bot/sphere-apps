-- STAGING ONLY: verification offers and admin status RPCs, never real fees.
create table public.sp_editor_offer_slots(editor_id uuid primary key references public.profiles(id) on delete cascade,slot integer unique not null check(slot between 1 and 50),created_at timestamptz not null default now());
create table public.sp_editor_offer_state(singleton boolean primary key default true check(singleton),slots_claimed integer not null default 0 check(slots_claimed between 0 and 50));
insert into public.sp_editor_offer_state(singleton) values(true);
alter table public.sp_editor_offer_slots enable row level security;
alter table public.sp_editor_offer_state enable row level security;
revoke all on public.sp_editor_offer_slots,public.sp_editor_offer_state from public,anon,authenticated;
create function sphere_staging_private.assign_offer() returns trigger language plpgsql security definer set search_path='' as $$
declare slot_no integer;
begin
 if new.role='EDITOR' and not exists(select 1 from public.sp_editor_offer_slots where editor_id=new.id) then
  update public.sp_editor_offer_state set slots_claimed=slots_claimed+1 where singleton and slots_claimed<50 returning slots_claimed into slot_no;
  if found then insert into public.sp_editor_offer_slots(editor_id,slot) values(new.id,slot_no);end if;
 end if;return new;
end $$;
revoke all on function sphere_staging_private.assign_offer() from public,anon,authenticated;
create trigger staging_editor_offer after insert or update of role on public.profiles for each row execute function sphere_staging_private.assign_offer();
create function sphere_staging_private.verification(a text,val text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();p public.profiles%rowtype;r integer;cnt integer;
begin
 if u is null or not sphere_staging_private.active_user() then raise exception 'access denied';end if;
 select * into p from public.profiles where id=u for update;
 select slot into r from public.sp_editor_offer_slots where editor_id=u;
 select slots_claimed into cnt from public.sp_editor_offer_state where singleton;
 if a='offer' then return jsonb_build_object('is_editor',p.role='EDITOR','editor_rank',r,'is_free',p.role='EDITOR' and r is not null,'show_banner',p.role='EDITOR' and cnt<50,'limit',50,'claimed',cnt,'remaining',50-cnt);end if;
 if p.role<>'EDITOR' or p.is_verified or p.verification_status<>'pending' then raise exception 'pending editor application required';end if;
 if a='video' then
  if val is null or length(val)>500 or val !~ '^https://(www\.|m\.)?(youtube\.com|youtu\.be|drive\.google\.com)/[^[:space:]]+$' then raise exception 'unsupported proof link';end if;
  update public.profiles set proof_video_url=val,proof_video_at=now() where id=u;
 elsif a='screenshot' then
  if r is null or val is null or val !~ ('^'||u::text||'/[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$') or not exists(select 1 from storage.objects o where o.bucket_id='sphere-editor-proof' and o.name=val) then raise exception 'invalid screenshot';end if;
  update public.profiles set proof_screenshot_path=val,proof_screenshot_at=now() where id=u;
 elsif a='claim' then
  if r is null then return jsonb_build_object('free',false);end if;
  if coalesce(p.proof_video_url,'')='' or coalesce(p.proof_screenshot_path,'')='' then return jsonb_build_object('free',true,'ready',false,'rank',r);end if;
  update public.profiles set verification_fee_status='waived' where id=u;
  return jsonb_build_object('free',true,'ready',true,'rank',r);
 else raise exception 'unsupported verification action';end if;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function sphere_staging_private.verification(text,text) from public,anon;
grant execute on function sphere_staging_private.verification(text,text) to authenticated;
create function public.sp_editor_offer_status() returns jsonb language sql security invoker set search_path='' as $$ select sphere_staging_private.verification('offer',null) $$;
revoke all on function public.sp_editor_offer_status() from public,anon;
grant execute on function public.sp_editor_offer_status() to authenticated;
create function public.sp_submit_proof_video(p_url text) returns jsonb language sql security invoker set search_path='' as $$ select sphere_staging_private.verification('video',p_url) $$;
revoke all on function public.sp_submit_proof_video(text) from public,anon;
grant execute on function public.sp_submit_proof_video(text) to authenticated;
create function public.sp_submit_proof_screenshot(p_path text) returns jsonb language sql security invoker set search_path='' as $$ select sphere_staging_private.verification('screenshot',p_path) $$;
revoke all on function public.sp_submit_proof_screenshot(text) from public,anon;
grant execute on function public.sp_submit_proof_screenshot(text) to authenticated;
create function public.sp_claim_free_verification() returns jsonb language sql security invoker set search_path='' as $$ select sphere_staging_private.verification('claim',null) $$;
revoke all on function public.sp_claim_free_verification() from public,anon;
grant execute on function public.sp_claim_free_verification() to authenticated;
-- Admin reads return explicit field projections, not phone/email/code or final links.
create function sphere_staging_private.admin_read(a text,x jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r jsonb; uid uuid:=auth.uid(); target uuid;
begin
 if uid is null or not sphere_staging_private.admin_user() then raise exception 'admin access denied' using errcode='42501';end if;
 case a
 when 'overview' then
  return jsonb_build_object('users',(select count(*) from public.profiles),'clients',(select count(*) from public.profiles where role='CLIENT'),'editors',(select count(*) from public.profiles where role='EDITOR'),'verified_editors',(select count(*) from public.profiles where is_verified and role='EDITOR'),'active_projects',(select count(*) from public.sp_jobs where status='in-progress'),'completed',(select count(*) from public.sp_jobs where status in ('approved','closed')),'pending_payments',0,'pending_refunds',0,'pending',jsonb_build_object('verifications',(select count(*) from public.profiles where role='EDITOR' and verification_status='pending'),'disputes',(select count(*) from public.sp_disputes where status='open'),'held_messages',0,'payouts',0,'refunds',0));
 when 'profiles' then
  select jsonb_agg(to_jsonb(q)) into r from (select id,role,full_name,created_at,bio,skills,portfolio_url,sample_video_url,is_verified,verification_status,verification_fee_status,proof_video_url from public.profiles where (x->>'role' is null or x->>'role'='all' or role=x->>'role') and (x->>'verified' is null or is_verified=(x->>'verified')::boolean) order by created_at limit 1000) q;
 when 'users' then
  select jsonb_agg(to_jsonb(q)) into r from (select p.id,p.full_name as name,p.role,p.is_verified as verified,p.suspended,0 as strikes,(select count(*) from public.sp_jobs j where p.id in (j.client_id,j.assigned_editor)) as projects from public.profiles p where (x->>'role' is null or x->>'role'='all' or p.role=x->>'role') and (x->>'search' is null or p.full_name ilike '%'||left(x->>'search',100)||'%') order by p.created_at desc limit least(greatest(coalesce((x->>'limit')::int,200),1),200)) q;
 when 'verifications' then
  select jsonb_agg(to_jsonb(q)) into r from (select p.id,p.full_name as name,p.verification_status as status,p.verification_fee_status as fee_status,p.proof_video_url as proof_video,p.proof_screenshot_path as proof_screenshot,p.categories,p.verification_note as note,s.slot as free_offer_rank from public.profiles p left join public.sp_editor_offer_slots s on s.editor_id=p.id where p.role='EDITOR' and not p.is_verified and p.verification_status in ('pending','rejected') order by p.created_at desc limit 1000) q;
 when 'verified' then
  select jsonb_agg(to_jsonb(q)) into r from (select id,full_name as name,verified_at,verification_status as status from public.profiles where role='EDITOR' and is_verified and (x->'ids' is null or x->'ids'='null'::jsonb or id::text in (select jsonb_array_elements_text(x->'ids'))) order by verified_at desc limit 1000) q;
 when 'outreach' then
  select jsonb_agg(jsonb_build_object('id',editor_id,'messaged_at',messaged_at)) into r from public.sp_editor_verification_outreach;
 when 'requests' then
  select jsonb_agg(to_jsonb(q)) into r from (select d.id,p.full_name as name,d.created_at as at from public.sp_detail_requests d join public.profiles p on p.id=d.editor_id where d.status='pending' order by d.created_at limit 100) q;
 when 'projects' then
  select jsonb_agg(to_jsonb(q)) into r from (select j.id,j.title,j.status,j.admin_flag as health,c.full_name as client_name,e.full_name as editor_name,j.budget as amount,j.payment_status from public.sp_jobs j join public.profiles c on c.id=j.client_id left join public.profiles e on e.id=j.assigned_editor where not exists(select 1 from public.sp_admin_hidden_jobs h where h.job_id=j.id) and (x->>'filter'='all' or j.admin_flag=x->>'filter') and (x->>'search' is null or coalesce(j.title,'') ilike '%'||left(x->>'search',100)||'%') order by j.created_at desc limit least(greatest(coalesce((x->>'limit')::int,60),1),100) offset greatest(coalesce((x->>'offset')::int,0),0)) q;
 when 'hidden' then
  select jsonb_agg(to_jsonb(q)) into r from (select j.id,j.title from public.sp_jobs j join public.sp_admin_hidden_jobs h on h.job_id=j.id limit 100) q;
 when 'metrics' then
  select jsonb_agg(to_jsonb(q)) into r from (select j.id as job_id,(select count(*) from public.sp_applications a where a.job_id=j.id) bids,(select count(*) from public.sp_messages m where m.job_id=j.id) messages,(select count(*) from public.sp_project_files f where f.job_id=j.id) files,(select count(*) from public.sp_revisions v where v.job_id=j.id) revisions,(select count(*) from public.sp_disputes d where d.job_id=j.id) disputes from public.sp_jobs j where j.id::text in(select jsonb_array_elements_text(coalesce(x->'jobs','[]'))) limit 100) q;
 when 'user_detail' then
  target=(x->>'id')::uuid;
  return jsonb_build_object('profile',(select jsonb_build_object('name',full_name,'role',role,'verified',is_verified,'verification_status',verification_status) from public.profiles where id=target),'projects',coalesce((select jsonb_agg(jsonb_build_object('id',id)) from public.sp_jobs where target in (client_id,assigned_editor)),'[]'),'flags',jsonb_build_object('strike_count',0));
 when 'project_detail' then
  target=(x->>'id')::uuid;
  return jsonb_build_object('job',(select jsonb_build_object('status',status,'review_state',review_state,'admin_flag',admin_flag,'admin_note',admin_note) from public.sp_jobs where id=target),'extensions',coalesce((select jsonb_agg(jsonb_build_object('id',id)) from public.sp_project_extensions where job_id=target),'[]'),'disputes',coalesce((select jsonb_agg(jsonb_build_object('id',id)) from public.sp_disputes where job_id=target),'[]'),'refunds',coalesce((select jsonb_agg(jsonb_build_object('id',id)) from public.sp_refunds where job_id=target),'[]'));
 when 'payments' then
  return jsonb_build_object('by_status',jsonb_build_object('paid',0,'pending',0,'failed',0,'refunded',0),'totals',jsonb_build_object('base',0,'bonus',0,'deductions',0,'sphere',0),'payments','[]'::jsonb,'manual_payouts','[]'::jsonb,'payout_items','[]'::jsonb,'refunds','[]'::jsonb,'settlements','[]'::jsonb,'simulation_only',true);
 when 'moderation' then
  return jsonb_build_object('hidden','[]'::jsonb,'reviewed','[]'::jsonb,'flagged_users',coalesce((select jsonb_agg(jsonb_build_object('name',full_name,'role',role,'strikes',0,'suspended',suspended)) from public.profiles where suspended),'[]'));
 when 'audit' then
  select jsonb_agg(to_jsonb(q)) into r from (select a.action,a.at,p.full_name as "by",a.old_status as old,a.new_status as new,a.reason from public.sp_admin_audit a left join public.profiles p on p.id=a.actor_id where x->>'action' is null or a.action=x->>'action' order by a.at desc limit least(greatest(coalesce((x->>'limit')::int,150),1),150)) q;
 else raise exception 'unsupported admin action';end case;
 return coalesce(r,'[]'::jsonb);
end $$;
revoke all on function sphere_staging_private.admin_read(text,jsonb) from public,anon;
grant execute on function sphere_staging_private.admin_read(text,jsonb) to authenticated;
create function public.sp_admin_overview() returns jsonb language sql stable security invoker set search_path='' as $$ select sphere_staging_private.admin_read('overview','{}'::jsonb) $$;
revoke all on function public.sp_admin_overview() from public,anon;
grant execute on function public.sp_admin_overview() to authenticated;
create function public.sp_admin_profiles(p_role text,p_verified boolean) returns jsonb language sql stable security invoker set search_path='' as $$ select sphere_staging_private.admin_read('profiles',jsonb_build_object('role',p_role,'verified',p_verified)) $$;
revoke all on function public.sp_admin_profiles(text,boolean) from public,anon;
grant execute on function public.sp_admin_profiles(text,boolean) to authenticated;
create function public.sp_admin_users(p_search text,p_role text,p_limit integer) returns jsonb language sql stable security invoker set search_path='' as $$ select sphere_staging_private.admin_read('users',jsonb_build_object('search',p_search,'role',p_role,'limit',p_limit)) $$;
revoke all on function public.sp_admin_users(text,text,integer) from public,anon;
grant execute on function public.sp_admin_users(text,text,integer) to authenticated;
create function public.sp_admin_verifications() returns jsonb language sql stable security invoker set search_path='' as $$ select sphere_staging_private.admin_read('verifications','{}'::jsonb) $$;
revoke all on function public.sp_admin_verifications() from public,anon;
grant execute on function public.sp_admin_verifications() to authenticated;
create function public.sp_admin_editor_review(p_ids uuid[]) returns jsonb language sql stable security invoker set search_path='' as $$ select sphere_staging_private.admin_read('verified',jsonb_build_object('ids',p_ids)) $$;
revoke all on function public.sp_admin_editor_review(uuid[]) from public,anon;
grant execute on function public.sp_admin_editor_review(uuid[]) to authenticated;
create function public.sp_admin_editor_outreach_list() returns jsonb language sql stable security invoker set search_path='' as $$ select sphere_staging_private.admin_read('outreach','{}'::jsonb) $$;
revoke all on function public.sp_admin_editor_outreach_list() from public,anon;
grant execute on function public.sp_admin_editor_outreach_list() to authenticated;
create function public.sp_admin_detail_requests() returns jsonb language sql stable security invoker set search_path='' as $$ select sphere_staging_private.admin_read('requests','{}'::jsonb) $$;
revoke all on function public.sp_admin_detail_requests() from public,anon;
grant execute on function public.sp_admin_detail_requests() to authenticated;
create function public.sp_admin_projects(p_filter text,p_search text,p_limit integer,p_offset integer) returns jsonb language sql stable security invoker set search_path='' as $$ select sphere_staging_private.admin_read('projects',jsonb_build_object('filter',p_filter,'search',p_search,'limit',p_limit,'offset',p_offset)) $$;
revoke all on function public.sp_admin_projects(text,text,integer,integer) from public,anon;
grant execute on function public.sp_admin_projects(text,text,integer,integer) to authenticated;
create function public.sp_admin_hidden_projects() returns jsonb language sql stable security invoker set search_path='' as $$ select sphere_staging_private.admin_read('hidden','{}'::jsonb) $$;
revoke all on function public.sp_admin_hidden_projects() from public,anon;
grant execute on function public.sp_admin_hidden_projects() to authenticated;
create function public.sp_admin_project_metrics(p_jobs uuid[]) returns jsonb language sql stable security invoker set search_path='' as $$ select sphere_staging_private.admin_read('metrics',jsonb_build_object('jobs',p_jobs)) $$;
revoke all on function public.sp_admin_project_metrics(uuid[]) from public,anon;
grant execute on function public.sp_admin_project_metrics(uuid[]) to authenticated;
create function public.sp_admin_user_detail(p_user uuid) returns jsonb language sql stable security invoker set search_path='' as $$ select sphere_staging_private.admin_read('user_detail',jsonb_build_object('id',p_user)) $$;
revoke all on function public.sp_admin_user_detail(uuid) from public,anon;
grant execute on function public.sp_admin_user_detail(uuid) to authenticated;
create function public.sp_admin_project_detail(p_job uuid) returns jsonb language sql stable security invoker set search_path='' as $$ select sphere_staging_private.admin_read('project_detail',jsonb_build_object('id',p_job)) $$;
revoke all on function public.sp_admin_project_detail(uuid) from public,anon;
grant execute on function public.sp_admin_project_detail(uuid) to authenticated;
create function public.sp_admin_payments() returns jsonb language sql stable security invoker set search_path='' as $$ select sphere_staging_private.admin_read('payments','{}'::jsonb) $$;
revoke all on function public.sp_admin_payments() from public,anon;
grant execute on function public.sp_admin_payments() to authenticated;
create function public.sp_admin_moderation() returns jsonb language sql stable security invoker set search_path='' as $$ select sphere_staging_private.admin_read('moderation','{}'::jsonb) $$;
revoke all on function public.sp_admin_moderation() from public,anon;
grant execute on function public.sp_admin_moderation() to authenticated;
create function public.sp_admin_audit_list(p_limit integer,p_action text) returns jsonb language sql stable security invoker set search_path='' as $$ select sphere_staging_private.admin_read('audit',jsonb_build_object('limit',p_limit,'action',p_action)) $$;
revoke all on function public.sp_admin_audit_list(integer,text) from public,anon;
grant execute on function public.sp_admin_audit_list(integer,text) to authenticated;
create function public.sp_admin_pin_status() returns boolean language plpgsql stable security invoker set search_path='' as $$
begin if not sphere_staging_private.admin_user() then raise exception 'admin access denied';end if;return false;end $$;
revoke all on function public.sp_admin_pin_status() from public,anon;
grant execute on function public.sp_admin_pin_status() to authenticated;
-- Deliberately no PIN unlock endpoint, payment operations, phone delivery or admin mutation.
