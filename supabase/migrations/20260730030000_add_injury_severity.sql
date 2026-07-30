-- Severity per noted injury tag, added as a PARALLEL column rather than
-- reshaping the existing injury_tags text[] -- that column is read directly
-- by generate-recommendation, generate-workout-plan, and safetyFlags.ts
-- today; reshaping it would break all three decoders at once for no real
-- gain. Keyed by InjuryTag rawValue -> 'mild'|'moderate'|'severe'. A tag
-- present in injury_tags with no entry here defaults to 'moderate'
-- treatment (never silently to "no injury") -- see contraindications.ts.

alter table users add column injury_severity jsonb not null default '{}'::jsonb;
