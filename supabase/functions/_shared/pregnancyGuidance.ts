// DRAFTED, NOT EXPERT-REVIEWED -- generic, widely-published prenatal
// exercise caution points (e.g. avoiding prolonged supine positioning and
// high fall-risk/contact work later in pregnancy), not individualized
// medical guidance. Deterministic on purpose, same rule this codebase
// already applies to contraindications.ts -- pregnancy-aware adjustment
// must never be left to LLM judgment. Always paired with PREGNANCY_DISCLAIMER,
// which is rendered client-side as a fixed UI banner (see
// RecommendationDetailView) rather than trusted to appear in LLM output.

export type Trimester = "first" | "second" | "third";

export function trimesterFromWeek(week: number | null): Trimester | null {
  if (week === null) return null;
  if (week <= 13) return "first";
  if (week <= 27) return "second";
  return "third";
}

export const PREGNANCY_DISCLAIMER =
  "This is general guidance only, not medical advice -- please follow your doctor's or midwife's recommendations, especially if you have any pregnancy complications.";

/// Builds a deterministic exclusion sentence for the prompt, plus a
/// flattened keyword list for exercise/template filtering -- same shape as
/// contraindications.ts's describeContraindications, so both merge cleanly
/// in safetyFlags.ts's excludedKeywords set.
export function describePregnancyGuidance(
  week: number | null,
): { promptLine: string; excludedKeywords: string[] } {
  const trimester = trimesterFromWeek(week);
  const weekLabel = week !== null ? ` (week ${week})` : "";

  // General caution that applies across all trimesters, and grows more
  // conservative as pregnancy advances -- broader exclusions later, never
  // narrower. Sources of caution: prolonged supine positioning after the
  // first trimester, contact/high fall-risk/high-impact work throughout,
  // heavy Valsalva (breath-holding) lifting, and overheating-risk steady
  // -state cardio.
  const base = {
    excludedPatterns: ["heavy Valsalva/breath-holding lifts", "high fall-risk or contact movements"],
    excludedKeywords: ["max effort", "1rm", "heavy deadlift", "contact", "box jump", "plyo"],
  };

  if (trimester === "first") {
    return {
      promptLine:
        `pregnant${weekLabel} -- keep effort moderate, avoid heavy breath-holding lifts and high fall-risk or contact movements, and stop immediately for pain, dizziness, or shortness of breath`,
      excludedKeywords: base.excludedKeywords,
    };
  }

  if (trimester === "second") {
    const keywords = [...base.excludedKeywords, "supine", "flat bench", "lying on back", "sit-up", "crunch"];
    return {
      promptLine:
        `pregnant${weekLabel}, second trimester -- avoid prolonged exercises lying flat on the back, heavy breath-holding lifts, and high fall-risk or contact movements; favor seated, standing, or side-lying positions`,
      excludedKeywords: keywords,
    };
  }

  // Third trimester OR unknown week -- a safety default has to fail
  // conservative, so no recorded week gets the broadest exclusions.
  const keywords = [
    ...base.excludedKeywords,
    "supine",
    "flat bench",
    "lying on back",
    "sit-up",
    "crunch",
    "jump",
    "run",
    "sprint",
    "agility",
  ];
  const stage = trimester === "third" ? `${weekLabel}, third trimester` : " (week not recorded -- assume late pregnancy)";
  return {
    promptLine:
      `pregnant${stage} -- avoid lying flat on the back, jumping/running/high-impact cardio, heavy breath-holding lifts, and any high fall-risk or contact movements; favor gentle, well-supported, low-impact work`,
    excludedKeywords: keywords,
  };
}
