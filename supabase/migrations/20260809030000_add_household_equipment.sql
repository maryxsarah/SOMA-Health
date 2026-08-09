-- What the user actually owns to cook with -- a hard input to
-- generate-meal-recommendation (a suggested recipe must never call for
-- equipment outside this set). Collected once at onboarding
-- (KitchenEquipmentQuestionView, always skippable) and editable afterward
-- from ProfileView, same shape as the existing `equipment`/
-- `other_equipment_notes` pair (gym/workout access) -- kept as its own
-- column rather than reusing `equipment` since the two answer unrelated
-- questions.
--
-- `not null default '{}'`, matching the existing `equipment` column
-- (20260721020000) -- the Swift side decodes this as a non-optional
-- [KitchenEquipmentTag], same as `equipment`/[EquipmentTag], so a NULL
-- here would fail to decode the whole profile row rather than reading as
-- "not set". An EMPTY array is exactly the "not set" signal "What can I
-- make?"'s own first-use prompt checks for (see
-- KitchenEquipmentTag.skipDefault for the sane-default-on-skip path).
alter table users add column household_equipment text[] not null default '{}';
alter table users add column other_household_equipment_notes text;
