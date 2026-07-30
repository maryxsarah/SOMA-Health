// DRAFTED, NOT EXPERT-REVIEWED -- thresholds for "exceptionally" high
// readiness, distinct from the ordinary push_hard bar (Whoop 67+ recovery,
// Oura 85+ readiness -- see generate-recommendation/index.ts's
// bandFromWhoop/bandFromOura). Used by generate-workout-plan (gates a more
// aggressive finisher) and generate-recommendation (weights the
// consecutive-training-days rest cap) -- hoisted here so both reference
// the same numbers rather than risking drift between two copies.
export const EXCEPTIONAL_WHOOP_RECOVERY = 90;
export const EXCEPTIONAL_OURA_READINESS = 95;
