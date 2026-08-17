// Run: deno test supabase/functions/
//
// selectTemplate is the deterministic half of the gym-photo feature -- if it
// picks wrong, the photo step is decorative. Two of these are regressions for
// bugs that made it exactly that.

import { assert, assertEquals, assertThrows } from "jsr:@std/assert";
import { CONFIRMED_NO_LIBRARY_EQUIVALENT, GYM_WORKOUT_TEMPLATES, selectTemplate } from "./templates.ts";
import { EQUIPMENT_VOCABULARY } from "../_shared/equipment.ts";

const CATEGORIES = ["rest", "light", "moderate", "push_hard"] as const;
const FULL_GYM = new Set(["barbell", "squat rack", "dumbbells"]);

Deno.test("INVARIANT: every category has a bodyweight, low-impact fallback", () => {
  // Without this, an injured user with no equipment has no eligible template
  // and selectTemplate throws. Documented on GymWorkoutTemplate.highImpact.
  for (const category of CATEGORIES) {
    const fallback = GYM_WORKOUT_TEMPLATES.find((t) =>
      t.category === category && t.requiredEquipment.length === 0 && !t.highImpact
    );
    assert(fallback, `no bodyweight low-impact template for "${category}"`);
  }
});

Deno.test("INVARIANT: requiredEquipment only uses the shared vocabulary", () => {
  // A typo here does not fail loudly -- it makes the template permanently
  // unreachable, because the vision model can only ever emit vocabulary
  // values.
  const vocabulary = new Set<string>(EQUIPMENT_VOCABULARY);
  for (const template of GYM_WORKOUT_TEMPLATES) {
    for (const item of template.requiredEquipment) {
      assert(
        vocabulary.has(item),
        `template "${template.id}" requires "${item}", which is not in EQUIPMENT_VOCABULARY`,
      );
    }
  }
});

Deno.test("REGRESSION: a fully equipped gym does not get a bodyweight workout", () => {
  // Bodyweight templates declare `requiredEquipment: []`, which satisfies
  // `.every()` vacuously, so they are candidates for everyone -- and they are
  // declared first. The old `pool.find(goalMatch) ?? pool[0]` therefore
  // returned them almost always, and the equipment-aware templates were
  // effectively unreachable.
  for (const category of ["moderate", "push_hard"] as const) {
    const template = selectTemplate(category, FULL_GYM, ["build_strength"]);
    assert(
      template.requiredEquipment.length > 0,
      `${category}: picked "${template.id}", which ignores the user's equipment`,
    );
  }
});

Deno.test("selection prefers the template using the most equipment", () => {
  const template = selectTemplate("light", new Set(["dumbbells"]), []);
  assertEquals(template.id, "light_dumbbells_full_body");
});

Deno.test("REGRESSION: confirming a treadmill actually selects a treadmill template", () => {
  // BUG report: "treadmill" was a real, recognized EQUIPMENT_VOCABULARY
  // entry, but no template's requiredEquipment ever named it, so
  // confirming one in the gym-photo flow had zero effect on selection.
  const template = selectTemplate("moderate", new Set(["treadmill"]), []);
  assertEquals(template.id, "moderate_treadmill_intervals");
  assert(template.requiredEquipment.includes("treadmill"));
});

Deno.test("the treadmill template is excluded (as high-impact) for a noted injury", () => {
  // Running/sprinting is repeated-impact work, unlike the low-impact
  // bike/rower cardio-machine templates -- an injured user with treadmill
  // access must still fall back to something low-impact, not this one.
  const template = selectTemplate("moderate", new Set(["treadmill"]), [], true);
  assertEquals(template.highImpact, false);
  assert(template.id !== "moderate_treadmill_intervals");
});

Deno.test("an injury excludes high-impact templates in every category", () => {
  for (const category of CATEGORIES) {
    for (const equipment of [new Set<string>(), FULL_GYM]) {
      const template = selectTemplate(category, equipment, ["general_fitness"], true);
      assertEquals(
        template.highImpact,
        false,
        `${category}: picked high-impact "${template.id}" despite a noted injury`,
      );
    }
  }
});

Deno.test("unknown equipment strings are ignored, not matched", () => {
  // Genuinely unrecognisable input must not open any equipment template.
  // Note "free weights" and "dumbbell" are NOT examples of this any more --
  // they are recognised synonyms (see equipment_test.ts); using them here
  // was the test asserting the very bug that silently dropped hand-typed
  // equipment.
  const template = selectTemplate("moderate", new Set(["a swimming pool", "vibes"]), []);
  assertEquals(template.requiredEquipment.length, 0);
});

Deno.test("synonyms typed by hand still reach the right template", () => {
  const template = selectTemplate("light", new Set(["dumbbell"]), []);
  assertEquals(template.id, "light_dumbbells_full_body");
});

Deno.test("equipment matching is case- and whitespace-insensitive", () => {
  const template = selectTemplate("light", new Set([" DUMBBELLS "]), []);
  assertEquals(template.id, "light_dumbbells_full_body");
});

Deno.test("goals break ties between equally specific templates", () => {
  const strength = selectTemplate("push_hard", new Set(["dumbbells"]), ["build_strength"]);
  assertEquals(strength.id, "push_hard_dumbbell_complex");
});

Deno.test("an unknown category throws rather than guessing", () => {
  assertThrows(() => selectTemplate("not_a_category", new Set(), []));
});

Deno.test("REGRESSION: every image-less template entry has been hand-audited, not silently unmatched", () => {
  // BUG report: 43 of 84 template entries had no library_id, and every one
  // of them turned out to return zero exact matches against the real
  // exercise_library table -- roughly half of every gym-photo-generated
  // workout had no media, by construction. 23 of those 43 turned out to
  // have a real equivalent under a different name and are now wired in
  // above; the remaining 20 genuinely have none (see
  // CONFIRMED_NO_LIBRARY_EQUIVALENT's own comment for why, split by
  // reason). This test is the enforcement: any exercise missing a
  // library_id must be explicitly on that allowlist -- a *new* image-less
  // entry that isn't on it means someone added an exercise without doing
  // the lookup, which is exactly how this bug happened the first time.
  const allNames = GYM_WORKOUT_TEMPLATES.flatMap((t) => [
    ...t.warm_up,
    ...t.blocks.flatMap((b) => b.exercises),
    ...t.cool_down,
  ]);

  const unmatched = allNames.filter((e) => !e.library_id);
  for (const exercise of unmatched) {
    assert(
      CONFIRMED_NO_LIBRARY_EQUIVALENT.has(exercise.name),
      `"${exercise.name}" has no library_id and is not on CONFIRMED_NO_LIBRARY_EQUIVALENT -- ` +
        `look it up against exercise_library and either wire in the real match or add it to the ` +
        `allowlist with a reason`,
    );
  }

  // And the reverse: every allowlisted name must still actually be
  // image-less in the templates today, so the list can't silently drift
  // stale (e.g. a later edit adds a library_id but forgets to remove the
  // now-wrong allowlist entry).
  const unmatchedNames = new Set(unmatched.map((e) => e.name));
  for (const name of CONFIRMED_NO_LIBRARY_EQUIVALENT) {
    assert(
      unmatchedNames.has(name),
      `"${name}" is on CONFIRMED_NO_LIBRARY_EQUIVALENT but now has a library_id (or no longer ` +
        `appears in any template) -- remove it from the allowlist`,
    );
  }
});

Deno.test("every exercise is performable with the declared equipment", () => {
  // Catches the class of bug where a barbell-only template prescribed
  // pull-ups and a dumbbell carry. Keyword-based and deliberately narrow --
  // it only knows about equipment nouns that appear in exercise names.
  // Every equipment noun that can appear in an exercise name needs an entry
  // here, or the check silently passes over it. The map originally had no
  // "treadmill" key, so the shared moderate warm-up prescribed an incline
  // treadmill walk inside zero-equipment templates and this test stayed
  // green -- a test that could not fail on the case it was written for.
  const IMPLIED: Record<string, string> = {
    dumbbell: "dumbbells",
    barbell: "barbell",
    kettlebell: "kettlebells",
    "pull-up": "pull-up bar",
    "cable ": "cable machine",
    rowing: "rowing machine",
    treadmill: "treadmill",
    elliptical: "elliptical",
    cycling: "stationary bike",
    "smith machine": "smith machine",
    "leg press": "leg press",
    "lat pulldown": "lat pulldown",
    "medicine ball": "medicine ball",
    "jump rope": "jump rope",
    "plyo box": "plyo box",
    "battle rope": "battle ropes",
    "foam roll": "foam roller",
    band: "resistance bands",
  };

  for (const template of GYM_WORKOUT_TEMPLATES) {
    const available = new Set(template.requiredEquipment);
    const names = [
      ...template.warm_up,
      ...template.blocks.flatMap((b) => b.exercises),
      ...template.cool_down,
    ].map((e) => e.name.toLowerCase());

    for (const name of names) {
      for (const [keyword, needed] of Object.entries(IMPLIED)) {
        if (!name.includes(keyword)) continue;
        // "assisted pull-up ... or your feet on the floor" is a documented
        // scaling option, and the bar itself is required by that template.
        assert(
          available.has(needed),
          `template "${template.id}" prescribes "${name}" but does not require "${needed}"`,
        );
      }
    }
  }
});
