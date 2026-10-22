-- SPHERE 045 — security hygiene: helper functions get a fixed search_path (Supabase advisor 0011). Behaviour unchanged.
begin;
alter function public.sp_ist(timestamp with time zone) set search_path = public, extensions;
alter function public.sp_ledger_lock() set search_path = public, extensions;
alter function public.sp_mask_log_text(text, integer) set search_path = public, extensions;
alter function public.sp_mod_numeric_only(text) set search_path = public, extensions;
alter function public.sp_mod_re(text) set search_path = public, extensions;
alter function public.sp_notif_guess(text) set search_path = public, extensions;
alter function public.sp_notif_link(text, uuid, text, text, boolean) set search_path = public, extensions;
alter function public.sp_notif_mandatory() set search_path = public, extensions;
alter function public.sp_notif_optional() set search_path = public, extensions;
alter function public.sp_pay_status_of(text, text) set search_path = public, extensions;
alter function public.sp_profile_private_cols() set search_path = public, extensions;
alter function public.sp_today_ist() set search_path = public, extensions;
insert into public.sp_schema_versions (version, name) values ('045', 'Fixed search_path on 12 helper functions (advisor hygiene)') on conflict (version) do update set applied_at = now();
commit;
