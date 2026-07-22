-- "somafirst" -- entered on the paywall, grants 3 weeks (21 days) of free
-- access with no payment method required. redeem-referral-code already
-- normalizes input to uppercase before lookup.
insert into referral_codes (code, bonus_days, max_redemptions)
values ('SOMAFIRST', 21, null)
on conflict (code) do nothing;
