BEGIN;

-- No full bank account numbers: only identity hints to coordinate Razorpay Route onboarding.
CREATE TABLE IF NOT EXISTS public.sp_editor_bank_links (
 editor_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
 holder text NOT NULL CHECK (char_length(holder) BETWEEN 3 AND 100),
 ifsc text NOT NULL CHECK (ifsc ~ '^[A-Z]{4}0[A-Z0-9]{6}$'),
 last4 text NOT NULL CHECK (last4 ~ '^[0-9]{4}$'),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','verified','rejected')),
 version uuid NOT NULL DEFAULT gen_random_uuid(),
 route_account_id text,
 verified_by uuid,
 verified_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.sp_editor_withdrawals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 job_id uuid NOT NULL REFERENCES public.sp_jobs(id) ON DELETE RESTRICT,
 editor_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
 amount numeric(12,2) NOT NULL CHECK(amount>0 AND amount<=10000000),
 status text NOT NULL DEFAULT 'requested' CHECK(status IN ('requested','approved','rejected','cancelled','paid')),
 bank_version uuid NOT NULL,
 bank_last4 text NOT NULL,
 bank_ifsc text NOT NULL,
 bank_holder text NOT NULL,
 reference text,
 reason text,
 reviewed_by uuid,
 requested_at timestamptz NOT NULL DEFAULT now(),
 reviewed_at timestamptz,
 paid_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS sp_editor_withdrawal_job_claim ON public.sp_editor_withdrawals(job_id)
 WHERE status IN ('requested','approved','paid');
CREATE UNIQUE INDEX IF NOT EXISTS sp_editor_withdrawal_reference_unique ON public.sp_editor_withdrawals(lower(reference))
 WHERE status='paid' AND reference IS NOT NULL;
CREATE INDEX IF NOT EXISTS sp_editor_withdrawal_queue_idx ON public.sp_editor_withdrawals(status,requested_at DESC);
CREATE INDEX IF NOT EXISTS sp_editor_withdrawal_editor_idx ON public.sp_editor_withdrawals(editor_id,requested_at DESC);
ALTER TABLE public.sp_editor_bank_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sp_editor_withdrawals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.sp_editor_bank_links,public.sp_editor_withdrawals FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.sp_editor_bank_links,public.sp_editor_withdrawals TO authenticated;
DROP POLICY IF EXISTS sp_bank_owner_read ON public.sp_editor_bank_links;
CREATE POLICY sp_bank_owner_read ON public.sp_editor_bank_links FOR SELECT TO authenticated
 USING(editor_id=(SELECT auth.uid()) OR (SELECT public.sp_core_has_role('ADMIN')));
DROP POLICY IF EXISTS sp_withdraw_owner_read ON public.sp_editor_withdrawals;
CREATE POLICY sp_withdraw_owner_read ON public.sp_editor_withdrawals FOR SELECT TO authenticated
 USING(editor_id=(SELECT auth.uid()) OR (SELECT public.sp_core_has_role('ADMIN')));

CREATE OR REPLACE FUNCTION public.sp_editor_bank_submit(p_holder text,p_ifsc text,p_last4 text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE me uuid:=auth.uid(); h text:=btrim(coalesce(p_holder,'')); code text:=upper(btrim(coalesce(p_ifsc,''))); digits text:=btrim(coalesce(p_last4,'')); v uuid:=gen_random_uuid();
BEGIN
 IF me IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=me AND upper(btrim(role))='EDITOR') THEN RAISE EXCEPTION 'Editor login required'; END IF;
 IF length(h)<3 OR length(h)>100 OR h !~ '^[a-zA-Z .''-]+$' THEN RAISE EXCEPTION 'Enter bank account holder name'; END IF;
 IF code !~ '^[A-Z]{4}0[A-Z0-9]{6}$' THEN RAISE EXCEPTION 'Invalid IFSC'; END IF;
 IF digits !~ '^[0-9]{4}$' THEN RAISE EXCEPTION 'Enter only last 4 account digits'; END IF;
 PERFORM 1 FROM public.sp_editor_bank_links WHERE editor_id=me FOR UPDATE;
 IF EXISTS(SELECT 1 FROM public.sp_editor_withdrawals WHERE editor_id=me AND status IN ('requested','approved')) THEN
   RAISE EXCEPTION 'Finish or cancel pending withdrawals before changing bank details';
 END IF;
 INSERT INTO public.sp_editor_bank_links(editor_id,holder,ifsc,last4,status,version,updated_at)
 VALUES (me,h,code,digits,'pending',v,now())
 ON CONFLICT(editor_id) DO UPDATE SET holder=excluded.holder,ifsc=excluded.ifsc,last4=excluded.last4,
 status='pending',version=excluded.version,route_account_id=NULL,verified_by=NULL,verified_at=NULL,updated_at=now();
 UPDATE public.profiles SET razorpay_account_id=NULL WHERE id=me;
 RETURN jsonb_build_object('ok',true,'status','pending','message','Bank request submitted. Sphere team must verify it through the payment provider.');
END $$;

CREATE OR REPLACE FUNCTION public.sp_editor_wallet()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
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
    SELECT w.id,w.job_id,j.title,w.amount,w.status,w.bank_last4,w.bank_ifsc,w.reference,w.reason,w.requested_at,w.reviewed_at,w.paid_at
    FROM public.sp_editor_withdrawals w JOIN public.sp_jobs j ON j.id=w.job_id
    WHERE w.editor_id=me ORDER BY w.requested_at DESC LIMIT 40
  ) x),'[]'::jsonb)
 );
END $$;

CREATE OR REPLACE FUNCTION public.sp_editor_withdraw_request()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE me uuid:=auth.uid(); b record; j record; n integer:=0; amt numeric:=0; a numeric;
BEGIN
 IF me IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=me AND upper(btrim(role))='EDITOR') THEN RAISE EXCEPTION 'Editor login required'; END IF;
 SELECT * INTO b FROM public.sp_editor_bank_links WHERE editor_id=me FOR SHARE;
 IF b.editor_id IS NULL OR b.status<>'verified' THEN RAISE EXCEPTION 'Please verify your bank account first'; END IF;
 FOR j IN SELECT * FROM public.sp_jobs WHERE assigned_editor=me AND status IN ('approved','closed') AND payout_status='manual' ORDER BY id FOR UPDATE LOOP
  a:=round(greatest(coalesce(j.editor_amount,0),0),2);
  IF a>0 AND NOT EXISTS(SELECT 1 FROM public.sp_editor_withdrawals WHERE job_id=j.id AND status IN ('requested','approved','paid')) THEN
   INSERT INTO public.sp_editor_withdrawals(job_id,editor_id,amount,bank_version,bank_last4,bank_ifsc,bank_holder)
   VALUES(j.id,me,a,b.version,b.last4,b.ifsc,b.holder) ON CONFLICT DO NOTHING;
   IF FOUND THEN n:=n+1;amt:=amt+a; END IF;
  END IF;
 END LOOP;
 IF n=0 THEN RAISE EXCEPTION 'No available balance or withdrawal already requested'; END IF;
 INSERT INTO public.sp_notifications(user_id,title,body) VALUES(me,'Withdrawal requested','₹'||amt||' submitted for Sphere team review. No funds have been sent yet.');
 RETURN jsonb_build_object('ok',true,'requests',n,'amount',amt,'status','requested');
END $$;

CREATE OR REPLACE FUNCTION public.sp_editor_withdraw_cancel(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE me uuid:=auth.uid(); w record;
BEGIN
 IF me IS NULL THEN RAISE EXCEPTION 'Login required'; END IF;
 SELECT * INTO w FROM public.sp_editor_withdrawals WHERE id=p_id AND editor_id=me FOR UPDATE;
 IF w.id IS NULL OR w.status<>'requested' THEN RAISE EXCEPTION 'Only your pending requests can be cancelled'; END IF;
 UPDATE public.sp_editor_withdrawals SET status='cancelled',reviewed_at=now() WHERE id=w.id;
 RETURN jsonb_build_object('ok',true);
END $$;

CREATE OR REPLACE FUNCTION public.sp_admin_withdraw_queue()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT public.sp_core_has_role('ADMIN') THEN RAISE EXCEPTION 'Admins only'; END IF;
 RETURN jsonb_build_object(
 'banks',coalesce((SELECT jsonb_agg(v) FROM (
   SELECT b.editor_id,b.holder,b.ifsc,b.last4,b.status,b.route_account_id,b.updated_at,p.full_name editor
   FROM public.sp_editor_bank_links b JOIN public.profiles p ON p.id=b.editor_id
   ORDER BY CASE WHEN b.status='pending' THEN 0 ELSE 1 END,b.updated_at DESC LIMIT 80
 ) v),'[]'::jsonb),
 'withdrawals',coalesce((SELECT jsonb_agg(v) FROM (
   SELECT w.id,w.job_id,w.editor_id,w.amount,w.status,w.bank_holder,w.bank_ifsc,w.bank_last4,
     w.reason,w.reference,w.requested_at,w.reviewed_at,p.full_name editor,j.title
   FROM public.sp_editor_withdrawals w JOIN public.profiles p ON p.id=w.editor_id JOIN public.sp_jobs j ON j.id=w.job_id
   ORDER BY CASE WHEN w.status='requested' THEN 0 WHEN w.status='approved' THEN 1 ELSE 2 END,w.requested_at DESC LIMIT 120
 ) v),'[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION public.sp_admin_bank_review(p_editor uuid,p_approve boolean,p_route text,p_reason text,p_pin text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE b record; linkid text:=nullif(btrim(coalesce(p_route,'')),''); r text:=btrim(coalesce(p_reason,''));
BEGIN
 IF NOT public.sp_core_has_role('ADMIN') THEN RAISE EXCEPTION 'Admins only'; END IF;
 PERFORM public.sp_admin_check_pin(p_pin:=p_pin);
 SELECT * INTO b FROM public.sp_editor_bank_links WHERE editor_id=p_editor FOR UPDATE;
 IF b.editor_id IS NULL OR b.status<>'pending' THEN RAISE EXCEPTION 'No pending bank setup request'; END IF;
 IF p_approve THEN
   IF linkid IS NOT NULL AND linkid !~ '^acc_[A-Za-z0-9]{8,}$' THEN RAISE EXCEPTION 'Invalid Razorpay Route account ID'; END IF;
   UPDATE public.sp_editor_bank_links SET status='verified',route_account_id=linkid,verified_at=now(),verified_by=auth.uid(),updated_at=now() WHERE editor_id=p_editor;
   UPDATE public.profiles SET razorpay_account_id=linkid WHERE id=p_editor;
 ELSE
   IF length(r)<5 THEN RAISE EXCEPTION 'Explain why bank verification failed'; END IF;
   UPDATE public.sp_editor_bank_links SET status='rejected',verified_by=auth.uid(),verified_at=now(),updated_at=now() WHERE editor_id=p_editor;
 END IF;
 INSERT INTO public.sp_notifications(user_id,title,body) VALUES(p_editor,
  CASE WHEN p_approve THEN 'Bank details verified ✅' ELSE 'Bank setup needs attention' END,
  CASE WHEN p_approve THEN 'Your bank setup is verified for manual withdrawals. Automatic Route payouts require a linked account.'
       ELSE left(r,180) END);
 RETURN jsonb_build_object('ok',true,'verified',p_approve);
END $$;

CREATE OR REPLACE FUNCTION public.sp_admin_withdraw_action(p_id uuid,p_action text,p_reference text,p_reason text,p_pin text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE w record; j record; bank record; ref text:=btrim(coalesce(p_reference,'')); why text:=btrim(coalesce(p_reason,''));
BEGIN
 IF NOT public.sp_core_has_role('ADMIN') THEN RAISE EXCEPTION 'Admins only'; END IF;
 PERFORM public.sp_admin_check_pin(p_pin:=p_pin);
 SELECT * INTO w FROM public.sp_editor_withdrawals WHERE id=p_id FOR UPDATE;
 IF w.id IS NULL THEN RAISE EXCEPTION 'Withdrawal not found'; END IF;
 SELECT * INTO j FROM public.sp_jobs WHERE id=w.job_id FOR UPDATE;
 SELECT * INTO bank FROM public.sp_editor_bank_links WHERE editor_id=w.editor_id FOR SHARE;
 IF p_action='reject' THEN
   IF w.status<>'requested' OR length(why)<5 THEN RAISE EXCEPTION 'Pending request and rejection reason required'; END IF;
   UPDATE public.sp_editor_withdrawals SET status='rejected',reason=left(why,300),reviewed_by=auth.uid(),reviewed_at=now() WHERE id=w.id;
 ELSIF p_action='approve' THEN
   IF w.status<>'requested' THEN RAISE EXCEPTION 'Request is no longer pending'; END IF;
   IF bank.status<>'verified' OR bank.version IS DISTINCT FROM w.bank_version THEN RAISE EXCEPTION 'Bank verification has changed'; END IF;
   IF j.status NOT IN ('approved','closed') OR j.payout_status<>'manual' OR round(coalesce(j.editor_amount,0),2)<>w.amount THEN RAISE EXCEPTION 'Job is not available for payout'; END IF;
   UPDATE public.sp_editor_withdrawals SET status='approved',reviewed_by=auth.uid(),reviewed_at=now() WHERE id=w.id;
 ELSIF p_action='paid' THEN
   IF w.status<>'approved' THEN RAISE EXCEPTION 'Approve request first; do not mark paid twice'; END IF;
   IF bank.status<>'verified' OR bank.version IS DISTINCT FROM w.bank_version THEN RAISE EXCEPTION 'Bank account changed'; END IF;
   IF j.status NOT IN ('approved','closed') OR j.payout_status<>'manual' OR round(coalesce(j.editor_amount,0),2)<>w.amount THEN RAISE EXCEPTION 'Job is not payable'; END IF;
   IF ref !~ '^[A-Za-z0-9/_-]{6,80}$' THEN RAISE EXCEPTION 'Enter a real bank/UPI transaction reference (UTR)'; END IF;
   UPDATE public.sp_editor_withdrawals SET status='paid',reference=ref,paid_at=now(),reviewed_by=auth.uid(),reviewed_at=now() WHERE id=w.id;
   UPDATE public.sp_jobs SET payout_status='paid-manually',razorpay_transfer_id=ref WHERE id=w.job_id AND payout_status='manual';
 ELSE RAISE EXCEPTION 'Unknown withdrawal action'; END IF;
 INSERT INTO public.sp_notifications(user_id,title,body) VALUES(w.editor_id,
  CASE p_action WHEN 'approve' THEN 'Withdrawal approved' WHEN 'paid' THEN 'Withdrawal marked paid' ELSE 'Withdrawal request rejected' END,
  CASE p_action WHEN 'approve' THEN '₹'||w.amount||' approved. Sphere team will send payment after verification.'
                WHEN 'paid' THEN '₹'||w.amount||' marked paid. Bank transfer reference: '||ref
                ELSE left(why,180) END);
 RETURN jsonb_build_object('ok',true,'status',CASE WHEN p_action='paid' THEN 'paid' WHEN p_action='approve' THEN 'approved' ELSE 'rejected' END);
END $$;

-- Existing app's manual payout shortcut must not race approved withdrawal requests.
CREATE OR REPLACE FUNCTION public.sp_editor_withdraw_manual_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF current_user IN ('authenticated','anon')
 AND NEW.payout_status IS DISTINCT FROM OLD.payout_status
 AND EXISTS(SELECT 1 FROM public.sp_editor_withdrawals WHERE job_id=OLD.id AND status IN ('requested','approved')) THEN
  RAISE EXCEPTION 'This job has a withdrawal request; use Admin Payments > Withdrawals';
 END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS a5_sp_editor_withdraw_manual_guard ON public.sp_jobs;
CREATE TRIGGER a5_sp_editor_withdraw_manual_guard BEFORE UPDATE OF payout_status ON public.sp_jobs FOR EACH ROW EXECUTE FUNCTION public.sp_editor_withdraw_manual_guard();

REVOKE ALL ON FUNCTION public.sp_editor_bank_submit(text,text,text),public.sp_editor_wallet(),public.sp_editor_withdraw_request(),public.sp_editor_withdraw_cancel(uuid),
 public.sp_admin_withdraw_queue(),public.sp_admin_bank_review(uuid,boolean,text,text,text),public.sp_admin_withdraw_action(uuid,text,text,text,text),
 public.sp_editor_withdraw_manual_guard() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sp_editor_bank_submit(text,text,text),public.sp_editor_wallet(),public.sp_editor_withdraw_request(),public.sp_editor_withdraw_cancel(uuid),
 public.sp_admin_withdraw_queue(),public.sp_admin_bank_review(uuid,boolean,text,text,text),public.sp_admin_withdraw_action(uuid,text,text,text,text)
 TO authenticated;
COMMIT;