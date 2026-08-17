// Run: deno test supabase/functions/
//
// describeAnchorSession is the deterministic half of Phase 4 (see
// docs/coaching-personalization-plan.md). 2026-08-03 is a Monday (JS
// getUTCDay 1) -- same reference date goalWork_test.ts already uses, so
// Tue=2026-08-04, Wed=2026-08-05, Thu=2026-08-06.

import { assert, assertEquals } from "jsr:@std/assert";
import { type Anchor, describeAnchorSession, describeAnchorSessions } from "./anchorSessionGuidance.ts";

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

// MARK: - describeAnchorSessions (item 6: a list of anchors, not one)

function anchor(id: string, name: string, days: number[]): Anchor {
  return { id, name, days };
}

Deno.test("empty anchor list yields no guidance", () => {
  assertEquals(describeAnchorSessions([], "2026-08-04"), null);
});

Deno.test("a single anchor in the list behaves exactly like describeAnchorSession", () => {
  const line = describeAnchorSessions([anchor("1", "Hot Yoga", [2])], "2026-08-04");
  assert(line);
  assert(line.includes("Hot Yoga"));
  assert(line.toLowerCase().includes("today"));
});

Deno.test("multiple anchors on different days each contribute their own line", () => {
  const line = describeAnchorSessions(
    [anchor("1", "Hot Yoga", [2]), anchor("2", "Tennis league", [3])],
    "2026-08-04", // Tuesday: Hot Yoga is today, Tennis league (Wed) is tomorrow
  );
  assert(line);
  assert(line.includes("Hot Yoga"));
  assert(line.includes("Tennis league"));
  assert(line.toLowerCase().includes("today"));
  assert(line.toLowerCase().includes("tomorrow"));
});

Deno.test("two anchors on the SAME day today are flagged as a heavier-than-usual day", () => {
  const line = describeAnchorSessions(
    [anchor("1", "Hot Yoga", [2]), anchor("2", "Boxing", [2])],
    "2026-08-04",
  );
  assert(line);
  assert(line.includes("Hot Yoga"));
  assert(line.includes("Boxing"));
  assert(line.toLowerCase().includes("heavier"));
  assert(line.includes("2 recurring commitments"));
});

Deno.test("same-day conflict note still defers to real safety/category rules", () => {
  const line = describeAnchorSessions(
    [anchor("1", "Hot Yoga", [2]), anchor("2", "Boxing", [2])],
    "2026-08-04",
  );
  assert(line?.includes("Never let this override"));
});

Deno.test("only one anchor today among several doesn't trigger the conflict note", () => {
  const line = describeAnchorSessions(
    [anchor("1", "Hot Yoga", [2]), anchor("2", "Tennis league", [4])],
    "2026-08-04",
  );
  assert(line);
  assert(!line.toLowerCase().includes("heavier"));
});

Deno.test("blank-name and empty-days anchors in the list are silently skipped, not errored", () => {
  const line = describeAnchorSessions(
    [anchor("1", "  ", [2]), anchor("2", "Hot Yoga", []), anchor("3", "Tennis league", [2])],
    "2026-08-04",
  );
  assert(line);
  assert(line.includes("Tennis league"));
  assert(!line.includes("Hot Yoga"));
});
