// Deterministic safety pass over a coach's free-text assignment. Extracted
// from index.ts so the conflict contract is testable without Deno.serve.

export interface Conflict {
  keyword: string;
  source: "injury" | "pregnancy";
  pregnancy: boolean;
  message: string;
}

/// Same coarse substring pass the rest of the codebase uses for exclusion
/// filtering -- deterministic, never left to a model.
export function findConflicts(text: string, keywords: string[], source: "injury" | "pregnancy"): Conflict[] {
  const haystack = text.toLowerCase();
  return keywords
    .filter((kw) => haystack.includes(kw.toLowerCase()))
    .map((keyword) => ({
      keyword,
      source,
      pregnancy: source === "pregnancy",
      message: source === "injury"
        ? `This assignment mentions "${keyword}", which conflicts with an injury you've noted. You can proceed if your coach knows your situation.`
        : `This assignment mentions "${keyword}", which is normally excluded during pregnancy. Please discuss this assignment with your healthcare provider before proceeding.`,
    }));
}
