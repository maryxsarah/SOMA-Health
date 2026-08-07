// Anthropic's json_schema output doesn't support min/max, so this clamp is
// the only real bound. Matches the CHECK constraints in 20260806080000_add_meal_log_macro_bounds.sql.
export const MAX_CALORIES = 5000;
export const MAX_MACRO_G = 500;

export interface MealEstimate {
  label: string;
  calories: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
}

function clamp(n: number, max: number): number {
  return Math.max(0, Math.min(max, Math.round(n)));
}

export function clampEstimate(raw: MealEstimate): MealEstimate {
  return {
    label: raw.label,
    calories: clamp(raw.calories, MAX_CALORIES),
    proteinG: clamp(raw.proteinG, MAX_MACRO_G),
    carbsG: clamp(raw.carbsG, MAX_MACRO_G),
    fatG: clamp(raw.fatG, MAX_MACRO_G),
  };
}
