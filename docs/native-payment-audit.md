# Task 02.7 — Payment safety audit (source review only)
Scope: native Compose development branch, repository Edge Functions, read-only schema check. No payment API was invoked and no live tables were changed. RLS is enabled on sp_jobs, sp_extra_payments, sp_refunds, sp_final_files, sp_webhook_events; this is not proof of correct row authorization. Deployed function versions and provider account approval not verified.

## Policy routing (provisional)
- Premium job posting, contact unlock and paid badge/verification treated conservatively as digital in-app functionality. Play Billing unless a documented exception or enrolled alternative billing applies.
- Asynchronous commissioned editing and paid revisions/changes need written Play classification; do not assume physical-service or live one-to-one exemption. No external checkout steering.
- Separate service compensation from platform features; do not build an arbitrary balance or wallet. An authorized adult business owner must handle provider onboarding, legal/KYC and agreement with licensed provider. Do not claim escrow or guaranteed payout without contractual approval.
- https://support.google.com/googleplay/android-developer/answer/9858738
- https://support.google.com/googleplay/android-developer/answer/10281818
- https://support.google.com/googleplay/android-developer/answer/13306652
- https://developer.android.com/google/play/billing/security

## Release blockers found in checked-in server source
P0 verify-razorpay-payment and sphere-extra-payment: HMAC alone is not a captured-payment confirmation. Verify provider payment record, bound order, exact amount in integer minor units, currency, capture status, expected owner/target; use atomic unique provider transaction receipt and reject cross-target reuse.
P0 release-payout: provider transfer side effect occurs before conditional job update; refund can race release and disputed review state is not checked in the inspected function. Require one atomic server-side operation claim shared by release and refund, eligibility checks and explicit admin adjudication; reconcile provider state before marking success. Do not assume failed/manual payout means released money.
P0 refund-payment: claims individual refund row but not the same job-level operation lock as release. Ambiguous provider timeout must not be treated as safely retryable; reconcile by provider reference and idempotency contract before retry. Track pending vs processed refunds.
P1 create-razorpay-order and sphere-extra-payment: reuse checks exist but concurrent initial requests can create separate provider orders; durable server claim before network call, persist and reconcile order reference.
P1 razorpay-webhook: signature and amount check exist; duplicate event insert short-circuits even if previous processing failed; final response returns success even for failed processing. Need durable inbox with processing lease, retry and reconciliation; bind order and currency for extra/fee events and audit downstream RPC constraints.
P0 final video: native UI guards now consistent; independently test final file RLS against unauthorized users and pre-release client, including direct API reads. UI is not authorization.

## Staging acceptance plan
Test with fictional orders and isolated provider sandbox only. Validate role, target, amounts, currency, pending/cancelled/captured, duplicate callback/webhook, wrong order/account, two simultaneous releases, refund versus release, provider timeout/reconciliation, dispute, refund pending/processed, final file lock and entitlement revocation. Play purchases need server verification of purchase token and target, unique token redemption, acknowledgement/consumption after durable fulfillment, pending state and revocation. No real card, bank details, provider credentials or purchases in the native simulator.
