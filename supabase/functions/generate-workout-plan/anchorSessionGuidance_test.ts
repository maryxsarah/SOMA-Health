// Run: deno test supabase/functions/
//
// describeAnchorSession is the deterministic half of Phase 4 (see
// docs/coaching-personalization-plan.md). 2026-08-03 is a Monday (JS
// getUTCDay 1) -- same reference date goalWork_test.ts already uses, so
// Tue=2026-08-04, Wed=2026-08-05, Thu=2026-08-06.

import { assert, assertEquals } from "jsr:@std/assert";
import { describeAnchorSession } from "./anchorSessionGuidance.ts";

Deno.test("null when no name is set", () => {
  assertEquals(describeAnchorSession({ name: null, days: [2], date: "2026-08-03" }), null);
  assertEquals(describeAnchorSession({ name: "  ", days: [2], date: "2026-08-03" }), null);
});

Deno.test("null when no days are set, even with a name", () => {
  assertEquals(describeAnchorSession({ name: "Hot Yoga", days: [], date: "2026-08-03" }), null);
});

Deno.test("null when today isn't the anchor day nor adjacent to one", () => {
  // Anchor is Tuesday (2); Thursday (2026-08-06) is neither the day, nor
  // the day before/after it.
  assertEquals(describeAnchorSession({ name: "Hot Yoga", days: [2], date: "2026-08-06" }), null);
});

Deno.test("today IS the anchor day -- names the session, frames it as complementary", () => {
  const line = describeAnchorSession({ name: "Hot Yoga", days: [2], date: "2026-08-04" });
  assert(line);
  assert(line.includes("Hot Yoga"));
  assert(line.toLowerCase().includes("today"));
  assert(line.toLowerCase().includes("complementary"));
});

Deno.test("tomorrow is the anchor day -- forward-looking, avoid pre-fatiguing", () => {
  const line = describeAnchorSession({ name: "Tennis league", days: [2], date: "2026-08-03" });
  assert(line);
  assert(line.includes("Tennis league"));
  assert(line.toLowerCase().includes("tomorrow"));
  assert(line.toLowerCase().includes("pre-fatiguing"));
});

Deno.test("yesterday was the anchor day -- backward-looking, notes possible lingering fatigue", () => {
  const line = describeAnchorSession({ name: "Hot Yoga", days: [2], date: "2026-08-05" });
  assert(line);
  assert(line.toLowerCase().includes("yesterday"));
  assert(line.toLowerCase().includes("fatigue"));
});

Deno.test("PRECEDENCE: today wins even when yesterday also qualifies (multi-day anchor)", () => {
  // Mon(1) and Tue(2) both anchor days; checked on Tuesday -- today should
  // win over "yesterday was Monday".
  const line = describeAnchorSession({ name: "Hot Yoga", days: [1, 2], date: "2026-08-04" });
  assert(line);
  assert(line.toLowerCase().includes("today"));
});

Deno.test("PRECEDENCE: tomorrow wins over yesterday when today itself doesn't match", () => {
  // Mon(1) and Wed(3) both anchor days; checked on Tuesday -- yesterday
  // (Mon) and tomorrow (Wed) both qualify, forward-looking should win.
  const line = describeAnchorSession({ name: "Hot Yoga", days: [1, 3], date: "2026-08-04" });
  assert(line);
  assert(line.toLowerCase().includes("tomorrow"));
  assert(!line.toLowerCase().includes("yesterday"));
});

Deno.test("every advisory line explicitly defers to the day's real safety/category rules", () => {
  const today = describeAnchorSession({ name: "Hot Yoga", days: [2], date: "2026-08-04" });
  const tomorrow = describeAnchorSession({ name: "Hot Yoga", days: [2], date: "2026-08-03" });
  assert(today?.includes("Never let this override"));
  assert(tomorrow?.includes("Never let this override"));
});
