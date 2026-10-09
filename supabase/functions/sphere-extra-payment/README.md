# sphere-extra-payment (Parts 11 + 15) — Razorpay for every extra payment

One function for:
* ₹50 fee of a 4th+ revision and the extra price of an accepted change request (Part 11) — `{ extraId }`
* ₹29 editor verification fee and ₹199 Editor Pro (Part 15) — `{ feeId }`

The amount always comes from the database. A payment becomes PAID only after this
function checks Razorpay's signature (or an admin confirms a UPI transaction ID).
Without the function, people pay by UPI and type the transaction ID.

## Deploy / update (Supabase dashboard)
1. Edge Functions → if `sphere-extra-payment` exists: open it → **Code** → replace everything with this `index.ts` → **Deploy**.
   If it does not exist: **Deploy a new function** → **Via Editor** → name `sphere-extra-payment` → paste → **Deploy**.
2. Edge Functions → **Secrets**: `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET` (the same Razorpay keys the other functions use).

## Test without real money
Keep the **test** keys (`rzp_test_…`). In the Razorpay window use the test card `4111 1111 1111 1111`
(any future date, any CVV) or UPI `success@razorpay` for Paid and `failure@razorpay` for Failed.
