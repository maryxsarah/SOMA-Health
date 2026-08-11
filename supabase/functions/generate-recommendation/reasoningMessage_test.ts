// Run: deno test supabase/functions/
//
// buildReasoningMessage never decides the category (that's index.ts's own
// computedCategory chain) -- these tests only check that the EXPLANATION
// text (a) cites real numbers when they exist, (b) never fabricates a
// number a source didn't report, and (c) picks the same "why" index.ts's
// own precedence would pick, so the two can never contradict each other.

import { assert } from "jsr:@std/assert";
import { buildReasoningMessage, type ReasoningMessageCaps, type ReasoningMessageInput } from "./reasoningMessage.ts";

const NO_CAPS: ReasoningMessageCaps = {
  sleep: false,
  hrv: false,
  stress: false,
  mood: false,
  consecutiveDays: false,
  consecutiveDaysRestEscalated: false,
  volume: false,
  injury: false,
  injuryModerate: false,
  injuryRest: false,
};

function baseInput(overrides: Partial<ReasoningMessageInput>): ReasoningMessageInput {
  return {
    category: "push_hard",
    userRequestedCategory: null,
    source: "whoop",
    band: "high",
    insufficientData: false,
    dataConfidence: "high",
    recoveryScore: null,
    readinessScore: null,
    hrvMs: null,
    sleepHours: null,
    restingHr: null,
    strainScore: null,
    stressMinutes: null,
    caps: NO_CAPS,
    ...overrides,
  };
}

Deno.test("cites the real Whoop recovery percentage, never a fabricated number", () => {
  const msg = buildReasoningMessage(baseInput({ source: "whoop", recoveryScore: 82 }));
  assert(msg.includes("82%"), msg);
  assert(msg.includes("Whoop"), msg);
});

Deno.test("cites the real Oura readiness score", () => {
  const msg = buildReasoningMessage(baseInput({ source: "oura", readinessScore: 71, recoveryScore: null }));
  assert(msg.includes("71"), msg);
  assert(msg.includes("Oura"), msg);
});

Deno.test("HealthKit (no single score) describes the band in plain language instead of a fabricated number", () => {
  const msg = buildReasoningMessage(baseInput({ source: "healthkit", band: "medium" }));
  assert(msg.includes("Apple Health"), msg);
  assert(msg.includes("recovering about average"), msg);
});

Deno.test("degrades gracefully: no secondary numbers populated still yields a clean sentence", () => {
  const msg = buildReasoningMessage(baseInput({ source: "whoop", recoveryScore: 60 }));
  assert(!msg.includes("undefined"), msg);
  assert(!msg.includes("null"), msg);
  assert(!/,\s*\)/.test(msg), `dangling comma before close-paren: ${msg}`);
});

Deno.test("supporting numbers are appended only when actually populated, generalized across whichever fields exist", () => {
  const msg = buildReasoningMessage(baseInput({
    source: "oura",
    readinessScore: 65,
    sleepHours: 7.5,
    restingHr: 58,
  }));
  assert(msg.includes("7.5h sleep"), msg);
  assert(msg.includes("58bpm"), msg);
  assert(!msg.includes("HRV"), "should not mention HRV when it wasn't populated");
});

Deno.test("insufficient HealthKit data never cites a fabricated number", () => {
  const msg = buildReasoningMessage(baseInput({
    category: "moderate",
    source: "healthkit",
    insufficientData: true,
    band: "medium",
  }));
  assert(msg.toLowerCase().includes("no wearable"), msg);
  assert(!msg.includes("%"), msg);
});

Deno.test("user's own request wins outright and is framed as their choice, not a data-driven read", () => {
  const msg = buildReasoningMessage(baseInput({
    category: "light",
    userRequestedCategory: "light",
    source: "whoop",
    recoveryScore: 91, // even with great recovery data --
    caps: NO_CAPS,
  }));
  assert(msg.toLowerCase().includes("you asked"), msg);
  assert(msg.includes("91"), "still cites data for reference");
});

Deno.test("consecutive-days rest escalation is cited, matching the rest-tier precedence", () => {
  const msg = buildReasoningMessage(baseInput({
    category: "rest",
    source: "whoop",
    recoveryScore: 75,
    caps: { ...NO_CAPS, consecutiveDaysRestEscalated: true },
  }));
  assert(msg.toLowerCase().includes("days in a row"), msg);
});

Deno.test("injury-protocol forced rest is cited independently of recovery data looking fine", () => {
  const msg = buildReasoningMessage(baseInput({
    category: "rest",
    source: "whoop",
    recoveryScore: 88,
    caps: { ...NO_CAPS, injuryRest: true },
  }));
  assert(msg.toLowerCase().includes("injury protocol"), msg);
});

Deno.test("a single light-tier cap is named by its own explanation, citing the real sleep number", () => {
  const msg = buildReasoningMessage(baseInput({
    category: "light",
    source: "oura",
    readinessScore: 70,
    sleepHours: 5,
    caps: { ...NO_CAPS, sleep: true },
  }));
  assert(msg.includes("5h"), msg);
  assert(msg.toLowerCase().includes("sleep"), msg);
});

Deno.test("multiple simultaneous light-tier caps: only ONE explanation is named, in index.ts's own precedence order", () => {
  // sleep precedes hrv in the shared OR-chain order -- sleep must win.
  const msg = buildReasoningMessage(baseInput({
    category: "light",
    source: "whoop",
    recoveryScore: 55,
    sleepHours: 5.5,
    caps: { ...NO_CAPS, sleep: true, hrv: true, stress: true },
  }));
  assert(msg.toLowerCase().includes("sleep"), msg);
  assert(!msg.toLowerCase().includes("hrv is down"), `should not also name HRV: ${msg}`);
});

Deno.test("moderate-tier injury cap is cited distinctly from the light-tier injury cap", () => {
  const msg = buildReasoningMessage(baseInput({
    category: "moderate",
    source: "whoop",
    recoveryScore: 90,
    caps: { ...NO_CAPS, injuryModerate: true },
  }));
  assert(msg.toLowerCase().includes("moderate injury protocol"), msg);
});

Deno.test("plain band-driven day (no caps at all) still cites the score with no fabricated 'why' clause", () => {
  const msg = buildReasoningMessage(baseInput({ category: "push_hard", source: "whoop", recoveryScore: 92 }));
  assert(msg.includes("92%"), msg);
  assert(!msg.toLowerCase().includes("capping"), msg);
});

Deno.test("low-confidence provisional baseline appends an explicit caveat", () => {
  const msg = buildReasoningMessage(baseInput({
    category: "moderate",
    source: "healthkit",
    band: "medium",
    dataConfidence: "low",
  }));
  assert(msg.toLowerCase().includes("still building"), msg);
});

Deno.test("high confidence never appends the low-confidence caveat", () => {
  const msg = buildReasoningMessage(baseInput({ source: "whoop", recoveryScore: 80, dataConfidence: "high" }));
  assert(!msg.toLowerCase().includes("still building"), msg);
});
