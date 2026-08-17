import { assert, assertEquals } from "jsr:@std/assert";
import { BODY_PART_SESSION_MRV, describeVolumeGuidance, VOLUME_LANDMARKS } from "./volumeLandmarks.ts";

Deno.test("describeVolumeGuidance returns empty text on rest/light days", () => {
  assertEquals(describeVolumeGuidance("moderate", "rest"), "");
  assertEquals(describeVolumeGuidance("moderate", "light"), "");
});

Deno.test("describeVolumeGuidance cites real upper/lower body MAV numbers for a training day", () => {
  const text = describeVolumeGuidance("moderate", "push_hard");
  const upper = VOLUME_LANDMARKS.upper_body.moderate;
  const lower = VOLUME_LANDMARKS.lower_body.moderate;
  assert(text.includes(`${upper.mav[0]}-${upper.mav[1]}`));
  assert(text.includes(`${lower.mav[0]}-${lower.mav[1]}`));
});

// --- BODY_PART_SESSION_MRV ---

Deno.test("BODY_PART_SESSION_MRV is tighter than full_body's session mrv at every experience level", () => {
  for (const level of ["newbie", "moderate", "advanced"] as const) {
    for (const part of ["upper_body", "lower_body"] as const) {
      const partMrv = BODY_PART_SESSION_MRV[part]?.[level];
      assert(partMrv !== undefined, `missing BODY_PART_SESSION_MRV for ${part}/${level}`);
      assert(
        partMrv < VOLUME_LANDMARKS.full_body[level].mrv,
        `${part}/${level}: per-body-part session mrv (${partMrv}) should be tighter than full_body's (${VOLUME_LANDMARKS.full_body[level].mrv})`,
      );
    }
  }
});

Deno.test("BODY_PART_SESSION_MRV increases with experience level, same as every other landmark table", () => {
  for (const part of ["upper_body", "lower_body"] as const) {
    const newbie = BODY_PART_SESSION_MRV[part]!.newbie;
    const moderate = BODY_PART_SESSION_MRV[part]!.moderate;
    const advanced = BODY_PART_SESSION_MRV[part]!.advanced;
    assert(newbie < moderate, `${part}: newbie should be lower than moderate`);
    assert(moderate < advanced, `${part}: moderate should be lower than advanced`);
  }
});

Deno.test("BODY_PART_SESSION_MRV deliberately has no core/cardio entry", () => {
  assertEquals(BODY_PART_SESSION_MRV.core, undefined);
  assertEquals(BODY_PART_SESSION_MRV.cardio, undefined);
});
