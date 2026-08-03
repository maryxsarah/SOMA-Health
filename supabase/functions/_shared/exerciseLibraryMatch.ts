import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// DRAFTED, NOT EXPERT-REVIEWED -- same standing caveat as
// contraindications.ts/LOAD_FRACTION_OF_BODYWEIGHT/volumeLandmarks.ts.
//
// Guarantees every exercise generate-workout-plan can possibly name has
// real, correctly matched media (Free Exercise DB, The Unlicense / public
// domain -- see exercise_library's own migration comment) by constraining
// the LLM's `name` field to a CLOSED vocabulary via a JSON-schema enum,
// same "deterministic vocabulary, never left to free text" pattern this
// codebase already uses for equipment/goal tags. The alternative (fuzzy-
// matching a freely-generated name against the library after the fact)
// risks exactly the wrong-match failure mode the feature exists to avoid.
//
// Deliberately scoped to a REQUEST-SCOPED candidate list, not the full
// ~870-exercise library -- passing all 870 names in every schema would add
// several thousand tokens of fixed overhead to every single generation,
// which runs directly against this app's own "avoid an AI cost spike"
// goal for this feature. Filtering by today's actual body part + equipment
// keeps the schema lean AND gives the model more relevant options.

const EQUIPMENT_TAG_TO_LIBRARY_EQUIPMENT: Record<string, string[]> = {
  gym: ["barbell", "dumbbell", "cable", "machine", "kettlebells", "medicine ball", "e-z curl bar", "exercise ball", "bands"],
  home_gym: ["barbell", "dumbbell", "kettlebells", "bands", "exercise ball", "medicine ball"],
  yoga_studio: ["body only", "exercise ball"],
  resistance_bands: ["bands"],
  boxing_gym: ["body only", "other"],
  mat_pilates: ["body only", "exercise ball"],
  calisthenics_gymnastics: ["body only"],
  crossfit: ["barbell", "dumbbell", "kettlebells", "body only", "medicine ball", "cable", "machine"],
  hiit_circuit_studio: ["body only", "dumbbell", "kettlebells", "bands", "medicine ball"],
  bodyweight_only: ["body only"],
  // bike, pool, other: the dataset has no matching equipment value (a
  // strength/bodybuilding-focused dataset, not cardio-machine-focused) --
  // no filter narrowing for these, falls through to the broad default.
};

const BODY_PART_TO_MUSCLES: Record<string, string[]> = {
  upper_body: ["chest", "shoulders", "biceps", "triceps", "forearms", "traps", "lats", "middle back", "neck"],
  lower_body: ["quadriceps", "hamstrings", "calves", "glutes", "abductors", "adductors"],
  core: ["abdominals", "lower back"],
  full_body: [
    "chest",
    "shoulders",
    "biceps",
    "triceps",
    "forearms",
    "traps",
    "lats",
    "middle back",
    "quadriceps",
    "hamstrings",
    "calves",
    "glutes",
    "abductors",
    "adductors",
    "abdominals",
    "lower back",
  ],
};

const MAIN_CANDIDATE_LIMIT = 150;
const STRETCH_CANDIDATE_LIMIT = 60;
const FALLBACK_LIMIT = 100;

/// Allowed library `equipment` values ("body only" always included; empty tags = bodyweight-only).
/// Null = no narrowing: unmapped tags (bike/pool/other) have no library equivalent to filter by.
export function resolveLibraryEquipment(equipment: string[]): string[] | null {
  if (equipment.some((tag) => tag !== "" && !(tag in EQUIPMENT_TAG_TO_LIBRARY_EQUIPMENT))) return null;
  const mapped = equipment.flatMap((tag) => EQUIPMENT_TAG_TO_LIBRARY_EQUIPMENT[tag] ?? []);
  return Array.from(new Set(["body only", ...mapped]));
}

/// PostgREST OR clause for the equipment filter: allowed values PLUS
/// NULL-equipment rows, which a plain `.in()` can never match.
function equipmentOrClause(values: string[]): string {
  return `equipment.is.null,equipment.in.(${values.map((v) => `"${v}"`).join(",")})`;
}

/// Library `level` values the user's experience actually supports --
/// keeps expert-only movements (rolling flyes, muscle-ups) out of the
/// vocabulary entirely for users who can't safely perform them, instead
/// of trusting the prompt's experience paragraph to steer the pick.
/// Unknown/absent experience defaults to moderate, same as buildPrompt.
export function resolveLibraryLevels(experienceLevel: string | null): string[] {
  switch (experienceLevel) {
    case "newbie":
      return ["beginner"];
    case "advanced":
      return ["beginner", "intermediate", "expert"];
    default:
      return ["beginner", "intermediate"];
  }
}

/// Returns a bounded, relevant list of real exercise names -- falls back
/// progressively broader rather than handing back an empty enum, EXCEPT
/// when safety exclusions empty even the broadest set: then it throws
/// (fail closed) instead of reinstating contraindicated names. Includes
/// stretching-category exercises unconditionally, since every plan needs
/// warm-up/cool-down candidates regardless of the main body-part focus.
export async function fetchCandidateExerciseNames(
  // deno-lint-ignore no-explicit-any
  supabase: SupabaseClient | any,
  bodyPart: string,
  equipment: string[],
  excludedKeywords: string[],
  experienceLevel: string | null = null,
): Promise<string[]> {
  const muscles = BODY_PART_TO_MUSCLES[bodyPart] ?? [];
  const equipmentValues = resolveLibraryEquipment(equipment);
  const levelValues = resolveLibraryLevels(experienceLevel);

  // Includes NULL-equipment rows: a row with no equipment value is a
  // no-gear movement, exactly what every filter here must keep pickable.
  // deno-lint-ignore no-explicit-any
  const withEquipmentFilter = (query: any) =>
    equipmentValues ? query.or(equipmentOrClause(equipmentValues)) : query;

  let mainNames: string[] = [];
  if (bodyPart !== "cardio" && bodyPart !== "recovery") {
    let query = withEquipmentFilter(
      supabase
        .from("exercise_library")
        .select("name")
        .in("level", levelValues)
        .limit(MAIN_CANDIDATE_LIMIT),
    );
    if (muscles.length > 0) query = query.overlaps("primary_muscles", muscles);
    const { data } = await query;
    // deno-lint-ignore no-explicit-any
    mainNames = (data ?? []).map((r: any) => r.name);

    // Progressively broaden, but never past the equipment or level
    // filters: an exercise the user has no equipment for -- or can't
    // safely perform -- is wrong no matter how well its muscles match
    // (the "Bodyweight Flyes"-on-EZ-bars bug).
    if (mainNames.length === 0) {
      const { data: byEquipmentOnly } = await withEquipmentFilter(
        supabase
          .from("exercise_library")
          .select("name")
          .eq("category", "strength")
          .in("level", levelValues)
          .limit(FALLBACK_LIMIT),
      );
      // deno-lint-ignore no-explicit-any
      mainNames = (byEquipmentOnly ?? []).map((r: any) => r.name);
    }
    if (mainNames.length === 0) {
      // Last resort so the enum is never empty -- beginner bodyweight
      // work is the one thing every user can safely be handed.
      const { data: broadFallback } = await supabase
        .from("exercise_library")
        .select("name")
        .eq("category", "strength")
        .eq("equipment", "body only")
        .eq("level", "beginner")
        .limit(FALLBACK_LIMIT);
      // deno-lint-ignore no-explicit-any
      mainNames = (broadFallback ?? []).map((r: any) => r.name);
    }
  } else if (bodyPart === "cardio") {
    const { data } = await withEquipmentFilter(
      supabase
        .from("exercise_library")
        .select("name")
        .eq("category", "cardio")
        .in("level", levelValues)
        .limit(FALLBACK_LIMIT),
    );
    // deno-lint-ignore no-explicit-any
    mainNames = (data ?? []).map((r: any) => r.name);

    // Cardio equipment is a weak signal (running needs no gym): broaden
    // rather than hand a cardio day a stretch-only vocabulary.
    if (mainNames.length === 0) {
      const { data: anyEquipment } = await supabase
        .from("exercise_library")
        .select("name")
        .eq("category", "cardio")
        .in("level", levelValues)
        .limit(FALLBACK_LIMIT);
      // deno-lint-ignore no-explicit-any
      mainNames = (anyEquipment ?? []).map((r: any) => r.name);
    }
    if (mainNames.length === 0) {
      const { data: anyCardio } = await supabase
        .from("exercise_library")
        .select("name")
        .eq("category", "cardio")
        .limit(FALLBACK_LIMIT);
      // deno-lint-ignore no-explicit-any
      mainNames = (anyCardio ?? []).map((r: any) => r.name);
    }
  }

  const { data: stretchData } = await withEquipmentFilter(
    supabase
      .from("exercise_library")
      .select("name")
      .eq("category", "stretching")
      .in("level", levelValues)
      .limit(STRETCH_CANDIDATE_LIMIT),
  );
  // deno-lint-ignore no-explicit-any
  const stretchNames: string[] = (stretchData ?? []).map((r: any) => r.name);

  const merged = new Set([...mainNames, ...stretchNames]);
  const lowerExcluded = excludedKeywords.map((k) => k.toLowerCase());
  const dropExcluded = (names: string[]) =>
    names.filter((name) => !lowerExcluded.some((kw) => name.toLowerCase().includes(kw)));
  const filtered = dropExcluded(Array.from(merged));
  if (filtered.length > 0) return filtered;

  // Safety exclusions emptied the list. Broaden to beginner bodyweight work
  // and re-filter -- NEVER hand back the contraindicated names themselves.
  const { data: safeFallback } = await supabase
    .from("exercise_library")
    .select("name")
    .eq("equipment", "body only")
    .eq("level", "beginner")
    .limit(FALLBACK_LIMIT);
  // deno-lint-ignore no-explicit-any
  const safeNames = dropExcluded((safeFallback ?? []).map((r: any) => r.name));
  if (safeNames.length > 0) return safeNames;

  // Fail closed (caller 500s and generates nothing) rather than suggest
  // movements the safety layer explicitly excluded.
  throw new Error("no library exercises remain after safety exclusions");
}
