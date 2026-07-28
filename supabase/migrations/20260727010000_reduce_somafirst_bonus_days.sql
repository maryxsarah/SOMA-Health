-- Reduces "somafirst"'s free-access bonus from 3 weeks to 2 weeks
-- (21 -> 14 days). Only affects referral_codes.bonus_days -- future
-- redemptions compute users.referral_bonus_until from this value at
-- redemption time; anyone who already redeemed keeps their existing
-- referral_bonus_until unchanged (future redemptions only, not
-- retroactive, per product decision).

update referral_codes set bonus_days = 14 where code = 'SOMAFIRST';
