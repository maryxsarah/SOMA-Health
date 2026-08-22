// Anthropic's json_schema output doesn't support min/max, so this clamp is
// the only real bound. Matches the CHECK constraints in 20260806080000_add_meal_log_macro_bounds.sql.
export const MAX_CALORIES = 5000;
export const MAX_MACRO_G = 500;

// Defensive ceiling on the ingredients array itself -- a pathological
// input (or a model that ignores the prompt) shouldn't be able to produce
// an unbounded array. 15 is generous for any real single meal description.
export const MAX_INGREDIENTS = 15;

export interface MealIngredientEstimate {
  name: string;
  gramsEstimate: number;
  calories: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
}

/// Raw shape returned by Claude -- ingredients only, no totals. Totals are
/// never asked of the model; they're computed by summing this array (see
/// sumIngredients below), so the returned total can never disagree with
/// the model's own per-item numbers the way an independently-stated total
/// could.
export interface RawMealEstimate {
  label: string;
  ingredients: MealIngredientEstimate[];
}

/// Final shape returned to the client -- unchanged from before this
/// redesign (calories/proteinG/carbsG/fatG totals), plus the new
/// ingredients array. LogMealView's existing field-population code reads
/// the four total fields exactly as it always has.
export interface MealEstimate {
  label: string;
  calories: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  ingredients: MealIngredientEstimate[];
}

function clamp(n: number, max: number): number {
  return Math.max(0, Math.min(max, Math.round(n)));
}

function clampIngredient(raw: MealIngredientEstimate): MealIngredientEstimate {
  return {
    name: raw.name,
    gramsEstimate: Math.max(0, Math.round(raw.gramsEstimate)),
    calories: clamp(raw.calories, MAX_CALORIES),
    proteinG: clamp(raw.proteinG, MAX_MACRO_G),
    carbsG: clamp(raw.carbsG, MAX_MACRO_G),
    fatG: clamp(raw.fatG, MAX_MACRO_G),
  };
}

/// Sums a (already-clamped) ingredients array into meal-level totals, then
/// clamps the sum too -- several small in-range ingredients could still
/// sum past MAX_CALORIES/MAX_MACRO_G.
export function sumIngredients(ingredients: MealIngredientEstimate[]): {
  calories: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
} {
  const totals = ingredients.reduce(
    (acc, ing) => ({
      calories: acc.calories + ing.calories,
      proteinG: acc.proteinG + ing.proteinG,
      carbsG: acc.carbsG + ing.carbsG,
      fatG: acc.fatG + ing.fatG,
    }),
    { calories: 0, proteinG: 0, carbsG: 0, fatG: 0 },
  );
  return {
    calories: clamp(totals.calories, MAX_CALORIES),
    proteinG: clamp(totals.proteinG, MAX_MACRO_G),
    carbsG: clamp(totals.carbsG, MAX_MACRO_G),
    fatG: clamp(totals.fatG, MAX_MACRO_G),
  };
}

export function clampEstimate(raw: RawMealEstimate): MealEstimate {
  const ingredients = raw.ingredients.slice(0, MAX_INGREDIENTS).map(clampIngredient);
  const totals = sumIngredients(ingredients);
  return {
    label: raw.label,
    ingredients,
    ...totals,
  };
}
