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
  assertFalse(items.has("barbell"), "mentioning a pull-up bar must not also imply a barbell");
});

// REGRESSION: "chin up bar" is both an ALIASES key and on the
// ambiguous-mask list (to stop bare "bar" matching "protein bar" etc.) --
// a masking-order bug erased the phrase before its own alias lookup ran,
// so it silently resolved to zero equipment.
Deno.test("REGRESSION: 'chin up bar' resolves via its own alias, not masked away by itself", () => {
  const items = parseFreeTextEquipment("I have a chin up bar at home");
  assert(items.has("pull-up bar"));
  assertFalse(items.has("barbell"), "mentioning a chin-up bar must not also imply a barbell");
});

Deno.test("resolveFreeTextEquipment maps to real exercise_library equipment values", () => {
  const result = resolveFreeTextEquipment("dumbbells, a workout bench, a yoga mat and a treadmill");
  assert(result.libraryEquipment.includes("dumbbell"));
  assert(result.libraryEquipment.includes("body only")); // from "yoga mat"
  assertFalse(result.libraryEquipment.includes("barbell"));
});

Deno.test("REGRESSION: cardio-only equipment (treadmill) resolves separately, never into libraryEquipment", () => {
  // "machine" also covers real strength machines (Leg Press) -- must stay
  // out of the tier every exercise type draws from.
  const result = resolveFreeTextEquipment("just a treadmill");
  assertFalse(result.libraryEquipment.includes("machine"));
  assert(result.cardioLibraryEquipment.includes("machine"));
});

// --- false-positive guards for bare single-word aliases (bar/rack/plates) ---
// REGRESSION: unguarded substring matching falsely unlocked barbell exercises.

Deno.test("REGRESSION: everyday food/kitchen words containing 'bar'/'rack'/'plates' never falsely unlock a barbell", () => {
  const phrases = [
    "just dumbbells and a protein bar for after",
    "I keep a spice rack in the kitchen",
    "we eat off paper plates most nights",
    "grabbing a candy bar on the way home",
    "granola bar in my gym bag",
  ];
  for (const text of phrases) {
    const result = resolveFreeTextEquipment(text);
    assertFalse(result.libraryEquipment.includes("barbell"), `"${text}" must not resolve to barbell`);
  }
});

Deno.test("a bare 'bar' or 'rack' standing alone still resolves (not forbidden, just not assumed from unrelated phrases)", () => {
  assert(resolveFreeTextEquipment("just a bar, nothing else").libraryEquipment.includes("barbell"));
  assert(resolveFreeTextEquipment("I have a rack at home").libraryEquipment.includes("barbell"));
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
