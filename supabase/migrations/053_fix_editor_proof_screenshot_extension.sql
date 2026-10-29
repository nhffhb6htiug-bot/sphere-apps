begin;
-- Strict PNG/JPEG/WEBP suffix: literal dot without ambiguous SQL backslashes.
CREATE OR REPLACE FUNCTION public.sp_submit_proof_screenshot(p_path text)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me uuid:=auth.uid(); t timestamptz:=now(); v text:=btrim(coalesce(p_path,''));
begin
  if me is null then raise exception 'Please sign in'; end if;
  if not exists(select 1 from public.sp_editor_offer_slots where editor_id=me) then
    raise exception 'Free screenshot submission is reserved for the first 50 editors';
  end if;
  if length(v)>260 or v !~ ('^'||me::text||'/[a-zA-Z0-9_.-]+[.](png|jpg|jpeg|webp)$') then
    raise exception 'Invalid screenshot path';
  end if;
  if not exists(select 1 from storage.objects where bucket_id='sphere-editor-proof' and name=v) then
    raise exception 'Upload the screenshot first';
  end if;
  update public.profiles set proof_screenshot_path=v, proof_screenshot_at=t where id=me;
  return t;
end $function$;
commit;