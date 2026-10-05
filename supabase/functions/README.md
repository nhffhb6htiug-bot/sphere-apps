# Edge Functions

These 5 functions run on Supabase but their code is **not in GitHub yet**:

| Function | Used by |
|---|---|
| `sphere-ai` | Sphere AI chat, job drafting (Gemini) |
| `create-razorpay-order` | Pay button |
| `verify-razorpay-payment` | After Razorpay checkout |
| `release-payout` | Approve & release to editor |
| `refund-payment` | Admin refund |

## How to save one here (2 minutes each)
1. Supabase Dashboard → **Edge Functions** → click the function → **Code** tab.
2. Select all the code → copy.
3. GitHub → `sphere-apps` → `supabase/functions/` → **Add file → Create new file**.
4. Name it `<function-name>/index.ts` (for example `sphere-ai/index.ts`) → paste → **Commit**.

Never paste secrets here. Keys belong in Supabase → Edge Functions → **Secrets**.
