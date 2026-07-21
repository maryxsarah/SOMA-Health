-- Referral codes grant bonus free access to the recommendation detail
-- view (RecommendationDetailView), independent of and additive to
-- Apple's StoreKit subscription/trial. A user can redeem a code before
-- ever starting the paid $4.99/mo subscription; once the bonus period
-- ends they still have their full untouched 14-day Apple trial available
-- when they do subscribe.

alter table users
  add column referral_bonus_until timestamptz,
  add column referral_code_used text;

create table referral_codes (
  code text primary key,
  bonus_days integer not null default 14,
  max_redemptions integer,  -- null = unlimited
  redemption_count integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- RLS enabled with NO client-facing policies -- codes are validated and
-- redeemed only via the redeem-referral-code Edge Function's service-role
-- client, same pattern as wearable_tokens. The app never reads this table
-- directly; it only ever sees the resulting users.referral_bonus_until.
alter table referral_codes enable row level security;
