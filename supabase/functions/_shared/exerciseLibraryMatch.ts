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
  // Deliberately NO barbell -- a loadable barbell + plates + rack is a much
  // bigger footprint than dumbbells/kettlebells/bands, and assuming it for
  // every "Home Gym" selection was recommending equipment a real majority
  // of home-gym users don't actually own (BUG report: barbell squats
  // recommended to a user with dumbbells/bench/mat/treadmill and no
  // barbell). A user who genuinely has a barbell at home can still get it
  // recognized via the free-text "what else do you have access to?" field
  // (see resolveFreeTextEquipment in _shared/equipment.ts) or by selecting
  // "Gym" instead.
  home_gym: ["dumbbell", "kettlebells", "bands", "exercise ball", "medicine ball"],
  yoga_studio: ["body only", "exercise ball"],
  resistance_bands: ["bands"],
  boxing_gym: ["body only", "other"],
  mat_pilates: ["body only", "exercise ball"],
  calisthenics_gymnastics: ["body only"],
  crossfit: ["barbell", "dumbbell", "kettlebells", "body only", "medicine ball", "cable", "machine"],
  hiit_circuit_studio: ["body only", "dumbbell", "kettlebells", "bands", "medicine ball"],
  bodyweight_only: ["body only"],
  // bike, pool, other: no direct library equivalent -- contribute nothing
  // (not "unlock everything", see the BUG this used to cause below), so
  // these fall through to whatever else the user selected, or "body only"
  // alone if nothing else was.
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

// Anthropic's structured-output schema compiler rejects the generated
// workout schema ("Schema is too complex for compilation") once the
// deduped candidate-name enum climbs into the ~130+ range, even with the
// exercise schema deduplicated via $defs/$ref (see buildWorkoutSchema in
// generate-workout-plan/index.ts). Empirically confirmed working at 115,
// failing at 130 -- these limits keep the merged (main + stretch, pre-
// dedup) total at 90, comfortably under that ceiling.
const MAIN_CANDIDATE_LIMIT = 70;
const STRETCH_CANDIDATE_LIMIT = 20;
const FALLBACK_LIMIT = 70;
// Kept small: MAIN + STRETCH already total 90 pre-dedup, right under the
// same ~115-130 schema-complexity ceiling referenced above -- 12 more
// keeps real headroom rather than creeping back toward it.
const WARMUP_CARDIO_LIMIT = 12;
/// Floor below which the day-over-day freshness exclusion backs off
/// rather than starve the candidate pool -- see recentlyUsedNames.
const MIN_CANDIDATES_AFTER_FRESHNESS_EXCLUSION = 5;

/// Allowed library `equipment` values -- "body only" is always included
/// (empty/fully-unmapped tags = bodyweight-only, the safe default).
///
/// Previously returned `null` ("no narrowing" -- the ENTIRE unfiltered
/// library, barbells and all) the moment ANY selected tag was unmapped
/// (bike/pool/other), even if the user also selected a real preset like
/// "gym" alongside it. That's exactly backwards for a feature whose whole
/// job is never suggesting equipment the user doesn't have: an unknown
/// tag should contribute nothing, not remove every other constraint.
/// Fixed after a real BUG report of barbell exercises (and other
/// unavailable gear) being recommended.
export function resolveLibraryEquipment(equipment: string[]): string[] {
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
  // Library ids to union in (a sport goal's goal_exercise mappings) --
  // fetched under the SAME equipment/level filters, before the exclusion
  // drop, so goal work never names gear or skills the user lacks.
  goalExerciseIds: string[] = [],
  // Additional exercise_library.equipment values parsed from the user's
  // free-text "what else do you have access to?" notes (see
  // resolveFreeTextEquipment in _shared/equipment.ts) -- unioned in
  // alongside whatever the structured EquipmentTag selections already
  // resolved, so a specific item the user typed out (but didn't have a
  // matching preset for) still actually unlocks matching exercises.
  extraLibraryEquipment: string[] = [],
  // True when the same free-text parse found treadmill/bike/rower/
  // elliptical/jump-rope -- unlocks a small cardio slice into the
  // candidate pool even on a non-cardio body-part day, so warm-up (which
  // draws from this SAME candidate list) can actually name a real cardio
  // item like an incline treadmill walk instead of only ever being able
  // to name strength/stretch candidates.
  unlockCardioCandidates: boolean = false,
  // Exercise names actually used in the last couple of sessions targeting
  // this same body part (see generate-workout-plan's fetchRecentExercise-
  // Names) -- soft-excluded so the same lifts don't recur day after day
  // (BUG report: identical workout, day after day). Soft, unlike
  // excludedKeywords: this is a freshness preference, not a safety rule,
  // so it's dropped entirely (see MIN_CANDIDATES_AFTER_FRESHNESS_EXCLUSION
  // below) rather than ever forcing a worse/unsafe fallback just for variety.
  recentlyUsedNames: string[] = [],
): Promise<string[]> {
  const muscles = BODY_PART_TO_MUSCLES[bodyPart] ?? [];
  const equipmentValues = Array.from(new Set([...resolveLibraryEquipment(equipment), ...extraLibraryEquipment]));
  const levelValues = resolveLibraryLevels(experienceLevel);

  // Includes NULL-equipment rows: a row with no equipment value is a
  // no-gear movement, exactly what every filter here must keep pickable.
  // Always applied now -- resolveLibraryEquipment always returns a real
  // (never empty, always includes "body only") array, so there's no more
  // "skip the filter entirely" case.
  // deno-lint-ignore no-explicit-any
  const withEquipmentFilter = (query: any) => query.or(equipmentOrClause(equipmentValues));
  // Excluded from every tier below, same "assume the more restrictive
  // case by default" posture as equipment (assume you don't have gear you
  // didn't list) -- most users train alone, and a suggestion that needs a
  // second person with no solo alternative isn't actually usable. See the
  // requires_partner migration for how this was classified.
  // deno-lint-ignore no-explicit-any
  const withoutPartnerRequired = (query: any) => query.eq("requires_partner", false);

  let mainNames: string[] = [];
  if (bodyPart !== "cardio" && bodyPart !== "recovery") {
    let query = withEquipmentFilter(
      withoutPartnerRequired(
        supabase
          .from("exercise_library")
          .select("name")
          .in("level", levelValues)
          .limit(MAIN_CANDIDATE_LIMIT),
      ),
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
        withoutPartnerRequired(
          supabase
            .from("exercise_library")
            .select("name")
            .eq("category", "strength")
            .in("level", levelValues)
            .limit(FALLBACK_LIMIT),
        ),
      );
      // deno-lint-ignore no-explicit-any
      mainNames = (byEquipmentOnly ?? []).map((r: any) => r.name);
    }
    if (mainNames.length === 0) {
      // Last resort so the enum is never empty -- beginner bodyweight
      // work is the one thing every user can safely be handed.
      const { data: broadFallback } = await withoutPartnerRequired(
        supabase
          .from("exercise_library")
          .select("name")
          .eq("category", "strength")
          .eq("equipment", "body only")
          .eq("level", "beginner")
          .limit(FALLBACK_LIMIT),
      );
      // deno-lint-ignore no-explicit-any
      mainNames = (broadFallback ?? []).map((r: any) => r.name);
    }
  } else if (bodyPart === "cardio") {
    const { data } = await withEquipmentFilter(
      withoutPartnerRequired(
        supabase
          .from("exercise_library")
          .select("name")
          .eq("category", "cardio")
          .in("level", levelValues)
          .limit(FALLBACK_LIMIT),
      ),
    );
    // deno-lint-ignore no-explicit-any
    mainNames = (data ?? []).map((r: any) => r.name);

    // Cardio equipment is a weak signal (running needs no gym): broaden
    // rather than hand a cardio day a stretch-only vocabulary.
    if (mainNames.length === 0) {
      const { data: anyEquipment } = await withoutPartnerRequired(
        supabase
          .from("exercise_library")
          .select("name")
          .eq("category", "cardio")
          .in("level", levelValues)
          .limit(FALLBACK_LIMIT),
      );
      // deno-lint-ignore no-explicit-any
      mainNames = (anyEquipment ?? []).map((r: any) => r.name);
    }
    if (mainNames.length === 0) {
      const { data: anyCardio } = await withoutPartnerRequired(
        supabase
          .from("exercise_library")
          .select("name")
          .eq("category", "cardio")
          .limit(FALLBACK_LIMIT),
      );
      // deno-lint-ignore no-explicit-any
      mainNames = (anyCardio ?? []).map((r: any) => r.name);
    }
  }

  const { data: stretchData } = await withEquipmentFilter(
    withoutPartnerRequired(
      supabase
        .from("exercise_library")
        .select("name")
        .eq("category", "stretching")
        .in("level", levelValues)
        .limit(STRETCH_CANDIDATE_LIMIT),
    ),
  );
  // deno-lint-ignore no-explicit-any
  const stretchNames: string[] = (stretchData ?? []).map((r: any) => r.name);

  // Small cardio slice for warm-up on a non-cardio day -- see
  // unlockCardioCandidates' own doc comment above. Deliberately not
  // merged when bodyPart IS "cardio" -- that branch above already pulls a
  // full, properly-broadened cardio candidate set; adding this on top
  // would just be a smaller, redundant duplicate query.
  let cardioNames: string[] = [];
  if (unlockCardioCandidates && bodyPart !== "cardio" && bodyPart !== "recovery") {
    const { data: cardioData } = await withEquipmentFilter(
      withoutPartnerRequired(
        supabase
          .from("exercise_library")
          .select("name")
          .eq("category", "cardio")
          .in("level", levelValues)
          .limit(WARMUP_CARDIO_LIMIT),
      ),
    );
    // deno-lint-ignore no-explicit-any
    cardioNames = (cardioData ?? []).map((r: any) => r.name);
  }

  // Goal-mapped exercises join the pool only when they pass the same
  // equipment, level, and partner filters as everything else -- no side door.
  let goalNames: string[] = [];
  if (goalExerciseIds.length > 0) {
    const { data: goalData } = await withEquipmentFilter(
      withoutPartnerRequired(
        supabase
          .from("exercise_library")
          .select("name")
          .in("id", goalExerciseIds)
          .in("level", levelValues)
          .limit(MAIN_CANDIDATE_LIMIT),
      ),
    );
    // deno-lint-ignore no-explicit-any
    goalNames = (goalData ?? []).map((r: any) => r.name);
  }

  const merged = new Set([...mainNames, ...stretchNames, ...cardioNames, ...goalNames]);
  const lowerExcluded = excludedKeywords.map((k) => k.toLowerCase());
  const dropExcluded = (names: string[]) =>
    names.filter((name) => !lowerExcluded.some((kw) => name.toLowerCase().includes(kw)));
  const filtered = dropExcluded(Array.from(merged));
  if (filtered.length > 0) {
    if (recentlyUsedNames.length > 0) {
      const fresh = filtered.filter((name) => !recentlyUsedNames.includes(name));
      // Only apply the freshness exclusion when enough candidates remain
      // to still build a real session -- never shrink the vocabulary so
      // far that a repeat becomes preferable to what's left (e.g. forcing
      // a near-empty enum). A couple of stale names lingering beats an
      // unsafe/degenerate fallback triggered purely for variety's sake.
      if (fresh.length >= MIN_CANDIDATES_AFTER_FRESHNESS_EXCLUSION) return fresh;
    }
    return filtered;
  }

  // Safety exclusions emptied the list. Broaden to beginner bodyweight work
  // and re-filter -- NEVER hand back the contraindicated names themselves.
  const { data: safeFallback } = await withoutPartnerRequired(
    supabase
      .from("exercise_library")
      .select("name")
      .eq("equipment", "body only")
      .eq("level", "beginner")
      .limit(FALLBACK_LIMIT),
  );
  // deno-lint-ignore no-explicit-any
  const safeNames = dropExcluded((safeFallback ?? []).map((r: any) => r.name));
  if (safeNames.length > 0) return safeNames;

  // Fail closed (caller 500s and generates nothing) rather than suggest
  // movements the safety layer explicitly excluded.
  throw new Error("no library exercises remain after safety exclusions");
}
