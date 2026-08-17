import { assertEquals } from "jsr:@std/assert";
import { effectiveCarbsTargetG, REST_DAY_CARB_TRIM } from "./recoveryDayAdjustment.ts";

Deno.test("effectiveCarbsTargetG: unchanged on a non-recovery day", () => {
  assertEquals(effectiveCarbsTargetG(200, false), 200);
});

Deno.test("REGRESSION: trimmed on a rest/light recovery day -- BUG: this function had zero category awareness before", () => {
  assertEquals(effectiveCarbsTargetG(200, true), 200 * REST_DAY_CARB_TRIM);
});

Deno.test("the trim is modest, not a big swing -- protein/fat are never touched by this function at all", () => {
  const trimmed = effectiveCarbsTargetG(200, true);
  assertEquals(trimmed, 176);
  // Within a reasonable "slightly lower, still a real amount" range --
  // never near-zero, never unchanged.
  const pctOfOriginal = trimmed / 200;
  const inRange = pctOfOriginal > 0.8 && pctOfOriginal < 1.0;
  assertEquals(inRange, true);
});

Deno.test("zero carbs target stays zero either way (no divide-by-zero or negative surprises)", () => {
  assertEquals(effectiveCarbsTargetG(0, true), 0);
  assertEquals(effectiveCarbsTargetG(0, false), 0);
});
