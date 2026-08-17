// Run: deno test supabase/functions/
//
// buildReasoningMessage never decides the category (that's index.ts's own
// computedCategory chain) -- these tests only check that the EXPLANATION
// text (a) cites real numbers when they exist, (b) never fabricates a
// number a source didn't report, and (c) picks the same "why" index.ts's
// own precedence would pick, so the two can never contradict each other.
//
// Returns { summary, detail } (item 4 fix): `summary` is the short,
// length-capped line (opening + data clause only -- no why-clause, no
// confidence trailer); `detail` is the fuller sentence, including both.
// Tests check whichever field the content in question actually lives in.

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
    language: "en",
    ...overrides,
  };
}

Deno.test("cites the real Whoop recovery percentage, never a fabricated number", () => {
  const msg = buildReasoningMessage(baseInput({ source: "whoop", recoveryScore: 82 }));
  assert(msg.summary.includes("82%"), msg.summary);
  assert(msg.summary.includes("Whoop"), msg.summary);
});

Deno.test("cites the real Oura readiness score", () => {
  const msg = buildReasoningMessage(baseInput({ source: "oura", readinessScore: 71, recoveryScore: null }));
  assert(msg.summary.includes("71"), msg.summary);
  assert(msg.summary.includes("Oura"), msg.summary);
});

Deno.test("HealthKit (no single score) describes the band in plain language instead of a fabricated number", () => {
  const msg = buildReasoningMessage(baseInput({ source: "healthkit", band: "medium" }));
  assert(msg.summary.includes("Apple Health"), msg.summary);
  assert(msg.summary.includes("recovering about average"), msg.summary);
});

Deno.test("degrades gracefully: no secondary numbers populated still yields a clean sentence", () => {
  const msg = buildReasoningMessage(baseInput({ source: "whoop", recoveryScore: 60 }));
  assert(!msg.summary.includes("undefined"), msg.summary);
  assert(!msg.summary.includes("null"), msg.summary);
  assert(!/,\s*\)/.test(msg.summary), `dangling comma before close-paren: ${msg.summary}`);
});

Deno.test("supporting numbers are appended only when actually populated, generalized across whichever fields exist", () => {
  const msg = buildReasoningMessage(baseInput({
    source: "oura",
    readinessScore: 65,
    sleepHours: 7.5,
    restingHr: 58,
  }));
  assert(msg.summary.includes("7.5h sleep"), msg.summary);
  assert(msg.summary.includes("58bpm"), msg.summary);
  assert(!msg.summary.includes("HRV"), "should not mention HRV when it wasn't populated");
});

Deno.test("insufficient HealthKit data never cites a fabricated number", () => {
  const msg = buildReasoningMessage(baseInput({
    category: "moderate",
    source: "healthkit",
    insufficientData: true,
    band: "medium",
  }));
  assert(msg.summary.toLowerCase().includes("no wearable"), msg.summary);
  assert(!msg.summary.includes("%"), msg.summary);
});

Deno.test("user's own request wins outright and is framed as their choice, not a data-driven read", () => {
  const msg = buildReasoningMessage(baseInput({
    category: "light",
    userRequestedCategory: "light",
    source: "whoop",
    recoveryScore: 91, // even with great recovery data --
    caps: NO_CAPS,
  }));
  assert(msg.summary.toLowerCase().includes("you asked"), msg.summary);
  // The "for reference" numbers clause can land past the summary's 90-char
  // cap (as it does here) -- detail is uncapped and always has it.
  assert(msg.detail.includes("91"), "detail still cites data for reference");
});

Deno.test("consecutive-days rest escalation is cited in the detail, matching the rest-tier precedence", () => {
  const msg = buildReasoningMessage(baseInput({
    category: "rest",
    source: "whoop",
    recoveryScore: 75,
    caps: { ...NO_CAPS, consecutiveDaysRestEscalated: true },
  }));
  assert(msg.detail.toLowerCase().includes("days in a row"), msg.detail);
});

Deno.test("injury-protocol forced rest is cited independently of recovery data looking fine", () => {
  const msg = buildReasoningMessage(baseInput({
    category: "rest",
    source: "whoop",
    recoveryScore: 88,
    caps: { ...NO_CAPS, injuryRest: true },
  }));
  assert(msg.detail.toLowerCase().includes("injury protocol"), msg.detail);
});

Deno.test("a single light-tier cap is named by its own explanation in the detail, citing the real sleep number", () => {
  const msg = buildReasoningMessage(baseInput({
    category: "light",
    source: "oura",
    readinessScore: 70,
    sleepHours: 5,
    caps: { ...NO_CAPS, sleep: true },
  }));
  assert(msg.detail.includes("5h"), msg.detail);
  assert(msg.detail.toLowerCase().includes("sleep"), msg.detail);
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
  assert(msg.detail.toLowerCase().includes("sleep"), msg.detail);
  assert(!msg.detail.toLowerCase().includes("hrv is down"), `should not also name HRV: ${msg.detail}`);
});

Deno.test("moderate-tier injury cap is cited distinctly from the light-tier injury cap", () => {
  const msg = buildReasoningMessage(baseInput({
    category: "moderate",
    source: "whoop",
    recoveryScore: 90,
    caps: { ...NO_CAPS, injuryModerate: true },
  }));
  assert(msg.detail.toLowerCase().includes("moderate injury protocol"), msg.detail);
});

Deno.test("plain band-driven day (no caps at all) still cites the score with no fabricated 'why' clause", () => {
  const msg = buildReasoningMessage(baseInput({ category: "push_hard", source: "whoop", recoveryScore: 92 }));
  assert(msg.summary.includes("92%"), msg.summary);
  assert(!msg.summary.toLowerCase().includes("capping"), msg.summary);
});

Deno.test("low-confidence provisional baseline appends an explicit caveat to detail, not summary", () => {
  const msg = buildReasoningMessage(baseInput({
    category: "moderate",
    source: "healthkit",
    band: "medium",
    dataConfidence: "low",
  }));
  assert(msg.detail.toLowerCase().includes("still building"), msg.detail);
  assert(!msg.summary.toLowerCase().includes("still building"), msg.summary);
});

Deno.test("high confidence never appends the low-confidence caveat", () => {
  const msg = buildReasoningMessage(baseInput({ source: "whoop", recoveryScore: 80, dataConfidence: "high" }));
  assert(!msg.detail.toLowerCase().includes("still building"), msg.detail);
});

Deno.test("summary is always short enough to fit the card's line limit, and never truncates mid-word", () => {
  const msg = buildReasoningMessage(baseInput({
    category: "light",
    source: "oura",
    readinessScore: 65,
    sleepHours: 7.5,
    hrvMs: 42,
    restingHr: 58,
    strainScore: 3,
    stressMinutes: 45,
    caps: { ...NO_CAPS, sleep: true },
    dataConfidence: "low",
  }));
  assert(msg.summary.length <= 91, `summary too long (${msg.summary.length}): ${msg.summary}`);
});

Deno.test("an unrecognized language code falls back to English rather than throwing", () => {
  const msg = buildReasoningMessage(baseInput({ source: "whoop", recoveryScore: 82, language: "xx" }));
  assert(msg.summary.includes("Whoop"), msg.summary);
});

Deno.test("a non-English language produces genuinely different text, not an English fallback", () => {
  const msg = buildReasoningMessage(baseInput({ source: "whoop", recoveryScore: 82, language: "ru" }));
  assert(msg.summary.includes("Whoop"), msg.summary);
  assert(!msg.summary.includes("well recovered"), msg.summary);
});
