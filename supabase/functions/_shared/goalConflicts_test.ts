// deno test supabase/functions/
//
// The create-goal safety pass: deterministic warnings over a coach's
// free-text assignment. The user decides -- these pin that the check
// itself never misses, never invents, and carries the right framing.
import { assert, assertEquals } from "jsr:@std/assert";
import { findConflicts } from "./goalConflicts.ts";

Deno.test("INVARIANT: clean text against any keywords yields no conflicts", () => {
  const conflicts = findConflicts(
    "Wall passes 3x60s, shoulder prehab band work, easy bike cool-down.",
    ["depth jump", "plyometric", "box jump"],
    "injury",
  );
  assertEquals(conflicts, []);
});

Deno.test("INVARIANT: matching is case-insensitive in both directions", () => {
  const conflicts = findConflicts(
    "Depth Drops 4x5, then APPROACH JUMPS 3x6.",
    ["depth drop", "approach jump"],
    "injury",
  );
  assertEquals(conflicts.map((c) => c.keyword).sort(), ["approach jump", "depth drop"]);
});

Deno.test("INVARIANT: every injury conflict names the keyword and lets the user proceed", () => {
  const [conflict] = findConflicts("Weighted box jumps.", ["box jump"], "injury");
  assert(conflict.message.includes('"box jump"'));
  assert(conflict.message.includes("your coach knows your situation"));
  assertEquals(conflict.pregnancy, false);
});

Deno.test("INVARIANT: pregnancy conflicts carry the provider-consultation line, never a block", () => {
  const [conflict] = findConflicts("Depth jumps after warm-up.", ["depth jump"], "pregnancy");
  assertEquals(conflict.pregnancy, true);
  assert(conflict.message.includes("healthcare provider"));
  assert(!conflict.message.toLowerCase().includes("cannot"));
});

Deno.test("REGRESSION: a keyword list is scanned in full, not first-match-only", () => {
  const conflicts = findConflicts(
    "Depth drops, box jumps, and sprints.",
    ["depth drop", "box jump", "sprint", "bench press"],
    "injury",
  );
  assertEquals(conflicts.length, 3);
});
