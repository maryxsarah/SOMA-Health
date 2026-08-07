-- Pairs with users.pregnancy: lets Soma give trimester-aware guidance
-- instead of the old hard block (see safetyFlags.ts / pregnancyGuidance.ts).
-- Nullable and unconstrained when pregnancy itself isn't set.
alter table users add column pregnancy_week integer check (pregnancy_week is null or (pregnancy_week between 1 and 42));
