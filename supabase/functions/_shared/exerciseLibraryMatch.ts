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

/// Returns a bounded, relevant list of real exercise names -- always
/// non-empty (falls back progressively broader rather than ever handing
/// back an empty enum, which would make generation impossible). Includes
/// stretching-category exercises unconditionally, since every plan needs
/// warm-up/cool-down candidates regardless of the main body-part focus.
export async function fetchCandidateExerciseNames(
  // deno-lint-ignore no-explicit-any
  supabase: SupabaseClient | any,
  bodyPart: string,
  equipment: string[],
  excludedKeywords: string[],
): Promise<string[]> {
  const muscles = BODY_PART_TO_MUSCLES[bodyPart] ?? [];
  const equipmentValues = Array.from(
    new Set(equipment.flatMap((tag) => EQUIPMENT_TAG_TO_LIBRARY_EQUIPMENT[tag] ?? [])),
  );

  let mainNames: string[] = [];
  if (bodyPart !== "cardio" && bodyPart !== "recovery") {
    let query = supabase.from("exercise_library").select("name").limit(MAIN_CANDIDATE_LIMIT);
    if (muscles.length > 0) query = query.overlaps("primary_muscles", muscles);
    if (equipmentValues.length > 0) query = query.in("equipment", equipmentValues);
    const { data } = await query;
    // deno-lint-ignore no-explicit-any
    mainNames = (data ?? []).map((r: any) => r.name);

    // Progressively broaden rather than ever returning an empty candidate
    // list for an unusual body-part/equipment combination.
    if (mainNames.length === 0 && muscles.length > 0) {
      const { data: byMuscleOnly } = await supabase
        .from("exercise_library")
        .select("name")
        .overlaps("primary_muscles", muscles)
        .limit(MAIN_CANDIDATE_LIMIT);
      // deno-lint-ignore no-explicit-any
      mainNames = (byMuscleOnly ?? []).map((r: any) => r.name);
    }
    if (mainNames.length === 0) {
      const { data: broadFallback } = await supabase
        .from("exercise_library")
        .select("name")
        .eq("category", "strength")
        .limit(FALLBACK_LIMIT);
      // deno-lint-ignore no-explicit-any
      mainNames = (broadFallback ?? []).map((r: any) => r.name);
    }
  } else if (bodyPart === "cardio") {
    const { data } = await supabase.from("exercise_library").select("name").eq("category", "cardio").limit(FALLBACK_LIMIT);
    // deno-lint-ignore no-explicit-any
    mainNames = (data ?? []).map((r: any) => r.name);
  }

  const { data: stretchData } = await supabase
    .from("exercise_library")
    .select("name")
    .eq("category", "stretching")
    .limit(STRETCH_CANDIDATE_LIMIT);
  // deno-lint-ignore no-explicit-any
  const stretchNames: string[] = (stretchData ?? []).map((r: any) => r.name);

  const merged = new Set([...mainNames, ...stretchNames]);
  const lowerExcluded = excludedKeywords.map((k) => k.toLowerCase());
  const filtered = Array.from(merged).filter((name) => {
    const lower = name.toLowerCase();
    return !lowerExcluded.some((kw) => lower.includes(kw));
  });

  // Excluding injury-unsafe names could, in principle, empty the list --
  // fall back to the unfiltered merge rather than a broken empty enum.
  return filtered.length > 0 ? filtered : Array.from(merged);
}
