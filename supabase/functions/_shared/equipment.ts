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

/// "bar"/"rack"/"plates" are real synonyms but also common everyday words
/// (protein bar, spice rack) -- masked out before the single-word alias pass.
const AMBIGUOUS_ALIAS_MASK_PHRASES = [
  "pull up bar", "chin up bar", "dip bar",
  "protein bar", "candy bar", "granola bar", "chocolate bar", "cereal bar", "snack bar", "energy bar",
  "spice rack", "shoe rack", "coat rack", "towel rack", "wine rack", "drying rack", "bike rack", "roof rack",
  "paper plate", "license plate", "hot plate", "number plate",
];

/// Scans a full free-text sentence for known vocabulary/alias PHRASES as
/// substrings, rather than expecting each array element to already be a
/// clean discrete term the way normalizeEquipment does (that function
/// exists for the vision model's own already-itemized output). Built for
/// UserRow.other_equipment_notes -- generate-workout-plan's onboarding
/// "what else do you have access to?" free text, e.g. "dumbbells, a
/// workout bench, a yoga mat and a treadmill" -- which was previously
/// captured and saved but never read by any generation path at all, so
/// specific gear the user actually typed out was silently ignored. Same
/// coarse substring approach already used elsewhere in this codebase for
/// keyword matching (e.g. contraindications.ts).
export function parseFreeTextEquipment(text: string): Set<EquipmentItem> {
  const canonicalText = ` ${canonical(text)} `;
  const out = new Set<EquipmentItem>();
  for (const item of EQUIPMENT_VOCABULARY) {
    if (canonicalText.includes(` ${canonical(item)} `)) out.add(item);
  }
  // Multi-word aliases are inherently unambiguous ("chin up bar" can't be
  // mistaken for "protein bar") -- scan them against the real text, before
  // masking, since some (like "chin up bar") are themselves on the
  // ambiguous-mask list below and would otherwise be erased before their
  // own lookup runs.
  for (const [alias, target] of Object.entries(ALIASES)) {
    if (!canonical(alias).includes(" ")) continue;
    if (canonicalText.includes(` ${canonical(alias)} `)) out.add(target as EquipmentItem);
  }
  // Single-word aliases (bar/rack/plates/...) only scan the masked text --
  // see AMBIGUOUS_ALIAS_MASK_PHRASES.
  let maskedForAliases = canonicalText;
  for (const phrase of AMBIGUOUS_ALIAS_MASK_PHRASES) {
    maskedForAliases = maskedForAliases.split(` ${canonical(phrase)} `).join(" ");
  }
  for (const [alias, target] of Object.entries(ALIASES)) {
    if (canonical(alias).includes(" ")) continue;
    if (maskedForAliases.includes(` ${canonical(alias)} `)) out.add(target as EquipmentItem);
  }
  return out;
}

/// Maps the item-level EQUIPMENT_VOCABULARY (dumbbells, treadmill, yoga
/// mat, ...) onto exercise_library's own equipment column values (barbell,
/// dumbbell, kettlebells, cable, machine, medicine ball, bands, body
/// only) -- two different closed vocabularies serving different purposes
/// (one is what a user/vision-model names real-world gear, the other is
/// what exercise_library actually filters on), so this is the bridge
/// between them. Items with no real filtering equivalent (a weight bench
/// is a supporting prop, not an exercise_library equipment value) are
/// simply omitted -- they're still accepted input, they just don't
/// narrow anything on their own.
const VOCABULARY_TO_LIBRARY_EQUIPMENT: Partial<Record<EquipmentItem, string>> = {
  "barbell": "barbell",
  "weight plates": "barbell",
  "squat rack": "barbell",
  "dumbbells": "dumbbell",
  "kettlebells": "kettlebells",
  "cable machine": "cable",
  "lat pulldown": "cable",
  "smith machine": "machine",
  "leg press": "machine",
  "chest press machine": "machine",
  "treadmill": "machine",
  "stationary bike": "machine",
  "rowing machine": "machine",
  "elliptical": "machine",
  "resistance bands": "bands",
  "medicine ball": "medicine ball",
  "pull-up bar": "body only",
  "dip bars": "body only",
  "suspension trainer": "body only",
  "plyo box": "body only",
  "jump rope": "body only",
  "yoga mat": "body only",
  "foam roller": "body only",
};

/// True for equipment items that unlock genuine cardio-category work
/// (treadmill, bike, rower, elliptical, jump rope) -- see
/// exerciseLibraryMatch.ts's cardio-candidate merge, which otherwise never
/// runs for a non-cardio body-part day even when the user owns exactly
/// this kind of equipment (the original gap behind "told Soma I have a
/// treadmill, but warm-up never suggested one").
const CARDIO_UNLOCKING_ITEMS: ReadonlySet<EquipmentItem> = new Set([
  "treadmill", "stationary bike", "rowing machine", "elliptical", "jump rope",
]);

export interface FreeTextEquipmentResolution {
  /// Values to union into the candidate filter for every tier.
  libraryEquipment: string[];
  /// Cardio-only items -- kept separate since they share the "machine" value
  /// with strength machines; only apply to the cardio query tier.
  cardioLibraryEquipment: string[];
  /// True if anything parsed out of the free text should unlock cardio
  /// candidates regardless of today's body-part focus.
  unlocksCardio: boolean;
}

/// The single entry point generate-workout-plan actually calls: parses
/// free text, maps to real exercise_library equipment values, and flags
/// whether cardio should be unlocked -- all in one deterministic pass.
export function resolveFreeTextEquipment(text: string | null | undefined): FreeTextEquipmentResolution {
  if (!text || text.trim().length === 0) return { libraryEquipment: [], cardioLibraryEquipment: [], unlocksCardio: false };
  const items = parseFreeTextEquipment(text);
  const libraryEquipment = new Set<string>();
  const cardioLibraryEquipment = new Set<string>();
  let unlocksCardio = false;
  for (const item of items) {
    const mapped = VOCABULARY_TO_LIBRARY_EQUIPMENT[item];
    const isCardioOnly = CARDIO_UNLOCKING_ITEMS.has(item);
    if (mapped) (isCardioOnly ? cardioLibraryEquipment : libraryEquipment).add(mapped);
    if (isCardioOnly) unlocksCardio = true;
  }
  return { libraryEquipment: Array.from(libraryEquipment), cardioLibraryEquipment: Array.from(cardioLibraryEquipment), unlocksCardio };
}

/// Unions any number of resolutions into one -- used to combine the
/// free-text other_equipment_notes resolution with the structured
/// gym-equipment-catalog resolution (see gymEquipmentCatalog.ts's
/// resolveGymEquipmentItems), so every downstream consumer (candidate
/// filtering, the finisher's cardio check) sees a single merged signal
/// instead of having to remember to check both sources separately.
export function mergeEquipmentResolutions(...resolutions: FreeTextEquipmentResolution[]): FreeTextEquipmentResolution {
  const libraryEquipment = new Set<string>();
  const cardioLibraryEquipment = new Set<string>();
  let unlocksCardio = false;
  for (const resolution of resolutions) {
    for (const value of resolution.libraryEquipment) libraryEquipment.add(value);
    for (const value of resolution.cardioLibraryEquipment) cardioLibraryEquipment.add(value);
    unlocksCardio = unlocksCardio || resolution.unlocksCardio;
  }
  return { libraryEquipment: Array.from(libraryEquipment), cardioLibraryEquipment: Array.from(cardioLibraryEquipment), unlocksCardio };
}
