// get-referral-code
//
// Fetch-or-create the caller's personal referral code (see the
// personal_referral_codes migration): an ordinary referral_codes row with
// owner_user_id set, redeemed by friends through the existing
// redeem-referral-code path. Body: none. Response:
// { code, bonusDays, redemptionCount }.
//
// Scope is deliberately "show + share" only -- no owner-side reward is
// granted automatically yet (product decision 2026-08-17); the
// redemption_count returned here is what a later reward pass would read.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";

const PERSONAL_CODE_BONUS_DAYS = 7;
// Unambiguous alphabet -- no 0/O/1/I/L, since codes get read aloud and
// retyped from screenshots.
const ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";

function generateCode(): string {
  let suffix = "";
  const bytes = new Uint8Array(5);
  crypto.getRandomValues(bytes);
  for (const byte of bytes) suffix += ALPHABET[byte % ALPHABET.length];
  return `SOMA-${suffix}`;
}

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const supabase = serviceRoleClient();

    const { data: existing } = await supabase
      .from("referral_codes")
      .select("code, bonus_days, redemption_count")
      .eq("owner_user_id", userId)
      .maybeSingle();
    if (existing) {
      return jsonResponse({
        code: existing.code,
        bonusDays: existing.bonus_days,
        redemptionCount: existing.redemption_count,
      });
    }

    // Collision odds per attempt are ~1 in 28M; the retry loop exists for
    // the unique-index race with a concurrent first-open, not entropy.
    for (let attempt = 0; attempt < 5; attempt++) {
      const code = generateCode();
      const { error } = await supabase.from("referral_codes").insert({
        code,
        bonus_days: PERSONAL_CODE_BONUS_DAYS,
        max_redemptions: null,
        active: true,
        owner_user_id: userId,
      });
      if (!error) {
        return jsonResponse({ code, bonusDays: PERSONAL_CODE_BONUS_DAYS, redemptionCount: 0 });
      }
      // The owner unique index fired -- a parallel request won; return its row.
      const { data: raced } = await supabase
        .from("referral_codes")
        .select("code, bonus_days, redemption_count")
        .eq("owner_user_id", userId)
        .maybeSingle();
      if (raced) {
        return jsonResponse({ code: raced.code, bonusDays: raced.bonus_days, redemptionCount: raced.redemption_count });
      }
    }
    throw new Error("could not allocate a referral code");
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});
