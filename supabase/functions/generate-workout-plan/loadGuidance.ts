// DRAFT -- NOT reviewed by a certified S&C professional. Rough NSCA/ACSM-
// style working-set load bands (fraction of bodyweight) per major lift
// pattern x experience level. Passed into the prompt as guideline RANGES
// the model should stay within, not parsed/clamped from its free-text
// weight_guidance after the fact (that parsing would be unreliable).
// Needs expert sign-off before shipping, same as templates.ts's own
// equipment-coverage disclaimer.
// BUG report: a 60kg, 168cm woman was prescribed 16-18kg PER kettlebell
// for an alternating (unilateral) kettlebell row. Root cause -- this table
// only ever had ONE band per pattern, meant as the TOTAL working-set load
// for a bilateral (both sides loaded together, e.g. a barbell) movement.
// For row_pull/overhead_press/horizontal_press specifically, that same
// number was being applied directly as the weight of a SINGLE dumbbell/
// kettlebell in a unilateral (one side at a time) variant -- roughly
// double what's actually appropriate, since unilateral work also demands
// more core/stability control that limits safe load well beyond a simple
// 50/50 split of the bilateral number. squat_pattern/hinge_pattern are
// left bilateral-only: a goblet squat or single-kettlebell deadlift still
// loads the body symmetrically even holding one implement, so the
// bilateral-total framing already applies correctly there.
// BUG report: a self-described non-powerlifter ("has nothing to do with
// powerlifting") was prescribed 125-135kg for a barbell deadlift -- near
// the OLD "advanced" ceiling of 1.75x bodyweight, which is genuinely
// elite/competitive-lifter territory for a working set, not just what
// "several years of consistent training" implies. A simple 3-tier
// newbie/moderate/advanced self-report has no way to distinguish a
// serious recreational lifter from an actual competitor, so the
// "advanced" ceiling was recalibrated down across every bilateral
// pattern to a more defensible default -- still meaningfully heavier
// than "moderate", just not assuming elite numbers by default. A user
// who genuinely knows their own working weight can now say so directly
// (see buildLoadGuidance's knownLifts param) and that real number always
// wins over this population-level estimate.
const LOAD_FRACTION_OF_BODYWEIGHT: Record<string, Record<string, [number, number]>> = {
  squat_pattern: { newbie: [0.3, 0.6], moderate: [0.5, 1.0], advanced: [0.7, 1.25] },
  hinge_pattern: { newbie: [0.4, 0.7], moderate: [0.6, 1.1], advanced: [0.8, 1.4] },
  overhead_press: { newbie: [0.15, 0.3], moderate: [0.25, 0.45], advanced: [0.32, 0.55] },
  horizontal_press: { newbie: [0.25, 0.5], moderate: [0.4, 0.7], advanced: [0.5, 0.9] },
  row_pull: { newbie: [0.2, 0.4], moderate: [0.35, 0.6], advanced: [0.45, 0.75] },
  // Per-implement weight for a ONE-ARM/ONE-SIDE-AT-A-TIME variant (e.g.
  // "Alternating Kettlebell Row", "One-Arm Dumbbell Row", "Single-Arm
  // Overhead Press", "One-Arm Floor Press") -- NOT half of the bilateral
  // band above, deliberately lower given the added stability demand.
  unilateral_overhead_press: { newbie: [0.06, 0.12], moderate: [0.10, 0.18], advanced: [0.15, 0.25] },
  unilateral_horizontal_press: { newbie: [0.10, 0.18], moderate: [0.15, 0.27], advanced: [0.22, 0.38] },
  unilateral_row_pull: { newbie: [0.08, 0.15], moderate: [0.13, 0.22], advanced: [0.20, 0.32] },
};

/// Exposed for tests -- the raw fraction bands themselves, not just the
/// formatted prompt text.
export function loadFractionRange(pattern: string, level: string): [number, number] {
  return LOAD_FRACTION_OF_BODYWEIGHT[pattern]?.[level] ?? LOAD_FRACTION_OF_BODYWEIGHT[pattern].moderate;
}

/// Guideline load ranges for today's experience level, as a prompt-ready
/// paragraph -- omitted entirely when bodyweight is unknown rather than
/// guessing a number.
///
/// `knownLifts` is optional, per-pattern real working weights the user
/// stated themselves (Profile's "your current lifts" section, keyed by
/// the same 5 bilateral pattern names as LOAD_FRACTION_OF_BODYWEIGHT
/// above) -- when present for a pattern, it always replaces the
/// population-level bodyweight-ratio estimate for THAT pattern, since an
/// actual number beats any estimate. Unilateral variants have no
/// equivalent -- nobody tracks a "one-arm dumbbell row max" -- so those
/// always stay population-based.
export function buildLoadGuidance(
  weightKg: number | null,
  experience: string,
  knownLifts?: Record<string, number> | null,
): string {
  if (weightKg === null) {
    return "The user's bodyweight isn't on file -- for any barbell/dumbbell/kettlebell working set, use conservative, experience-appropriate language ('start light and build') instead of a specific number.";
  }
  const level = LOAD_FRACTION_OF_BODYWEIGHT.squat_pattern[experience] ? experience : "moderate";
  const range = (pattern: string) => {
    const known = knownLifts?.[pattern];
    if (typeof known === "number" && known > 0) {
      // A real stated working weight, not an estimate -- +/-10% band
      // around it rather than a bare single number, same "a range, not a
      // strict ceiling" framing as the population estimate below.
      const low = known * 0.9;
      const high = known * 1.1;
      return `${low.toFixed(0)}-${high.toFixed(0)}kg (the user told us this directly -- use it as-is, do not second-guess it against bodyweight)`;
    }
    const [low, high] = loadFractionRange(pattern, level);
    return `${(low * weightKg).toFixed(0)}-${(high * weightKg).toFixed(0)}kg`;
  };
  return `The user weighs ${weightKg}kg, ${experience} experience. For any working set targeting these patterns, keep weight_guidance's suggested load within these guideline ranges once warmed up (not a strict per-rep ceiling, use professional judgment for warm-ups): squat pattern ${
    range("squat_pattern")
  }; hinge pattern (deadlift-style) ${range("hinge_pattern")}; overhead press, BOTH ARMS TOGETHER (e.g. barbell/double-dumbbell press) ${
    range("overhead_press")
  }; horizontal press, BOTH ARMS TOGETHER (bench/push-up-with-added-load) ${
    range("horizontal_press")
  }; row/pull, BOTH ARMS/SIDES TOGETHER (e.g. barbell row, seated cable row) ${range("row_pull")}.
CRITICAL -- UNILATERAL vs BILATERAL: the ranges above are for BILATERAL movements (both arms/sides loaded together). For a UNILATERAL variant of the SAME pattern -- one arm/side at a time, e.g. "Alternating Kettlebell Row", "One-Arm Dumbbell Row", "Single-Arm Dumbbell Press", "One-Arm Floor Press" -- use these separate, deliberately lighter PER-IMPLEMENT ranges instead (this is the weight of the ONE dumbbell/kettlebell being used, not half of the bilateral number above): unilateral overhead press ${
    range("unilateral_overhead_press")
  }; unilateral horizontal press ${range("unilateral_horizontal_press")}; unilateral row/pull ${
    range("unilateral_row_pull")
  }. Using the bilateral number for a unilateral movement prescribes roughly double the appropriate load -- always check whether an exercise is unilateral before picking a number.
Also: round every prescribed weight to a size that's actually sold/available -- dumbbells and kettlebells come in fixed increments (commonly 2/2.5kg steps at the light end, e.g. 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 24kg), never an arbitrary decimal like "13.5kg".`;
}
