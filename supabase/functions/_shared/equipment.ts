// Canonical equipment vocabulary.
//
// Single source of truth shared by analyze-gym-photo (which constrains the
// vision model's output to exactly these values via a JSON-schema `enum`)
// and templates.ts (whose `requiredEquipment` entries are drawn from the
// same list).
//
// Why a closed vocabulary: the previous version asked the model for free
// text and then matched it against template requirements with exact string
// comparison. "dumbbell", "free weights", and "adjustable dumbbells" all
// silently missed "dumbbells", dropping the user to a bodyweight workout
// while standing in a fully equipped gym -- with no error to notice. With a
// strict enum the model must map what it sees onto a known value, so the
// match is guaranteed by construction rather than by luck of phrasing.
//
// Adding a value here is safe. REMOVING or RENAMING one is not: template
// `requiredEquipment` entries would stop matching, silently. Grep
// templates.ts before changing an existing entry.

export const EQUIPMENT_VOCABULARY = [
  // free weights
  "barbell",
  "weight plates",
  "dumbbells",
  "kettlebells",
  "weight bench",
  "squat rack",
  // machines
  "cable machine",
  "smith machine",
  "leg press",
  "chest press machine",
  "lat pulldown",
  // cardio
  "treadmill",
  "stationary bike",
  "rowing machine",
  "elliptical",
  // bodyweight & accessories
  "pull-up bar",
  "dip bars",
  "resistance bands",
  "suspension trainer",
  "medicine ball",
  "jump rope",
  "plyo box",
  "battle ropes",
  "yoga mat",
  "foam roller",
] as const;

export type EquipmentItem = typeof EQUIPMENT_VOCABULARY[number];

/// Normalizes a caller-supplied list down to known vocabulary entries.
/// The client lets users edit the detected list before confirming, so
/// unknown strings can still arrive here -- they are dropped rather than
/// trusted, since nothing downstream can act on a value no template
/// references.
export function normalizeEquipment(input: string[]): Set<string> {
  const known = new Set<string>(EQUIPMENT_VOCABULARY);
  const out = new Set<string>();
  for (const raw of input) {
    const value = raw.toLowerCase().trim();
    if (known.has(value)) out.add(value);
  }
  return out;
}
