// Run: deno test supabase/functions/
//
// The manual-entry path is the reason this matters: the client asks the user
// to type equipment exactly when photo recognition failed, so silently
// discarding their input is the worst possible moment to do it.

import { assertEquals } from "jsr:@std/assert";
import { normalizeEquipment } from "./equipment.ts";

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
