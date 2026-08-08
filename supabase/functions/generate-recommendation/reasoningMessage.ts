// Deterministic replacement for the old fixed-string-per-category MESSAGES
// map (Phase 2: see docs/coaching-personalization-plan.md) -- a short,
// plain-language sentence citing the ACTUAL numbers that drove today's
// category, generalized off whichever wearable fields are actually
// populated rather than assuming any one of them exists.
//
// Deliberately NOT an LLM call: generate-recommendation has zero AI calls
// today, and every number this needs is already sitting in local variables
// right where the old MESSAGES[category] lookup lived. A deterministic
// builder keeps BOTH the category decision and its explanation fully
// deterministic and unit-testable -- same "split into a pure module" shape
// as healthkitBand.ts/independentCaps.ts, this function's own siblings.
//
// The precedence used below to pick WHICH driver to cite mirrors index.ts's
// own computedCategory conditional exactly (same booleans, same left-to-
// right order) so this message can never contradict the category it's
// explaining -- it is purely a "why", never a second vote on "what".

import type { Band, DataConfidence } from "./healthkitBand.ts";
import type { Category } from "../_shared/independentCaps.ts";

export type Source = "whoop" | "oura" | "healthkit";

export interface ReasoningMessageCaps {
  sleep: boolean;
  hrv: boolean;
  stress: boolean;
  mood: boolean;
  consecutiveDays: boolean;
  consecutiveDaysRestEscalated: boolean;
  volume: boolean;
  injury: boolean;
  injuryModerate: boolean;
  injuryRest: boolean;
}

export interface ReasoningMessageInput {
  category: Category;
  /// The user's own explicit rest/active-recovery request for today, if
  /// any -- wins outright over every computed signal below, same
  /// precedence `category` itself already gives it (set-recommendation-
  /// override).
  userRequestedCategory: Category | null;
  source: Source;
  band: Band;
  /// True only for a HealthKit read with literally zero usable signals
  /// today (index.ts's own insufficientData) -- every number below is
  /// meaningless in that case, so the message must not cite any of them.
  insufficientData: boolean;
  dataConfidence: DataConfidence;
  recoveryScore: number | null;
  readinessScore: number | null;
  hrvMs: number | null;
  sleepHours: number | null;
  restingHr: number | null;
  strainScore: number | null;
  stressMinutes: number | null;
  caps: ReasoningMessageCaps;
}

const CATEGORY_OPENING: Record<Category, string> = {
  push_hard: "Today's a good day to push",
  moderate: "Today calls for a moderate session",
  light: "Today's a lighter day",
  rest: "Today's a full recovery day",
};

const CATEGORY_LABEL: Record<Category, string> = {
  push_hard: "high-intensity",
  moderate: "moderate",
  light: "light",
  rest: "rest",
};

// HealthKit has no single authoritative recovery score the way Whoop/Oura
// do (assessHealthKit derives a band from HRV/RHR vs. the user's own
// baseline) -- this translates that band into plain language instead of
// exposing the internal band label ("medium_high") verbatim.
const BAND_PHRASE: Record<Band, string> = {
  high: "well recovered",
  medium_high: "solidly recovered",
  medium: "recovering about average",
  low: "showing signs of poor recovery",
};

/// One clause citing whichever recovery score actually exists for the
/// deciding source -- never fabricates a number the source didn't report.
function scoreClause(input: ReasoningMessageInput): string {
  if (input.source === "whoop" && input.recoveryScore !== null) {
    return `Whoop recovery is ${input.recoveryScore}%`;
  }
  if (input.source === "oura" && input.readinessScore !== null) {
    return `Oura readiness is ${input.readinessScore}`;
  }
  return `Apple Health signals point to ${BAND_PHRASE[input.band]}`;
}

/// Trailing list of whichever secondary numbers are actually populated --
/// generalizes across sources rather than assuming any one field exists
/// (degrade gracefully with no wearable connected / a partial read).
function supportingNumbers(input: ReasoningMessageInput): string | null {
  const bits: string[] = [];
  if (input.sleepHours !== null) bits.push(`${input.sleepHours}h sleep`);
  if (input.hrvMs !== null) bits.push(`HRV ${Math.round(input.hrvMs)}ms`);
  if (input.restingHr !== null) bits.push(`resting HR ${Math.round(input.restingHr)}bpm`);
  if (input.strainScore !== null) {
    bits.push(
      input.source === "whoop" ? `day strain ${input.strainScore}/21` : `${input.strainScore} recent hard session(s)`,
    );
  }
  if (input.stressMinutes !== null) bits.push(`${Math.round(input.stressMinutes)}min high stress`);
  return bits.length > 0 ? bits.join(", ") : null;
}

/// Every populated number worth citing "for reference" -- the primary
/// recovery/readiness score (when the source actually reports one; skipped
/// for HealthKit, which has no single number, only a derived band) plus
/// whichever supportingNumbers exist. Used only by the user-requested-
/// override path below, which isn't explaining a data-driven decision but
/// still wants to show the user their numbers alongside their own choice.
function referenceNumbers(input: ReasoningMessageInput): string | null {
  const bits: string[] = [];
  if (input.source === "whoop" && input.recoveryScore !== null) bits.push(`Whoop recovery ${input.recoveryScore}%`);
  if (input.source === "oura" && input.readinessScore !== null) bits.push(`Oura readiness ${input.readinessScore}`);
  const supporting = supportingNumbers(input);
  if (supporting) bits.push(supporting);
  return bits.length > 0 ? bits.join(", ") : null;
}

/// Same left-to-right order as index.ts's light-tier OR-chain
/// (consecutiveDaysCapApplied || injuryProtocolCapApplied ||
/// volumeCapApplied || sleepCapApplied || hrvCapApplied || stressCapApplied
/// || moodCapApplied) -- picks ONE explanation to name even when several
/// caps are simultaneously true, for a readable sentence rather than a
/// laundry list.
const LIGHT_CAP_EXPLANATIONS: { key: keyof ReasoningMessageCaps; text: (i: ReasoningMessageInput) => string }[] = [
  { key: "consecutiveDays", text: () => "you've trained hard enough days in a row that it's time to back off" },
  { key: "injury", text: () => "your active injury protocol is capping today's intensity" },
  { key: "volume", text: () => "your recent training volume is already high for this stretch" },
  {
    key: "sleep",
    text: (i) => `last night's ${i.sleepHours !== null ? `${i.sleepHours}h` : "short"} sleep is capping today's intensity`,
  },
  { key: "hrv", text: () => "today's HRV is down from your usual baseline" },
  { key: "stress", text: () => "today's stress load is elevated" },
  { key: "mood", text: () => "you checked in feeling rough today" },
];

/// The full reasoning sentence(s) for daily_recommendation.message -- 2-3
/// sentences, always citing real numbers when any exist. The CATEGORY
/// decision itself is never recomputed here; `input.category` is trusted
/// as-is and this function only ever explains it.
export function buildReasoningMessage(input: ReasoningMessageInput): string {
  // The user's own request wins outright, same as it does for `category`
  // itself -- still splices in today's data as context, never as the
  // reason (that would misattribute the user's own choice to the wearable).
  if (input.userRequestedCategory !== null) {
    const numbers = referenceNumbers(input);
    return `You asked for a ${CATEGORY_LABEL[input.category]} day today, so that's what's planned` +
      (numbers ? ` (today's data for reference: ${numbers}).` : ".");
  }

  if (input.insufficientData) {
    return `No wearable or HealthKit signals yet today, so we're starting you at a safe ${
      CATEGORY_LABEL[input.category]
    } baseline until there's enough history to read your recovery accurately.`;
  }

  const opening = CATEGORY_OPENING[input.category];
  const score = scoreClause(input);
  const numbers = supportingNumbers(input);
  const dataClause = numbers ? `${score}, ${numbers}` : score;

  let whyClause: string | null = null;
  if (input.caps.consecutiveDaysRestEscalated) {
    whyClause = "you've pushed hard enough days in a row that your body needs a real reset, not just a lighter session";
  } else if (input.caps.injuryRest) {
    whyClause = "your active injury protocol calls for full rest today, regardless of how your recovery data looks";
  } else {
    const firedLightCap = LIGHT_CAP_EXPLANATIONS.find((c) => input.caps[c.key]);
    if (firedLightCap) {
      whyClause = firedLightCap.text(input);
    } else if (input.caps.injuryModerate) {
      whyClause = "a moderate injury protocol is keeping today capped below your usual push-hard days";
    }
  }

  const base = whyClause ? `${opening} -- ${whyClause} (${dataClause}).` : `${opening} -- ${dataClause}.`;

  // Only the HealthKit path can ever be low-confidence (a provisional
  // baseline built from as little as 2 days of history) -- flagged so the
  // user knows to treat today's read as a rough one, not silently trusted
  // the same as a firm baseline.
  return input.dataConfidence === "low"
    ? `${base} Your recovery baseline is still building, so treat this as a rough read for now.`
    : base;
}
