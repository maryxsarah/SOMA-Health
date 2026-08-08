# Coaching personalization plan — reference doc

## Context
SOMA is a multi-user iOS app (Swift client + Supabase/Deno edge functions). We're upgrading
personalization depth in workout generation, nutrition, and onboarding, inspired by a bespoke
single-user Claude Projects prototype coach — but nothing here hardcodes a specific person. Every
pattern below must generalize off whatever profile/wearable/goal data each user actually has, and
degrade gracefully when that data is missing.

Existing architecture to preserve: a deterministic decision layer (readiness bands, finisher
decisions in `finisherCatalog.ts`, goal work in `goalWork.ts`, injury substitution, weather safety,
volume/RIR guidance) feeding a single Claude Haiku call in `generate-workout-plan/index.ts` that
elaborates into structured JSON blocks. Keep this pattern — deterministic policy, LLM elaborates —
don't hand policy decisions to the LLM.

## Reference material (inspiration, generalize, never hardcode)
- Hard readiness+sleep thresholds with specific actions per band; combined-threshold rule overrides
  individual bands.
- Per-exercise rest period (not just per-block).
- Session-opening reasoning line citing the user's actual numbers, never a canned sentence.
- Forward-looking scheduling (today's choice considers tomorrow's plan).
- Goal-specific rep-range science + a small recurring set of "foundation" exercises per goal.
- Nutrition must use measured BMR when available, never formula-only (RED-S/safety risk otherwise).
- Cycle-phase-aware training/nutrition, opt-in, female users only, four broad phases.
- End-of-session dashboard summary + a compact nutrition hand-off line.

## Verified gaps in this codebase
1. `generate-recommendation/index.ts` `MESSAGES` (~L48-55): one fixed canned string per category,
   never references actual numbers.
2. `generate-workout-plan/index.ts` `buildExerciseSchema` (~L68-91): no per-exercise rest field.
3. `_shared/nutritionTargets.ts`: pure Mifflin-St Jeor formula, no measured-BMR override path.
4. `sexAwareGuidance.ts`: explicitly states no cycle data is collected anywhere in the app.
5. Shaping goals only nudge the LLM loosely via free-text tags (index.ts ~L769-781) — no
   deterministic rep-range/fixture-exercise rule the way `decideFinisher`/`decideGoalWork` work.
6. `buildPrompt` sees `recentLogs` (past 14 days) but nothing about tomorrow's schedule.
7. Onboarding has no measured-BMR field, no cycle opt-in, no "weekly anchor session" concept.

## Guardrails (apply to every phase)
- Never regress deterministic safety logic (injury substitution, pregnancy guidance, weather safety,
  generation limits, goal-work insertion) — read surrounding comments before touching a file; several
  document real past bugs that must not reappear.
- Every new personalization signal must gracefully degrade when a user hasn't provided it.
- No test data or examples using personal numbers — synthetic profiles only.
- Add/extend tests matching the existing `*_test.ts` pattern.
- New DB columns/migrations or onboarding screens: propose the plan and confirm before writing
  migrations against real data.

## Phase status
- [x] Phase 1 — Measured-BMR nutrition override
- [x] Phase 2 — Workout reasoning text, per-exercise rest, forward-looking scheduling
- [x] Phase 3 — Goal-specific rep-range / fixture-exercise engine
- [x] Phase 4 — Weekly anchor-session concept + onboarding
- [x] Phase 5 — Cycle-phase tracking (design first, then implement)
