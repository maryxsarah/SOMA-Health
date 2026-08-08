import { assertEquals } from "jsr:@std/assert";
import { clampEstimate, MAX_CALORIES, MAX_MACRO_G } from "./estimateBounds.ts";

Deno.test("passes through a normal, in-range estimate unchanged", () => {
  const result = clampEstimate({ label: "Chicken and rice", calories: 520, proteinG: 42, carbsG: 55, fatG: 12 });
  assertEquals(result, { label: "Chicken and rice", calories: 520, proteinG: 42, carbsG: 55, fatG: 12 });
});

Deno.test("clamps calories above the ceiling instead of trusting the model", () => {
  const result = clampEstimate({ label: "Feast", calories: 99999, proteinG: 30, carbsG: 30, fatG: 30 });
  assertEquals(result.calories, MAX_CALORIES);
});

Deno.test("clamps each macro above its own ceiling independently", () => {
  const result = clampEstimate({ label: "Feast", calories: 1000, proteinG: 9000, carbsG: 9000, fatG: 9000 });
  assertEquals(result.proteinG, MAX_MACRO_G);
  assertEquals(result.carbsG, MAX_MACRO_G);
  assertEquals(result.fatG, MAX_MACRO_G);
});

Deno.test("clamps negative values up to zero rather than passing them through", () => {
  const result = clampEstimate({ label: "Bad estimate", calories: -50, proteinG: -5, carbsG: -5, fatG: -5 });
  assertEquals(result, { label: "Bad estimate", calories: 0, proteinG: 0, carbsG: 0, fatG: 0 });
});

Deno.test("rounds fractional values to whole numbers", () => {
  const result = clampEstimate({ label: "Snack", calories: 199.6, proteinG: 12.4, carbsG: 20.5, fatG: 5.5 });
  assertEquals(result, { label: "Snack", calories: 200, proteinG: 12, carbsG: 21, fatG: 6 });
});

Deno.test("values exactly at the ceiling pass through unclamped", () => {
  const result = clampEstimate({ label: "Huge meal", calories: MAX_CALORIES, proteinG: MAX_MACRO_G, carbsG: 0, fatG: 0 });
  assertEquals(result.calories, MAX_CALORIES);
  assertEquals(result.proteinG, MAX_MACRO_G);
});
