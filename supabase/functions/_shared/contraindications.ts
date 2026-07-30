// DRAFTED, NOT EXPERT-REVIEWED -- needs sign-off from a certified S&C/PT
// professional before this is treated as authoritative. Deterministic on
// purpose: contraindication mapping must never be left to LLM judgment,
// same rule this codebase already applies to template/category selection
// (see generate-gym-workout/templates.ts) and load guidance (see
// generate-workout-plan/index.ts's LOAD_FRACTION_OF_BODYWEIGHT).

export type InjurySeverityLevel = "mild" | "moderate" | "severe";

export interface Contraindication {
  /// Human-readable movement patterns to avoid, folded into the prompt.
  excludedPatterns: string[];
  /// Lowercase substrings matched against generated/template exercise
  /// names or target areas -- the deterministic filter, not the LLM.
  excludedKeywords: string[];
  /// One-line summary of what to avoid, for the prompt's exclusion line.
  note: string;
}

const EMPTY: Contraindication = { excludedPatterns: [], excludedKeywords: [], note: "" };

export const CONTRAINDICATIONS: Record<string, Record<InjurySeverityLevel, Contraindication>> = {
  knee: {
    mild: {
      excludedPatterns: ["deep knee flexion beyond 90 degrees"],
      excludedKeywords: ["jump", "plyo", "box jump"],
      note: "avoid deep knee flexion and jumping/plyometric work",
    },
    moderate: {
      excludedPatterns: ["deep squats", "lunges", "jumping/plyometric work", "cycling", "deep-knee-flexion yoga poses"],
      excludedKeywords: ["squat", "lunge", "jump", "plyo", "bike", "cycle", "cycling", "spin", "yoga", "vinyasa", "pigeon"],
      note: "avoid deep squats, lunges, jumping/plyometric work, cycling (repetitive loaded knee flexion), and deep-knee-flexion yoga poses",
    },
    severe: {
      excludedPatterns: ["any loaded knee flexion", "jumping/plyometric work", "running/sprinting", "cycling", "yoga poses involving knee flexion"],
      excludedKeywords: ["squat", "lunge", "jump", "plyo", "run", "sprint", "bike", "cycle", "cycling", "spin", "yoga", "vinyasa", "pigeon"],
      note: "avoid all loaded knee flexion, jumping, running, cycling, and yoga poses involving knee flexion -- upper-body and seated work only",
    },
  },
  shoulder: {
    mild: {
      excludedPatterns: ["heavy overhead pressing"],
      excludedKeywords: ["overhead press"],
      note: "keep overhead pressing light",
    },
    moderate: {
      excludedPatterns: ["overhead press", "heavy bench press", "dips", "weight-bearing overhead yoga poses"],
      excludedKeywords: ["overhead", "bench press", "dip", "yoga", "vinyasa", "chaturanga", "downward dog"],
      note: "avoid overhead pressing, heavy bench press, dips, and weight-bearing overhead yoga poses (e.g. chaturanga, downward dog)",
    },
    severe: {
      excludedPatterns: ["any overhead movement", "pressing movements", "dips", "weight-bearing yoga poses"],
      excludedKeywords: ["overhead", "press", "dip", "yoga", "vinyasa", "chaturanga", "downward dog"],
      note: "avoid all overhead and pressing movements, and weight-bearing yoga poses -- lower-body work only",
    },
  },
  back: {
    mild: {
      excludedPatterns: ["heavy loaded spinal flexion"],
      excludedKeywords: ["deadlift", "good morning"],
      note: "keep loaded spinal flexion light",
    },
    moderate: {
      excludedPatterns: ["loaded spinal flexion", "heavy deadlifts", "loaded twisting", "backbend/loaded-flexion yoga poses"],
      excludedKeywords: ["deadlift", "good morning", "russian twist", "yoga", "vinyasa"],
      note: "avoid loaded spinal flexion, heavy deadlifts, loaded twisting, and backbend/loaded-flexion yoga poses",
    },
    severe: {
      excludedPatterns: ["any spinal loading", "deadlifts", "loaded twisting", "high-impact cardio", "yoga poses involving spinal loading"],
      excludedKeywords: ["deadlift", "twist", "run", "jump", "yoga", "vinyasa"],
      note: "avoid all spinal loading, high-impact cardio, and yoga poses involving spinal loading -- gentle mobility only",
    },
  },
  ankle: {
    mild: {
      excludedPatterns: ["jumping/plyometric work"],
      excludedKeywords: ["jump", "plyo"],
      note: "avoid jumping/plyometric work",
    },
    moderate: {
      // Balance-heavy single-leg yoga poses (tree, warrior III, etc.) load
      // an unstable ankle under bodyweight -- a weaker case than knee's
      // cycling/yoga exclusion above, so kept narrower and moderate+ only.
      excludedPatterns: ["jumping/plyometric work", "lateral cutting/agility drills", "running on uneven surfaces", "balance-heavy standing yoga poses"],
      excludedKeywords: ["jump", "plyo", "sprint", "agility", "run", "yoga", "vinyasa"],
      note: "avoid jumping, lateral cutting/agility drills, running, and balance-heavy standing yoga poses",
    },
    severe: {
      excludedPatterns: ["any weight-bearing impact", "jumping/plyometric work", "running/sprinting", "standing yoga poses"],
      excludedKeywords: ["jump", "plyo", "sprint", "run", "agility", "yoga", "vinyasa"],
      note: "avoid all weight-bearing impact work and standing yoga poses -- seated or upper-body work only",
    },
  },
  hip: {
    mild: {
      excludedPatterns: ["deep hip flexion under load"],
      excludedKeywords: ["deep lunge"],
      note: "keep deep hip flexion light",
    },
    moderate: {
      excludedPatterns: ["deep hip flexion", "heavy loaded hip hinge", "lateral impact movements"],
      excludedKeywords: ["lunge", "deadlift", "jump"],
      note: "avoid deep hip flexion, heavy loaded hip hinges, and lateral impact movements",
    },
    severe: {
      excludedPatterns: ["any loaded hip flexion", "hip hinge movements", "jumping/lateral impact"],
      excludedKeywords: ["lunge", "squat", "deadlift", "jump"],
      note: "avoid all loaded hip flexion and impact work -- upper-body work only",
    },
  },
  wrist: {
    mild: {
      excludedPatterns: ["heavy loaded wrist extension"],
      excludedKeywords: ["push-up"],
      note: "keep loaded wrist extension light",
    },
    moderate: {
      excludedPatterns: ["loaded wrist extension (push-ups, front rack)", "heavy grip work"],
      excludedKeywords: ["push-up", "front rack", "farmer carry", "deadlift"],
      note: "avoid loaded wrist extension (push-ups, front rack holds) and heavy grip work",
    },
    severe: {
      excludedPatterns: ["any wrist loading", "grip-dependent movements"],
      excludedKeywords: ["push-up", "front rack", "carry", "deadlift", "row", "pull-up"],
      note: "avoid all wrist loading and grip-dependent movements -- lower-body work only",
    },
  },
  other: {
    mild: { ...EMPTY, note: "use general caution per the user's free-text notes" },
    moderate: { ...EMPTY, note: "use general caution per the user's free-text notes" },
    severe: { ...EMPTY, note: "use significant caution per the user's free-text notes" },
  },
};

/// Builds the deterministic exclusion sentence for a prompt, plus a
/// flattened keyword list for template/exercise filtering -- the two call
/// sites are generate-workout-plan/index.ts's buildPrompt and
/// safetyFlags.ts/templates.ts's selectTemplate.
export function describeContraindications(
  injuryTags: string[],
  severityMap: Record<string, InjurySeverityLevel>,
): { promptLine: string; excludedKeywords: string[] } {
  if (injuryTags.length === 0) {
    return { promptLine: "none noted", excludedKeywords: [] };
  }

  const parts: string[] = [];
  const keywords = new Set<string>();
  for (const tag of injuryTags) {
    const severity = severityMap[tag] ?? "moderate";
    const entry = CONTRAINDICATIONS[tag]?.[severity] ?? CONTRAINDICATIONS.other[severity];
    if (entry.note) {
      parts.push(`${tag} (${severity} severity) -- ${entry.note}`);
    } else {
      parts.push(`${tag} (${severity} severity)`);
    }
    for (const kw of entry.excludedKeywords) keywords.add(kw);
  }

  return {
    promptLine: parts.join("; "),
    excludedKeywords: Array.from(keywords),
  };
}
