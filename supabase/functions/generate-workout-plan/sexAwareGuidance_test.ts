import { assertEquals, assertNotEquals } from "jsr:@std/assert";
import { describeSexAwareConsiderations, describeSexAwareGoalDoseConsideration } from "./sexAwareGuidance.ts";

Deno.test("describeSexAwareConsiderations: female + non-rest day returns the caveat", () => {
  assertNotEquals(describeSexAwareConsiderations("female", "moderate"), "");
});

Deno.test("describeSexAwareConsiderations: female + rest day returns nothing", () => {
  assertEquals(describeSexAwareConsiderations("female", "rest"), "");
});

Deno.test("describeSexAwareConsiderations: male returns nothing regardless of category", () => {
  assertEquals(describeSexAwareConsiderations("male", "moderate"), "");
});

Deno.test("describeSexAwareConsiderations: null sex returns nothing", () => {
  assertEquals(describeSexAwareConsiderations(null, "moderate"), "");
});

Deno.test("describeSexAwareGoalDoseConsideration: female returns the goal-dose caveat", () => {
  const line = describeSexAwareGoalDoseConsideration("female");
  assertNotEquals(line, "");
  assertEquals(line.includes("goal block"), true);
});

Deno.test("describeSexAwareGoalDoseConsideration: male returns nothing", () => {
  assertEquals(describeSexAwareGoalDoseConsideration("male"), "");
});

Deno.test("describeSexAwareGoalDoseConsideration: null sex returns nothing", () => {
  assertEquals(describeSexAwareGoalDoseConsideration(null), "");
});

Deno.test("describeSexAwareGoalDoseConsideration: never mentions target numbers -- dosing only", () => {
  const line = describeSexAwareGoalDoseConsideration("female");
  assertEquals(line.toLowerCase().includes("target"), false);
  assertEquals(line.toLowerCase().includes("gain"), false);
});
