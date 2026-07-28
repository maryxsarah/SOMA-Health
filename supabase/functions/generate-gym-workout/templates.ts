// Fixed, versioned-in-code template library for the gym-photo-workout
// feature -- deliberately NOT an admin-managed DB table for v1, and
// deliberately NOT LLM-generated: template selection is a decision, not a
// generation task, per the product requirement that this step stay
// deterministic. Analogous in spirit to the Swift-side
// RecommendationCategory.workoutSuggestions fixed catalog.

export interface TemplateExercise {
  name: string;
  sets: number;
  reps: string;
  weight_guidance: string;
  intensity: string;
  duration_minutes: number;
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
  // Empty array = bodyweight-only, always available regardless of what
  // equipment was detected/confirmed.
  requiredEquipment: string[];
  // GoalTag raw values (Soma/Models/DailyRecommendation.swift), for
  // prioritization only -- never a hard filter.
  goals: string[];
  focus: string;
  warm_up: TemplateExercise[];
  blocks: TemplateBlock[];
  cool_down: TemplateExercise[];
}

const WARM_UP_LIGHT: TemplateExercise[] = [
  { name: "Brisk walk in place", sets: 1, reps: "3 min", weight_guidance: "N/A", intensity: "easy", duration_minutes: 3 },
  { name: "Arm circles", sets: 1, reps: "20 total", weight_guidance: "N/A", intensity: "easy", duration_minutes: 1 },
];

const WARM_UP_MODERATE: TemplateExercise[] = [
  { name: "Incline treadmill walk", sets: 1, reps: "5 min", weight_guidance: "N/A", intensity: "easy", duration_minutes: 5 },
  { name: "Bodyweight squats", sets: 1, reps: "10", weight_guidance: "N/A", intensity: "easy", duration_minutes: 2 },
  { name: "Shoulder rolls", sets: 1, reps: "10 each direction", weight_guidance: "N/A", intensity: "easy", duration_minutes: 1 },
];

const COOL_DOWN: TemplateExercise[] = [
  { name: "Standing quad stretch", sets: 1, reps: "30 sec each side", weight_guidance: "N/A", intensity: "easy", duration_minutes: 2 },
  { name: "Seated forward fold", sets: 1, reps: "45 sec", weight_guidance: "N/A", intensity: "easy", duration_minutes: 1 },
  { name: "Box breathing", sets: 1, reps: "2 min", weight_guidance: "N/A", intensity: "easy", duration_minutes: 2 },
];

export const GYM_WORKOUT_TEMPLATES: GymWorkoutTemplate[] = [
  // ---- rest ----
  {
    id: "rest_bodyweight_mobility",
    category: "rest",
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
          { name: "Cat-cow stretch", sets: 1, reps: "10", weight_guidance: "N/A", intensity: "easy", duration_minutes: 3 },
          { name: "Hip circles", sets: 1, reps: "10 each direction", weight_guidance: "N/A", intensity: "easy", duration_minutes: 2 },
          { name: "Walking lunge with reach", sets: 1, reps: "8 each leg", weight_guidance: "bodyweight", intensity: "easy", duration_minutes: 4 },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },

  // ---- light ----
  {
    id: "light_bodyweight_full_body",
    category: "light",
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
          { name: "Bodyweight squat", sets: 1, reps: "12", weight_guidance: "bodyweight", intensity: "RPE 5/10", duration_minutes: 3 },
          { name: "Incline push-up", sets: 1, reps: "10", weight_guidance: "bodyweight", intensity: "RPE 5/10", duration_minutes: 3 },
          { name: "Glute bridge", sets: 1, reps: "15", weight_guidance: "bodyweight", intensity: "RPE 5/10", duration_minutes: 3 },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "light_dumbbells_full_body",
    category: "light",
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
          { name: "Dumbbell goblet squat", sets: 1, reps: "12", weight_guidance: "light, 2x8-12kg", intensity: "RPE 5/10", duration_minutes: 3 },
          { name: "Dumbbell shoulder press", sets: 1, reps: "10", weight_guidance: "light, 2x5-8kg", intensity: "RPE 5/10", duration_minutes: 3 },
          { name: "Dumbbell row", sets: 1, reps: "12 each side", weight_guidance: "light, 1x8-12kg", intensity: "RPE 5/10", duration_minutes: 3 },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },

  // ---- moderate ----
  {
    id: "moderate_bodyweight_full_body",
    category: "moderate",
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
          { name: "Jump squat", sets: 1, reps: "10", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 2 },
          { name: "Push-up", sets: 1, reps: "12", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 2 },
          { name: "Mountain climber", sets: 1, reps: "20 total", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 2 },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Plank hold", sets: 1, reps: "45 sec", weight_guidance: "bodyweight", intensity: "RPE 7/10", duration_minutes: 2 },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "moderate_barbell_full_body",
    category: "moderate",
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
          { name: "Barbell back squat", sets: 4, reps: "8", weight_guidance: "moderate -- last rep should feel like RPE 7", intensity: "RPE 7/10", duration_minutes: 12 },
        ],
      },
      {
        name: "Block 2",
        rounds: 1,
        rest_between_rounds: "90 sec",
        exercises: [
          { name: "Barbell bench press", sets: 3, reps: "8", weight_guidance: "moderate -- last rep should feel like RPE 7", intensity: "RPE 7/10", duration_minutes: 10 },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },

  // ---- push_hard ----
  {
    id: "push_hard_bodyweight_hiit",
    category: "push_hard",
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
          { name: "Burpee", sets: 1, reps: "12", weight_guidance: "bodyweight", intensity: "RPE 9/10", duration_minutes: 2 },
          { name: "Jump lunge", sets: 1, reps: "16 total", weight_guidance: "bodyweight", intensity: "RPE 9/10", duration_minutes: 2 },
        ],
      },
      {
        name: "Block 2 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Sprint in place", sets: 1, reps: "60 sec max effort", weight_guidance: "bodyweight", intensity: "RPE 10/10", duration_minutes: 1 },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
  {
    id: "push_hard_barbell_strength",
    category: "push_hard",
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
          { name: "Barbell deadlift", sets: 4, reps: "5", weight_guidance: "heavy -- last rep should feel like RPE 8", intensity: "RPE 8/10", duration_minutes: 15 },
        ],
      },
      {
        name: "Superset A",
        rounds: 3,
        rest_between_rounds: "60 sec",
        exercises: [
          { name: "Barbell overhead press", sets: 1, reps: "6", weight_guidance: "moderate-heavy", intensity: "RPE 8/10", duration_minutes: 3 },
          { name: "Pull-up", sets: 1, reps: "6-8", weight_guidance: "bodyweight", intensity: "RPE 8/10", duration_minutes: 3 },
        ],
      },
      {
        name: "Block 3 - Finisher",
        rounds: 1,
        rest_between_rounds: "N/A",
        exercises: [
          { name: "Farmer's carry", sets: 1, reps: "40m", weight_guidance: "heavy dumbbells", intensity: "RPE 9/10", duration_minutes: 2 },
        ],
      },
    ],
    cool_down: COOL_DOWN,
  },
];

/// Deterministic selection: filter by category + equipment subset,
/// prioritize a goals match, fall back to the guaranteed bodyweight
/// template for that category if nothing else matches. Never LLM-driven.
export function selectTemplate(
  category: string,
  confirmedEquipment: Set<string>,
  goals: string[],
): GymWorkoutTemplate {
  const normalizedEquipment = new Set(
    Array.from(confirmedEquipment, (e) => e.toLowerCase().trim()),
  );
  const inCategory = GYM_WORKOUT_TEMPLATES.filter((t) => t.category === category);
  const candidates = inCategory.filter((t) =>
    t.requiredEquipment.every((eq) => normalizedEquipment.has(eq))
  );
  const pool = candidates.length > 0 ? candidates : inCategory.filter((t) => t.requiredEquipment.length === 0);
  const goalMatch = pool.find((t) => t.goals.some((g) => goals.includes(g)));
  return goalMatch ?? pool[0];
}
