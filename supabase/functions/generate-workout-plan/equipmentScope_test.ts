import { assertEquals } from "jsr:@std/assert";
import type { FreeTextEquipmentResolution } from "../_shared/equipment.ts";
import { FULL_PROFILE_EQUIPMENT_TAGS, NARROW_EQUIPMENT_DESCRIPTION, resolveEquipmentScope } from "./equipmentScope.ts";

const noFreeText: FreeTextEquipmentResolution = { libraryEquipment: [], cardioLibraryEquipment: [], unlocksCardio: false };

// Every EquipmentTag raw value (Soma/Models/DailyRecommendation.swift) --
// hardcoded here, same "kept in sync manually" drift risk this codebase
// already accepts between the Swift enum and _shared/gymEquipmentCatalog.ts's
// own mirrored list (see that file's own header comment).
const ALL_EQUIPMENT_TAGS = [
  "gym",
  "home_gym",
  "yoga_studio",
  "resistance_bands",
  "bike",
  "pool",
  "boxing_gym",
  "mat_pilates",
  "calisthenics_gymnastics",
  "crossfit",
  "hiit_circuit_studio",
  "bodyweight_only",
  "other",
];

Deno.test("every EquipmentTag that isn't full-profile has a NARROW_EQUIPMENT_DESCRIPTION entry", () => {
  for (const tag of ALL_EQUIPMENT_TAGS) {
    if (FULL_PROFILE_EQUIPMENT_TAGS.has(tag)) continue;
    assertEquals(
      typeof NARROW_EQUIPMENT_DESCRIPTION[tag],
      "string",
      `EquipmentTag "${tag}" is missing a NARROW_EQUIPMENT_DESCRIPTION entry`,
    );
  }
});

Deno.test("REGRESSION: a resistance-bands suggestion never leaks the user's gym/home-gym equipment", () => {
  // The exact reported scenario -- a user with a full home-gym profile
  // (kettlebells, bench, etc. via .gym/.home_gym) picks a resistance-band
  // suggestion. Before this fix, fetchCandidateExerciseNames received the
  // user's WHOLE profile regardless of which suggestion was picked.
  const scope = resolveEquipmentScope("resistance_bands", ["gym", "home_gym"], noFreeText, "Kettlebells, Adjustable bench");
  assertEquals(scope.equipment, ["resistance_bands"]);
  assertEquals(scope.equipment.includes("gym"), false);
  assertEquals(scope.equipment.includes("home_gym"), false);
  assertEquals(scope.extraLibraryEquipment, []);
  assertEquals(scope.unlocksCardio, false);
  assertEquals(scope.cardioLibraryEquipment, []);
});

Deno.test(".gym suggestions still pull from the user's full real equipment profile, unchanged", () => {
  const freeText: FreeTextEquipmentResolution = { libraryEquipment: ["rower"], cardioLibraryEquipment: ["treadmill"], unlocksCardio: true };
  const scope = resolveEquipmentScope("gym", ["gym", "home_gym"], freeText, "Kettlebells, Adjustable bench");
  assertEquals(scope.equipment, ["gym", "home_gym"]);
  assertEquals(scope.extraLibraryEquipment, ["rower"]);
  assertEquals(scope.unlocksCardio, true);
  assertEquals(scope.cardioLibraryEquipment, ["treadmill"]);
  assertEquals(scope.promptDescription, "gym, home_gym Specific gym equipment available: Kettlebells, Adjustable bench.");
});

Deno.test(".home_gym also stays full-profile, same as .gym", () => {
  const scope = resolveEquipmentScope("home_gym", ["home_gym"], noFreeText, "");
  assertEquals(scope.equipment, ["home_gym"]);
  assertEquals(scope.extraLibraryEquipment, noFreeText.libraryEquipment);
});

Deno.test("a missing/null suggestion tag falls back to full-profile behavior, not a hard failure", () => {
  const scope = resolveEquipmentScope(null, ["gym"], noFreeText, "");
  assertEquals(scope.equipment, ["gym"]);
});

Deno.test("an unrecognized/future suggestion tag falls back to full-profile behavior, not a silent narrow guess", () => {
  const scope = resolveEquipmentScope("some_new_category_nobody_classified_yet", ["gym"], noFreeText, "");
  assertEquals(scope.equipment, ["gym"]);
});

Deno.test("bike and pool are narrow-scoped -- a confirmed behavior change, not an oversight", () => {
  const bikeScope = resolveEquipmentScope("bike", ["gym", "home_gym"], noFreeText, "Rowing machine");
  assertEquals(bikeScope.equipment, ["bike"]);
  assertEquals(bikeScope.extraLibraryEquipment, []);
  assertEquals(bikeScope.promptDescription.includes("cardio-only cycling"), true);

  const poolScope = resolveEquipmentScope("pool", ["gym", "home_gym"], noFreeText, "Rowing machine");
  assertEquals(poolScope.equipment, ["pool"]);
  assertEquals(poolScope.promptDescription.includes("cardio-only swimming"), true);
});

Deno.test("yoga/bodyweight/other narrow categories each resolve to exactly their own tag, nothing else", () => {
  for (const tag of ["yoga_studio", "resistance_bands", "boxing_gym", "mat_pilates", "calisthenics_gymnastics", "crossfit", "hiit_circuit_studio", "bodyweight_only", "other"]) {
    const scope = resolveEquipmentScope(tag, ["gym", "home_gym"], noFreeText, "Kettlebells");
    assertEquals(scope.equipment, [tag], `tag=${tag}`);
    assertEquals(scope.extraLibraryEquipment, [], `tag=${tag}`);
  }
});

Deno.test("full-profile with no stored equipment at all falls back to the bodyweight-only prompt line", () => {
  const scope = resolveEquipmentScope("gym", [], noFreeText, "");
  assertEquals(scope.promptDescription, "no equipment (bodyweight only)");
});
