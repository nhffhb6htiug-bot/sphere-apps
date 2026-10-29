CREATE OR REPLACE FUNCTION public.sp_admin_bank_review(p_editor uuid, p_approve boolean, p_route text, p_reason text, p_pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE b record; linkid text:=nullif(btrim(coalesce(p_route,'')),''); r text:=btrim(coalesce(p_reason,''));
BEGIN
 IF NOT public.sp_core_has_role('ADMIN') THEN RAISE EXCEPTION 'Admins only'; END IF;
 PERFORM public.sp_admin_check_pin(p_pin:=p_pin);
 SELECT * INTO b FROM public.sp_editor_bank_links WHERE editor_id=p_editor FOR UPDATE;
 IF b.editor_id IS NULL OR b.status<>'pending' THEN RAISE EXCEPTION 'No pending bank setup request'; END IF;
 IF p_approve THEN
   IF b.payout_method='upi' AND linkid IS NOT NULL THEN RAISE EXCEPTION 'UPI QR/ID is a manual payout method; do not attach a Razorpay Route account'; END IF;
   IF linkid IS NOT NULL AND linkid !~ '^acc_[A-Za-z0-9]{8,}$' THEN RAISE EXCEPTION 'Invalid Razorpay Route account ID'; END IF;
   UPDATE public.sp_editor_bank_links SET status='verified',route_account_id=linkid,verified_at=now(),verified_by=auth.uid(),updated_at=now() WHERE editor_id=p_editor;
   UPDATE public.profiles SET razorpay_account_id=linkid WHERE id=p_editor;
 ELSE
   IF length(r)<5 THEN RAISE EXCEPTION 'Explain why bank verification failed'; END IF;
   UPDATE public.sp_editor_bank_links SET status='rejected',verified_by=auth.uid(),verified_at=now(),updated_at=now() WHERE editor_id=p_editor;
 END IF;
 INSERT INTO public.sp_notifications(user_id,title,body) VALUES(p_editor,
  CASE WHEN p_approve THEN 'Payout destination reviewed ✅' ELSE 'Payout setup needs attention' END,
  CASE WHEN p_approve THEN 'Your verified payout method can receive manually approved withdrawals. Automatic Route payouts need separate linked-account setup.'
       ELSE left(r,180) END);
 RETURN jsonb_build_object('ok',true,'verified',p_approve);
END $function$
;