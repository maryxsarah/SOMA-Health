-- Frequency-cap bookkeeping for the exit-intent win-back paywall offer
-- (the "paywall_exit_offer" Superwall placement, registered from
-- HomeView/ProfileView's onDismiss handler on a declined view_premium/
-- detail_access paywall). Mirrors referral_bonus_until's existing
-- server-as-source-of-truth / client-cache pattern (AppState.
-- refreshReferralBonus / SupabaseClient.fetchReferralBonusUntil) rather
-- than inventing a new one -- the client reads this once per relevant
-- screen appearance and caches it, the same shape as the referral bonus.
--
-- NOT a security boundary, same trust model as users.subscription_tier
-- (see SupabaseClient.updateSubscriptionTier's own comment) -- a client
-- that lied about this would only ever see the win-back offer more
-- often, not gain entitlement or a real discount it isn't otherwise
-- eligible for (the discount itself is authorized server-side by
-- sign-promotional-offer, independent of this column).
--
-- Additive, nullable, no backfill -- null means "never shown."
alter table users
  add column exit_offer_shown_at timestamptz;
