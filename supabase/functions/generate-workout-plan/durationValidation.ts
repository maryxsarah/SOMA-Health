// generate-workout-plan-specific -- NOT shared with generate-gym-workout,
// whose durations are hand-authored in templates.ts, not LLM-guessed, so
// this bug doesn't apply there (its TemplateExercise doesn't even carry
// rest_seconds). Deterministic per-exercise duration reconciliation,
// pulled out as its own small module, same pattern as planValidation.ts/
// weightValidation.ts.
//
// BUG report: a plan displayed "~47 min total" but actually took 30-35
// min to do. Root cause -- computeTotalDuration (_shared/duration.ts)
// sums duration_minutes fields the LLM assigns to each exercise on its
// own say-so; nothing independently checks that number against what the
// SAME exercise's own sets x rest_seconds actually implies once done for
// real. Fixed here: a deterministic per-exercise estimate from fields the
// model already had to state anyway (sets, rest_seconds), compared
// against its stated duration_minutes -- on meaningful divergence, the
// computed estimate WINS (overwrites duration_minutes). Unlike
// planValidation.ts's duplicate check or weightValidation.ts's ceiling
// check, this never re-prompts the model: sets/rest_seconds are the
// model's own numbers, so the time a real session with those numbers
// actually takes is arithmetic, not something worth spending another AI
// round-trip asking the model to "try again."

/// Rough real-world working-set pace: the actual reps of a strength set
/// take about this long, independent of how many reps are prescribed
/// (a few extra reps at a controlled tempo don't meaningfully change a
/// set's real-world duration the way an extra REST second does).
const WORK_SECONDS_PER_SET = 40;
/// Small fixed per-exercise slack for re-racking weight, moving to the
/// next station, re-reading the instructions, etc. -- not zero, but not
/// padded enough to meaningfully mask an inflated duration_minutes either.
const SETUP_BUFFER_SECONDS = 15;

interface ExerciseWithDuration {
  sets: number;
  rest_seconds: number | null;
  duration_minutes: number;
}

/// One round's worth of one exercise's realistic time: work time per set,
/// plus rest BETWEEN sets (never after the last one -- there's no next
/// set to rest before), plus a small fixed setup/transition buffer.
/// Un-rounded minutes -- rounding happens once, at the total, same as
/// computeTotalDuration's own convention.
export function estimateExerciseMinutes(exercise: { sets: number; rest_seconds: number | null }): number {
  const sets = Math.max(1, exercise.sets);
  const restPerGapSeconds = Math.max(0, exercise.rest_seconds ?? 0);
  const workSeconds = sets * WORK_SECONDS_PER_SET;
  const restSeconds = Math.max(0, sets - 1) * restPerGapSeconds;
  return (workSeconds + restSeconds + SETUP_BUFFER_SECONDS) / 60;
}

/// More than 2 min OR more than 30% of the estimate, whichever is larger
/// -- a small legitimate difference (extra instructional time, a
/// slightly padded number) isn't worth overwriting. The reported bug's
/// gap (~47 min stated vs. ~30-35 min real, on a session built from
/// several exercises) is well past either threshold.
function divergesMeaningfully(statedMinutes: number, estimatedMinutes: number): boolean {
  const tolerance = Math.max(2, estimatedMinutes * 0.3);
  return Math.abs(statedMinutes - estimatedMinutes) > tolerance;
}

/// Reconciles every multi-set exercise INSIDE blocks (the plan's actual
/// working sets) against its own deterministic time estimate, overwriting
/// duration_minutes on meaningful divergence. Deliberately narrow:
/// - Single-set exercises (sets < 2) are left untouched -- the schema's
///   own "use 1 for anything that's just a held stretch or a single
///   timed activity, not part of a multi-round block" comment means the
///   sets x rest formula doesn't describe those, and it also happens to
///   protect buildCoachBlock's hand-built placeholder exercise (always
///   sets: 1) from ever being touched, which matters: the coach's
///   session must stay untouched, never rewritten by anything server-side.
/// - warm_up/cool_down are left untouched for the same "not a multi-set
///   working exercise" reason -- those are typically stretches or a
///   cardio ramp, not the sets x rest work this estimate models.
/// Returns a NEW plan object (does not mutate the input) -- call
/// computeTotalDuration (_shared/duration.ts) on the result afterward,
/// exactly as before this function existed.
export function reconcileExerciseDurations<T extends { blocks: { exercises: ExerciseWithDuration[] }[] }>(plan: T): T {
  return {
    ...plan,
    blocks: plan.blocks.map((block) => ({
      ...block,
      exercises: block.exercises.map((exercise) => {
        if (exercise.sets < 2) return exercise;
        const estimated = estimateExerciseMinutes(exercise);
        if (!divergesMeaningfully(exercise.duration_minutes, estimated)) return exercise;
        return { ...exercise, duration_minutes: Math.round(estimated) };
      }),
    })),
  } as T;
}
