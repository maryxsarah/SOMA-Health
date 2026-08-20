// The 78-item "what's actually in your gym" catalog -- a much more
// granular signal than EquipmentTag's coarse access-type presets (gym,
// home_gym, ...), collected via the client's GymEquipmentPicker and
// stored on users.gym_equipment_items / users.custom_gym_equipment.
//
// Mirrors Soma/Models/GymEquipmentTag.swift's raw values exactly -- same
// duplication precedent EquipmentTag/KitchenEquipmentTag already accept
// (no codegen shares this list structurally between Swift and Deno).
// Changing an id here without changing it there breaks that mirror
// silently -- grep GymEquipmentTag.swift before renaming one.

import { resolveFreeTextEquipment, type FreeTextEquipmentResolution } from "./equipment.ts";

export interface GymEquipmentCatalogEntry {
  id: string;
  label: string;
}

export const GYM_EQUIPMENT_CATALOG: GymEquipmentCatalogEntry[] = [
  { id: "ab_mats", label: "Ab Mats" },
  { id: "adjustable_benches", label: "Adjustable Benches" },
  { id: "adjustable_dumbbells", label: "Adjustable Dumbbells" },
  { id: "air_bikes_fan_bikes", label: "Air Bikes / Fan Bikes" },
  { id: "ankle_straps_cable_machines", label: "Ankle Straps for Cable Machines" },
  { id: "arm_blasters", label: "Arm Blasters" },
  { id: "abdominal_crunch_machines", label: "Abdominal Crunch Machines" },
  { id: "back_extension_benches", label: "Back Extension Benches / Hyperextension Benches" },
  { id: "barbells", label: "Barbells (Standard, Olympic)" },
  { id: "battle_ropes", label: "Battle Ropes" },
  { id: "bumper_plates", label: "Bumper Plates" },
  { id: "cable_attachments", label: "Cable Attachments (V-Bars, Tricep Ropes, Straight Bars, Stirrup Handles)" },
  { id: "cable_cross_functional_trainers", label: "Cable Cross / Functional Trainers" },
  { id: "cast_iron_weight_plates", label: "Cast Iron Weight Plates" },
  { id: "chest_fly_pec_deck_machines", label: "Chest Fly / Pec Deck Machines" },
  { id: "chest_press_machines", label: "Chest Press Machines" },
  { id: "curved_manual_treadmills", label: "Curved Manual Treadmills" },
  { id: "dip_bars_dip_stations", label: "Dip Bars / Dip Stations" },
  { id: "dumbbells", label: "Dumbbells" },
  { id: "ellipticals", label: "Ellipticals" },
  { id: "ez_curl_bars", label: "EZ Curl Bars" },
  { id: "fabric_hip_bands", label: "Fabric Hip Bands" },
  { id: "flat_benches", label: "Flat Benches" },
  { id: "foam_rollers", label: "Foam Rollers" },
  { id: "fractional_micro_weight_plates", label: "Fractional / Micro Weight Plates" },
  { id: "gymnastic_rings", label: "Gymnastic Rings" },
  { id: "hack_squat_machines", label: "Hack Squat Machines" },
  { id: "half_racks", label: "Half Racks" },
  { id: "hip_thrust_machines", label: "Hip Thrust Machines" },
  { id: "incline_benches", label: "Incline Benches" },
  { id: "incline_trainers", label: "Incline Trainers" },
  { id: "iron_weight_plates", label: "Iron Weight Plates" },
  { id: "jacobs_ladder", label: "Jacob's Ladder" },
  { id: "jump_ropes_speed_ropes", label: "Jump Ropes / Speed Ropes" },
  { id: "kettlebells", label: "Kettlebells" },
  { id: "knee_sleeves", label: "Knee Sleeves" },
  { id: "lacrosse_balls_massage_balls", label: "Lacrosse Balls / Massage Balls" },
  { id: "lat_pulldown_machines", label: "Lat Pulldown Machines" },
  { id: "lateral_raise_machines", label: "Lateral Raise Machines" },
  { id: "leg_curl_machines", label: "Leg Curl Machines (Seated, Lying)" },
  { id: "leg_extension_machines", label: "Leg Extension Machines" },
  { id: "leg_press_machines", label: "Leg Press Machines" },
  { id: "lifting_straps", label: "Lifting Straps" },
  { id: "liquid_chalk_chalk_blocks", label: "Liquid Chalk / Chalk Blocks" },
  { id: "long_loop_resistance_bands", label: "Long Loop Resistance Bands" },
  { id: "medicine_balls", label: "Medicine Balls" },
  { id: "mini_loop_resistance_bands", label: "Mini Loop Resistance Bands" },
  { id: "olympic_bench_press_racks", label: "Olympic Bench Press Racks" },
  { id: "parallettes", label: "Parallettes" },
  { id: "plyo_boxes", label: "Plyo Boxes" },
  { id: "power_cages_power_racks", label: "Power Cages / Power Racks" },
  { id: "preacher_curl_benches", label: "Preacher Curl Benches" },
  { id: "recumbent_bikes", label: "Recumbent Bikes" },
  { id: "resistance_tubes_with_handles", label: "Resistance Tubes with Handles" },
  { id: "rotary_torso_machines", label: "Rotary Torso Machines" },
  { id: "rowing_machines", label: "Rowing Machines" },
  { id: "safety_squat_bars", label: "Safety Squat Bars" },
  { id: "sandbags", label: "Sandbags" },
  { id: "seated_cable_row_machines", label: "Seated Cable Row Machines" },
  { id: "shoulder_press_machines", label: "Shoulder Press Machines" },
  { id: "slam_balls", label: "Slam Balls" },
  { id: "sleds_prowlers", label: "Sleds / Prowlers" },
  { id: "smith_machines", label: "Smith Machines" },
  { id: "spin_bikes", label: "Spin Bikes" },
  { id: "squat_stands", label: "Squat Stands" },
  { id: "stair_climbers_stepmills", label: "Stair Climbers / Stepmills" },
  { id: "standing_calf_raise_machines", label: "Standing Calf Raise Machines" },
  { id: "suspension_trainers_trx", label: "Suspension Trainers / TRX" },
  { id: "swiss_bars_multi_grip_bars", label: "Swiss Bars / Multi-Grip Bars" },
  { id: "treadmills", label: "Treadmills" },
  { id: "trap_bars_hex_bars", label: "Trap Bars / Hex Bars" },
  { id: "upright_exercise_bikes", label: "Upright Exercise Bikes" },
  { id: "vertical_leg_press_machines", label: "Vertical Leg Press Machines" },
  { id: "wall_balls", label: "Wall Balls" },
  { id: "weightlifting_belts", label: "Weightlifting Belts" },
  { id: "weighted_vests", label: "Weighted Vests" },
  { id: "wrist_wraps", label: "Wrist Wraps" },
  { id: "yoga_mats", label: "Yoga Mats" },
];

/// Maps each catalog id onto zero or more of the same closed
/// `exercise_library.equipment` values `exerciseLibraryMatch.ts`'s
/// `EQUIPMENT_TAG_TO_LIBRARY_EQUIPMENT` already targets (barbell,
/// dumbbell, cable, machine, kettlebells, medicine ball, e-z curl bar,
/// exercise ball, bands, body only). Ids absent from this map (ab mats,
/// arm blasters, battle ropes, flat/incline/preacher-curl benches, knee
/// sleeves, lifting straps, chalk, sandbags, sleds/prowlers,
/// weightlifting belts, wrist wraps, ...) are pure accessories or props
/// with no filtering equivalent -- still valid, accepted input, they
/// just don't narrow anything, same precedent `equipment.ts`'s own
/// "a weight bench is a supporting prop ... simply omitted" comment sets.
const GYM_EQUIPMENT_TO_LIBRARY_EQUIPMENT: Record<string, string[]> = {
  adjustable_dumbbells: ["dumbbell"],
  air_bikes_fan_bikes: ["machine"],
  ankle_straps_cable_machines: ["cable"],
  abdominal_crunch_machines: ["machine"],
  back_extension_benches: ["machine"],
  barbells: ["barbell"],
  bumper_plates: ["barbell"],
  cable_attachments: ["cable"],
  cable_cross_functional_trainers: ["cable"],
  cast_iron_weight_plates: ["barbell"],
  chest_fly_pec_deck_machines: ["machine"],
  chest_press_machines: ["machine"],
  curved_manual_treadmills: ["machine"],
  dip_bars_dip_stations: ["body only"],
  dumbbells: ["dumbbell"],
  ellipticals: ["machine"],
  ez_curl_bars: ["e-z curl bar"],
  fabric_hip_bands: ["bands"],
  foam_rollers: ["body only"],
  fractional_micro_weight_plates: ["barbell"],
  gymnastic_rings: ["body only"],
  hack_squat_machines: ["machine"],
  half_racks: ["barbell"],
  hip_thrust_machines: ["machine"],
  incline_trainers: ["machine"],
  iron_weight_plates: ["barbell"],
  jacobs_ladder: ["machine"],
  jump_ropes_speed_ropes: ["body only"],
  kettlebells: ["kettlebells"],
  lacrosse_balls_massage_balls: ["body only"],
  lat_pulldown_machines: ["cable"],
  lateral_raise_machines: ["machine"],
  leg_curl_machines: ["machine"],
  leg_extension_machines: ["machine"],
  leg_press_machines: ["machine"],
  long_loop_resistance_bands: ["bands"],
  medicine_balls: ["medicine ball"],
  mini_loop_resistance_bands: ["bands"],
  olympic_bench_press_racks: ["barbell"],
  parallettes: ["body only"],
  plyo_boxes: ["body only"],
  power_cages_power_racks: ["barbell"],
  recumbent_bikes: ["machine"],
  resistance_tubes_with_handles: ["bands"],
  rotary_torso_machines: ["machine"],
  rowing_machines: ["machine"],
  safety_squat_bars: ["barbell"],
  seated_cable_row_machines: ["cable"],
  shoulder_press_machines: ["machine"],
  slam_balls: ["medicine ball"],
  smith_machines: ["machine"],
  spin_bikes: ["machine"],
  squat_stands: ["barbell"],
  stair_climbers_stepmills: ["machine"],
  standing_calf_raise_machines: ["machine"],
  suspension_trainers_trx: ["body only"],
  swiss_bars_multi_grip_bars: ["barbell"],
  treadmills: ["machine"],
  trap_bars_hex_bars: ["barbell"],
  upright_exercise_bikes: ["machine"],
  vertical_leg_press_machines: ["machine"],
  wall_balls: ["medicine ball"],
  weighted_vests: ["body only"],
  yoga_mats: ["body only"],
};

/// True for equipment that unlocks genuine cardio-category work -- same
/// role as `equipment.ts`'s `CARDIO_UNLOCKING_ITEMS`.
const GYM_EQUIPMENT_CARDIO_IDS: ReadonlySet<string> = new Set([
  "air_bikes_fan_bikes",
  "curved_manual_treadmills",
  "ellipticals",
  "incline_trainers",
  "jacobs_ladder",
  "jump_ropes_speed_ropes",
  "recumbent_bikes",
  "rowing_machines",
  "spin_bikes",
  "stair_climbers_stepmills",
  "treadmills",
  "upright_exercise_bikes",
]);

export interface GymEquipmentResolution extends FreeTextEquipmentResolution {
  /// Human-readable labels (catalog + custom), for the prompt text --
  /// e.g. "Specific gym equipment available: Dumbbells, Treadmills, ..."
  displayLine: string;
}

/// The entry point generate-workout-plan calls: resolves the structured
/// catalog selections + free-typed "Other" entries into the same
/// FreeTextEquipmentResolution shape resolveFreeTextEquipment already
/// produces, plus a human-readable display line for the prompt.
///
/// Unknown ids are dropped, not trusted -- same rule normalizeEquipment
/// in equipment.ts already follows, and the only way an id here could be
/// unrecognized is a client/server catalog drifting out of sync.
export function resolveGymEquipmentItems(ids: string[], customNames: string[]): GymEquipmentResolution {
  const labelById = new Map(GYM_EQUIPMENT_CATALOG.map((entry) => [entry.id, entry.label]));
  const libraryEquipment = new Set<string>();
  const cardioLibraryEquipment = new Set<string>();
  let unlocksCardio = false;
  const labels: string[] = [];

  for (const id of ids) {
    const label = labelById.get(id);
    if (!label) continue;
    labels.push(label);
    const isCardio = GYM_EQUIPMENT_CARDIO_IDS.has(id);
    for (const value of GYM_EQUIPMENT_TO_LIBRARY_EQUIPMENT[id] ?? []) {
      (isCardio ? cardioLibraryEquipment : libraryEquipment).add(value);
    }
    if (isCardio) unlocksCardio = true;
  }

  // Free-typed "Other" entries -- always shown in the prompt verbatim,
  // and best-effort matched into the existing 26-word vocabulary via the
  // same parser real free-text equipment notes already use (reused
  // rather than duplicated).
  const customTrimmed = customNames.map((name) => name.trim()).filter((name) => name.length > 0);
  labels.push(...customTrimmed);
  if (customTrimmed.length > 0) {
    const customResolution = resolveFreeTextEquipment(customTrimmed.join(", "));
    for (const value of customResolution.libraryEquipment) libraryEquipment.add(value);
    for (const value of customResolution.cardioLibraryEquipment) cardioLibraryEquipment.add(value);
    unlocksCardio = unlocksCardio || customResolution.unlocksCardio;
  }

  return {
    libraryEquipment: Array.from(libraryEquipment),
    cardioLibraryEquipment: Array.from(cardioLibraryEquipment),
    unlocksCardio,
    displayLine: labels.join(", "),
  };
}

