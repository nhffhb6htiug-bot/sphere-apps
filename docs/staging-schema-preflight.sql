-- READ-ONLY staging catalog preflight. Confirm project ref before execution.
-- No data reads from application tables, writes, functions invoked, or migrations.
with required_tables(name) as (values
 ('profiles'),('sp_jobs'),('sp_applications'),('sp_settings'),('sp_messages'),
 ('sp_notifications'),('sp_blocks'),('sp_presence'),('sp_portfolio'),('sp_job_drafts'),
 ('sp_project_work'),('sp_project_files'),('sp_project_extensions'),('sp_revisions'),
 ('sp_change_requests'),('sp_project_events'),('sp_disputes'),('sp_refunds'),('sp_final_files'),
 ('sp_settlements'),('sp_payments'),('sp_extra_payments'),('sp_phone_verifications'),
 ('sp_admin_audit'),('sp_editor_verification_outreach'),('sp_reports')
), required_rpc(name) as (values
 ('sp_core_whoami'),('sp_phone_verify_status'),('sp_phone_verify_start'),
 ('sp_seen_ping'),('sp_last_seen'),('sp_submit_proof_video'),('sp_submit_proof_screenshot'),
 ('sp_editor_offer_status'),('sp_files_begin'),('sp_files_finish'),('sp_files_add_link'),
 ('sp_approve_preview'),('sp_final_submit'),('sp_rev_request'),('sp_rev_cancel'),
 ('sp_cr_create'),('sp_cr_answer'),('sp_cr_cancel'),('sp_dispute_open'),
 ('sp_work_request_extension'),('sp_work_answer_extension'),('sp_work_give_time'),
 ('sp_rating_submit'),('sp_admin_overview'),('sp_admin_profiles'),('sp_admin_verifications'),
 ('sp_admin_users'),('sp_admin_projects'),('sp_admin_payments'),('sp_admin_unlock')
), required_buckets(name,must_be_private) as (values
 ('sphere-raw',true),('sphere-chat',true),('sphere-project',true),
 ('sphere-editor-proof',true),('sphere-media',false)
)
select 'table' as kind,r.name,case when c.oid is null then 'MISSING' when not c.relrowsecurity then 'RLS OFF' else 'PASS' end as status
from required_tables r left join pg_namespace n on n.nspname='public'
left join pg_class c on c.relnamespace=n.oid and c.relname=r.name and c.relkind in ('r','p')
union all
select 'rpc',r.name,case when exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=r.name) then 'PASS' else 'MISSING' end
from required_rpc r
union all
select 'bucket',r.name,case when b.id is null then 'MISSING' when r.must_be_private and b.public then 'PUBLIC BUCKET' else 'PASS' end
from required_buckets r left join storage.buckets b on b.id=r.name
order by kind,name;
