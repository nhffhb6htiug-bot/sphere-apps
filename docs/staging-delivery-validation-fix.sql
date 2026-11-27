create or replace function sphere_staging_private.delivery(a text,p_job uuid,x jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); j public.sp_jobs%rowtype; w public.sp_project_work%rowtype;
 f public.sp_project_files%rowtype; ex public.sp_project_extensions%rowtype;
 rv public.sp_revisions%rowtype; cr public.sp_change_requests%rowtype;
 v integer; h integer; k text; s text; p text; n text; mime text; sz bigint; fee numeric; target uuid; ids uuid[];
begin
 if u is null or not sphere_staging_private.active_user() then raise exception 'access denied'; end if;
 -- resolve targets using metadata only; authorization still checked after job lock.
 if a in ('finish','rev_cancel','cr_cancel','cr_answer') then
  target=(x->>'id')::uuid;
  if a='finish' then select job_id into p_job from public.sp_project_files where id=target;
  elsif a='rev_cancel' then select job_id into p_job from public.sp_revisions where id=target;
  else select job_id into p_job from public.sp_change_requests where id=target; end if;
 end if;
 select * into j from public.sp_jobs where id=p_job for update;
 if not found or (u<>j.client_id and u is distinct from j.assigned_editor) then raise exception 'project access denied'; end if;
 if a in ('begin','finish','preview','final','extension_request','cr_answer') and u is distinct from j.assigned_editor and not (a in ('begin','finish') and u=j.client_id) then raise exception 'editor only'; end if;
 if a in ('approve','revision','rev_cancel','cr_create','cr_cancel','extension_answer','extension_give','dispute','rating') and u<>j.client_id then raise exception 'client only'; end if;
 if a='rating' then
  if j.status not in ('approved','closed') or j.assigned_editor is null or (x->>'score')::int not between -3 and 3 or char_length(coalesce(x->>'feedback',''))>2000 then raise exception 'invalid rating'; end if;
  insert into public.sp_project_ratings(job_id,editor_id,client_id,score,feedback) values(j.id,j.assigned_editor,u,(x->>'score')::int,x->>'feedback');
  return jsonb_build_object('ok',true);
 end if;
 if a='dispute' then
  if not (j.status='delivered' and j.review_state='awaiting_client') then raise exception 'case not available'; end if;
  if x->>'category' not in ('quality','not_as_asked','missing','late','other') or char_length(trim(coalesce(x->>'details',''))) not between 20 and 2000 then raise exception 'invalid case'; end if;
  insert into public.sp_disputes(job_id,opened_by,category,details) values(j.id,u,x->>'category',x->>'details');
  update public.sp_jobs set review_state='disputed' where id=j.id;
  insert into public.sp_project_events(job_id,actor_id,kind,title) values(j.id,u,'dispute','Case opened (staging)');
  return jsonb_build_object('ok',true);
 end if;
 if j.status<>'in-progress' or j.assigned_editor is null then raise exception 'project is not in progress'; end if;
 select * into w from public.sp_project_work where job_id=j.id for update;
 if not found or w.client_id<>j.client_id or w.editor_id<>j.assigned_editor then raise exception 'staging work not initialized'; end if;
 if a='begin' then
  k=x->>'kind';n=x->>'name';mime=x->>'mime';sz=(x->>'size')::bigint;
  if k is null or k not in ('preview','client_file') or n is null or char_length(n) not between 1 and 80 or sz is null or sz not between 1 and 52428800 then raise exception 'invalid file'; end if;
  if (k='preview' and (u<>j.assigned_editor or mime<>'video/mp4' or w.phase not in ('active','preview'))) or (k='client_file' and (u<>j.client_id or mime not in ('image/jpeg','image/png','image/webp','video/mp4','video/webm','video/quicktime'))) then raise exception 'file access denied'; end if;
  if (select count(*) from public.sp_project_files where job_id=j.id)>=100 then raise exception 'staging file limit'; end if;
  target=gen_random_uuid();
  p=j.id::text||case when k='preview' then '/preview/' else '/client/' end||target::text||case mime when 'image/jpeg' then '.jpg' when 'image/png' then '.png' when 'image/webp' then '.webp' when 'video/webm' then '.webm' when 'video/quicktime' then '.mov' else '.mp4' end;
  select coalesce(max(version),0)+1 into v from public.sp_project_files where job_id=j.id and kind=k;
  insert into public.sp_project_files(id,job_id,uploaded_by,kind,source,storage_path,file_name,mime,size_bytes,version) values(target,j.id,u,k,'upload',p,n,mime,sz,v);
  return jsonb_build_object('id',target,'path',p,'bucket','sphere-project');
 elsif a='finish' then
  select * into f from public.sp_project_files where id=target for update;
  if not found or f.uploaded_by<>u or f.status<>'uploading' then raise exception 'file access denied'; end if;
  if not coalesce((x->>'ok')::boolean,false) then update public.sp_project_files set status='failed',updated_at=now() where id=f.id;return jsonb_build_object('status','failed'); end if;
  if not exists(select 1 from storage.objects o where o.bucket_id='sphere-project' and o.name=f.storage_path and o.metadata->>'size'=f.size_bytes::text and o.metadata->>'mimetype'=f.mime) then raise exception 'uploaded object not confirmed'; end if;
  if f.kind='preview' and (w.phase not in ('active','preview') or (x->>'duration') is null or (x->>'duration')::numeric not between 0.001 and 600) then raise exception 'invalid preview duration or phase'; end if;
  update public.sp_project_files set status='ready',duration_sec=(x->>'duration')::numeric,note=left(x->>'note',500),updated_at=now() where id=f.id;
  if f.kind='client_file' then return jsonb_build_object('status','ready'); end if;
  v=f.version;
 elsif a='preview' then
  if w.phase not in ('active','preview') or x->>'kind'<>'preview' or length(coalesce(x->>'url',''))>500 or coalesce(x->>'url','') !~ '^https://[^[:space:]]+$' then raise exception 'invalid preview'; end if;
  select coalesce(max(version),0)+1 into v from public.sp_project_files where job_id=j.id and kind='preview';
  insert into public.sp_project_files(job_id,uploaded_by,kind,source,external_url,file_name,version,status,note) values(j.id,u,'preview','link',x->>'url',left(x->>'name',80),v,'ready',left(x->>'note',500));
 elsif a='approve' then
  if w.phase<>'preview' or w.preview_at is null or exists(select 1 from public.sp_revisions where job_id=j.id and status in ('open','awaiting_payment')) or exists(select 1 from public.sp_change_requests where job_id=j.id and status in ('pending','accepted_awaiting_payment')) then raise exception 'preview not approvable'; end if;
  update public.sp_project_work set preview_approved_at=now() where job_id=j.id;
 elsif a='revision' then
  if w.phase<>'preview' or w.preview_at is null or char_length(trim(coalesce(x->>'notes',''))) not between 5 and 2000 then raise exception 'invalid revision'; end if;
  if exists(select 1 from public.sp_change_requests where job_id=j.id and status in ('pending','accepted_awaiting_payment')) then raise exception 'pending change'; end if;
  select coalesce(max(number),0)+1 into v from public.sp_revisions where job_id=j.id;
  fee=case when (select count(*) from public.sp_revisions where job_id=j.id and status<>'cancelled')<3 then 0 else 50 end;
  insert into public.sp_revisions(job_id,number,requested_by,notes,fee,status,old_due_at,new_due_at,opened_at) values(j.id,v,u,x->>'notes',fee,case when fee=0 then 'open' else 'awaiting_payment' end,w.due_at,case when fee=0 then now()+interval '24 hours' end,case when fee=0 then now() end);
  if fee=0 then update public.sp_project_work set phase='active',due_at=now()+interval '24 hours',preview_approved_at=null where job_id=j.id;end if;
 elsif a='rev_cancel' then
  update public.sp_revisions set status='cancelled' where id=target and job_id=j.id and status='awaiting_payment';
  if not found then raise exception 'revision not cancellable';end if;
 elsif a in ('extension_request','extension_give','extension_answer') then
  if w.phase<>'active' then raise exception 'extension unavailable';end if;
  if a='extension_answer' then
   select * into ex from public.sp_project_extensions where job_id=j.id and status='pending' for update;
   if not found then raise exception 'no pending extension';end if;
   h=ex.hours;
   update public.sp_project_extensions set status=case when (x->>'approve')::boolean then 'approved' else 'rejected' end,decided_at=now(),decided_by=u where id=ex.id;
   if coalesce((x->>'approve')::boolean,false) then update public.sp_project_work set due_at=greatest(due_at,now())+make_interval(hours=>h),extended_hours=extended_hours+h,pending_extension_hours=null where job_id=j.id;
   else update public.sp_project_work set pending_extension_hours=null where job_id=j.id;end if;
  else
   h=(x->>'hours')::int;if h is null or h not between 1 and 72 or w.extended_hours+h>168 then raise exception 'invalid extension';end if;
   if a='extension_request' then
    if char_length(trim(coalesce(x->>'reason',''))) not between 5 and 300 then raise exception 'invalid reason';end if;
    insert into public.sp_project_extensions(job_id,requested_by,hours,reason) values(j.id,u,h,x->>'reason');
    update public.sp_project_work set pending_extension_hours=h where job_id=j.id;
   else
    if exists(select 1 from public.sp_project_extensions where job_id=j.id and status='pending') then raise exception 'pending extension';end if;
    insert into public.sp_project_extensions(job_id,requested_by,hours,reason,status,decided_at,decided_by) values(j.id,u,h,left(x->>'reason',300),'approved',now(),u);
    update public.sp_project_work set due_at=greatest(due_at,now())+make_interval(hours=>h),extended_hours=extended_hours+h where job_id=j.id;
   end if;
  end if;
 elsif a='cr_create' then
  h=(x->>'hours')::int;fee=(x->>'price')::numeric;
  if h is null or h not between 0 and 72 or fee is null or fee not between 0 and 1000000 or char_length(trim(coalesce(x->>'details',''))) not between 10 and 2000 then raise exception 'invalid change'; end if;
  if coalesce(x->>'link','')<>'' and (length(x->>'link')>500 or x->>'link' !~ '^https://[^[:space:]]+$') then raise exception 'invalid link';end if;
  select coalesce(array_agg(value::uuid),'{}') into ids from jsonb_array_elements_text(coalesce(x->'files','[]'::jsonb));
  if cardinality(ids)>5 or exists(select 1 from unnest(ids) z(id) where not exists(select 1 from public.sp_project_files pf where pf.id=z.id and pf.job_id=j.id and pf.uploaded_by=u and pf.kind='client_file' and pf.status='ready')) then raise exception 'invalid attachments';end if;
  if exists(select 1 from public.sp_revisions where job_id=j.id and status in ('open','awaiting_payment')) then raise exception 'pending revision';end if;
  insert into public.sp_change_requests(job_id,requested_by,details,extra_price,extra_hours,link,file_ids) values(j.id,u,x->>'details',fee,h,x->>'link',ids);
 elsif a='cr_cancel' then
  update public.sp_change_requests set status='cancelled',decided_at=now() where id=target and job_id=j.id and status in ('pending','accepted_awaiting_payment');
  if not found then raise exception 'change not cancellable';end if;
 elsif a='cr_answer' then
  select * into cr from public.sp_change_requests where id=target and job_id=j.id and status='pending' for update;
  if not found then raise exception 'change not pending';end if;
  if not coalesce((x->>'accept')::boolean,false) then s='rejected';
  elsif cr.extra_price>0 then s='accepted_awaiting_payment';
  else s='applied';update public.sp_project_work set phase='active',preview_approved_at=null,due_at=greatest(due_at,now())+make_interval(hours=>cr.extra_hours),extended_hours=extended_hours+cr.extra_hours where job_id=j.id;end if;
  update public.sp_change_requests set status=s,editor_note=left(x->>'note',300),decided_at=now(),applied_at=case when s='applied' then now() end where id=cr.id;
 elsif a='final' then
  if w.phase<>'preview' or w.preview_at is null or w.preview_approved_at is null or w.preview_approved_at<w.preview_at or exists(select 1 from public.sp_revisions where job_id=j.id and status in ('open','awaiting_payment')) or exists(select 1 from public.sp_change_requests where job_id=j.id and status in ('pending','accepted_awaiting_payment')) then raise exception 'preview must be approved; pending requests must be resolved';end if;
  select * into f from public.sp_project_files where id=(x->>'preview')::uuid and job_id=j.id and kind='preview' and status='ready';
  if not found or f.version<>(select max(version) from public.sp_project_files where job_id=j.id and kind='preview' and status='ready') or length(coalesce(x->>'url',''))>500 or coalesce(x->>'url','') !~ '^https://[^[:space:]]+$' then raise exception 'invalid final';end if;
  insert into public.sp_final_files(job_id,preview_file_id,preview_version,final_link,note,submitted_by) values(j.id,f.id,f.version,x->>'url',left(x->>'note',500),u);
  update public.sp_jobs set status='delivered',review_state='awaiting_client',final_submitted_at=now(),decision_due_at=now()+interval '10 hours' where id=j.id;
  update public.sp_project_work set phase='completed',completed_at=now() where job_id=j.id;
 else raise exception 'unsupported staging operation';end if;
 if a in ('finish','preview') then
  update public.sp_project_work set phase='preview',preview_at=now(),preview_approved_at=null,preview_on_time=(now()<=due_at),preview_note=left(x->>'note',500),preview_link=case when a='preview' then x->>'url' else null end where job_id=j.id;
  update public.sp_revisions set status='delivered',delivered_version=v,delivered_at=now() where job_id=j.id and status='open';
 end if;
 insert into public.sp_project_events(job_id,actor_id,kind,title) values(j.id,u,a,'Staging: '||a);
 return jsonb_build_object('ok',true,'status','ready');
end $$;
