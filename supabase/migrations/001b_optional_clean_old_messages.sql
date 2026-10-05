-- =====================================================================
-- SPHERE — PART 1, OPTIONAL: hide numbers in OLD messages / jobs / bids
-- Run only after 2_part1_number_block.sql. Old content gives NO strikes.
-- =====================================================================
begin;
select set_config('sphere.no_strike', '1', true);

update public.sp_messages m set "text" = (public.sp_mod_mask(m."text")).masked
where m."text" is not null and (public.sp_mod_mask(m."text")).hard
  and not public.sp_mod_is_admin(m.sender_id);

update public.sp_jobs j set description = (public.sp_mod_mask(j.description)).masked
where j.description is not null and (public.sp_mod_mask(j.description)).hard
  and not public.sp_mod_is_admin(j.client_id);

update public.sp_applications a set message = (public.sp_mod_mask(a.message)).masked
where a.message is not null and (public.sp_mod_mask(a.message)).hard
  and not public.sp_mod_is_admin(a.editor_id);

commit;
