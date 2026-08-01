-- Adds 'addon_suggestion' as a valid ai_generation_log.source so
-- suggest-workout-addons (previously deliberately uncapped -- cheap
-- Haiku model, tiny prompts) can get a generous flat daily cap for
-- defense-in-depth, reusing the same log table generate-workout-plan
-- and generate-gym-workout already write to.
alter table ai_generation_log drop constraint ai_generation_log_source_check;
alter table ai_generation_log add constraint ai_generation_log_source_check
  check (source in ('suggestion', 'gym_photo', 'addon_suggestion'));
