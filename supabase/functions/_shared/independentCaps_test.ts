import { assertEquals } from "jsr:@std/assert";
import {
  computeInjuryProtocolRestApplied,
  computeMoodCapApplied,
  LOW_MOOD_RATING_THRESHOLD,
  RECENT_SEVERE_INJURY_WINDOW_HOURS,
  SEVERE_INJURY_BAD_DAYS_TO_REST,
} from "./independentCaps.ts";

const HOUR_MS = 3600 * 1000;

Deno.test("computeInjuryProtocolRestApplied: no severe injuries -> false", () => {
  assertEquals(computeInjuryProtocolRestApplied([], Date.now()), false);
});

Deno.test("computeInjuryProtocolRestApplied: severe injury reported minutes ago -> true", () => {
  const now = Date.now();
  const rows = [{ protocol_started_at: new Date(now - 5 * 60 * 1000).toISOString(), consecutive_bad_days: 0 }];
  assertEquals(computeInjuryProtocolRestApplied(rows, now), true);
});

Deno.test("computeInjuryProtocolRestApplied: severe injury reported exactly at the window boundary -> true", () => {
  const now = Date.now();
  const rows = [{
    protocol_started_at: new Date(now - RECENT_SEVERE_INJURY_WINDOW_HOURS * HOUR_MS).toISOString(),
    consecutive_bad_days: 0,
  }];
  assertEquals(computeInjuryProtocolRestApplied(rows, now), true);
});

Deno.test("computeInjuryProtocolRestApplied: severe injury reported well outside the window with no bad streak -> false", () => {
  const now = Date.now();
  const rows = [{
    protocol_started_at: new Date(now - (RECENT_SEVERE_INJURY_WINDOW_HOURS + 1) * HOUR_MS).toISOString(),
    consecutive_bad_days: 0,
  }];
  assertEquals(computeInjuryProtocolRestApplied(rows, now), false);
});

Deno.test("computeInjuryProtocolRestApplied: old severe injury trending worse for the threshold -> true", () => {
  const now = Date.now();
  const rows = [{
    protocol_started_at: new Date(now - 30 * 24 * HOUR_MS).toISOString(),
    consecutive_bad_days: SEVERE_INJURY_BAD_DAYS_TO_REST,
  }];
  assertEquals(computeInjuryProtocolRestApplied(rows, now), true);
});

Deno.test("computeInjuryProtocolRestApplied: old severe injury one bad day short of the threshold -> false", () => {
  const now = Date.now();
  const rows = [{
    protocol_started_at: new Date(now - 30 * 24 * HOUR_MS).toISOString(),
    consecutive_bad_days: SEVERE_INJURY_BAD_DAYS_TO_REST - 1,
  }];
  assertEquals(computeInjuryProtocolRestApplied(rows, now), false);
});

Deno.test("computeInjuryProtocolRestApplied: one qualifying row among several old, stable ones -> true", () => {
  const now = Date.now();
  const rows = [
    { protocol_started_at: new Date(now - 30 * 24 * HOUR_MS).toISOString(), consecutive_bad_days: 0 },
    { protocol_started_at: new Date(now - 1 * HOUR_MS).toISOString(), consecutive_bad_days: 0 },
  ];
  assertEquals(computeInjuryProtocolRestApplied(rows, now), true);
});

Deno.test("computeMoodCapApplied: rough mood (1) on a push_hard day downgrades", () => {
  assertEquals(computeMoodCapApplied(1, "push_hard"), true);
});

Deno.test("computeMoodCapApplied: not-great mood at the threshold (2) on a moderate day downgrades", () => {
  assertEquals(computeMoodCapApplied(LOW_MOOD_RATING_THRESHOLD, "moderate"), true);
});

Deno.test("computeMoodCapApplied: okay mood (3) does not downgrade", () => {
  assertEquals(computeMoodCapApplied(3, "push_hard"), false);
});

Deno.test("computeMoodCapApplied: great mood (5) never upgrades a rest/light day -- cap simply doesn't apply", () => {
  assertEquals(computeMoodCapApplied(5, "push_hard"), false);
});

Deno.test("computeMoodCapApplied: rough mood on an already-light day doesn't re-fire (nothing lower to cap to via this path)", () => {
  assertEquals(computeMoodCapApplied(1, "light"), false);
});

Deno.test("computeMoodCapApplied: no check-in today (null) never caps", () => {
  assertEquals(computeMoodCapApplied(null, "push_hard"), false);
});
