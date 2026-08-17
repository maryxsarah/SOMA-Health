// DRAFT -- NOT reviewed by a certified S&C professional. Rough NSCA/ACSM-
// style working-set load bands (fraction of bodyweight) per major lift
// pattern x experience level. Passed into the prompt as guideline RANGES
// the model should stay within, not parsed/clamped from its free-text
// weight_guidance after the fact for MOST exercises -- see the
// TWO-DUMBBELL squat/hinge exception below, where free-text IS now also
// parsed and checked, because the prompt-only approach already failed
// once for exactly that case. Needs expert sign-off before shipping,
// same as templates.ts's own equipment-coverage disclaimer.
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
// BUG report (2026-08-15): a 168cm/60kg woman was prescribed 16-24kg PER
// DUMBBELL (32-48kg total, ~double a sane number) for a TWO-DUMBBELL
// squat. Root cause -- squat_pattern's range above IS a correct TOTAL
// system-load estimate for a single-implement barbell squat, but nothing
// told the model that a two-dumbbell variant splits that total across two
// separate objects it must size independently, let alone that a front-
// loaded/grip-limited two-dumbbell hold safely carries meaningfully LESS
// total load than an equivalent back-loaded barbell in the first place.
// Fixed by twoDumbbellLoadRangeKg below (applied to squat_pattern and
// hinge_pattern, the two patterns this file already documents as
// "bilateral-only" -- see the paragraph above): the prompt now states
// BOTH the derated total and the per-dumbbell number explicitly, in a
// fixed "2xNkg dumbbells" format, and index.ts's plan-validation retry
// (see weightValidation.ts) deterministically re-prompts if the model's
// free-text weight_guidance names a per-dumbbell number over the same
// derated ceiling anyway -- the same "instruction is a request, not a
// guarantee" backstop this codebase already uses for duplicate exercise
// names (planValidation.ts). The TWO_IMPLEMENT_DERATE fraction below is
// still an unreviewed estimate, same standing caveat as everything else
// in this file -- what changed is that a two-dumbbell squat/hinge no
// longer silently reuses the barbell-total number as a per-dumbbell
// figure, which is the specific failure the bug report showed.
//
// NOT fixed here (same latent shape, but out of this bug's reported
// scope and untested against a real report): overhead_press/
// horizontal_press's bilateral ranges are also TOTAL system-load
// estimates, so a "double-dumbbell" bench/shoulder press could in
// principle hit the identical per-implement confusion. Tracked, not
// acted on, until there's a real report to calibrate against -- same
// posture exerciseLibraryMatch_test.ts takes on its own tracked-not-
// fixed note.
//
// SEX-AWARENESS INVESTIGATION (2026-08-15, reported not changed --
// see buildLoadGuidance's own comment below for why): asked whether
// these bodyweight-fraction bands should be sex-specific, or whether
// their width already covers the population difference. Finding: likely
// NOT fully covered for the press/row patterns, more likely fine for
// squat/hinge -- see the full reasoning in buildLoadGuidance's doc
// comment. No band was changed for this.
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

/// Unknown/unrecognized experience always falls back to "moderate" --
/// same normalization buildLoadGuidance and twoDumbbellLoadRangeKg both
/// need, pulled out once so the two can never silently disagree.
function resolveExperienceLevel(experience: string): string {
  return LOAD_FRACTION_OF_BODYWEIGHT.squat_pattern[experience] ? experience : "moderate";
}

/// A two-dumbbell (or two-kettlebell) squat_pattern/hinge_pattern variant
/// splits its load across two separate implements the model must size
/// independently -- see this file's 2026-08-15 BUG report comment up top.
/// This is the single source of truth for that conversion: both
/// buildLoadGuidance's prompt text AND weightValidation.ts's deterministic
/// post-generation ceiling call this same function, so the "guideline" and
/// the "hard ceiling" can never drift apart from each other.
///
/// Derates the barbell-equivalent TOTAL by TWO_IMPLEMENT_DERATE before
/// splitting it across two implements -- a front-loaded (goblet) or
/// side-carried two-dumbbell hold is grip- and stability-limited well
/// below what the same total-system-load barbell number would suggest,
/// not just "half the barbell total, held in two hands instead of one."
/// `knownLifts`, when present for `pattern`, still wins over the
/// population estimate first (same precedence as buildLoadGuidance's own
/// `range` helper) -- a real stated barbell-equivalent number is a better
/// base to derate from than a population guess.
///
/// 0.4 (not, say, 0.5) is deliberate: at 0.5, a moderate/advanced 60kg
/// lifter's per-dumbbell squat ceiling still lands right at/above the
/// reported bug's OWN 16kg floor (30-60kg barbell total x0.5/2 =
/// 7.5-15kg each at moderate, 10.5-18.75kg at advanced) -- too close to
/// the number this fix exists to rule out to credibly call it fixed. At
/// 0.4 every tier for a 60kg lifter lands clearly under that 16kg floor
/// (see loadGuidance_test.ts's regression test), while still producing
/// plausible, real-increment dumbbell numbers (roughly 4-15kg each
/// newbie-through-advanced) rather than an implausibly light one.
const TWO_IMPLEMENT_DERATE = 0.4;

export interface TwoDumbbellLoadRange {
  totalLowKg: number;
  totalHighKg: number;
  eachLowKg: number;
  eachHighKg: number;
}

export function twoDumbbellLoadRangeKg(
  pattern: "squat_pattern" | "hinge_pattern",
  weightKg: number,
  experience: string,
  knownLifts?: Record<string, number> | null,
): TwoDumbbellLoadRange {
  const known = knownLifts?.[pattern];
  let barbellLowKg: number;
  let barbellHighKg: number;
  if (typeof known === "number" && known > 0) {
    barbellLowKg = known * 0.9;
    barbellHighKg = known * 1.1;
  } else {
    const level = resolveExperienceLevel(experience);
    const [lowFrac, highFrac] = loadFractionRange(pattern, level);
    barbellLowKg = lowFrac * weightKg;
    barbellHighKg = highFrac * weightKg;
  }
  const totalLowKg = barbellLowKg * TWO_IMPLEMENT_DERATE;
  const totalHighKg = barbellHighKg * TWO_IMPLEMENT_DERATE;
  return { totalLowKg, totalHighKg, eachLowKg: totalLowKg / 2, eachHighKg: totalHighKg / 2 };
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
///
/// SEX-AWARENESS INVESTIGATION (2026-08-15): asked whether
/// LOAD_FRACTION_OF_BODYWEIGHT should carry separate bands per sex, or
/// whether the existing ranges are already wide enough to cover the
/// population difference. Finding, not yet acted on:
/// - squat_pattern/hinge_pattern (lower body): published strength-to-
///   bodyweight research generally shows a SMALLER sex gap for lower-body
///   patterns than upper-body ones -- relative leg strength is fairly
///   close across sexes once expressed as a fraction of bodyweight. The
///   current bands are wide (e.g. moderate squat 0.5-1.0x) relative to
///   that gap, so they're plausibly wide enough already.
/// - overhead_press/horizontal_press (upper-body pushing): the
///   documented sex gap in relative (bodyweight-normalized) pushing
///   strength is larger than for lower body, and these bands are
///   narrower in absolute terms (e.g. moderate overhead press
///   0.25-0.45x) -- a population female newbie's realistic starting
///   point plausibly sits at or below today's newbie floor for these
///   two patterns specifically, more likely than the squat/hinge bands
///   understating a real gap.
/// - row_pull: probably an intermediate case, closer to the press
///   patterns' gap than to squat/hinge's.
/// This is a plausibility read, not a verified number -- explicitly NOT
/// acted on here pending an actual product/expert decision, per the
/// request that triggered this comment. If sex-awareness is added later,
/// overhead_press/horizontal_press (and maybe row_pull) are the patterns
/// most likely to actually need it; squat_pattern/hinge_pattern are the
/// weaker case for it.
export function buildLoadGuidance(
  weightKg: number | null,
  experience: string,
  knownLifts?: Record<string, number> | null,
): string {
  if (weightKg === null) {
    return "The user's bodyweight isn't on file -- for any barbell/dumbbell/kettlebell working set, use conservative, experience-appropriate language ('start light and build') instead of a specific number.";
  }
  const level = resolveExperienceLevel(experience);
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
  const twoDumbbellLine = (pattern: "squat_pattern" | "hinge_pattern", label: string) => {
    const { totalLowKg, totalHighKg, eachLowKg, eachHighKg } = twoDumbbellLoadRangeKg(pattern, weightKg, experience, knownLifts);
    return `${label} with TWO dumbbells/kettlebells (one in each hand, e.g. "Dumbbell Squat", "Dumbbell Romanian Deadlift") -- TOTAL ${
      totalLowKg.toFixed(0)
    }-${totalHighKg.toFixed(0)}kg, i.e. ${eachLowKg.toFixed(0)}-${eachHighKg.toFixed(0)}kg EACH dumbbell`;
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
CRITICAL -- TWO-DUMBBELL SQUAT/HINGE ARE NOT THE BARBELL NUMBER PER DUMBBELL: the squat/hinge ranges above are TOTAL system-load estimates for a single-implement barbell movement. A TWO-DUMBBELL variant splits that load across two separate objects AND safely carries meaningfully less total load than the barbell estimate (grip and front/side-carry stability limit it well below a back-loaded bar) -- ${
    twoDumbbellLine("squat_pattern", "Squat")
  }; ${
    twoDumbbellLine("hinge_pattern", "Hinge/deadlift-style")
  }. State BOTH numbers in weight_guidance using the exact format "2xNkg dumbbells" (e.g. "2x8kg dumbbells") so it's unambiguous -- NEVER write the barbell-equivalent total (or a number anywhere near it) as if it were the weight of ONE dumbbell; that roughly doubles the real load, exactly like the unilateral mistake above but for a different reason.
Also: round every prescribed weight to a size that's actually sold/available -- dumbbells and kettlebells come in fixed increments (commonly 2/2.5kg steps at the light end, e.g. 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 24kg), never an arbitrary decimal like "13.5kg".`;
}
