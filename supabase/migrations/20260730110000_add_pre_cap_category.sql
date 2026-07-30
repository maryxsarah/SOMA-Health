-- The uncapped recovery-band category, alongside the (possibly capped)
-- `category` column -- lets the client offer "a standard workout anyway"
-- override without re-deriving the recovery band itself. Nullable: rows
-- written before this column existed have no uncapped value on record.

alter table daily_recommendation
  add column pre_cap_category text check (pre_cap_category in ('rest', 'light', 'moderate', 'push_hard'));
