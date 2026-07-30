// Shared by generate-workout-plan and generate-gym-workout -- both produce
// the same warm_up/blocks/cool_down shape, and both have free-text
// rest_between_rounds ("60 sec", "90 sec", "2 min", "N/A") that needs the
// same parsing to fold into a session total.

interface ExerciseLike {
  duration_minutes: number;
}
interface BlockLike {
  rounds: number;
  rest_between_rounds: string;
  exercises: ExerciseLike[];
}
interface PlanLike {
  warm_up: ExerciseLike[];
  blocks: BlockLike[];
  cool_down: ExerciseLike[];
}

/// Parses a free-text duration like "60 sec", "90 seconds", "2 min" into
/// minutes. Returns 0 for "N/A" or anything unparseable -- a missing rest
/// period shouldn't crash the total, it just contributes nothing.
export function parseMinutes(text: string): number {
  const match = text.match(/(\d+(?:\.\d+)?)\s*(sec|second|min|minute)/i);
  if (!match) return 0;
  const value = parseFloat(match[1]);
  return /sec/i.test(match[2]) ? value / 60 : value;
}

/// Sums every exercise's duration_minutes across warm_up + blocks (each
/// exercise repeated per round, plus rest between rounds) + cool_down.
/// Rounded to the nearest minute for display.
export function computeTotalDuration(plan: PlanLike): number {
  const sum = (arr: ExerciseLike[]) => arr.reduce((s, e) => s + (e.duration_minutes ?? 0), 0);
  let total = sum(plan.warm_up) + sum(plan.cool_down);
  for (const block of plan.blocks) {
    total += sum(block.exercises) * block.rounds +
      parseMinutes(block.rest_between_rounds) * Math.max(0, block.rounds - 1);
  }
  return Math.round(total);
}
