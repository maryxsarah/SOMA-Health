-- Example code for testing the redemption flow. Add real marketing codes
-- the same way via the Supabase Dashboard's SQL Editor or Table Editor --
-- this table has no client-facing access, so codes must be created
-- server-side (Dashboard) or via a future admin function.
insert into referral_codes (code, bonus_days, max_redemptions)
values ('SOMA14', 14, null)
on conflict (code) do nothing;
