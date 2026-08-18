-- Personal referral codes ("show + share" scope for now -- rewards for
-- the owner get wired up later by hand). A personal code is an ordinary
-- referral_codes row owned by a user: same redemption path, same
-- bonus_days semantics as the marketing codes (somafirst etc.), which
-- stay ownerless. One personal code per user, generated lazily by the
-- get-referral-code edge function on first open of the referral sheet.
alter table referral_codes add column owner_user_id uuid references users(id) on delete cascade;
create unique index referral_codes_owner_idx on referral_codes (owner_user_id) where owner_user_id is not null;
