
BEGIN;

-- UPI/manual payee setup, with bank details optional. Never store full bank number or UPI PIN.
ALTER TABLE public.sp_editor_bank_links
  ADD COLUMN IF NOT EXISTS payout_method text NOT NULL DEFAULT 'bank',
  ADD COLUMN IF NOT EXISTS upi_id text,
  ADD COLUMN IF NOT EXISTS upi_phone text,
  ADD COLUMN IF NOT EXISTS upi_qr_path text;
ALTER TABLE public.sp_editor_bank_links ALTER COLUMN holder DROP NOT NULL;
ALTER TABLE public.sp_editor_bank_links ALTER COLUMN ifsc DROP NOT NULL;
ALTER TABLE public.sp_editor_bank_links ALTER COLUMN last4 DROP NOT NULL;
ALTER TABLE public.sp_editor_bank_links DROP CONSTRAINT IF EXISTS sp_editor_bank_links_holder_check;
ALTER TABLE public.sp_editor_bank_links DROP CONSTRAINT IF EXISTS sp_editor_bank_links_ifsc_check;
ALTER TABLE public.sp_editor_bank_links DROP CONSTRAINT IF EXISTS sp_editor_bank_links_last4_check;
ALTER TABLE public.sp_editor_bank_links DROP CONSTRAINT IF EXISTS sp_editor_bank_links_payout_method_check;
ALTER TABLE public.sp_editor_bank_links ADD CONSTRAINT sp_editor_bank_links_payout_method_check
  CHECK (
    payout_method IN ('upi','bank') AND
    (holder IS NULL OR (length(holder) BETWEEN 3 AND 100)) AND
    (ifsc IS NULL OR ifsc ~ '^[A-Z]{4}0[A-Z0-9]{6}$') AND
    (last4 IS NULL OR last4 ~ '^[0-9]{4}$') AND
    ((holder IS NULL AND ifsc IS NULL AND last4 IS NULL) OR
     (holder IS NOT NULL AND ifsc IS NOT NULL AND last4 IS NOT NULL)) AND
    (upi_id IS NULL OR upi_id ~ '^[A-Za-z0-9._-]{2,100}@[A-Za-z][A-Za-z0-9.-]{1,64}$') AND
    (upi_phone IS NULL OR upi_phone ~ '^[6-9][0-9]{9}$') AND
    (upi_qr_path IS NULL OR length(upi_qr_path) <= 260) AND
    (payout_method <> 'bank' OR holder IS NOT NULL) AND
    (payout_method <> 'upi' OR upi_id IS NOT NULL OR upi_phone IS NOT NULL OR upi_qr_path IS NOT NULL)
  );

ALTER TABLE public.sp_editor_withdrawals
 ADD COLUMN IF NOT EXISTS payout_method text NOT NULL DEFAULT 'bank',
 ADD COLUMN IF NOT EXISTS upi_id text,
 ADD COLUMN IF NOT EXISTS upi_phone text,
 ADD COLUMN IF NOT EXISTS upi_qr_path text;
ALTER TABLE public.sp_editor_withdrawals ALTER COLUMN bank_holder DROP NOT NULL;
ALTER TABLE public.sp_editor_withdrawals ALTER COLUMN bank_ifsc DROP NOT NULL;
ALTER TABLE public.sp_editor_withdrawals ALTER COLUMN bank_last4 DROP NOT NULL;
ALTER TABLE public.sp_editor_withdrawals DROP CONSTRAINT IF EXISTS sp_editor_withdrawals_payout_method_check;
ALTER TABLE public.sp_editor_withdrawals ADD CONSTRAINT sp_editor_withdrawals_payout_method_check CHECK (payout_method IN ('upi','bank'));

-- QR proof must only be readable by the owner or authorized Sphere admins.
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 VALUES('sphere-payout-qr','sphere-payout-qr',false,2097152,ARRAY['image/png','image/jpeg','image/webp'])
 ON CONFLICT(id) DO UPDATE SET public=false,file_size_limit=2097152,allowed_mime_types=ARRAY['image/png','image/jpeg','image/webp'];
DROP POLICY IF EXISTS sp_payout_qr_insert ON storage.objects;
CREATE POLICY sp_payout_qr_insert ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated
 WITH CHECK (bucket_id='sphere-payout-qr'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  AND public.sp_core_has_role('EDITOR'));
DROP POLICY IF EXISTS sp_payout_qr_read ON storage.objects;
CREATE POLICY sp_payout_qr_read ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated
 USING (bucket_id='sphere-payout-qr'
  AND ((storage.foldername(name))[1] = (SELECT auth.uid())::text OR public.sp_core_has_role('ADMIN')));
DROP POLICY IF EXISTS sp_payout_qr_delete ON storage.objects;
CREATE POLICY sp_payout_qr_delete ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated
 USING (bucket_id='sphere-payout-qr' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);

-- No direct edits to payout destinations, approval statuses, or withdrawal history.
REVOKE INSERT,UPDATE,DELETE ON public.sp_editor_bank_links FROM anon,authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.sp_editor_withdrawals FROM anon,authenticated;

CREATE OR REPLACE FUNCTION public.sp_editor_payout_submit(
 p_method text, p_upi_id text, p_upi_phone text, p_qr_path text,
 p_holder text DEFAULT NULL, p_ifsc text DEFAULT NULL, p_last4 text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE me uuid:=auth.uid(); meth text:=lower(btrim(coalesce(p_method,'')));
 u text:=nullif(lower(btrim(coalesce(p_upi_id,''))),'');
 ph text:=nullif(btrim(coalesce(p_upi_phone,'')),'');
 qr text:=nullif(btrim(coalesce(p_qr_path,'')),'');
 h text:=nullif(btrim(coalesce(p_holder,'')),'');
 bankcode text:=nullif(upper(btrim(coalesce(p_ifsc,''))),'');
 digits text:=nullif(btrim(coalesce(p_last4,'')),'');
 v uuid:=gen_random_uuid();
BEGIN
 IF me IS NULL OR NOT public.sp_core_has_role('EDITOR') THEN RAISE EXCEPTION 'Editor login required'; END IF;
 IF meth NOT IN ('upi','bank') THEN RAISE EXCEPTION 'Choose UPI or Bank'; END IF;
 IF h IS NOT NULL OR bankcode IS NOT NULL OR digits IS NOT NULL THEN
  IF h IS NULL OR bankcode IS NULL OR digits IS NULL THEN RAISE EXCEPTION 'For optional bank setup, enter holder name, IFSC and last 4 digits together'; END IF;
  IF length(h)<3 OR length(h)>100 OR h !~ '^[a-zA-Z .''-]+$' THEN RAISE EXCEPTION 'Enter valid bank holder name'; END IF;
  IF bankcode !~ '^[A-Z]{4}0[A-Z0-9]{6}$' OR digits !~ '^[0-9]{4}$' THEN RAISE EXCEPTION 'Invalid bank IFSC or last four digits'; END IF;
 END IF;
 IF meth='bank' AND h IS NULL THEN RAISE EXCEPTION 'Enter bank details or choose UPI'; END IF;
 IF u IS NOT NULL AND u !~ '^[a-z0-9._-]{2,100}@[a-z][a-z0-9.-]{1,64}$' THEN RAISE EXCEPTION 'Invalid UPI ID'; END IF;
 IF ph IS NOT NULL AND ph !~ '^[6-9][0-9]{9}$' THEN RAISE EXCEPTION 'Enter a valid 10-digit UPI mobile number'; END IF;
 IF qr IS NOT NULL THEN
  IF length(qr)>260 OR qr !~ ('^'||me::text||'/[0-9a-zA-Z_.-]+[.](png|jpg|jpeg|webp)$')
    OR NOT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='sphere-payout-qr' AND name=qr)
  THEN RAISE EXCEPTION 'Upload a valid UPI QR in your own account'; END IF;
 END IF;
 IF meth='upi' AND u IS NULL AND ph IS NULL AND qr IS NULL THEN RAISE EXCEPTION 'Add a UPI QR, UPI ID or UPI mobile number'; END IF;
 PERFORM 1 FROM public.sp_editor_bank_links WHERE editor_id=me FOR UPDATE;
 IF EXISTS(SELECT 1 FROM public.sp_editor_withdrawals WHERE editor_id=me AND status IN ('requested','approved')) THEN
  RAISE EXCEPTION 'Finish or cancel existing withdrawal requests before changing payout details';
 END IF;
 INSERT INTO public.sp_editor_bank_links(editor_id,holder,ifsc,last4,payout_method,upi_id,upi_phone,upi_qr_path,status,version,updated_at)
 VALUES(me,h,bankcode,digits,meth,u,ph,qr,'pending',v,now())
 ON CONFLICT(editor_id) DO UPDATE SET holder=excluded.holder,ifsc=excluded.ifsc,last4=excluded.last4,
 payout_method=excluded.payout_method,upi_id=excluded.upi_id,upi_phone=excluded.upi_phone,upi_qr_path=excluded.upi_qr_path,
 status='pending',version=excluded.version,route_account_id=NULL,verified_by=NULL,verified_at=NULL,updated_at=now();
 UPDATE public.profiles SET razorpay_account_id=NULL WHERE id=me;
 INSERT INTO public.sp_notifications(user_id,title,body) VALUES(me,'Payout setup submitted','Sphere team will review your '||upper(meth)||' payout details before withdrawals are enabled.');
 RETURN jsonb_build_object('ok',true,'status','pending','method',meth);
END $$;
REVOKE ALL ON FUNCTION public.sp_editor_payout_submit(text,text,text,text,text,text,text) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.sp_editor_payout_submit(text,text,text,text,text,text,text) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.sp_editor_wallet()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE me uuid:=auth.uid(); b jsonb; earned numeric; work_pending numeric; available numeric; awaiting numeric; paid numeric;
BEGIN
 IF me IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=me AND upper(btrim(role))='EDITOR') THEN RAISE EXCEPTION 'Editor login required'; END IF;
 SELECT to_jsonb(l)-'editor_id'-'version'-'verified_by' INTO b FROM public.sp_editor_bank_links l WHERE editor_id=me;
 SELECT
 coalesce(sum(CASE WHEN j.status IN ('approved','closed') THEN greatest(coalesce(j.editor_amount,0),0) ELSE 0 END),0),
 coalesce(sum(CASE WHEN j.status IN ('in-progress','delivered') AND j.payment_status='escrow-held' THEN greatest(coalesce(j.editor_amount,0),0) ELSE 0 END),0),
 coalesce(sum(CASE WHEN j.status IN ('approved','closed') AND j.payout_status='manual'
   AND NOT EXISTS(SELECT 1 FROM public.sp_editor_withdrawals w WHERE w.job_id=j.id AND w.status IN ('requested','approved','paid'))
   THEN greatest(coalesce(j.editor_amount,0),0) ELSE 0 END),0),
 coalesce(sum(CASE WHEN j.status IN ('approved','closed') AND j.payout_status='manual'
   AND EXISTS(SELECT 1 FROM public.sp_editor_withdrawals w WHERE w.job_id=j.id AND w.status IN ('requested','approved'))
   THEN greatest(coalesce(j.editor_amount,0),0) ELSE 0 END),0),
 coalesce(sum(CASE WHEN j.status IN ('approved','closed') AND j.payout_status IN ('released','paid-manually','paid','transferred')
   THEN greatest(coalesce(j.editor_amount,0),0) ELSE 0 END),0)
 INTO earned,work_pending,available,awaiting,paid
 FROM public.sp_jobs j WHERE j.assigned_editor=me;
 RETURN jsonb_build_object(
  'total_earned',earned,'pending_work',work_pending,'available',available,'requested',awaiting,
  'paid_or_released',paid,'bank',b,
  'history',coalesce((SELECT jsonb_agg(x) FROM (
    SELECT w.id,w.job_id,j.title,w.amount,w.status,w.bank_last4,w.bank_ifsc,w.payout_method,w.upi_id,w.upi_phone,w.upi_qr_path,w.reference,w.reason,w.requested_at,w.reviewed_at,w.paid_at
    FROM public.sp_editor_withdrawals w JOIN public.sp_jobs j ON j.id=w.job_id
    WHERE w.editor_id=me ORDER BY w.requested_at DESC LIMIT 40
  ) x),'[]'::jsonb)
 );
END $function$
;
CREATE OR REPLACE FUNCTION public.sp_admin_withdraw_queue()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF NOT public.sp_core_has_role('ADMIN') THEN RAISE EXCEPTION 'Admins only'; END IF;
 RETURN jsonb_build_object(
 'banks',coalesce((SELECT jsonb_agg(v) FROM (
   SELECT b.editor_id,b.holder,b.ifsc,b.last4,b.payout_method,b.upi_id,b.upi_phone,b.upi_qr_path,b.status,b.route_account_id,b.updated_at,p.full_name editor
   FROM public.sp_editor_bank_links b JOIN public.profiles p ON p.id=b.editor_id
   ORDER BY CASE WHEN b.status='pending' THEN 0 ELSE 1 END,b.updated_at DESC LIMIT 80
 ) v),'[]'::jsonb),
 'withdrawals',coalesce((SELECT jsonb_agg(v) FROM (
   SELECT w.id,w.job_id,w.editor_id,w.amount,w.status,w.bank_holder,w.bank_ifsc,w.bank_last4,w.payout_method,w.upi_id,w.upi_phone,w.upi_qr_path,
     w.reason,w.reference,w.requested_at,w.reviewed_at,p.full_name editor,j.title
   FROM public.sp_editor_withdrawals w JOIN public.profiles p ON p.id=w.editor_id JOIN public.sp_jobs j ON j.id=w.job_id
   ORDER BY CASE WHEN w.status='requested' THEN 0 WHEN w.status='approved' THEN 1 ELSE 2 END,w.requested_at DESC LIMIT 120
 ) v),'[]'::jsonb));
END $function$
;
CREATE OR REPLACE FUNCTION public.sp_editor_withdraw_request()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE me uuid:=auth.uid(); b record; j record; n integer:=0; amt numeric:=0; a numeric;
BEGIN
 IF me IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=me AND upper(btrim(role))='EDITOR') THEN RAISE EXCEPTION 'Editor login required'; END IF;
 SELECT * INTO b FROM public.sp_editor_bank_links WHERE editor_id=me FOR SHARE;
 IF b.editor_id IS NULL OR b.status<>'verified' THEN RAISE EXCEPTION 'Please verify your bank account first'; END IF;
 FOR j IN SELECT * FROM public.sp_jobs WHERE assigned_editor=me AND status IN ('approved','closed') AND payout_status='manual' ORDER BY id FOR UPDATE LOOP
  a:=round(greatest(coalesce(j.editor_amount,0),0),2);
  IF a>0 AND NOT EXISTS(SELECT 1 FROM public.sp_editor_withdrawals WHERE job_id=j.id AND status IN ('requested','approved','paid')) THEN
   INSERT INTO public.sp_editor_withdrawals(job_id,editor_id,amount,bank_version,bank_last4,bank_ifsc,bank_holder,payout_method,upi_id,upi_phone,upi_qr_path)
   VALUES(j.id,me,a,b.version,b.last4,b.ifsc,b.holder,b.payout_method,b.upi_id,b.upi_phone,b.upi_qr_path) ON CONFLICT DO NOTHING;
   IF FOUND THEN n:=n+1;amt:=amt+a; END IF;
  END IF;
 END LOOP;
 IF n=0 THEN RAISE EXCEPTION 'No available balance or withdrawal already requested'; END IF;
 INSERT INTO public.sp_notifications(user_id,title,body) VALUES(me,'Withdrawal requested','₹'||amt||' submitted for Sphere team review. No funds have been sent yet.');
 RETURN jsonb_build_object('ok',true,'requests',n,'amount',amt,'status','requested');
END $function$
;

-- Legacy bank-only interface remains supported for existing clients; new UI uses sp_editor_payout_submit.
COMMIT;
