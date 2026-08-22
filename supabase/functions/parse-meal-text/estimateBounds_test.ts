import { assertEquals } from "jsr:@std/assert";
import { clampEstimate, MAX_CALORIES, MAX_INGREDIENTS, MAX_MACRO_G, sumIngredients } from "./estimateBounds.ts";

function ingredient(
  overrides: Partial<{ name: string; gramsEstimate: number; calories: number; proteinG: number; carbsG: number; fatG: number }> = {},
) {
  return { name: "Item", gramsEstimate: 100, calories: 100, proteinG: 10, carbsG: 10, fatG: 5, ...overrides };
}

Deno.test("sums a normal, in-range ingredients array into totals unchanged", () => {
  const result = clampEstimate({
    label: "Chicken and rice",
    ingredients: [
      ingredient({ name: "Chicken breast", gramsEstimate: 150, calories: 250, proteinG: 32, carbsG: 0, fatG: 12 }),
      ingredient({ name: "Rice", gramsEstimate: 158, calories: 270, proteinG: 10, carbsG: 55, fatG: 0 }),
    ],
  });
  assertEquals(result.label, "Chicken and rice");
  assertEquals(result.calories, 520);
  assertEquals(result.proteinG, 42);
  assertEquals(result.carbsG, 55);
  assertEquals(result.fatG, 12);
  assertEquals(result.ingredients.length, 2);
});

Deno.test("the returned total is always the sum of the ingredients, never an independent number", () => {
  // Guards the whole point of this redesign: totals are computed, not
  // asked of the model as a second figure that could disagree with its
  // own per-item numbers.
  const ingredients = [
    ingredient({ calories: 111, proteinG: 7, carbsG: 13, fatG: 3 }),
    ingredient({ calories: 222, proteinG: 14, carbsG: 26, fatG: 6 }),
    ingredient({ calories: 333, proteinG: 21, carbsG: 39, fatG: 9 }),
  ];
  const result = clampEstimate({ label: "Three items", ingredients });
  const expected = sumIngredients(ingredients);
  assertEquals(result.calories, expected.calories);
  assertEquals(result.proteinG, expected.proteinG);
  assertEquals(result.carbsG, expected.carbsG);
  assertEquals(result.fatG, expected.fatG);
});

Deno.test("clamps a single ingredient's calories above the ceiling instead of trusting the model", () => {
  const result = clampEstimate({ label: "Feast", ingredients: [ingredient({ calories: 99999 })] });
  assertEquals(result.ingredients[0].calories, MAX_CALORIES);
});

Deno.test("clamps each ingredient's macros above their own ceiling independently", () => {
  const result = clampEstimate({
    label: "Feast",
    ingredients: [ingredient({ calories: 1000, proteinG: 9000, carbsG: 9000, fatG: 9000 })],
  });
  assertEquals(result.ingredients[0].proteinG, MAX_MACRO_G);
  assertEquals(result.ingredients[0].carbsG, MAX_MACRO_G);
  assertEquals(result.ingredients[0].fatG, MAX_MACRO_G);
});

Deno.test("clamps the SUMMED total too, even when every individual ingredient is in range", () => {
  // Several small in-range ingredients can still sum past the ceiling.
  const ingredients = Array.from({ length: 10 }, () => ingredient({ calories: 900, proteinG: 90, carbsG: 90, fatG: 90 }));
  const result = clampEstimate({ label: "Buffet", ingredients });
  assertEquals(result.calories, MAX_CALORIES);
  assertEquals(result.proteinG, MAX_MACRO_G);
  assertEquals(result.carbsG, MAX_MACRO_G);
  assertEquals(result.fatG, MAX_MACRO_G);
});

Deno.test("clamps negative ingredient values up to zero rather than passing them through", () => {
  const result = clampEstimate({
    label: "Bad estimate",
    ingredients: [ingredient({ gramsEstimate: -20, calories: -50, proteinG: -5, carbsG: -5, fatG: -5 })],
  });
  assertEquals(result.ingredients[0], { name: "Item", gramsEstimate: 0, calories: 0, proteinG: 0, carbsG: 0, fatG: 0 });
  assertEquals(result.calories, 0);
});

Deno.test("rounds fractional ingredient values to whole numbers", () => {
  const result = clampEstimate({
    label: "Snack",
    ingredients: [ingredient({ gramsEstimate: 30.4, calories: 199.6, proteinG: 12.4, carbsG: 20.5, fatG: 5.5 })],
  });
  assertEquals(result.ingredients[0], { name: "Item", gramsEstimate: 30, calories: 200, proteinG: 12, carbsG: 21, fatG: 6 });
});

Deno.test("caps the ingredients array length rather than accepting an unbounded list", () => {
  const ingredients = Array.from({ length: MAX_INGREDIENTS + 10 }, (_, i) => ingredient({ name: `Item ${i}`, calories: 10 }));
  const result = clampEstimate({ label: "Huge list", ingredients });
  assertEquals(result.ingredients.length, MAX_INGREDIENTS);
});

Deno.test("an empty ingredients array sums to a zero total rather than throwing", () => {
  const result = clampEstimate({ label: "Nothing described", ingredients: [] });
  assertEquals(result, { label: "Nothing described", ingredients: [], calories: 0, proteinG: 0, carbsG: 0, fatG: 0 });
});

Deno.test("values exactly at the ceiling pass through unclamped", () => {
  const result = clampEstimate({
    label: "Huge meal",
    ingredients: [ingredient({ calories: MAX_CALORIES, proteinG: MAX_MACRO_G, carbsG: 0, fatG: 0 })],
  });
  assertEquals(result.calories, MAX_CALORIES);
  assertEquals(result.proteinG, MAX_MACRO_G);
});
