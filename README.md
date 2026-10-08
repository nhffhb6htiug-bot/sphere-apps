# sphere-extra-payment (Part 11) — optional Razorpay for extra payments

Used for the ₹50 fee of a 4th+ revision and for the extra price of an accepted change request.
Without it, clients pay by UPI and type the transaction ID; an admin confirms it in
Admin Panel → 💳 Extra payments to check.

## Deploy (Supabase dashboard)
1. Edge Functions → **Deploy a new function** → **Via Editor**.
2. Name: `sphere-extra-payment` (exactly) → paste `index.ts` → **Deploy**.
3. Edge Functions → **Secrets**: `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET` must be there
   (the same keys the other Razorpay functions use; add them under these names if they have other names).

## Note
The money arrives in Sphere's Razorpay account. The editor's share (100 % of revision fees,
change price minus Sphere's fee) is recorded in `sp_extra_splits` and is paid out with the
project payout (payment release is a later part).
