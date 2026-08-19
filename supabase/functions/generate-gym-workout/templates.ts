// Fixed, versioned-in-code template library for the gym-photo-workout
// feature -- deliberately NOT an admin-managed DB table for v1, and
// deliberately NOT LLM-generated: template selection is a decision, not a
// generation task, per the product requirement that this step stay
// deterministic. Analogous in spirit to the Swift-side
// RecommendationCategory.workoutSuggestions fixed catalog.
//
// Finisher coverage added 2026-07-29: every template now ends in a
// "Finisher" block (previously 13 of 20 had none, so a session could
// silently ship with no finisher at all). Each new finisher uses only that
// template's own requiredEquipment and is scaled to its category (rest/light
// = gentle, ~1-2 min; moderate = moderate effort, ~1-2 min; push_hard =
// short-but-hard, RPE 8-10). DRAFTED, NOT EXPERT-REVIEWED -- same caveat as
// the equipment-coverage additions below.
//
// Body-part coverage added 2026-08-19: until then the catalog had zero
// "lower_body" and zero "core" templates, so selectTemplate's resolved-
// target-body-part ranking (see its own doc comment) had nothing to match
// on a leg day or ab day and silently fell back to whichever full-body
// template used the most equipment -- see the dedicated comment block at
// the bottom of GYM_WORKOUT_TEMPLATES for the new entries.

import { normalizeEquipment } from "../_shared/equipment.ts";

export interface TemplateExercise {
  name: string;
  sets: number;
  reps: string;
  weight_guidance: string;
  intensity: string;
  duration_minutes: number;
  // Which muscles/body area this exercise targets -- fixed per exercise,
  // not LLM-guessed (anatomy is a fact, not a generation task), shown on
  // the gym-photo result screen for the "what's targeted and why" copy.
  target_area: string;
  // exercise_library.id, hand-verified against the actual Free Exercise DB
  // record (name AND equipment both consistent -- see
  // CONFIRMED_NO_LIBRARY_EQUIVALENT below for the cases deliberately left
  // unmatched, and why). Omitted entirely, not guessed, when no confident
  // match exists -- the client falls back to a category-appropriate
  // illustration (ExerciseDetailView.swift) rather than a wrong-equipment
  // photo.
  library_id?: string;
}

// 2026-08-15 hand audit: every one of the 84 exercise entries below was
// checked against the live 874-row exercise_library table (exact match,
// then a fuzzy pass on the core movement name). 43 had no library_id;
// 23 turned out to have a real equivalent under a different name (now
// wired in above -- e.g. "Dumbbell farmer's hold" -> Farmers_Walk,
// "Glute bridge" -> Butt_Lift_Bridge) and 20 genuinely have no equivalent
// anywhere in the table. Those 20 are listed here, not left silently
// unmatched, so (a) ExerciseDetailView.swift can show a deliberate
// category-appropriate fallback instead of the old plain-text "No
// reference photo" placeholder, and (b) templates_test.ts can fail loudly
// if a *new* image-less entry shows up later that nobody has actually
// checked -- see that test for the enforcement.
//
// Two sub-reasons, worth telling apart if this ever gets revisited:
// - Genuinely not covered by the underlying Free Exercise DB import at
//   all (breathing drills, marching/sprinting-in-place, foam-roll-plus-
//   breathing combos): "Box breathing", "Brisk walk in place", "Brisk
//   march in place", "Burpee", "Foam roll + deep breathing", "Sprint in
//   place".
// - A real close cousin exists in the table, but only in a form that
//   would show materially different equipment or load than what's
//   prescribed here (a barbell photo for a "Dumbbell push press", a
//   loaded photo for an explicitly bodyweight "Reverse lunge" or
//   "Bulgarian split squat") -- showing it would be more misleading than
//   showing nothing, so it was deliberately left unmatched instead:
//   "Barbell front-rack hold", "Barbell front-rack carry", "Bulgarian
//   split squat", "Dead-hang", "Dumbbell push press", "Kettlebell
//   deadlift", "Kettlebell halo", "Kettlebell rack hold", "Kettlebell
//   suitcase hold", "Banded squat", "Banded row", "Banded plank
//   pull-apart", "Reverse lunge", "Wall sit".
export const CONFIRMED_NO_LIBRARY_EQUIVALENT: ReadonlySet<string> = new Set([
  "Brisk walk in place",
  "Brisk march in place",
  "Box breathing",
  "Barbell front-rack hold",
  "Burpee",
  "Sprint in place",
  "Barbell front-rack carry",
  "Foam roll + deep breathing",
  "Kettlebell deadlift",
  "Kettlebell halo",
  "Kettlebell suitcase hold",
  "Banded squat",
  "Banded row",
  "Banded plank pull-apart",
  "Kettlebell rack hold",
  "Dead-hang",
  "Dumbbell push press",
  "Reverse lunge",
  "Bulgarian split squat",
  "Wall sit",
]);

export interface TemplateBlock {
  name: string;
  rounds: number;
  rest_between_rounds: string;
  exercises: TemplateExercise[];
}

export interface GymWorkoutTemplate {
  id: string;
  category: "rest" | "light" | "moderate" | "push_hard";
  // Values MUST come from EQUIPMENT_VOCABULARY (_shared/equipment.ts) --
  // that is the same closed list the vision model is constrained to, which
  // is what makes matching reliable. A typo here does not fail loudly; it
  // just makes the template permanently unreachable.
  //
  // Empty array = bodyweight-only, always available regardless of what
  // equipment was detected/confirmed. Note that every exercise in a
  // template must be performable with only what is listed here.
  requiredEquipment: string[];
  // GoalTag raw values (Soma/Models/DailyRecommendation.swift), for
  // prioritization only -- never a hard filter.
  goals: string[];
  // Jumping, sprinting, or other repeated-impact work. Excluded when the
  // user has a noted injury, mirroring WorkoutSuggestion.highImpact and the
  // filter RecommendationDetailView already applies to the normal list.
  //
  // INVARIANT: every category must keep at least one template with
  // `requiredEquipment: []` AND `highImpact: false`, or an injured user
  // with no equipment has nothing to be given. selectTemplate throws rather
  // than quietly handing them the high-impact option.
  highImpact: boolean;
  // Stable label + BodyPartFocus raw value (Soma/Models/DailyRecommendation.swift)
  // -- returned to the client so it can populate selectedTitle/
  // selectedBodyPart directly, the same state the normal "Workouts that
  // fit today" picker sets, letting a gym-photo-generated plan slot into
  // the same AI-generated-workout card without a bespoke display path.
  title: string;
  bodyPart: string;
  focus: string;
  warm_up: TemplateExercise[];
  blocks: TemplateBlock[];
  cool_down: TemplateExercise[];
}

const WARM_UP_LIGHT: TemplateExercise[] = [
  { name: "Brisk walk in place", sets: 1, reps: "3 min", weight_guidance: "N/A", intensity: "easy", duration_minutes: 3, target_area: "Full body -- raises heart rate and core temperature" },
  { name: "Arm circles", library_id: "Arm_Circles", sets: 1, reps: "20 total", weight_guidance: "N/A", intensity: "easy", duration_minutes: 1, target_area: "Shoulders" },
];

// Equipment-free by necessity: this warm-up is shared by every moderate and
// push_hard template, INCLUDING the zero-equipment ones. It used to open with
// an incline treadmill walk, so a user who photographed an empty living room
// was told to start on a treadmill they had just demonstrated they lacked.
// Nothing in a shared warm-up may assume equipment that individual templates
// do not require.
const WARM_UP_MODERATE: TemplateExercise[] = [
  { name: "Brisk march in place", sets: 1, reps: "5 min", weight_guidance: "N/A", intensity: "easy", duration_minutes: 5, target_area: "Full body -- raises heart rate and core temperature" },
  { name: "Bodyweight squats", library_id: "Bodyweight_Squat", sets: 1, reps: "10", weight_guidance: "N/A", intensity: "easy", duration_minutes: 2, target_area: "Quads, glutes" },
  { name: "Shoulder rolls", library_id: "Shoulder_Circles", sets: 1, reps: "10 each direction", weight_guidance: "N/A", intensity: "easy", duration_minutes: 1, target_area: "Shoulders" },
];

const COOL_DOWN: TemplateExercise[] = [
  { name: "Standing quad stretch", library_id: "Standing_Elevated_Quad_Stretch", sets: 1, reps: "30 sec each side", weight_guidance: "N/A", intensity: "easy", duration_minutes: 2, target_area: "Quads" },
  { name: "Seated forward fold", library_id: "The_Straddle", sets: 1, reps: "45 sec", weight_guidance: "N/A", intensity: "easy", duration_minutes: 1, target_area: "Hamstrings, lower back" },
  { name: "Box breathing", sets: 1, reps: "2 min", weight_guidance: "N/A", intensity: "easy", duration_minutes: 2, target_area: "Nervous system -- brings heart rate back down" },
];

export const GYM_WORKOUT_TEMPLATES: GymWorkoutTemplate[] = [
  // ---- rest ----
  {
    id: "rest_bodyweight_mobility",
    title: "Gym Photo: Mobility & Recovery Flow",
    bodyPart: "recovery",
    category: "rest",
    highImpact: false,
    requiredEquipment: [],
    goals: ["active_recovery", "better_sleep", "improve_flexibility"],
    focus: "Gentle mobility and recovery",
    warm_up: WARM_UP_LIGHT,
    blocks: [
      {
        name: "Block 1",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Cat-cow stretch", library_id: "Cat_Stretch", sets: 1, reps: "10", weight_guidance: "N/A", intensity: "easy", duration_minutes: 3, target_area: "Spine, core" },
          { name: "Hip circles", library_id: "Standing_Hip_Circles", sets: 1, reps: "10 each direction", weight_guidance: "N/A", intensity: "easy", duration_minutes: 2, target_area: "Hips" },
          { name: "Walking lunge with reach", library_id: "Bodyweight_Walking_Lunge", sets: 1, reps: "8 each leg", weight_guidance: "bodyweight", intensity: "easy", duration_minutes: 4, target_area: "Quads, glutes, hip flexors" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Supported child's pose with deep breathing", library_id: "Childs_Pose", sets: 1, reps: "90 sec", weight_guidance: "N/A", intensity: "RPE 2/10", duration_minutes: 2, target_area: "Nervous system, lower back -- brings heart rate down" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },

  // ---- light ----
  {
    id: "light_bodyweight_full_body",
    title: "Gym Photo: Bodyweight Full-Body (Light)",
    bodyPart: "full_body",
    category: "light",
    highImpact: false,
    requiredEquipment: [],
    goals: ["general_fitness", "leaner_toned", "cardio_endurance"],
    focus: "Light full-body activation",
    warm_up: WARM_UP_LIGHT,
    blocks: [
      {
        name: "Block 1",
        rounds: 2,
        rest_between_rounds: "60 sec",
        exercises: [
          { name: "Bodyweight squat", library_id: "Bodyweight_Squat", sets: 1, reps: "12", weight_guidance: "bodyweight", intensity: "RPE 5/10", duration_minutes: 3, target_area: "Quads, glutes" },
          { name: "Incline push-up", library_id: "Incline_Push-Up", sets: 1, reps: "10", weight_guidance: "bodyweight", intensity: "RPE 5/10", duration_minutes: 3, target_area: "Chest, shoulders, triceps" },
          { name: "Glute bridge", library_id: "Butt_Lift_Bridge", sets: 1, reps: "15", weight_guidance: "bodyweight", intensity: "RPE 5/10", duration_minutes: 3, target_area: "Glutes, hamstrings" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Plank hold", library_id: "Plank", sets: 1, reps: "30-45 sec", weight_guidance: "bodyweight", intensity: "RPE 5/10", duration_minutes: 1, target_area: "Core" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "light_dumbbells_full_body",
    title: "Gym Photo: Dumbbell Full-Body (Light)",
    bodyPart: "full_body",
    category: "light",
    highImpact: false,
    requiredEquipment: ["dumbbells"],
    goals: ["leaner_toned", "general_fitness"],
    focus: "Light full-body with dumbbells",
    warm_up: WARM_UP_LIGHT,
    blocks: [
      {
        name: "Block 1",
        rounds: 2,
        rest_between_rounds: "60 sec",
        exercises: [
          { name: "Dumbbell goblet squat", library_id: "Goblet_Squat", sets: 1, reps: "12", weight_guidance: "light, 2x8-12kg", intensity: "RPE 5/10", duration_minutes: 3, target_area: "Quads, glutes, core" },
          { name: "Dumbbell shoulder press", library_id: "Dumbbell_Shoulder_Press", sets: 1, reps: "10", weight_guidance: "light, 2x5-8kg", intensity: "RPE 5/10", duration_minutes: 3, target_area: "Shoulders, triceps" },
          { name: "Dumbbell row", library_id: "One-Arm_Dumbbell_Row", sets: 1, reps: "12 each side", weight_guidance: "light, 1x8-12kg", intensity: "RPE 5/10", duration_minutes: 3, target_area: "Back, biceps" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Dumbbell farmer's hold", library_id: "Farmers_Walk", sets: 1, reps: "45 sec", weight_guidance: "light, 2x8-12kg", intensity: "RPE 5/10", duration_minutes: 1, target_area: "Grip, core" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },

  // ---- moderate ----
  {
    id: "moderate_bodyweight_full_body",
    title: "Gym Photo: Bodyweight Conditioning (Moderate)",
    bodyPart: "full_body",
    category: "moderate",
    highImpact: true,
    requiredEquipment: [],
    goals: ["general_fitness", "cardio_endurance"],
    focus: "Moderate bodyweight conditioning",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Block 1",
        rounds: 3,
        rest_between_rounds: "45 sec",
        exercises: [
          { name: "Jump squat", library_id: "Freehand_Jump_Squat", sets: 1, reps: "10", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 2, target_area: "Quads, glutes, calves" },
          { name: "Push-up", library_id: "Pushups", sets: 1, reps: "12", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 2, target_area: "Chest, shoulders, triceps" },
          { name: "Mountain climber", library_id: "Mountain_Climbers", sets: 1, reps: "20 total", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 2, target_area: "Core, hip flexors" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Plank hold", library_id: "Plank", sets: 1, reps: "45 sec", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 2, target_area: "Core" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "moderate_barbell_full_body",
    title: "Gym Photo: Barbell Full-Body (Moderate)",
    bodyPart: "full_body",
    category: "moderate",
    highImpact: false,
    requiredEquipment: ["barbell", "squat rack"],
    goals: ["build_strength", "gain_muscle"],
    focus: "Moderate barbell strength",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Block 1",
        rounds: 1,
        rest_between_rounds: "90 sec",
        exercises: [
          { name: "Barbell back squat", library_id: "Barbell_Squat", sets: 4, reps: "8", weight_guidance: "moderate -- last rep should feel like RPE 7", intensity: "RPE 7/10", duration_minutes: 12, target_area: "Quads, glutes, core" },
        ],
      },
      {
        name: "Block 2",
        rounds: 1,
        rest_between_rounds: "90 sec",
        exercises: [
          { name: "Barbell bench press", library_id: "Barbell_Bench_Press_-_Medium_Grip", sets: 3, reps: "8", weight_guidance: "moderate -- last rep should feel like RPE 7", intensity: "RPE 7/10", duration_minutes: 10, target_area: "Chest, shoulders, triceps" },
        ],
      },
      {
        name: "Block 3 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Barbell front-rack hold", sets: 1, reps: "30 sec", weight_guidance: "light -- the bar should feel manageable, not maximal", intensity: "RPE 6/10", duration_minutes: 1, target_area: "Core, upper back, shoulders" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },

  // ---- push_hard ----
  {
    id: "push_hard_bodyweight_hiit",
    title: "Gym Photo: Bodyweight HIIT Circuit",
    bodyPart: "cardio",
    category: "push_hard",
    highImpact: true,
    requiredEquipment: [],
    goals: ["cardio_endurance", "lose_weight"],
    focus: "High-intensity bodyweight circuit",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Superset A",
        rounds: 4,
        rest_between_rounds: "30 sec",
        exercises: [
          { name: "Burpee", sets: 1, reps: "12", weight_guidance: "bodyweight", intensity: "RPE 9/10", duration_minutes: 2, target_area: "Full body, cardio" },
          { name: "Jump lunge", library_id: "Split_Jump", sets: 1, reps: "16 total", weight_guidance: "bodyweight", intensity: "RPE 9/10", duration_minutes: 2, target_area: "Quads, glutes, calves" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Sprint in place", sets: 1, reps: "60 sec max effort", weight_guidance: "bodyweight", intensity: "RPE 10/10", duration_minutes: 1, target_area: "Full body, cardio" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "push_hard_barbell_strength",
    title: "Gym Photo: Barbell Strength Session",
    bodyPart: "full_body",
    category: "push_hard",
    highImpact: false,
    requiredEquipment: ["barbell", "squat rack"],
    goals: ["build_strength", "gain_muscle"],
    focus: "High-effort barbell strength session",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Block 1",
        rounds: 1,
        rest_between_rounds: "2 min",
        exercises: [
          { name: "Barbell deadlift", library_id: "Barbell_Deadlift", sets: 4, reps: "5", weight_guidance: "heavy -- last rep should feel like RPE 8", intensity: "RPE 8/10", duration_minutes: 15, target_area: "Hamstrings, glutes, back" },
        ],
      },
      {
        name: "Superset A",
        rounds: 3,
        rest_between_rounds: "60 sec",
        exercises: [
          { name: "Barbell overhead press", library_id: "Standing_Military_Press", sets: 1, reps: "6", weight_guidance: "moderate-heavy", intensity: "RPE 8/10", duration_minutes: 3, target_area: "Shoulders, triceps" },
          // Was a pull-up, and the finisher below was a dumbbell farmer's
          // carry -- both needed equipment this template does not require,
          // so a user with only a barbell and rack was prescribed movements
          // they had no way to perform. Every exercise here now uses only
          // what requiredEquipment guarantees.
          { name: "Barbell bent-over row", library_id: "Bent_Over_Barbell_Row", sets: 1, reps: "8", weight_guidance: "moderate", intensity: "RPE 8/10", duration_minutes: 3, target_area: "Back, biceps" },
        ],
      },
      {
        name: "Block 3 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Barbell front-rack carry", sets: 1, reps: "40m", weight_guidance: "moderate -- the bar should feel heavy by the end", intensity: "RPE 9/10", duration_minutes: 2, target_area: "Core, shoulders, upper back" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },

  // ==== Equipment coverage added 2026-07-28 ====
  // Previously only three templates referenced equipment at all (dumbbells,
  // and barbell+squat rack twice), so kettlebells, machines, bands, bars,
  // and cardio machines were recognised in the photo and then ignored --
  // and `rest` had no equipment branch whatsoever.
  //
  // DRAFTED, NOT EXPERT-REVIEWED. These follow the same conservative shape
  // as the originals (volume scaled to category, RPE capped by category),
  // but they are physical prescriptions and should be read by someone with
  // strength-and-conditioning credentials before they reach users.

  // ---- rest ----
  {
    id: "rest_foam_roller_release",
    title: "Gym Photo: Soft-Tissue Release",
    bodyPart: "recovery",
    category: "rest",
    highImpact: false,
    requiredEquipment: ["foam roller"],
    goals: ["active_recovery", "improve_flexibility", "better_sleep"],
    focus: "Soft-tissue release and gentle mobility",
    warm_up: WARM_UP_LIGHT,
    blocks: [
      {
        name: "Block 1",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Foam roll quads", library_id: "Quadriceps-SMR", sets: 1, reps: "60 sec each leg", weight_guidance: "N/A", intensity: "easy", duration_minutes: 3, target_area: "Quads" },
          { name: "Foam roll upper back", library_id: "Rhomboids-SMR", sets: 1, reps: "90 sec", weight_guidance: "N/A", intensity: "easy", duration_minutes: 2, target_area: "Upper back, thoracic spine" },
          { name: "Foam roll glutes", library_id: "Piriformis-SMR", sets: 1, reps: "60 sec each side", weight_guidance: "N/A", intensity: "easy", duration_minutes: 3, target_area: "Glutes" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Foam roll + deep breathing", sets: 1, reps: "90 sec", weight_guidance: "N/A", intensity: "RPE 2/10", duration_minutes: 2, target_area: "Nervous system -- brings heart rate down" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },

  // ---- light ----
  {
    id: "light_kettlebell_flow",
    title: "Gym Photo: Kettlebell Flow (Light)",
    bodyPart: "full_body",
    category: "light",
    highImpact: false,
    requiredEquipment: ["kettlebells"],
    goals: ["general_fitness", "leaner_toned", "active_recovery"],
    focus: "Light kettlebell movement flow",
    warm_up: WARM_UP_LIGHT,
    blocks: [
      {
        name: "Block 1",
        rounds: 2,
        rest_between_rounds: "60 sec",
        exercises: [
          { name: "Kettlebell deadlift", sets: 1, reps: "12", weight_guidance: "light, 1x12-16kg", intensity: "RPE 5/10", duration_minutes: 3, target_area: "Hamstrings, glutes, lower back" },
          { name: "Kettlebell halo", sets: 1, reps: "8 each direction", weight_guidance: "light, 1x8-12kg", intensity: "RPE 4/10", duration_minutes: 3, target_area: "Shoulders, upper back" },
          { name: "Kettlebell goblet squat", library_id: "Goblet_Squat", sets: 1, reps: "10", weight_guidance: "light, 1x12-16kg", intensity: "RPE 5/10", duration_minutes: 3, target_area: "Quads, glutes, core" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Kettlebell suitcase hold", sets: 1, reps: "45 sec each side", weight_guidance: "light, 1x12-16kg", intensity: "RPE 5/10", duration_minutes: 2, target_area: "Grip, obliques, core" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "light_bands_full_body",
    title: "Gym Photo: Banded Full-Body (Light)",
    bodyPart: "full_body",
    category: "light",
    highImpact: false,
    requiredEquipment: ["resistance bands"],
    goals: ["general_fitness", "improve_flexibility", "active_recovery"],
    focus: "Light banded full-body activation",
    warm_up: WARM_UP_LIGHT,
    blocks: [
      {
        name: "Block 1",
        rounds: 2,
        rest_between_rounds: "45 sec",
        exercises: [
          { name: "Band pull-apart", library_id: "Band_Pull_Apart", sets: 1, reps: "15", weight_guidance: "light band", intensity: "RPE 4/10", duration_minutes: 2, target_area: "Rear delts, upper back" },
          { name: "Banded squat", sets: 1, reps: "15", weight_guidance: "light band", intensity: "RPE 5/10", duration_minutes: 3, target_area: "Quads, glutes" },
          { name: "Banded row", sets: 1, reps: "15", weight_guidance: "medium band", intensity: "RPE 5/10", duration_minutes: 3, target_area: "Back, biceps" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Banded plank pull-apart", sets: 1, reps: "45 sec", weight_guidance: "light band", intensity: "RPE 5/10", duration_minutes: 1, target_area: "Core, rear delts" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "light_bike_steady",
    title: "Gym Photo: Easy Steady Spin",
    bodyPart: "cardio",
    category: "light",
    highImpact: false,
    requiredEquipment: ["stationary bike"],
    goals: ["active_recovery", "cardio_endurance"],
    focus: "Easy steady-state spin",
    warm_up: WARM_UP_LIGHT,
    blocks: [
      {
        name: "Block 1",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Steady-state cycling", library_id: "Bicycling_Stationary", sets: 1, reps: "20 min", weight_guidance: "light resistance -- you should be able to hold a conversation", intensity: "RPE 4/10", duration_minutes: 20, target_area: "Legs, cardiovascular system" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Slightly-faster spin", library_id: "Bicycling_Stationary", sets: 1, reps: "1 min", weight_guidance: "light-moderate resistance -- a bit quicker than the steady pace above", intensity: "RPE 5/10", duration_minutes: 1, target_area: "Legs, cardiovascular system" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },

  // ---- moderate ----
  {
    id: "moderate_dumbbell_full_body",
    title: "Gym Photo: Dumbbell Strength (Moderate)",
    bodyPart: "full_body",
    category: "moderate",
    highImpact: false,
    requiredEquipment: ["dumbbells"],
    goals: ["build_strength", "gain_muscle", "more_sculpted"],
    focus: "Moderate dumbbell strength",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Block 1",
        rounds: 1,
        rest_between_rounds: "75 sec",
        exercises: [
          { name: "Dumbbell Romanian deadlift", library_id: "Stiff-Legged_Dumbbell_Deadlift", sets: 3, reps: "10", weight_guidance: "moderate, 2x12-20kg", intensity: "RPE 7/10", duration_minutes: 9, target_area: "Hamstrings, glutes" },
          { name: "Dumbbell floor press", library_id: "Dumbbell_Floor_Press", sets: 3, reps: "10", weight_guidance: "moderate, 2x10-16kg", intensity: "RPE 7/10", duration_minutes: 9, target_area: "Chest, triceps" },
        ],
      },
      {
        name: "Superset A",
        rounds: 2,
        rest_between_rounds: "60 sec",
        exercises: [
          { name: "Dumbbell split squat", library_id: "Split_Squat_with_Dumbbells", sets: 1, reps: "10 each leg", weight_guidance: "moderate, 2x8-14kg", intensity: "RPE 7/10", duration_minutes: 4, target_area: "Quads, glutes" },
          { name: "Dumbbell lateral raise", library_id: "Side_Lateral_Raise", sets: 1, reps: "12", weight_guidance: "light, 2x4-8kg", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Side delts" },
        ],
      },
      {
        name: "Block 3 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Dumbbell farmer's carry", library_id: "Farmers_Walk", sets: 1, reps: "40m", weight_guidance: "moderate, 2x12-20kg", intensity: "RPE 7/10", duration_minutes: 1, target_area: "Grip, core, traps" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "moderate_kettlebell_full_body",
    title: "Gym Photo: Kettlebell Strength (Moderate)",
    bodyPart: "full_body",
    category: "moderate",
    highImpact: false,
    requiredEquipment: ["kettlebells"],
    goals: ["cardio_endurance", "build_strength", "leaner_toned"],
    focus: "Moderate kettlebell strength and conditioning",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Block 1",
        rounds: 3,
        rest_between_rounds: "60 sec",
        exercises: [
          { name: "Kettlebell swing", library_id: "One-Arm_Kettlebell_Swings", sets: 1, reps: "15", weight_guidance: "moderate, 1x16-24kg", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Glutes, hamstrings, core" },
          { name: "Kettlebell front squat", library_id: "Front_Squats_With_Two_Kettlebells", sets: 1, reps: "10", weight_guidance: "moderate, 1x16-20kg", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Quads, glutes, core" },
          { name: "Kettlebell single-arm row", library_id: "One-Arm_Kettlebell_Row", sets: 1, reps: "10 each side", weight_guidance: "moderate, 1x16-24kg", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Back, biceps" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Kettlebell rack hold", sets: 1, reps: "45-60 sec", weight_guidance: "moderate, 1x16-20kg", intensity: "RPE 7/10", duration_minutes: 1, target_area: "Core, shoulders, grip" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "moderate_cable_circuit",
    title: "Gym Photo: Cable Machine Circuit",
    bodyPart: "full_body",
    category: "moderate",
    highImpact: false,
    requiredEquipment: ["cable machine"],
    goals: ["gain_muscle", "more_sculpted", "general_fitness"],
    focus: "Moderate cable-machine circuit",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Block 1",
        rounds: 3,
        rest_between_rounds: "60 sec",
        exercises: [
          { name: "Cable row", library_id: "Seated_Cable_Rows", sets: 1, reps: "12", weight_guidance: "moderate -- last rep should feel like RPE 7", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Back, biceps" },
          { name: "Cable chest press", library_id: "Cable_Chest_Press", sets: 1, reps: "12", weight_guidance: "moderate", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Chest, triceps" },
          { name: "Cable woodchop", library_id: "Standing_Cable_Wood_Chop", sets: 1, reps: "10 each side", weight_guidance: "light-moderate", intensity: "RPE 6/10", duration_minutes: 3, target_area: "Obliques, core" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Cable anti-rotation hold", library_id: "Pallof_Press", sets: 1, reps: "45 sec each side", weight_guidance: "light", intensity: "RPE 6/10", duration_minutes: 2, target_area: "Core, obliques" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "moderate_calisthenics_pull",
    title: "Gym Photo: Pulling Calisthenics",
    bodyPart: "upper_body",
    category: "moderate",
    highImpact: false,
    requiredEquipment: ["pull-up bar"],
    goals: ["build_strength", "gain_muscle", "general_fitness"],
    focus: "Moderate pulling-focused calisthenics",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Block 1",
        rounds: 3,
        rest_between_rounds: "90 sec",
        exercises: [
          { name: "Pull-up or assisted pull-up", library_id: "Pullups", sets: 1, reps: "5-8", weight_guidance: "bodyweight -- use a band or your feet on the floor if needed", intensity: "RPE 7/10", duration_minutes: 4, target_area: "Back, biceps" },
          { name: "Hanging knee raise", library_id: "Hanging_Leg_Raise", sets: 1, reps: "10", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Lower abs, hip flexors" },
          { name: "Push-up", library_id: "Pushups", sets: 1, reps: "12", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Chest, shoulders, triceps" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Dead-hang", sets: 1, reps: "20-30 sec", weight_guidance: "bodyweight", intensity: "RPE 6/10", duration_minutes: 1, target_area: "Grip, shoulders, lats" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  // BUG report: confirming a treadmill in the gym photo flow had ZERO
  // effect on template selection -- "treadmill" was a real, recognized
  // EQUIPMENT_VOCABULARY entry (normalizeEquipment matched it correctly)
  // but no template's requiredEquipment ever named it, so it could never
  // become the differentiator between templates. This is that template.
  // Running/sprinting is repeated-impact work -- highImpact: true, unlike
  // the bike/rower cardio-machine templates below (cycling/rowing are
  // low-impact), so this is correctly excluded for a noted injury.
  {
    id: "moderate_treadmill_intervals",
    title: "Gym Photo: Treadmill Intervals",
    bodyPart: "cardio",
    category: "moderate",
    highImpact: true,
    requiredEquipment: ["treadmill"],
    goals: ["cardio_endurance", "lose_weight", "general_fitness"],
    focus: "Treadmill incline walk into tempo and sprint intervals",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Block 1 - Incline Walk",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Incline treadmill walk", library_id: "Walking_Treadmill", sets: 1, reps: "5 min", weight_guidance: "N/A", intensity: "RPE 4/10, incline 6-8%", duration_minutes: 5, target_area: "Legs, cardiovascular system" },
        ],
      },
      {
        name: "Block 2 - Tempo Intervals",
        rounds: 4,
        rest_between_rounds: "60 sec easy walk",
        exercises: [
          { name: "Tempo jog interval", library_id: "Jogging_Treadmill", sets: 1, reps: "2 min", weight_guidance: "N/A", intensity: "RPE 7/10 -- comfortably hard, not a sprint", duration_minutes: 2, target_area: "Legs, cardiovascular system" },
        ],
      },
      {
        name: "Block 3 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "All-out treadmill sprint", library_id: "Running_Treadmill", sets: 1, reps: "30-45 sec max effort", weight_guidance: "N/A", intensity: "RPE 9/10", duration_minutes: 2, target_area: "Legs, cardiovascular system" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },

  // ---- push_hard ----
  {
    id: "push_hard_dumbbell_complex",
    title: "Gym Photo: Dumbbell Complex",
    bodyPart: "full_body",
    category: "push_hard",
    highImpact: false,
    requiredEquipment: ["dumbbells"],
    goals: ["build_strength", "gain_muscle", "lose_weight"],
    focus: "High-effort dumbbell complex",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Block 1",
        rounds: 1,
        rest_between_rounds: "90 sec",
        exercises: [
          { name: "Dumbbell front squat", library_id: "Front_Squats_With_Two_Kettlebells", sets: 4, reps: "8", weight_guidance: "heavy, 2x16-24kg -- last rep should feel like RPE 8", intensity: "RPE 8/10", duration_minutes: 12, target_area: "Quads, glutes, core" },
        ],
      },
      {
        name: "Superset A",
        rounds: 3,
        rest_between_rounds: "60 sec",
        exercises: [
          { name: "Dumbbell push press", sets: 1, reps: "8", weight_guidance: "moderate-heavy, 2x12-18kg", intensity: "RPE 8/10", duration_minutes: 3, target_area: "Shoulders, triceps, legs" },
          { name: "Dumbbell renegade row", library_id: "Alternating_Renegade_Row", sets: 1, reps: "8 each side", weight_guidance: "moderate, 2x10-16kg", intensity: "RPE 8/10", duration_minutes: 3, target_area: "Back, core, shoulders" },
        ],
      },
      {
        name: "Block 3 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Dumbbell farmer's carry", library_id: "Farmers_Walk", sets: 1, reps: "40m", weight_guidance: "heavy, 2x20-30kg", intensity: "RPE 9/10", duration_minutes: 2, target_area: "Grip, traps, core" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "push_hard_kettlebell_conditioning",
    title: "Gym Photo: Kettlebell Conditioning",
    bodyPart: "full_body",
    category: "push_hard",
    highImpact: false,
    requiredEquipment: ["kettlebells"],
    goals: ["cardio_endurance", "lose_weight", "leaner_toned"],
    focus: "High-intensity kettlebell conditioning",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Superset A",
        rounds: 5,
        rest_between_rounds: "45 sec",
        exercises: [
          { name: "Kettlebell swing", library_id: "One-Arm_Kettlebell_Swings", sets: 1, reps: "20", weight_guidance: "moderate-heavy, 1x20-28kg", intensity: "RPE 9/10", duration_minutes: 2, target_area: "Glutes, hamstrings, core" },
          { name: "Kettlebell goblet squat", library_id: "Goblet_Squat", sets: 1, reps: "12", weight_guidance: "moderate, 1x16-24kg", intensity: "RPE 8/10", duration_minutes: 2, target_area: "Quads, glutes, core" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Kettlebell farmer's hold", library_id: "Farmers_Walk", sets: 1, reps: "45 sec", weight_guidance: "heavy, 2x24kg+", intensity: "RPE 9/10", duration_minutes: 2, target_area: "Grip, traps, core" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "push_hard_rower_intervals",
    title: "Gym Photo: Rowing Intervals",
    bodyPart: "cardio",
    category: "push_hard",
    highImpact: false,
    requiredEquipment: ["rowing machine"],
    goals: ["cardio_endurance", "lose_weight"],
    focus: "Hard rowing intervals",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Block 1",
        rounds: 6,
        rest_between_rounds: "90 sec easy paddle",
        exercises: [
          { name: "Rowing interval", library_id: "Rowing_Stationary", sets: 1, reps: "250m hard", weight_guidance: "damper 5-6 -- pace you can just hold for all 6 rounds", intensity: "RPE 9/10", duration_minutes: 3, target_area: "Full body -- legs, back, cardiovascular system" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "All-out row sprint", library_id: "Rowing_Stationary", sets: 1, reps: "60-90 sec max effort", weight_guidance: "damper 7-8", intensity: "RPE 10/10", duration_minutes: 2, target_area: "Full body -- legs, back, cardiovascular system" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },

  // ---- low-impact bodyweight fallbacks ----
  // Required by the invariant on GymWorkoutTemplate.highImpact. Before
  // these existed, the ONLY zero-equipment templates for moderate and
  // push_hard were the jumping ones, so a user with a noted injury and no
  // equipment had no eligible template at all. Effort is carried by tempo
  // and isometrics instead of impact.
  {
    id: "moderate_bodyweight_low_impact",
    title: "Gym Photo: Low-Impact Bodyweight (Moderate)",
    bodyPart: "full_body",
    category: "moderate",
    highImpact: false,
    requiredEquipment: [],
    goals: ["general_fitness", "build_strength", "leaner_toned"],
    focus: "Moderate low-impact bodyweight strength",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Block 1",
        rounds: 3,
        rest_between_rounds: "60 sec",
        exercises: [
          { name: "Tempo bodyweight squat", library_id: "Bodyweight_Squat", sets: 1, reps: "12 (3 sec down, 1 sec up)", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Quads, glutes" },
          { name: "Push-up", library_id: "Pushups", sets: 1, reps: "10", weight_guidance: "bodyweight -- hands elevated if needed", intensity: "RPE 7/10", duration_minutes: 2, target_area: "Chest, shoulders, triceps" },
          { name: "Reverse lunge", sets: 1, reps: "10 each leg", weight_guidance: "bodyweight -- step back, no jumping", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Quads, glutes" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Side plank", library_id: "Side_Bridge", sets: 1, reps: "30 sec each side", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 2, target_area: "Obliques, core" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "push_hard_bodyweight_low_impact",
    title: "Gym Photo: Low-Impact Bodyweight (Hard)",
    bodyPart: "full_body",
    category: "push_hard",
    highImpact: false,
    requiredEquipment: [],
    goals: ["build_strength", "general_fitness", "leaner_toned"],
    focus: "High-effort bodyweight work without impact",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Superset A",
        rounds: 4,
        rest_between_rounds: "45 sec",
        exercises: [
          { name: "Bulgarian split squat", sets: 1, reps: "10 each leg", weight_guidance: "bodyweight -- rear foot on a chair or step", intensity: "RPE 8/10", duration_minutes: 4, target_area: "Quads, glutes" },
          { name: "Tempo push-up", library_id: "Pushups", sets: 1, reps: "8 (3 sec down)", weight_guidance: "bodyweight", intensity: "RPE 8/10", duration_minutes: 3, target_area: "Chest, triceps, shoulders" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Wall sit", sets: 1, reps: "60 sec", weight_guidance: "bodyweight", intensity: "RPE 9/10", duration_minutes: 2, target_area: "Quads" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },

  // ==== Body-part-targeted coverage added 2026-08-19 (fixes gym-photo
  // body-part-blind selection) ====
  // BUG report: until this addition, the entire catalog above had ZERO
  // templates tagged bodyPart "lower_body" and ZERO tagged "core" -- so
  // even after selectTemplate started ranking by resolved target body part
  // (see selectTemplate's doc comment / targetBodyPart.ts), a leg day or
  // ab day had no matching template to prefer and silently fell back to
  // whichever full-body template used the most equipment, which is exactly
  // the bug the fix exists to remove.
  //
  // Coverage below follows an explicit (category x equipment tier) matrix,
  // not just "one template per gap": lower_body gets a bodyweight-only
  // template for both moderate and push_hard (mandatory per the
  // requiredEquipment:[] + highImpact:false invariant documented on
  // GYM_WORKOUT_TEMPLATES above) plus at least one equipped variant per
  // category; core gets the same bodyweight-plus-equipped pairing across
  // ALL THREE of light/moderate/push_hard.
  //
  // "core" here is deliberately genuine ab/core-STRENGTH work (planks,
  // side planks, anti-rotation holds, glute bridges) -- NOT an alias into
  // DailyRecommendation.swift's existing `.core`-tagged workoutSuggestions
  // (yoga session, restorative yoga, foam rolling), which are yoga/
  // mobility content wearing the same BodyPartFocus label. That's a real
  // naming collision worth flagging back rather than silently papering
  // over: the same "core" target can be reached today via a goals/rotation
  // signal that was really asking for flexibility/mobility work, and this
  // gym-photo template will still hand back a hard ab-strength session.
  // Not resolved here -- would need a product decision on whether
  // BodyPartFocus.core should split into two concepts, or the Swift
  // catalog's yoga entries should be retagged off "core" entirely.
  //
  // Every equipped variant below uses "cable machine" (EQUIPMENT_VOCABULARY)
  // for its one genuinely core-specific movement, "Cable anti-rotation
  // hold" (Pallof_Press) -- already audited and in use by
  // moderate_cable_circuit -- deliberately chosen over any crunch/sit-up/
  // twist variant: those are loaded-spinal-flexion or loaded-twisting
  // patterns, exactly what CONTRAINDICATIONS.back (both moderate and
  // severe) exists to keep out of a "core" template, and neither
  // "crunch"/"sit-up" nor a literal "twist" substring is in that back
  // entry's excludedKeywords today -- so a flexion/twist exercise here
  // would NOT have been caught by the existing keyword filter at
  // selection time. Pallof press is anti-rotation (resists a rotational
  // force without the spine actually moving), which is why it's hand-
  // checked safe here rather than excluded/flagged. Every exercise below
  // reuses an already-hand-audited name/library_id from elsewhere in this
  // file (or "Reverse lunge"/"Bulgarian split squat"/"Wall sit", already on
  // CONFIRMED_NO_LIBRARY_EQUIVALENT) rather than introducing a new
  // unaudited one.
  //
  // DRAFTED, NOT EXPERT-REVIEWED -- these are physical prescriptions, same
  // caveat as the 2026-07-28 equipment coverage above; a certified S&C/PT
  // professional should review before this content ships to users.

  // ---- light ----
  {
    id: "light_core",
    title: "Gym Photo: Core Activation (Light)",
    bodyPart: "core",
    category: "light",
    highImpact: false,
    requiredEquipment: [],
    goals: ["general_fitness", "more_sculpted"],
    focus: "Light core activation",
    warm_up: WARM_UP_LIGHT,
    blocks: [
      {
        name: "Block 1",
        rounds: 2,
        rest_between_rounds: "60 sec",
        exercises: [
          { name: "Plank hold", library_id: "Plank", sets: 1, reps: "20-30 sec", weight_guidance: "bodyweight", intensity: "RPE 4/10", duration_minutes: 2, target_area: "Core" },
          { name: "Side plank", library_id: "Side_Bridge", sets: 1, reps: "20 sec each side", weight_guidance: "bodyweight", intensity: "RPE 4/10", duration_minutes: 2, target_area: "Obliques, core" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Glute bridge", library_id: "Butt_Lift_Bridge", sets: 1, reps: "12", weight_guidance: "bodyweight", intensity: "RPE 4/10", duration_minutes: 2, target_area: "Glutes, hamstrings, core" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "light_cable_core",
    title: "Gym Photo: Cable Core Activation (Light)",
    bodyPart: "core",
    category: "light",
    highImpact: false,
    requiredEquipment: ["cable machine"],
    goals: ["general_fitness", "more_sculpted"],
    focus: "Light cable-based core activation",
    warm_up: WARM_UP_LIGHT,
    blocks: [
      {
        name: "Block 1",
        rounds: 2,
        rest_between_rounds: "60 sec",
        exercises: [
          { name: "Cable anti-rotation hold", library_id: "Pallof_Press", sets: 1, reps: "20 sec each side", weight_guidance: "light cable stack", intensity: "RPE 4/10", duration_minutes: 2, target_area: "Core, obliques" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Plank hold", library_id: "Plank", sets: 1, reps: "20-30 sec", weight_guidance: "bodyweight", intensity: "RPE 4/10", duration_minutes: 2, target_area: "Core" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },

  // ---- moderate ----
  {
    id: "moderate_barbell_lower_body",
    title: "Gym Photo: Barbell Lower-Body (Moderate)",
    bodyPart: "lower_body",
    category: "moderate",
    highImpact: false,
    requiredEquipment: ["barbell", "squat rack"],
    goals: ["build_strength", "gain_muscle", "general_fitness"],
    focus: "Moderate barbell lower-body strength",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Block 1",
        rounds: 1,
        rest_between_rounds: "90 sec",
        exercises: [
          { name: "Barbell back squat", library_id: "Barbell_Squat", sets: 4, reps: "8", weight_guidance: "moderate -- last rep should feel like RPE 7", intensity: "RPE 7/10", duration_minutes: 12, target_area: "Quads, glutes, core" },
        ],
      },
      {
        name: "Block 2",
        rounds: 1,
        rest_between_rounds: "90 sec",
        exercises: [
          { name: "Barbell deadlift", library_id: "Barbell_Deadlift", sets: 3, reps: "8", weight_guidance: "moderate -- last rep should feel like RPE 7", intensity: "RPE 7/10", duration_minutes: 10, target_area: "Hamstrings, glutes, back" },
        ],
      },
      {
        name: "Block 3 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Walking lunge with reach", library_id: "Bodyweight_Walking_Lunge", sets: 1, reps: "10 each leg", weight_guidance: "bodyweight", intensity: "RPE 6/10", duration_minutes: 3, target_area: "Quads, glutes, hip flexors" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "moderate_dumbbell_lower_body",
    title: "Gym Photo: Dumbbell Lower-Body (Moderate)",
    bodyPart: "lower_body",
    category: "moderate",
    highImpact: false,
    requiredEquipment: ["dumbbells"],
    goals: ["build_strength", "gain_muscle", "more_sculpted"],
    focus: "Moderate dumbbell lower-body strength",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Block 1",
        rounds: 1,
        rest_between_rounds: "75 sec",
        exercises: [
          { name: "Dumbbell Romanian deadlift", library_id: "Stiff-Legged_Dumbbell_Deadlift", sets: 3, reps: "10", weight_guidance: "moderate, 2x12-20kg", intensity: "RPE 7/10", duration_minutes: 9, target_area: "Hamstrings, glutes" },
          { name: "Dumbbell goblet squat", library_id: "Goblet_Squat", sets: 3, reps: "12", weight_guidance: "moderate, 1x16-24kg", intensity: "RPE 7/10", duration_minutes: 9, target_area: "Quads, glutes, core" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Dumbbell split squat", library_id: "Split_Squat_with_Dumbbells", sets: 1, reps: "10 each leg", weight_guidance: "moderate, 2x8-14kg", intensity: "RPE 7/10", duration_minutes: 4, target_area: "Quads, glutes" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "moderate_bodyweight_lower_body",
    title: "Gym Photo: Bodyweight Lower-Body (Moderate)",
    bodyPart: "lower_body",
    category: "moderate",
    highImpact: false,
    requiredEquipment: [],
    goals: ["general_fitness", "leaner_toned", "build_strength"],
    focus: "Moderate low-impact lower-body strength",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Block 1",
        rounds: 3,
        rest_between_rounds: "60 sec",
        exercises: [
          { name: "Tempo bodyweight squat", library_id: "Bodyweight_Squat", sets: 1, reps: "12 (3 sec down, 1 sec up)", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Quads, glutes" },
          { name: "Reverse lunge", sets: 1, reps: "10 each leg", weight_guidance: "bodyweight -- step back, no jumping", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Quads, glutes" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Glute bridge", library_id: "Butt_Lift_Bridge", sets: 1, reps: "20", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 2, target_area: "Glutes, hamstrings" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "moderate_core",
    title: "Gym Photo: Core Strength (Moderate)",
    bodyPart: "core",
    category: "moderate",
    highImpact: false,
    requiredEquipment: [],
    goals: ["general_fitness", "improve_flexibility", "more_sculpted"],
    focus: "Moderate core strength and stability",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Block 1",
        rounds: 3,
        rest_between_rounds: "45 sec",
        exercises: [
          { name: "Plank hold", library_id: "Plank", sets: 1, reps: "30-45 sec", weight_guidance: "bodyweight", intensity: "RPE 6/10", duration_minutes: 2, target_area: "Core" },
          { name: "Side plank", library_id: "Side_Bridge", sets: 1, reps: "30 sec each side", weight_guidance: "bodyweight", intensity: "RPE 6/10", duration_minutes: 2, target_area: "Obliques, core" },
          { name: "Glute bridge", library_id: "Butt_Lift_Bridge", sets: 1, reps: "15", weight_guidance: "bodyweight", intensity: "RPE 6/10", duration_minutes: 2, target_area: "Glutes, hamstrings, core" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Mountain climber", library_id: "Mountain_Climbers", sets: 1, reps: "30 total", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 2, target_area: "Core, hip flexors" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "moderate_cable_core",
    title: "Gym Photo: Cable Core Stability (Moderate)",
    bodyPart: "core",
    category: "moderate",
    highImpact: false,
    requiredEquipment: ["cable machine"],
    goals: ["general_fitness", "more_sculpted", "build_strength"],
    focus: "Moderate cable-based core stability",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Block 1",
        rounds: 3,
        rest_between_rounds: "45 sec",
        exercises: [
          { name: "Cable anti-rotation hold", library_id: "Pallof_Press", sets: 1, reps: "30 sec each side", weight_guidance: "moderate cable stack", intensity: "RPE 6/10", duration_minutes: 3, target_area: "Core, obliques" },
          { name: "Plank hold", library_id: "Plank", sets: 1, reps: "30-45 sec", weight_guidance: "bodyweight", intensity: "RPE 6/10", duration_minutes: 2, target_area: "Core" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Side plank", library_id: "Side_Bridge", sets: 1, reps: "30 sec each side", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 2, target_area: "Obliques, core" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },

  // ---- push_hard ----
  {
    id: "push_hard_barbell_lower_body",
    title: "Gym Photo: Barbell Lower-Body (Hard)",
    bodyPart: "lower_body",
    category: "push_hard",
    highImpact: false,
    requiredEquipment: ["barbell", "squat rack"],
    goals: ["build_strength", "gain_muscle"],
    focus: "High-effort barbell lower-body strength",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Block 1",
        rounds: 1,
        rest_between_rounds: "2 min",
        exercises: [
          { name: "Barbell back squat", library_id: "Barbell_Squat", sets: 4, reps: "5", weight_guidance: "heavy -- last rep should feel like RPE 8", intensity: "RPE 8/10", duration_minutes: 15, target_area: "Quads, glutes, core" },
        ],
      },
      {
        name: "Block 2",
        rounds: 1,
        rest_between_rounds: "90 sec",
        exercises: [
          { name: "Barbell deadlift", library_id: "Barbell_Deadlift", sets: 3, reps: "6", weight_guidance: "moderate-heavy", intensity: "RPE 8/10", duration_minutes: 10, target_area: "Hamstrings, glutes, back" },
        ],
      },
      {
        name: "Block 3 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Walking lunge with reach", library_id: "Bodyweight_Walking_Lunge", sets: 1, reps: "12 each leg", weight_guidance: "bodyweight", intensity: "RPE 8/10", duration_minutes: 2, target_area: "Quads, glutes, hip flexors" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "push_hard_bodyweight_lower_body",
    title: "Gym Photo: Low-Impact Lower-Body (Hard)",
    bodyPart: "lower_body",
    category: "push_hard",
    highImpact: false,
    requiredEquipment: [],
    goals: ["build_strength", "general_fitness", "leaner_toned"],
    focus: "High-effort low-impact lower-body strength",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Block 1",
        rounds: 4,
        rest_between_rounds: "45 sec",
        exercises: [
          { name: "Bulgarian split squat", sets: 1, reps: "10 each leg", weight_guidance: "bodyweight -- rear foot on a chair or step", intensity: "RPE 8/10", duration_minutes: 4, target_area: "Quads, glutes" },
          { name: "Tempo bodyweight squat", library_id: "Bodyweight_Squat", sets: 1, reps: "15 (3 sec down, 1 sec up)", weight_guidance: "bodyweight", intensity: "RPE 8/10", duration_minutes: 3, target_area: "Quads, glutes" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Wall sit", sets: 1, reps: "60-75 sec", weight_guidance: "bodyweight", intensity: "RPE 9/10", duration_minutes: 2, target_area: "Quads" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "push_hard_core",
    title: "Gym Photo: Core Conditioning (Hard)",
    bodyPart: "core",
    category: "push_hard",
    highImpact: false,
    requiredEquipment: [],
    goals: ["general_fitness", "build_strength", "leaner_toned"],
    focus: "High-effort core conditioning without impact",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Superset A",
        rounds: 4,
        rest_between_rounds: "30 sec",
        exercises: [
          { name: "Plank hold", library_id: "Plank", sets: 1, reps: "45-60 sec", weight_guidance: "bodyweight", intensity: "RPE 8/10", duration_minutes: 2, target_area: "Core" },
          { name: "Mountain climber", library_id: "Mountain_Climbers", sets: 1, reps: "30 total", weight_guidance: "bodyweight", intensity: "RPE 8/10", duration_minutes: 2, target_area: "Core, hip flexors" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Side plank", library_id: "Side_Bridge", sets: 1, reps: "45 sec each side", weight_guidance: "bodyweight", intensity: "RPE 8/10", duration_minutes: 2, target_area: "Obliques, core" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "push_hard_cable_core",
    title: "Gym Photo: Cable Core Conditioning (Hard)",
    bodyPart: "core",
    category: "push_hard",
    highImpact: false,
    requiredEquipment: ["cable machine"],
    goals: ["build_strength", "general_fitness", "leaner_toned"],
    focus: "High-effort cable-based core conditioning",
    warm_up: WARM_UP_MODERATE,
    blocks: [
      {
        name: "Superset A",
        rounds: 4,
        rest_between_rounds: "30 sec",
        exercises: [
          { name: "Cable anti-rotation hold", library_id: "Pallof_Press", sets: 1, reps: "45 sec each side", weight_guidance: "moderate-heavy cable stack", intensity: "RPE 8/10", duration_minutes: 4, target_area: "Core, obliques" },
          { name: "Plank hold", library_id: "Plank", sets: 1, reps: "45-60 sec", weight_guidance: "bodyweight", intensity: "RPE 8/10", duration_minutes: 2, target_area: "Core" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Side plank", library_id: "Side_Bridge", sets: 1, reps: "45 sec each side", weight_guidance: "bodyweight", intensity: "RPE 8/10", duration_minutes: 2, target_area: "Obliques, core" },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
];

/// Deterministic selection: filter by category, keep templates whose
/// equipment the user actually has, then rank by (1) whether the template's
/// bodyPart matches today's resolved target, (2) how much of that equipment
/// it uses, (3) a goals match. Never LLM-driven.
///
/// Ordering matters more than it looks. Bodyweight templates declare
/// `requiredEquipment: []`, which satisfies `.every()` vacuously, so they
/// are candidates for *everyone* -- and they appear first in the array. The
/// previous implementation took `pool.find(goalMatch) ?? pool[0]`, i.e. the
/// first match in declaration order, so a user standing in a fully equipped
/// gym was handed the bodyweight session whenever its goals happened to
/// match. The equipment-specific templates were nearly unreachable, which
/// made the whole photo step decorative. Sorting by specificity first fixed
/// that: if you photographed a squat rack, you get the session that uses it.
///
/// BUG report (2026-08-19): that equipment-first ordering then went too
/// far the other way -- a fully-equipped gym photo always outranked
/// whatever body part today's category actually called for (e.g. a leg day
/// got overridden to a full-body/barbell session just because the photo
/// showed a squat rack). `targetBodyPart` (resolved server-side by
/// targetBodyPart.ts, mirroring the goals+injury-aware default the normal
/// picker flow already applies) is now sort key #1, ahead of equipment
/// specificity -- a body-part match always outranks a bigger equipment
/// match; equipment specificity and goals remain tie-breakers within (and
/// outside) a body-part match, same comparator as before.
/// True if any exercise name or target_area in the template mentions one of
/// the given keywords -- a second, more granular pass on top of the coarse
/// highImpact filter below, from the deterministic contraindication map
/// (see _shared/contraindications.ts). Severe injuries pass a longer
/// keyword list than mild ones, so this excludes more broadly for them.
function matchesExcludedKeyword(t: GymWorkoutTemplate, keywords: string[]): boolean {
  if (keywords.length === 0) return false;
  const haystack = [t.warm_up, ...t.blocks.map((b) => b.exercises), t.cool_down]
    .flat()
    .map((e) => `${e.name} ${e.target_area}`.toLowerCase())
    .join(" ");
  return keywords.some((kw) => haystack.includes(kw.toLowerCase()));
}

export function selectTemplate(
  category: string,
  confirmedEquipment: Set<string>,
  goals: string[],
  excludeHighImpact = false,
  excludedKeywords: string[] = [],
  // Optional and trailing so existing callers (and every pre-existing test
  // below) that don't pass one keep today's equipment-first behavior
  // unchanged. index.ts always resolves and passes one in production.
  targetBodyPart?: string,
): GymWorkoutTemplate {
  const normalizedEquipment = normalizeEquipment(Array.from(confirmedEquipment));
  const inCategory = GYM_WORKOUT_TEMPLATES.filter((t) =>
    t.category === category && (!excludeHighImpact || !t.highImpact)
  );
  // Soft on purpose: the ~20-template library hasn't been manually audited
  // against every contraindication keyword yet (tracked as a follow-up), so
  // if applying it would leave nothing for this category, fall back to the
  // coarse highImpact-only filter rather than throwing -- excludeHighImpact
  // is still the hard safety floor either way.
  const keywordFiltered = inCategory.filter((t) => !matchesExcludedKeyword(t, excludedKeywords));
  const afterKeywordFilter = keywordFiltered.length > 0 ? keywordFiltered : inCategory;
  const candidates = afterKeywordFilter.filter((t) =>
    t.requiredEquipment.every((eq) => normalizedEquipment.has(eq))
  );
  // The zero-equipment fallback must respect the keyword filter too: it
  // fires precisely when every keyword-safe template needed missing
  // equipment, so drawing it from `inCategory` handed back a
  // keyword-violating template (bodyweight squats to a severe-knee user)
  // in exactly the case the filter mattered most. Keyword-safe
  // zero-equipment first; the raw zero-equipment pool remains as the very
  // last resort per the soft-filter policy above -- excludeHighImpact is
  // already baked into `inCategory` as the hard floor either way.
  const zeroEquipmentSafe = afterKeywordFilter.filter((t) => t.requiredEquipment.length === 0);
  const pool = candidates.length > 0
    ? candidates
    : zeroEquipmentSafe.length > 0
      ? zeroEquipmentSafe
      : inCategory.filter((t) => t.requiredEquipment.length === 0);
  // Deliberately loud. The alternative -- relaxing excludeHighImpact to
  // find something -- would hand an injured user the jumping session, which
  // is the one outcome this filter exists to prevent. If this throws, the
  // invariant documented on GymWorkoutTemplate.highImpact has been broken
  // and the template library needs fixing, not the caller.
  if (pool.length === 0) {
    throw new Error(
      `no gym workout template available for category "${category}"` +
        (excludeHighImpact ? " with high-impact templates excluded" : ""),
    );
  }

  const matchesGoal = (t: GymWorkoutTemplate) => t.goals.some((g) => goals.includes(g));
  const ranked = [...pool].sort((a, b) => {
    // 1. A body-part match always outranks a bigger equipment match --
    // otherwise a well-equipped photo silently overrides today's actual
    // training target (see BUG report above selectTemplate's doc comment).
    if (targetBodyPart) {
      const aTarget = Number(a.bodyPart === targetBodyPart);
      const bTarget = Number(b.bodyPart === targetBodyPart);
      if (aTarget !== bTarget) return bTarget - aTarget;
    }
    // 2. Among body-part ties, use as much of the user's actual equipment
    // as possible.
    if (b.requiredEquipment.length !== a.requiredEquipment.length) {
      return b.requiredEquipment.length - a.requiredEquipment.length;
    }
    // 3. Among equally specific options, honour the user's goals.
    return Number(matchesGoal(b)) - Number(matchesGoal(a));
  });
  return ranked[0];
}
