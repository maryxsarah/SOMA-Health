// DRAFTED, NOT EXPERT-REVIEWED -- needs sign-off from a certified S&C/PT
// professional before this is treated as authoritative, same caveat as
// contraindications.ts. Deterministic on purpose: which body part a user
// gets redirected to must never be left to LLM judgment.
//
// Today's mechanism (before this file existed) was exclusion-within-the-
// same-workout: generate-workout-plan's prompt explicitly told the model
// "do not substitute a different type of workout or body part focus...
// keep it a close, safe variant of the same movement pattern." That's
// fine for a MILD injury (a genuinely safe variant of the same body part
// usually exists), but for a MODERATE/SEVERE injury there often isn't a
// safe variant of "leg day" for someone with a bad knee -- the day itself
// needs to become a different body part. This file is that redirect,
// applied BEFORE the prompt is built, so the LLM only ever sees an
// already-safe target instead of being asked to reshape an unsafe one.

import type { InjurySeverityLevel } from "./contraindications.ts";

export type BodyPartFocus = "full_body" | "upper_body" | "lower_body" | "core" | "cardio" | "recovery";

const KNOWN_BODY_PARTS: BodyPartFocus[] = ["full_body", "upper_body", "lower_body", "core", "cardio", "recovery"];

function isKnownBodyPart(value: string): value is BodyPartFocus {
  return (KNOWN_BODY_PARTS as string[]).includes(value);
}

/// Only moderate/severe injuries redirect the day's body part at all --
/// mild stays exclusion-only (contraindications.ts handles it within the
/// same body part). Each entry maps a body part this injury conflicts
/// with to a genuinely different, safe one.
const SUBSTITUTION_RULES: Record<string, Partial<Record<BodyPartFocus, BodyPartFocus>>> = {
  knee: { lower_body: "upper_body", cardio: "upper_body", full_body: "upper_body" },
  ankle: { lower_body: "upper_body", cardio: "upper_body", full_body: "upper_body" },
  hip: { lower_body: "upper_body", cardio: "upper_body", full_body: "upper_body" },
  shoulder: { upper_body: "lower_body", full_body: "lower_body" },
  wrist: { upper_body: "lower_body", full_body: "lower_body" },
  back: { full_body: "upper_body", lower_body: "upper_body", cardio: "recovery" },
};

const MAX_ITERATIONS = 4;

/// Resolves the body part a user should actually be assigned today, given
/// their active injuries. Walks the substitution table until it lands on a
/// body part none of the user's moderate/severe injuries conflict with,
/// bounded to avoid looping on contradictory rules -- falls back to
/// "recovery" (always safe) if no resolution converges.
export function resolveBodyPartForInjuries(
  assignedBodyPart: string,
  injuryTags: string[],
  severityMap: Record<string, InjurySeverityLevel>,
): { bodyPart: BodyPartFocus; substituted: boolean } {
  if (!isKnownBodyPart(assignedBodyPart)) {
    return { bodyPart: "full_body", substituted: false };
  }

  const relevantTags = injuryTags.filter((tag) => {
    const severity = severityMap[tag] ?? "moderate";
    return severity === "moderate" || severity === "severe";
  });
  if (relevantTags.length === 0) {
    return { bodyPart: assignedBodyPart, substituted: false };
  }

  let candidate: BodyPartFocus = assignedBodyPart;
  for (let i = 0; i < MAX_ITERATIONS; i++) {
    const conflictingTag = relevantTags.find((tag) => SUBSTITUTION_RULES[tag]?.[candidate] !== undefined);
    if (!conflictingTag) {
      return { bodyPart: candidate, substituted: candidate !== assignedBodyPart };
    }
    candidate = SUBSTITUTION_RULES[conflictingTag]![candidate]!;
  }
  // Couldn't converge within the bound -- fail safe rather than risk an
  // unresolved conflict slipping through.
  return { bodyPart: "recovery", substituted: true };
}

/// Every body-part redirect currently active for a user's injuries --
/// consumed by the resolve-injury-substitutions Edge Function so the
/// client can steer its suggestion list away from conflicting body parts
/// before the user even picks one, rather than only resolving at
/// generation time.
export function activeSubstitutionMap(
  injuryTags: string[],
  severityMap: Record<string, InjurySeverityLevel>,
): Record<string, BodyPartFocus> {
  const map: Record<string, BodyPartFocus> = {};
  for (const bodyPart of KNOWN_BODY_PARTS) {
    const { bodyPart: resolved, substituted } = resolveBodyPartForInjuries(bodyPart, injuryTags, severityMap);
    if (substituted) map[bodyPart] = resolved;
  }
  return map;
}
