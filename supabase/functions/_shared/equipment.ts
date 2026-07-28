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

/// Common ways people write the same thing. The vision model is constrained
/// to the vocabulary by schema, but the CLIENT also lets users type equipment
/// by hand -- and it does so precisely when recognition failed, i.e. exactly
/// when getting it right matters most. Someone typing "dumbbell", "bench" or
/// "pull up bar" was silently dropped to a bodyweight workout while standing
/// in a fully equipped gym, having just listed its contents.
///
/// Singular/plural and hyphen/space variants are handled generically below;
/// this map is only for genuine synonyms.
const ALIASES: Record<string, string> = {
  "free weights": "dumbbells",
  "hand weights": "dumbbells",
  "bench": "weight bench",
  "flat bench": "weight bench",
  "power rack": "squat rack",
  "rack": "squat rack",
  "chin up bar": "pull-up bar",
  "bar": "barbell",
  "plates": "weight plates",
  "kettle bell": "kettlebells",
  "bands": "resistance bands",
  "exercise bands": "resistance bands",
  "rower": "rowing machine",
  "erg": "rowing machine",
  "exercise bike": "stationary bike",
  "spin bike": "stationary bike",
  "cross trainer": "elliptical",
  "trx": "suspension trainer",
  "skipping rope": "jump rope",
  "mat": "yoga mat",
  "box": "plyo box",
};

/// Collapses punctuation and plural forms so "Pull Up Bar", "pull-up bars"
/// and "pull-up bar" all land on the same key.
function canonical(raw: string): string {
  return raw
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/s\b/g, "");
}

/// Normalizes a caller-supplied list down to known vocabulary entries.
/// Unknown strings are dropped rather than trusted, since nothing downstream
/// can act on a value no template references.
export function normalizeEquipment(input: string[]): Set<string> {
  const byCanonical = new Map<string, string>();
  for (const item of EQUIPMENT_VOCABULARY) byCanonical.set(canonical(item), item);
  for (const [alias, target] of Object.entries(ALIASES)) {
    byCanonical.set(canonical(alias), target);
  }

  const out = new Set<string>();
  for (const raw of input) {
    const match = byCanonical.get(canonical(raw));
    if (match) out.add(match);
  }
  return out;
}
