import { assertEquals } from "jsr:@std/assert";
import {
  countConsecutiveTrainingDays,
  countRecentTrainingDays,
  countRecentTrainingDaysByBodyPart,
  fetchRecentRecommendationCategories,
  fetchTrainingDates,
} from "./trainingDayCounters.ts";

Deno.test("countConsecutiveTrainingDays: no training dates at all -> 0", () => {
  assertEquals(countConsecutiveTrainingDays(new Set(), "2026-08-15"), 0);
});

Deno.test("countConsecutiveTrainingDays: an unbroken run immediately before date", () => {
  const dates = new Set(["2026-08-14", "2026-08-13", "2026-08-12"]);
  assertEquals(countConsecutiveTrainingDays(dates, "2026-08-15"), 3);
});

Deno.test("countConsecutiveTrainingDays: stops at the first gap, ignores anything further back", () => {
  // Trained d-1, d-2, d-3, gap at d-4, then more training further back --
  // must stop counting at the gap, not keep going.
  const dates = new Set(["2026-08-14", "2026-08-13", "2026-08-12", "2026-08-10", "2026-08-09"]);
  assertEquals(countConsecutiveTrainingDays(dates, "2026-08-15"), 3);
});

Deno.test("countConsecutiveTrainingDays: no training yesterday -> 0, regardless of history", () => {
  const dates = new Set(["2026-08-13", "2026-08-12"]);
  assertEquals(countConsecutiveTrainingDays(dates, "2026-08-15"), 0);
});

Deno.test("REGRESSION: the exact reported scenario -- recommendation-only history (no workout_log rows) still counts as a real streak", () => {
  // The bug this exists to fix: countConsecutiveTrainingDays used to only
  // ever see workout_log rows. This function itself is agnostic to WHERE
  // the dates came from (that's fetchTrainingDates's job in index.ts) --
  // this test proves the counting logic works correctly on a set built
  // purely from daily_recommendation history, zero logged workouts.
  const recommendationOnlyDates = new Set(["2026-08-14", "2026-08-13", "2026-08-12", "2026-08-11"]);
  assertEquals(countConsecutiveTrainingDays(recommendationOnlyDates, "2026-08-15"), 4);
});

Deno.test("countRecentTrainingDays: just the set size, gaps allowed", () => {
  assertEquals(countRecentTrainingDays(new Set()), 0);
  assertEquals(countRecentTrainingDays(new Set(["2026-08-14", "2026-08-10"])), 2);
});

Deno.test("countRecentTrainingDays: a rolling count catches a gappy-but-frequent week a consecutive-streak count would miss", () => {
  // hard-hard-hard-rest-hard-hard-hard is only a 3-day consecutive streak
  // but 6 of the last 7 days.
  const dates = new Set(["2026-08-14", "2026-08-13", "2026-08-12", "2026-08-10", "2026-08-09", "2026-08-08"]);
  assertEquals(countConsecutiveTrainingDays(dates, "2026-08-15"), 3);
  assertEquals(countRecentTrainingDays(dates), 6);
});

// --- fake supabase client: mirrors the small slice of postgrest-js these
// query functions use (from/select/eq/in/gte/lt), same pattern as
// _shared/exerciseLibraryMatch_test.ts's MockQuery -- filters actually
// apply, so these tests exercise real query semantics, not just recorded
// calls. ---

// deno-lint-ignore no-explicit-any
class FakeQuery {
  #rows: any[];
  constructor(rows: any[]) {
    this.#rows = [...rows];
  }
  select(_cols: string) {
    return this;
  }
  eq(col: string, value: unknown) {
    this.#rows = this.#rows.filter((r) => r[col] === value);
    return this;
  }
  in(col: string, values: unknown[]) {
    this.#rows = this.#rows.filter((r) => values.includes(r[col]));
    return this;
  }
  gte(col: string, value: string) {
    this.#rows = this.#rows.filter((r) => r[col] >= value);
    return this;
  }
  lt(col: string, value: string) {
    this.#rows = this.#rows.filter((r) => r[col] < value);
    return this;
  }
  // deno-lint-ignore no-explicit-any
  then(resolve: (v: { data: any[] }) => void) {
    resolve({ data: this.#rows });
  }
}

// deno-lint-ignore no-explicit-any
function fakeSupabase(tables: Record<string, any[]>) {
  return { from: (table: string) => new FakeQuery(tables[table] ?? []) };
}

// All fixture rows below carry user_id: "user-1" to match the userId
// argument passed to each function under test -- FakeQuery's .eq()
// filters on it for real, same as the live query does.

// --- fetchTrainingDates ---

Deno.test("REGRESSION: the exact reported bug -- a user with zero workout_log rows but a week of moderate/push_hard recommendations is no longer invisible", () => {
  const supabase = fakeSupabase({
    workout_log: [],
    daily_recommendation: [
      { user_id: "user-1", date: "2026-08-14", category: "push_hard" },
      { user_id: "user-1", date: "2026-08-13", category: "moderate" },
      { user_id: "user-1", date: "2026-08-12", category: "push_hard" },
      { user_id: "user-1", date: "2026-08-11", category: "moderate" },
    ],
  });
  return fetchTrainingDates(supabase, "user-1", "2026-08-15").then((dates) => {
    assertEquals(dates, new Set(["2026-08-14", "2026-08-13", "2026-08-12", "2026-08-11"]));
    assertEquals(countConsecutiveTrainingDays(dates, "2026-08-15"), 4);
  });
});

Deno.test("fetchTrainingDates unions logged and recommended dates, not just one or the other", () => {
  const supabase = fakeSupabase({
    workout_log: [{ user_id: "user-1", date: "2026-08-14", category: "push_hard" }],
    daily_recommendation: [{ user_id: "user-1", date: "2026-08-13", category: "moderate" }],
  });
  return fetchTrainingDates(supabase, "user-1", "2026-08-15").then((dates) => {
    assertEquals(dates, new Set(["2026-08-14", "2026-08-13"]));
  });
});

Deno.test("fetchTrainingDates never double-counts a date that's both logged AND recommended", () => {
  const supabase = fakeSupabase({
    workout_log: [{ user_id: "user-1", date: "2026-08-14", category: "push_hard" }],
    daily_recommendation: [{ user_id: "user-1", date: "2026-08-14", category: "push_hard" }],
  });
  return fetchTrainingDates(supabase, "user-1", "2026-08-15").then((dates) => {
    assertEquals(dates.size, 1);
  });
});

Deno.test("fetchTrainingDates excludes rest/light rows from both sources", () => {
  const supabase = fakeSupabase({
    workout_log: [{ user_id: "user-1", date: "2026-08-14", category: "rest" }],
    daily_recommendation: [{ user_id: "user-1", date: "2026-08-13", category: "light" }],
  });
  return fetchTrainingDates(supabase, "user-1", "2026-08-15").then((dates) => {
    assertEquals(dates.size, 0);
  });
});

Deno.test("fetchTrainingDates never includes today itself, only strictly before", () => {
  const supabase = fakeSupabase({
    workout_log: [],
    daily_recommendation: [{ user_id: "user-1", date: "2026-08-15", category: "push_hard" }],
  });
  return fetchTrainingDates(supabase, "user-1", "2026-08-15").then((dates) => {
    assertEquals(dates.size, 0);
  });
});

// --- countRecentTrainingDaysByBodyPart ---

Deno.test("REGRESSION: a legs-heavy week is caught per-body-part even though total session count alone wouldn't trip the coarse cap", () => {
  const supabase = fakeSupabase({
    workout_log: [
      { user_id: "user-1", date: "2026-08-14", category: "moderate", body_part: "lower_body" },
      { user_id: "user-1", date: "2026-08-12", category: "moderate", body_part: "lower_body" },
      { user_id: "user-1", date: "2026-08-10", category: "moderate", body_part: "lower_body" },
    ],
  });
  return countRecentTrainingDaysByBodyPart(supabase, "user-1", "2026-08-15").then((byBodyPart) => {
    assertEquals(byBodyPart, { lower_body: 3 });
  });
});

Deno.test("countRecentTrainingDaysByBodyPart groups distinct body parts separately", () => {
  const supabase = fakeSupabase({
    workout_log: [
      { user_id: "user-1", date: "2026-08-14", category: "moderate", body_part: "lower_body" },
      { user_id: "user-1", date: "2026-08-13", category: "moderate", body_part: "upper_body" },
      { user_id: "user-1", date: "2026-08-12", category: "moderate", body_part: "upper_body" },
    ],
  });
  return countRecentTrainingDaysByBodyPart(supabase, "user-1", "2026-08-15").then((byBodyPart) => {
    assertEquals(byBodyPart, { lower_body: 1, upper_body: 2 });
  });
});

Deno.test("countRecentTrainingDaysByBodyPart ignores rows with no body_part", () => {
  const supabase = fakeSupabase({
    workout_log: [{ user_id: "user-1", date: "2026-08-14", category: "moderate", body_part: null }],
  });
  return countRecentTrainingDaysByBodyPart(supabase, "user-1", "2026-08-15").then((byBodyPart) => {
    assertEquals(byBodyPart, {});
  });
});

// --- fetchRecentRecommendationCategories ---

Deno.test("fetchRecentRecommendationCategories returns every category in the window, including rest/light (unlike fetchTrainingDates)", () => {
  const supabase = fakeSupabase({
    daily_recommendation: [
      { user_id: "user-1", date: "2026-08-14", category: "push_hard" },
      { user_id: "user-1", date: "2026-08-13", category: "rest" },
      { user_id: "user-1", date: "2026-08-12", category: "light" },
    ],
  });
  return fetchRecentRecommendationCategories(supabase, "user-1", "2026-08-15").then((categories) => {
    assertEquals(new Set(categories), new Set(["push_hard", "rest", "light"]));
  });
});
