// Run: deno test supabase/functions/
//
// selectTemplate is the deterministic half of the gym-photo feature -- if it
// picks wrong, the photo step is decorative. Two of these are regressions for
// bugs that made it exactly that.
//
// The "exact reported failure" regression below (2026-08-19) was verified
// to actually fail against the pre-fix code, not just written as new-code
// coverage with nothing to prove it: pre-fix `templates.ts` swapped in via
// `git show HEAD:...` (HEAD had zero lower_body/core templates and
// selectTemplate's old 5-arg signature), then this test file run against
// it. Type-checked, it fails to even compile: `TS2554 Expected 3-5
// arguments, but got 6` -- the pre-fix API had no way to express a target
// body part at all. Re-run with `--no-check` to see the actual runtime
// bug it was written to catch: `AssertionError: ... moderate/lower_body:
// picked "moderate_barbell_full_body" (bodyPart="full_body") instead of a
// "lower_body" template` -- the literal reported failure, reproduced.
// Pre-fix files were then restored from a backup copy (not committed at
// any point) and the full suite re-confirmed green before this test
// landed for real.

import { assert, assertEquals, assertThrows } from "jsr:@std/assert";
import { CONFIRMED_NO_LIBRARY_EQUIVALENT, GYM_WORKOUT_TEMPLATES, selectTemplate } from "./templates.ts";
import { EQUIPMENT_VOCABULARY } from "../_shared/equipment.ts";

const CATEGORIES = ["rest", "light", "moderate", "push_hard"] as const;
const FULL_GYM = new Set(["barbell", "squat rack", "dumbbells"]);
// A genuinely fully-equipped gym -- every equipment tag any template in the
// catalog actually requires, not just the three FULL_GYM happens to cover.
// Used by the reported-failure regression below so "fully equipped" means
// what a real user photographing a real gym would confirm, not a minimal
// set that happens to make the test pass.
const FULLY_EQUIPPED_GYM = new Set([
  "barbell", "squat rack", "dumbbells", "cable machine", "kettlebells",
  "pull-up bar", "resistance bands", "weight bench", "treadmill",
]);

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

Deno.test("REGRESSION: a fully equipped gym does not override today's resolved lower-body/core target with a full-body/barbell template", () => {
  // BUG report: selectTemplate ranked by equipment specificity ONLY, so a
  // well-equipped gym photo always won regardless of what body part today's
  // category actually called for -- a leg day got silently overridden to a
  // full-body/barbell session just because the photo showed a squat rack.
  const lowerBody = selectTemplate("moderate", FULL_GYM, [], false, [], "lower_body");
  assertEquals(lowerBody.bodyPart, "lower_body");
  assert(lowerBody.id !== "moderate_barbell_full_body");

  // The clearest proof body-part match outranks equipment specificity, not
  // just picks among equally-equipped options: moderate_core needs NO
  // equipment at all, yet must still beat a 2-item-equipment full-body/
  // barbell template when the resolved target is "core".
  const core = selectTemplate("moderate", FULL_GYM, [], false, [], "core");
  assertEquals(core.id, "moderate_core");
  assertEquals(core.requiredEquipment.length, 0);
});

Deno.test("a resolved target body part outranks equipment specificity even when the match uses LESS equipment", () => {
  // moderate_calisthenics_pull (1 required item: pull-up bar) must still
  // beat moderate_barbell_full_body (2 required items: barbell, squat
  // rack) when the target is "upper_body" -- despite using less equipment.
  const equipment = new Set([...FULL_GYM, "pull-up bar"]);
  const template = selectTemplate("moderate", equipment, [], false, [], "upper_body");
  assertEquals(template.id, "moderate_calisthenics_pull");
});

Deno.test("a target with no matching template in this category falls through to the old equipment-first ranking", () => {
  // push_hard has no "upper_body" template in any equipment configuration
  // -- selectTemplate must not throw or silently ignore the user's
  // equipment when the resolved target matches nothing available.
  const template = selectTemplate("push_hard", FULL_GYM, [], false, [], "upper_body");
  assert(template.requiredEquipment.length > 0, `picked "${template.id}", which ignores the user's equipment`);
});

Deno.test("omitting targetBodyPart keeps the old equipment-first ranking (backward compatible)", () => {
  const template = selectTemplate("moderate", FULL_GYM, ["build_strength"]);
  assertEquals(template.id, "moderate_barbell_full_body");
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

Deno.test("INVARIANT: lower_body (moderate, push_hard) and core (light, moderate, push_hard) each have a bodyweight-only AND an equipped variant", () => {
  // The (category x equipment tier) coverage matrix this addition exists to
  // fill -- a resolved lower_body/core target with no equipment confirmed
  // (or a fully-equipped gym) must have something real to select in every
  // one of these categories, not just "at least one template exists".
  const required: { category: string; bodyPart: string }[] = [
    { category: "moderate", bodyPart: "lower_body" },
    { category: "push_hard", bodyPart: "lower_body" },
    { category: "light", bodyPart: "core" },
    { category: "moderate", bodyPart: "core" },
    { category: "push_hard", bodyPart: "core" },
  ];
  for (const { category, bodyPart } of required) {
    const matches = GYM_WORKOUT_TEMPLATES.filter((t) => t.category === category && t.bodyPart === bodyPart);
    const bodyweightOnly = matches.filter((t) => t.requiredEquipment.length === 0);
    const equipped = matches.filter((t) => t.requiredEquipment.length > 0);
    assert(bodyweightOnly.length > 0, `${category}/${bodyPart}: no bodyweight-only (requiredEquipment: []) template`);
    assert(equipped.length > 0, `${category}/${bodyPart}: no equipped variant`);
  }
});

Deno.test("REGRESSION: a resolved lower_body target is reachable with zero confirmed equipment in every required category", () => {
  for (const category of ["moderate", "push_hard"] as const) {
    const template = selectTemplate(category, new Set(), [], false, [], "lower_body");
    assertEquals(template.bodyPart, "lower_body");
    assertEquals(template.requiredEquipment.length, 0);
  }
});

Deno.test("REGRESSION: a resolved core target is reachable with zero confirmed equipment in every required category", () => {
  for (const category of ["light", "moderate", "push_hard"] as const) {
    const template = selectTemplate(category, new Set(), [], false, [], "core");
    assertEquals(template.bodyPart, "core");
    assertEquals(template.requiredEquipment.length, 0);
  }
});

Deno.test("a resolved core target with a cable machine confirmed prefers the cable variant over the bodyweight one", () => {
  for (const category of ["light", "moderate", "push_hard"] as const) {
    const template = selectTemplate(category, new Set(["cable machine"]), [], false, [], "core");
    assertEquals(template.bodyPart, "core");
    assert(template.requiredEquipment.includes("cable machine"), `${category}: picked "${template.id}", which ignores the confirmed cable machine`);
  }
});

Deno.test("SANITY CHECK: no core-tagged template prescribes a loaded-spinal-flexion or loaded-twisting movement", () => {
  // Per CONTRAINDICATIONS.back (_shared/contraindications.ts) neither
  // "crunch"/"sit-up" nor a literal "twist" substring is in that entry's
  // excludedKeywords -- so a crunch/sit-up/twist exercise in a "core"
  // template would NOT be filtered out for a user with a noted back
  // injury. This is the deterministic guard against ever adding one
  // instead of a by-hand review catching it later.
  const FLEXION_OR_TWIST_KEYWORDS = ["crunch", "sit-up", "situp", "sit up", "twist", "russian twist", "good morning"];
  const coreTemplates = GYM_WORKOUT_TEMPLATES.filter((t) => t.bodyPart === "core");
  assert(coreTemplates.length > 0, "expected at least one core-tagged template to check");
  for (const template of coreTemplates) {
    const exercises = [...template.warm_up, ...template.blocks.flatMap((b) => b.exercises), ...template.cool_down];
    for (const exercise of exercises) {
      const haystack = `${exercise.name} ${exercise.target_area}`.toLowerCase();
      for (const keyword of FLEXION_OR_TWIST_KEYWORDS) {
        assert(
          !haystack.includes(keyword),
          `template "${template.id}" prescribes "${exercise.name}", which reads as loaded spinal flexion/twisting -- CONTRAINDICATIONS.back would not catch this`,
        );
      }
    }
  }
});

// ==== Coverage added for the "verify test coverage" follow-up (2026-08-19) ====

Deno.test("REGRESSION (the exact reported failure): a fully-equipped gym on a leg day or ab day returns a template whose bodyPart matches the resolved target, not the highest-equipment-specificity full_body template", () => {
  // This is the literal bug report: a well-equipped gym photo always won
  // regardless of what body part today's category actually called for.
  // Verified to fail against the pre-fix code -- see the paragraph below
  // this test file's header comment for how, since the pre-fix
  // selectTemplate signature has no bodyPart parameter at all (a TS2554
  // compile error, not just a wrong runtime answer) and the pre-fix
  // template catalog had zero lower_body/core templates to return even if
  // it did.
  for (const category of ["moderate", "push_hard"] as const) {
    for (const target of ["lower_body", "core"] as const) {
      const template = selectTemplate(category, FULLY_EQUIPPED_GYM, [], false, [], target);
      assertEquals(
        template.bodyPart,
        target,
        `${category}/${target}: picked "${template.id}" (bodyPart="${template.bodyPart}") instead of a "${target}" template`,
      );
      assert(
        !template.id.includes("full_body") && !template.id.includes("barbell_strength"),
        `${category}/${target}: picked "${template.id}", which reads as the old equipment-maxing full-body/barbell pick`,
      );
    }
  }
});

Deno.test("a target with genuinely no matching template in the category falls through gracefully, not silently to a fabricated full_body match", () => {
  // light has no lower_body-tagged template in any equipment configuration
  // (confirmed live against the current catalog, not assumed) -- the
  // fallback must not throw, must not ignore the user's equipment, and
  // must not silently claim to have matched a target it didn't.
  const lightLowerBody = selectTemplate("light", FULLY_EQUIPPED_GYM, [], false, [], "lower_body");
  assert(
    lightLowerBody.requiredEquipment.length > 0,
    `picked "${lightLowerBody.id}", which ignores the user's equipment`,
  );
  assert(
    lightLowerBody.bodyPart !== "lower_body",
    `light now has a "lower_body" template ("${lightLowerBody.id}") -- update this test's premise`,
  );

  // rest has NO lower_body and NO core template at all -- every rest
  // template is tagged "recovery". The fallback must land on rest's own
  // real content, not a defaulted/fabricated "full_body" -- proving the
  // fallback isn't secretly "always full_body" but genuinely just the old
  // equipment/goals ranking over whatever the category actually has.
  for (const target of ["lower_body", "core"] as const) {
    const rest = selectTemplate("rest", new Set(), [], false, [], target);
    assertEquals(rest.bodyPart, "recovery");
    assert(rest.bodyPart !== "full_body", "fell back to full_body rather than rest's own recovery content");
  }
});

Deno.test("bodyPart-priority ranking is driven by the target alone, independent of equipment", () => {
  // Equipment is held constant at zero the entire time -- every candidate
  // ties 0-vs-0 on equipment specificity, so if a different template comes
  // back for each target, the ranking's first key (bodyPart match) is what
  // moved, not equipment.
  const noEquipment = new Set<string>();
  const targets = ["full_body", "lower_body", "core"] as const;
  for (const category of ["moderate", "push_hard"] as const) {
    for (const target of targets) {
      const template = selectTemplate(category, noEquipment, [], false, [], target);
      assertEquals(template.bodyPart, target, `${category}/${target}: got "${template.id}" (bodyPart="${template.bodyPart}")`);
      assertEquals(
        template.requiredEquipment.length,
        0,
        `${category}/${target}: picked "${template.id}", which requires equipment despite none being confirmed`,
      );
    }
  }
});
