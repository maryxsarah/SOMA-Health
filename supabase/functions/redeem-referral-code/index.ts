// redeem-referral-code
//
// Grants bonus free access to the recommendation detail view, additive to
// (not a replacement for) Apple's StoreKit subscription/trial. Called
// from PaywallView when the user enters a code.
//
// Body: { code: string }
// Response: { referral_bonus_until: string (ISO date) }

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const rawCode: string | undefined = body.code;

    if (!rawCode || !rawCode.trim()) {
      return jsonResponse({ error: "missing 'code'" }, 400);
    }
    const code = rawCode.trim().toUpperCase();

    const supabase = serviceRoleClient();

    const { data: referral } = await supabase
      .from("referral_codes")
      .select("code, bonus_days, max_redemptions, redemption_count, active, owner_user_id")
      .eq("code", code)
      .maybeSingle();

    if (!referral || !referral.active) {
      return jsonResponse({ error: "Invalid or expired referral code." }, 404);
    }
    if (referral.owner_user_id === userId) {
      return jsonResponse({ error: "That's your own code -- share it with a friend instead." }, 409);
    }
    if (referral.max_redemptions !== null && referral.redemption_count >= referral.max_redemptions) {
      return jsonResponse({ error: "This referral code has already been fully redeemed." }, 409);
    }

    const { data: userRow } = await supabase
      .from("users")
      .select("referral_bonus_until, referral_code_used")
      .eq("id", userId)
      .maybeSingle();

    // One redemption per (user, code) -- re-entering the same code used to
    // silently stack bonus_days onto the expiry every time.
    if (userRow?.referral_code_used === code) {
      return jsonResponse({ error: "You've already used this code." }, 409);
    }

    const now = new Date();
    const currentBonusUntil = userRow?.referral_bonus_until ? new Date(userRow.referral_bonus_until) : null;
    const base = currentBonusUntil && currentBonusUntil > now ? currentBonusUntil : now;
    const newBonusUntil = new Date(base.getTime() + referral.bonus_days * 24 * 60 * 60 * 1000);

    await supabase
      .from("users")
      .update({
        referral_bonus_until: newBonusUntil.toISOString(),
        referral_code_used: code,
      })
      .eq("id", userId);

    await supabase
      .from("referral_codes")
      .update({ redemption_count: referral.redemption_count + 1 })
      .eq("code", code);

    return jsonResponse({ referral_bonus_until: newBonusUntil.toISOString() });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});
