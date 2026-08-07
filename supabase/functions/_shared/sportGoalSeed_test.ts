// deno test --allow-read supabase/functions/
//
// Integrity of the sport-goal seed migration against the exercise-library
// seed: every mapped exercise id must exist (a miss silently drops media
// and vocabulary entries), every target_table must be valid JSON, and the
// catalog must ship dark (status='internal' -- the kill-switch default).
// Skips itself politely under the bare `deno test` command (no read perm).
import { assert, assertEquals } from "jsr:@std/assert";

const canRead = (await Deno.permissions.query({ name: "read" })).state === "granted";

function repoPath(rel: string): string {
  return new URL(`../../${rel}`, import.meta.url).pathname;
}

Deno.test({
  name: "INVARIANT: every seeded goal_exercise id exists in the exercise library seed",
  ignore: !canRead,
  fn: async () => {
    const seed = await Deno.readTextFile(repoPath("migrations/20260803130000_seed_sport_goal_catalog.sql"));
    const library = await Deno.readTextFile(repoPath("migrations/20260731091000_seed_exercise_library.sql"));
    const libraryIds = new Set([...library.matchAll(/\('([A-Za-z0-9_-]+)'/g)].map((m) => m[1]));
    assert(libraryIds.size > 500, `library seed parse looks broken: ${libraryIds.size} ids`);

    const section = seed.split("insert into goal_exercise")[1]?.split(";")[0] ?? "";
    assert(section.length > 0, "goal_exercise insert section not found");
    const rows = [...section.matchAll(/\('([^']+)',\s*'([^']+)',\s*'([^']+)'\)/g)];
    assert(rows.length >= 80, `expected the seeded mapping rows, found ${rows.length}`);
    const missing = rows.map((r) => r[2]).filter((id) => !libraryIds.has(id));
    assertEquals(missing, [], `goal_exercise ids missing from exercise_library: ${missing.join(", ")}`);
  },
});

Deno.test({
  name: "INVARIANT: every seeded target_table parses as JSON with a bands object",
  ignore: !canRead,
  fn: async () => {
    const seed = await Deno.readTextFile(repoPath("migrations/20260803130000_seed_sport_goal_catalog.sql"));
    const blocks = [...seed.matchAll(/'(\{[\s\S]*?\})'(?:::jsonb)?\s*,\s*(?:true|false)/g)];
    assert(blocks.length >= 8, `expected 8 target_table blocks, found ${blocks.length}`);
    for (const [, raw] of blocks) {
      const parsed = JSON.parse(raw.replaceAll("''", "'"));
      assert(typeof parsed === "object" && parsed !== null);
      assert("bands" in parsed, "target_table without a bands object");
    }
  },
});

Deno.test({
  name: "INVARIANT: the catalog ships dark -- every seeded sport is status='internal'",
  ignore: !canRead,
  fn: async () => {
    const seed = await Deno.readTextFile(repoPath("migrations/20260803130000_seed_sport_goal_catalog.sql"));
    const sportsSection = seed.split("insert into sports")[1]?.split(";")[0] ?? "";
    const statuses = [...sportsSection.matchAll(/'(seeded|internal|live)'/g)].map((m) => m[1]);
    assertEquals(statuses.length, 4, "expected 4 seeded sports");
    assert(statuses.every((s) => s === "internal"), `non-dark sport in seed: ${statuses.join(", ")}`);
  },
});
