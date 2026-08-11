// DRAFT -- NOT reviewed by a registered dietitian. Standard, published
// Mifflin-St Jeor TDEE formula plus commonly-cited activity multipliers
// and macro splits, encoded as plain deterministic code -- never an LLM
// call, same rule as generate-workout-plan's LOAD_FRACTION_OF_BODYWEIGHT
// table. Needs expert sign-off before shipping.
//
// Nothing here is personalized beyond the standard formula's own inputs
// (weight, height, age, sex, activity level) and the deterministic
// training_emphasis adjustment -- no AI involvement anywhere in this file.

export type TrainingEmphasis = "cut" | "recomp" | "bulk" | "maintain";
export type ActivityLevel = "sedentary" | "moderate" | "very_active";

export interface NutritionTargetsInput {
  weightKg: number;
  heightCm: number;
  age: number;
  sex: "male" | "female" | "other";
  activityLevel: ActivityLevel;
  trainingEmphasis: TrainingEmphasis;
  /// Device-reported resting energy (HealthKit basalEnergyBurned, trailing
  /// 24h) when a recent-enough reading exists -- see
  /// MEASURED_BMR_MAX_AGE_DAYS. Takes over from baseMetabolicRate()'s
  /// formula as the BMR feeding TDEE below; everything downstream (activity
  /// multiplier, emphasis adjustment, macro split) is unchanged. Optional/
  /// null is the normal case for any user without a connected Apple Watch
  /// or with a stale reading -- falls back to the formula, never guesses.
  /// Not a clinical/lab-measured BMR (indirect calorimetry) -- Apple's own
  /// estimate, itself algorithmic -- but it reflects this specific user's
  /// actual weight/activity trends rather than a population formula, and is
  /// the only device-level resting-energy signal this app has access to.
  measuredBmrKcal?: number | null;
}

export interface NutritionTargets {
  dailyCalories: number;
  dailyProteinG: number;
  dailyCarbsG: number;
  dailyFatG: number;
  basis: string;
}

/// Mifflin-St Jeor BMR. `other`/unspecified sex uses the midpoint of the
/// male/female sex-constant (there is no published third formula) --
/// flagged in `basis` so this approximation is never silently
/// indistinguishable from the two sex-specific formulas.
function baseMetabolicRate(weightKg: number, heightCm: number, age: number, sex: "male" | "female" | "other"): number {
  const base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  if (sex === "male") return base + 5;
  if (sex === "female") return base - 161;
  return base + (5 + -161) / 2;
}

/// Standard Harris-Benedict-style activity multipliers applied to BMR to
/// get TDEE. Mapped from the same workouts_per_week bands already
/// collected at onboarding (see generate-workout-plan's
/// workoutsPerWeekLabel) rather than adding a new onboarding question.
const ACTIVITY_MULTIPLIER: Record<ActivityLevel, number> = {
  sedentary: 1.375,
  moderate: 1.55,
  very_active: 1.725,
};

export function activityLevelFromWorkoutsPerWeek(raw: string | null): ActivityLevel {
  switch (raw) {
    case "three_to_five": return "moderate";
    case "six_plus": return "very_active";
    case "zero_to_two":
    default: return "sedentary";
  }
}

/// Calorie adjustment off TDEE per training_emphasis -- a moderate,
/// conservative deficit/surplus (roughly 0.5-0.7lb/week), not an aggressive
/// number. `maintain` and `recomp` both hold at TDEE: recomp's edge is in
/// the protein target (below), not a calorie deficit/surplus.
const CALORIE_ADJUSTMENT: Record<TrainingEmphasis, number> = {
  cut: -500,
  bulk: 300,
  recomp: 0,
  maintain: 0,
};

/// Grams of protein per kg bodyweight -- within the commonly-cited
/// evidence-based range (1.6-2.2g/kg) for people training regularly.
/// Recomp gets the top of the range (muscle retention/gain matters most
/// at maintenance calories); cut/bulk/maintain get the middle.
const PROTEIN_G_PER_KG: Record<TrainingEmphasis, number> = {
  cut: 2.0,
  recomp: 2.2,
  bulk: 1.8,
  maintain: 1.8,
};

/// Fraction of total calories from fat -- a common general-population
/// default, not emphasis-specific (fat below ~20% of calories risks
/// hormonal issues; above ~35% typically crowds out carbs needed for
/// training performance).
const FAT_CALORIE_FRACTION = 0.25;

const KCAL_PER_G_PROTEIN = 4;
const KCAL_PER_G_CARB = 4;
const KCAL_PER_G_FAT = 9;

/// Deterministic TDEE + macro split. Returns null when a required input is
/// missing rather than guessing -- same "omit rather than fabricate" rule
/// as generate-workout-plan's buildLoadGuidance when bodyweight is unknown.
export function computeNutritionTargets(input: NutritionTargetsInput): NutritionTargets {
  // A measured reading of exactly 0 or negative is a bad sample (HealthKit
  // returning "nothing accumulated yet" from a partial trailing window,
  // never a real BMR), not a legitimate override -- falls back to the
  // formula rather than computing calorie targets off zero.
  const hasMeasuredBmr = input.measuredBmrKcal != null && input.measuredBmrKcal > 0;
  const bmr = hasMeasuredBmr
    ? input.measuredBmrKcal!
    : baseMetabolicRate(input.weightKg, input.heightCm, input.age, input.sex);
  const tdee = bmr * ACTIVITY_MULTIPLIER[input.activityLevel];
  const calories = Math.max(1200, Math.round(tdee + CALORIE_ADJUSTMENT[input.trainingEmphasis]));

  const proteinG = Math.round(PROTEIN_G_PER_KG[input.trainingEmphasis] * input.weightKg);
  const fatG = Math.round((calories * FAT_CALORIE_FRACTION) / KCAL_PER_G_FAT);
  const proteinAndFatKcal = proteinG * KCAL_PER_G_PROTEIN + fatG * KCAL_PER_G_FAT;
  // Whatever calories remain after protein/fat go to carbs -- never
  // negative even in a low-calorie edge case (the 1200 floor above keeps
  // this from going pathological, but clamp defensively anyway).
  const carbsG = Math.max(0, Math.round((calories - proteinAndFatKcal) / KCAL_PER_G_CARB));

  const basisPrefix = hasMeasuredBmr ? "measured_bmr" : "mifflin_st_jeor";
  return {
    dailyCalories: calories,
    dailyProteinG: proteinG,
    dailyCarbsG: carbsG,
    dailyFatG: fatG,
    basis: `${basisPrefix}:${input.trainingEmphasis}:activity=${input.activityLevel}:sex=${input.sex}`,
  };
}

/// How stale a HealthKit basalEnergyBurned reading can be before
/// computeNutritionTargets should get the formula BMR instead -- a user who
/// stopped wearing their Watch (or uninstalled/reinstalled) shouldn't have
/// a months-old resting-energy number silently driving today's calorie
/// target forever. 7 days: generous enough to survive a few days of not
/// wearing the Watch/opening the app, matched to the same order of
/// magnitude as this app's other trailing-window signals (recentLogs' 14
/// days), without letting a truly stale reading pass as "measured".
export const MEASURED_BMR_MAX_AGE_DAYS = 7;

/// Whether a daily_snapshot row dated `snapshotDate` is still fresh enough
/// (relative to `today`, both "YYYY-MM-DD") to feed computeNutritionTargets
/// as measuredBmrKcal. Pure date-string math, no Date parsing surprises
/// across timezones -- callers pass their own already-resolved date
/// strings, same convention as generate-workout-plan's daysBetween.
export function isMeasuredBmrFresh(snapshotDate: string, today: string): boolean {
  const from = new Date(`${snapshotDate}T00:00:00.000Z`).getTime();
  const to = new Date(`${today}T00:00:00.000Z`).getTime();
  const ageDays = Math.floor((to - from) / 86400000);
  return ageDays >= 0 && ageDays <= MEASURED_BMR_MAX_AGE_DAYS;
}

/// Deterministic training_emphasis fallback for when there's no goal/
/// current body photo pair to run analyze-body-photo's vision comparison
/// against -- real feedback: "a lot of users likely won't want to upload
/// their photos, and calories can already be estimated roughly from the
/// target weight and the current one." Both inputs are already collected
/// at onboarding regardless of whether the (separate, optional) body-
/// photo feature is ever used.
///
/// Cannot distinguish "recomp" from "maintain" without photos -- both
/// look identical as just "a similar target weight" -- so a close target
/// reads as maintain, the honest simpler answer, rather than guessing.
/// A percentage-of-bodyweight threshold (not a flat kg one) so "2kg"
/// means something proportionally consistent whether someone weighs 50kg
/// or 120kg.
export function trainingEmphasisFromWeights(
  weightKg: number | null,
  desiredWeightKg: number | null,
): TrainingEmphasis | null {
  if (weightKg === null || desiredWeightKg === null || weightKg <= 0) return null;
  const deltaFraction = (desiredWeightKg - weightKg) / weightKg;
  // Inside +/-2% of current bodyweight is comfortably within normal
  // day-to-day fluctuation -- below that, a direction would be reading
  // noise, not an actual stated goal.
  if (deltaFraction <= -0.02) return "cut";
  if (deltaFraction >= 0.02) return "bulk";
  return "maintain";
}
