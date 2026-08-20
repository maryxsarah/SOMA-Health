// Run: deno test supabase/functions/
//
// Covers catalog integrity (this list is hand-mirrored on the Swift side
// in GymEquipmentTag.swift -- a typo'd or duplicated id here silently
// breaks that mirror), a sample of the id -> library-equipment mapping,
// and resolveGymEquipmentItems's merge of canonical ids with free-typed
// "Other" entries.

import { assert, assertEquals, assertFalse } from "jsr:@std/assert";
import { GYM_EQUIPMENT_CATALOG, resolveGymEquipmentItems } from "./gymEquipmentCatalog.ts";

Deno.test("catalog has exactly 78 unique ids, each with a non-empty label", () => {
  assertEquals(GYM_EQUIPMENT_CATALOG.length, 78);
  const ids = new Set(GYM_EQUIPMENT_CATALOG.map((entry) => entry.id));
  assertEquals(ids.size, 78, "no duplicate ids");
  for (const entry of GYM_EQUIPMENT_CATALOG) {
    assert(entry.label.trim().length > 0, `${entry.id} must have a non-empty label`);
  }
});

Deno.test("representative id -> library-equipment mappings", () => {
  assertEquals(resolveGymEquipmentItems(["adjustable_dumbbells"], []).libraryEquipment, ["dumbbell"]);
  assertEquals(resolveGymEquipmentItems(["kettlebells"], []).libraryEquipment, ["kettlebells"]);
  assertEquals(resolveGymEquipmentItems(["ez_curl_bars"], []).libraryEquipment, ["e-z curl bar"]);
});

Deno.test("cardio machines unlock cardio and land in the cardio-only bucket, not the general one", () => {
  const resolution = resolveGymEquipmentItems(["treadmills"], []);
  assert(resolution.unlocksCardio);
  assertEquals(resolution.cardioLibraryEquipment, ["machine"]);
  assertEquals(resolution.libraryEquipment, []);
});

Deno.test("pure accessories are accepted but narrow nothing", () => {
  const resolution = resolveGymEquipmentItems(["ab_mats"], []);
  assertFalse(resolution.unlocksCardio);
  assertEquals(resolution.libraryEquipment, []);
  assertEquals(resolution.cardioLibraryEquipment, []);
  assertEquals(resolution.displayLine, "Ab Mats");
});

Deno.test("unknown/garbage ids are dropped, not trusted -- same rule normalizeEquipment follows", () => {
  const resolution = resolveGymEquipmentItems(["ab_mats", "made_up_id"], []);
  assertEquals(resolution.displayLine, "Ab Mats");
});

Deno.test("free-typed custom names are always shown verbatim in the display line", () => {
  const resolution = resolveGymEquipmentItems([], ["Vibration plate", "  Reverse hyper  "]);
  assertEquals(resolution.displayLine, "Vibration plate, Reverse hyper");
});

Deno.test("custom names are also best-effort matched into the existing library vocabulary", () => {
  // Reuses the same parser real other_equipment_notes free text already
  // goes through -- "a treadmill" should still unlock cardio even when
  // typed as a custom gym-equipment item rather than picked from the
  // fixed catalog.
  const resolution = resolveGymEquipmentItems([], ["a treadmill and some dumbbells"]);
  assert(resolution.unlocksCardio);
  assertEquals(resolution.cardioLibraryEquipment, ["machine"]);
  assertEquals(resolution.libraryEquipment, ["dumbbell"]);
});

Deno.test("canonical selections and custom names union into one resolution", () => {
  const resolution = resolveGymEquipmentItems(["barbells"], ["a rowing machine"]);
  assert(resolution.libraryEquipment.includes("barbell"));
  assert(resolution.unlocksCardio);
  assertEquals(resolution.displayLine, "Barbells (Standard, Olympic), a rowing machine");
});
