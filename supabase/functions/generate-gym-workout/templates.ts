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
}

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
  { name: "Arm circles", sets: 1, reps: "20 total", weight_guidance: "N/A", intensity: "easy", duration_minutes: 1, target_area: "Shoulders" },
];

// Equipment-free by necessity: this warm-up is shared by every moderate and
// push_hard template, INCLUDING the zero-equipment ones. It used to open with
// an incline treadmill walk, so a user who photographed an empty living room
// was told to start on a treadmill they had just demonstrated they lacked.
// Nothing in a shared warm-up may assume equipment that individual templates
// do not require.
const WARM_UP_MODERATE: TemplateExercise[] = [
  { name: "Brisk march in place", sets: 1, reps: "5 min", weight_guidance: "N/A", intensity: "easy", duration_minutes: 5, target_area: "Full body -- raises heart rate and core temperature" },
  { name: "Bodyweight squats", sets: 1, reps: "10", weight_guidance: "N/A", intensity: "easy", duration_minutes: 2, target_area: "Quads, glutes" },
  { name: "Shoulder rolls", sets: 1, reps: "10 each direction", weight_guidance: "N/A", intensity: "easy", duration_minutes: 1, target_area: "Shoulders" },
];

const COOL_DOWN: TemplateExercise[] = [
  { name: "Standing quad stretch", sets: 1, reps: "30 sec each side", weight_guidance: "N/A", intensity: "easy", duration_minutes: 2, target_area: "Quads" },
  { name: "Seated forward fold", sets: 1, reps: "45 sec", weight_guidance: "N/A", intensity: "easy", duration_minutes: 1, target_area: "Hamstrings, lower back" },
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
          { name: "Cat-cow stretch", sets: 1, reps: "10", weight_guidance: "N/A", intensity: "easy", duration_minutes: 3, target_area: "Spine, core" },
          { name: "Hip circles", sets: 1, reps: "10 each direction", weight_guidance: "N/A", intensity: "easy", duration_minutes: 2, target_area: "Hips" },
          { name: "Walking lunge with reach", sets: 1, reps: "8 each leg", weight_guidance: "bodyweight", intensity: "easy", duration_minutes: 4, target_area: "Quads, glutes, hip flexors" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Supported child's pose with deep breathing", sets: 1, reps: "90 sec", weight_guidance: "N/A", intensity: "RPE 2/10", duration_minutes: 2, target_area: "Nervous system, lower back -- brings heart rate down" },
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
          { name: "Bodyweight squat", sets: 1, reps: "12", weight_guidance: "bodyweight", intensity: "RPE 5/10", duration_minutes: 3, target_area: "Quads, glutes" },
          { name: "Incline push-up", sets: 1, reps: "10", weight_guidance: "bodyweight", intensity: "RPE 5/10", duration_minutes: 3, target_area: "Chest, shoulders, triceps" },
          { name: "Glute bridge", sets: 1, reps: "15", weight_guidance: "bodyweight", intensity: "RPE 5/10", duration_minutes: 3, target_area: "Glutes, hamstrings" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Plank hold", sets: 1, reps: "30-45 sec", weight_guidance: "bodyweight", intensity: "RPE 5/10", duration_minutes: 1, target_area: "Core" },
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
          { name: "Dumbbell goblet squat", sets: 1, reps: "12", weight_guidance: "light, 2x8-12kg", intensity: "RPE 5/10", duration_minutes: 3, target_area: "Quads, glutes, core" },
          { name: "Dumbbell shoulder press", sets: 1, reps: "10", weight_guidance: "light, 2x5-8kg", intensity: "RPE 5/10", duration_minutes: 3, target_area: "Shoulders, triceps" },
          { name: "Dumbbell row", sets: 1, reps: "12 each side", weight_guidance: "light, 1x8-12kg", intensity: "RPE 5/10", duration_minutes: 3, target_area: "Back, biceps" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Dumbbell farmer's hold", sets: 1, reps: "45 sec", weight_guidance: "light, 2x8-12kg", intensity: "RPE 5/10", duration_minutes: 1, target_area: "Grip, core" },
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
          { name: "Jump squat", sets: 1, reps: "10", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 2, target_area: "Quads, glutes, calves" },
          { name: "Push-up", sets: 1, reps: "12", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 2, target_area: "Chest, shoulders, triceps" },
          { name: "Mountain climber", sets: 1, reps: "20 total", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 2, target_area: "Core, hip flexors" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Plank hold", sets: 1, reps: "45 sec", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 2, target_area: "Core" },
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
          { name: "Barbell back squat", sets: 4, reps: "8", weight_guidance: "moderate -- last rep should feel like RPE 7", intensity: "RPE 7/10", duration_minutes: 12, target_area: "Quads, glutes, core" },
        ],
      },
      {
        name: "Block 2",
        rounds: 1,
        rest_between_rounds: "90 sec",
        exercises: [
          { name: "Barbell bench press", sets: 3, reps: "8", weight_guidance: "moderate -- last rep should feel like RPE 7", intensity: "RPE 7/10", duration_minutes: 10, target_area: "Chest, shoulders, triceps" },
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
          { name: "Jump lunge", sets: 1, reps: "16 total", weight_guidance: "bodyweight", intensity: "RPE 9/10", duration_minutes: 2, target_area: "Quads, glutes, calves" },
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
          { name: "Barbell deadlift", sets: 4, reps: "5", weight_guidance: "heavy -- last rep should feel like RPE 8", intensity: "RPE 8/10", duration_minutes: 15, target_area: "Hamstrings, glutes, back" },
        ],
      },
      {
        name: "Superset A",
        rounds: 3,
        rest_between_rounds: "60 sec",
        exercises: [
          { name: "Barbell overhead press", sets: 1, reps: "6", weight_guidance: "moderate-heavy", intensity: "RPE 8/10", duration_minutes: 3, target_area: "Shoulders, triceps" },
          // Was a pull-up, and the finisher below was a dumbbell farmer's
          // carry -- both needed equipment this template does not require,
          // so a user with only a barbell and rack was prescribed movements
          // they had no way to perform. Every exercise here now uses only
          // what requiredEquipment guarantees.
          { name: "Barbell bent-over row", sets: 1, reps: "8", weight_guidance: "moderate", intensity: "RPE 8/10", duration_minutes: 3, target_area: "Back, biceps" },
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
          { name: "Foam roll quads", sets: 1, reps: "60 sec each leg", weight_guidance: "N/A", intensity: "easy", duration_minutes: 3, target_area: "Quads" },
          { name: "Foam roll upper back", sets: 1, reps: "90 sec", weight_guidance: "N/A", intensity: "easy", duration_minutes: 2, target_area: "Upper back, thoracic spine" },
          { name: "Foam roll glutes", sets: 1, reps: "60 sec each side", weight_guidance: "N/A", intensity: "easy", duration_minutes: 3, target_area: "Glutes" },
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
          { name: "Kettlebell goblet squat", sets: 1, reps: "10", weight_guidance: "light, 1x12-16kg", intensity: "RPE 5/10", duration_minutes: 3, target_area: "Quads, glutes, core" },
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
          { name: "Band pull-apart", sets: 1, reps: "15", weight_guidance: "light band", intensity: "RPE 4/10", duration_minutes: 2, target_area: "Rear delts, upper back" },
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
          { name: "Steady-state cycling", sets: 1, reps: "20 min", weight_guidance: "light resistance -- you should be able to hold a conversation", intensity: "RPE 4/10", duration_minutes: 20, target_area: "Legs, cardiovascular system" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Slightly-faster spin", sets: 1, reps: "1 min", weight_guidance: "light-moderate resistance -- a bit quicker than the steady pace above", intensity: "RPE 5/10", duration_minutes: 1, target_area: "Legs, cardiovascular system" },
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
          { name: "Dumbbell Romanian deadlift", sets: 3, reps: "10", weight_guidance: "moderate, 2x12-20kg", intensity: "RPE 7/10", duration_minutes: 9, target_area: "Hamstrings, glutes" },
          { name: "Dumbbell floor press", sets: 3, reps: "10", weight_guidance: "moderate, 2x10-16kg", intensity: "RPE 7/10", duration_minutes: 9, target_area: "Chest, triceps" },
        ],
      },
      {
        name: "Superset A",
        rounds: 2,
        rest_between_rounds: "60 sec",
        exercises: [
          { name: "Dumbbell split squat", sets: 1, reps: "10 each leg", weight_guidance: "moderate, 2x8-14kg", intensity: "RPE 7/10", duration_minutes: 4, target_area: "Quads, glutes" },
          { name: "Dumbbell lateral raise", sets: 1, reps: "12", weight_guidance: "light, 2x4-8kg", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Side delts" },
        ],
      },
      {
        name: "Block 3 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Dumbbell farmer's carry", sets: 1, reps: "40m", weight_guidance: "moderate, 2x12-20kg", intensity: "RPE 7/10", duration_minutes: 1, target_area: "Grip, core, traps" },
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
          { name: "Kettlebell swing", sets: 1, reps: "15", weight_guidance: "moderate, 1x16-24kg", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Glutes, hamstrings, core" },
          { name: "Kettlebell front squat", sets: 1, reps: "10", weight_guidance: "moderate, 1x16-20kg", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Quads, glutes, core" },
          { name: "Kettlebell single-arm row", sets: 1, reps: "10 each side", weight_guidance: "moderate, 1x16-24kg", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Back, biceps" },
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
          { name: "Cable row", sets: 1, reps: "12", weight_guidance: "moderate -- last rep should feel like RPE 7", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Back, biceps" },
          { name: "Cable chest press", sets: 1, reps: "12", weight_guidance: "moderate", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Chest, triceps" },
          { name: "Cable woodchop", sets: 1, reps: "10 each side", weight_guidance: "light-moderate", intensity: "RPE 6/10", duration_minutes: 3, target_area: "Obliques, core" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Cable anti-rotation hold", sets: 1, reps: "45 sec each side", weight_guidance: "light", intensity: "RPE 6/10", duration_minutes: 2, target_area: "Core, obliques" },
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
          { name: "Pull-up or assisted pull-up", sets: 1, reps: "5-8", weight_guidance: "bodyweight -- use a band or your feet on the floor if needed", intensity: "RPE 7/10", duration_minutes: 4, target_area: "Back, biceps" },
          { name: "Hanging knee raise", sets: 1, reps: "10", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Lower abs, hip flexors" },
          { name: "Push-up", sets: 1, reps: "12", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Chest, shoulders, triceps" },
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
          { name: "Dumbbell front squat", sets: 4, reps: "8", weight_guidance: "heavy, 2x16-24kg -- last rep should feel like RPE 8", intensity: "RPE 8/10", duration_minutes: 12, target_area: "Quads, glutes, core" },
        ],
      },
      {
        name: "Superset A",
        rounds: 3,
        rest_between_rounds: "60 sec",
        exercises: [
          { name: "Dumbbell push press", sets: 1, reps: "8", weight_guidance: "moderate-heavy, 2x12-18kg", intensity: "RPE 8/10", duration_minutes: 3, target_area: "Shoulders, triceps, legs" },
          { name: "Dumbbell renegade row", sets: 1, reps: "8 each side", weight_guidance: "moderate, 2x10-16kg", intensity: "RPE 8/10", duration_minutes: 3, target_area: "Back, core, shoulders" },
        ],
      },
      {
        name: "Block 3 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Dumbbell farmer's carry", sets: 1, reps: "40m", weight_guidance: "heavy, 2x20-30kg", intensity: "RPE 9/10", duration_minutes: 2, target_area: "Grip, traps, core" },
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
          { name: "Kettlebell swing", sets: 1, reps: "20", weight_guidance: "moderate-heavy, 1x20-28kg", intensity: "RPE 9/10", duration_minutes: 2, target_area: "Glutes, hamstrings, core" },
          { name: "Kettlebell goblet squat", sets: 1, reps: "12", weight_guidance: "moderate, 1x16-24kg", intensity: "RPE 8/10", duration_minutes: 2, target_area: "Quads, glutes, core" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Kettlebell farmer's hold", sets: 1, reps: "45 sec", weight_guidance: "heavy, 2x24kg+", intensity: "RPE 9/10", duration_minutes: 2, target_area: "Grip, traps, core" },
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
          { name: "Rowing interval", sets: 1, reps: "250m hard", weight_guidance: "damper 5-6 -- pace you can just hold for all 6 rounds", intensity: "RPE 9/10", duration_minutes: 3, target_area: "Full body -- legs, back, cardiovascular system" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "All-out row sprint", sets: 1, reps: "60-90 sec max effort", weight_guidance: "damper 7-8", intensity: "RPE 10/10", duration_minutes: 2, target_area: "Full body -- legs, back, cardiovascular system" },
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
          { name: "Tempo bodyweight squat", sets: 1, reps: "12 (3 sec down, 1 sec up)", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Quads, glutes" },
          { name: "Push-up", sets: 1, reps: "10", weight_guidance: "bodyweight -- hands elevated if needed", intensity: "RPE 7/10", duration_minutes: 2, target_area: "Chest, shoulders, triceps" },
          { name: "Reverse lunge", sets: 1, reps: "10 each leg", weight_guidance: "bodyweight -- step back, no jumping", intensity: "RPE 7/10", duration_minutes: 3, target_area: "Quads, glutes" },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Side plank", sets: 1, reps: "30 sec each side", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 2, target_area: "Obliques, core" },
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
          { name: "Tempo push-up", sets: 1, reps: "8 (3 sec down)", weight_guidance: "bodyweight", intensity: "RPE 8/10", duration_minutes: 3, target_area: "Chest, triceps, shoulders" },
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
];

/// Deterministic selection: filter by category, keep templates whose
/// equipment the user actually has, then prefer the one that makes the most
/// use of that equipment, breaking ties on a goals match. Never LLM-driven.
///
/// Ordering matters more than it looks. Bodyweight templates declare
/// `requiredEquipment: []`, which satisfies `.every()` vacuously, so they
/// are candidates for *everyone* -- and they appear first in the array. The
/// previous implementation took `pool.find(goalMatch) ?? pool[0]`, i.e. the
/// first match in declaration order, so a user standing in a fully equipped
/// gym was handed the bodyweight session whenever its goals happened to
/// match. The equipment-specific templates were nearly unreachable, which
/// made the whole photo step decorative. Sorting by specificity first fixes
/// that: if you photographed a squat rack, you get the session that uses it.
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
  // `candidates` always contains at least the zero-equipment templates, so
  // this fallback only fires if a category somehow has none declared.
  const pool = candidates.length > 0
    ? candidates
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
    // 1. Use as much of the user's actual equipment as possible.
    if (b.requiredEquipment.length !== a.requiredEquipment.length) {
      return b.requiredEquipment.length - a.requiredEquipment.length;
    }
    // 2. Among equally specific options, honour the user's goals.
    return Number(matchesGoal(b)) - Number(matchesGoal(a));
  });
  return ranked[0];
}
