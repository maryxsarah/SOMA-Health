import { assert, assertEquals } from "jsr:@std/assert";
import { decideFinisher } from "./finisherCatalog.ts";

const noRecentLogs: { date: string; body_part: string; category: string }[] = [];

Deno.test("rest/light days never get a finisher, regardless of training_emphasis", () => {
  const rest = decideFinisher("rest", "lower_body", false, [], noRecentLogs, "2026-08-03", "cut");
  const light = decideFinisher("light", "lower_body", false, [], noRecentLogs, "2026-08-03", "cut");
  assertEquals(rest.include, false);
  assertEquals(light.include, false);
});

Deno.test("without a cut emphasis, the finisher still matches today's body part (unchanged default behavior)", () => {
  const decision = decideFinisher("moderate", "lower_body", false, [], noRecentLogs, "2026-08-03", null);
  assertEquals(decision.include, true);
  assertEquals(decision.definition?.focusArea, "lower_body");
});

Deno.test("REGRESSION: a cut emphasis overrides the body-part match with the cardio finisher on leg day", () => {
  const decision = decideFinisher("moderate", "lower_body", false, [], noRecentLogs, "2026-08-03", "cut");
  assertEquals(decision.include, true);
  assertEquals(decision.definition?.focusArea, "cardio");
  assertEquals(decision.definition?.modality, "sprint_interval");
});

Deno.test("bulk emphasis keeps the body-part match (never redirected to cardio)", () => {
  const decision = decideFinisher("moderate", "lower_body", false, [], noRecentLogs, "2026-08-03", "bulk");
  assertEquals(decision.definition?.focusArea, "lower_body");
});

Deno.test("recomp and maintain also keep the body-part match, same as no emphasis at all", () => {
  const recomp = decideFinisher("push_hard", "upper_body", false, [], noRecentLogs, "2026-08-03", "recomp");
  const maintain = decideFinisher("push_hard", "upper_body", false, [], noRecentLogs, "2026-08-03", "maintain");
  assertEquals(recomp.definition?.focusArea, "upper_body");
  assertEquals(maintain.definition?.focusArea, "upper_body");
});

Deno.test("a cut-redirected cardio finisher still respects injury exclusion keywords", () => {
  const decision = decideFinisher("moderate", "lower_body", false, ["sprint"], noRecentLogs, "2026-08-03", "cut");
  // Cardio finisher's description mentions "sprint" -- excluded keyword
  // means it's no longer safe, so exceptional can never fire for it, but
  // the finisher itself is still included at the non-exceptional tier.
  assert(!decision.exceptional);
});

Deno.test("exceptional readiness can still apply to a cut-redirected cardio finisher when nothing conflicts", () => {
  const decision = decideFinisher("push_hard", "lower_body", true, [], noRecentLogs, "2026-08-03", "cut");
  assertEquals(decision.exceptional, true);
  assertEquals(decision.definition?.focusArea, "cardio");
});

Deno.test("a cut emphasis on a body part with no direct catalog match (e.g. an injury-substituted one) still redirects to cardio, not the full_body fallback", () => {
  const decision = decideFinisher("moderate", "some_unmapped_part", false, [], noRecentLogs, "2026-08-03", "cut");
  assertEquals(decision.definition?.focusArea, "cardio");
});

Deno.test("with no emphasis and an unmapped body part, falls back to full_body as before", () => {
  const decision = decideFinisher("moderate", "some_unmapped_part", false, [], noRecentLogs, "2026-08-03", null);
  assertEquals(decision.definition?.focusArea, "full_body");
});

Deno.test("REGRESSION: a cut-redirected cardio finisher still detects yesterday's push_hard split conflict on the REAL body part", () => {
  // Today's finisher is cut-redirected to "cardio", but the conflict check
  // must still key off the real muscle group trained (lower_body).
  const recentLogs = [{ date: "2026-08-03", body_part: "lower_body", category: "push_hard" }];
  const decision = decideFinisher("push_hard", "lower_body", true, [], recentLogs, "2026-08-03", "cut");
  assertEquals(decision.definition?.focusArea, "cardio");
  assertEquals(decision.exceptional, false, "split conflict on the real body part must still block the exceptional tier");
});
