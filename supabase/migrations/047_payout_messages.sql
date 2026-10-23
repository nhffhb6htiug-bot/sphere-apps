-- SPHERE 047 — manual payouts: the admins get "Pay the editor ₹X" when a project is approved;
-- the editor is not told "your payout has started" (they already got "Sphere will send you ₹X soon").
-- (Applied to production 23 Oct 2026; full function in the database — see sp_final_job_after.)
insert into public.sp_schema_versions (version, name) values ('047', 'Manual payouts: admins get "Pay the editor ₹X"; no misleading "payout started" to the editor')
on conflict (version) do update set applied_at = now();
