// Run: deno test supabase/functions/
//
// The manual-entry path is the reason this matters: the client asks the user
// to type equipment exactly when photo recognition failed, so silently
// discarding their input is the worst possible moment to do it.

import { assert, assertEquals, assertFalse } from "jsr:@std/assert";
import { normalizeEquipment, parseFreeTextEquipment, resolveFreeTextEquipment } from "./equipment.ts";

const one = (s: string) => Array.from(normalizeEquipment([s]))[0];

Deno.test("exact vocabulary values pass through", () => {
  assertEquals(one("dumbbells"), "dumbbells");
  assertEquals(one("pull-up bar"), "pull-up bar");
});

Deno.test("REGRESSION: singular forms are accepted", () => {
  // "dumbbell" used to miss "dumbbells" and drop the user to bodyweight.
  assertEquals(one("dumbbell"), "dumbbells");
  assertEquals(one("kettlebell"), "kettlebells");
});

Deno.test("REGRESSION: punctuation and spacing variants are accepted", () => {
  assertEquals(one("pull up bar"), "pull-up bar");
  assertEquals(one("Pull-Up Bars"), "pull-up bar");
  assertEquals(one("  SQUAT RACK  "), "squat rack");
});

Deno.test("common synonyms map onto the vocabulary", () => {
  assertEquals(one("free weights"), "dumbbells");
  assertEquals(one("bench"), "weight bench");
  assertEquals(one("power rack"), "squat rack");
  assertEquals(one("rower"), "rowing machine");
  assertEquals(one("trx"), "suspension trainer");
});

Deno.test("genuinely unknown input is still dropped, not guessed", () => {
  assertEquals(normalizeEquipment(["a swimming pool", "vibes"]).size, 0);
});

Deno.test("duplicates collapse to one entry", () => {
  assertEquals(normalizeEquipment(["dumbbell", "dumbbells", "free weights"]).size, 1);
});

// --- parseFreeTextEquipment / resolveFreeTextEquipment ---
//
// REGRESSION coverage for the real bug report: "dumbbells, a workout
// bench, a yoga mat and a treadmill" typed into onboarding's free-text
// equipment field was captured and saved, but never read by any
// generation path -- so a user who explicitly listed their real equipment
// still got barbell exercises recommended, and never got their treadmill
// considered even for a warm-up.

Deno.test("REGRESSION: a full free-text sentence resolves every item it names", () => {
  const items = parseFreeTextEquipment("dumbbells, a workout bench, a yoga mat and a treadmill");
  assert(items.has("dumbbells"));
  assert(items.has("weight bench"));
  assert(items.has("yoga mat"));
  assert(items.has("treadmill"));
  assertFalse(items.has("barbell"), "must not invent equipment the user never mentioned");
});

Deno.test("free-text parsing is punctuation/case-insensitive, same as normalizeEquipment", () => {
  const items = parseFreeTextEquipment("KETTLEBELLS, resistance-bands!! and a Pull Up Bar.");
  assert(items.has("kettlebells"));
  assert(items.has("resistance bands"));
  assert(items.has("pull-up bar"));
});

Deno.test("resolveFreeTextEquipment maps to real exercise_library equipment values", () => {
  const result = resolveFreeTextEquipment("dumbbells, a workout bench, a yoga mat and a treadmill");
  assert(result.libraryEquipment.includes("dumbbell"));
  assert(result.libraryEquipment.includes("body only")); // from "yoga mat"
  assert(result.libraryEquipment.includes("machine")); // from "treadmill"
  assertFalse(result.libraryEquipment.includes("barbell"));
});

Deno.test("REGRESSION: treadmill/bike/rower/elliptical/jump-rope unlock cardio candidates; a bench alone does not", () => {
  assert(resolveFreeTextEquipment("I have a treadmill").unlocksCardio);
  assert(resolveFreeTextEquipment("stationary bike in the garage").unlocksCardio);
  assertFalse(resolveFreeTextEquipment("just dumbbells and a bench").unlocksCardio);
});

Deno.test("null, empty, and whitespace-only notes resolve to nothing, not a crash", () => {
  assertEquals(resolveFreeTextEquipment(null).libraryEquipment.length, 0);
  assertEquals(resolveFreeTextEquipment(undefined).libraryEquipment.length, 0);
  assertEquals(resolveFreeTextEquipment("   ").libraryEquipment.length, 0);
  assertFalse(resolveFreeTextEquipment(null).unlocksCardio);
});

Deno.test("a barbell explicitly mentioned in free text IS recognized (this system doesn't forbid barbells, just never assumes one)", () => {
  const result = resolveFreeTextEquipment("full barbell set with a squat rack");
  assert(result.libraryEquipment.includes("barbell"));
});
