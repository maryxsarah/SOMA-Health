import Foundation

/// The specific gear the user's gym actually has -- a much more granular
/// hard input to generate-workout-plan than `EquipmentTag` (`equipment`
/// column), which only captures an *access type* (Gym, Home Gym, Yoga
/// Studio, ...). Collected once at onboarding (GymEquipmentQuestionView,
/// always skippable) and editable afterward from ProfileView via
/// GymEquipmentPicker, same "collect once, edit forever" shape
/// `KitchenEquipmentTag` already uses -- kept as its own field rather than
/// folded into `EquipmentTag` since the two answer unrelated questions
/// (what kind of access do you have vs. what's actually in the gym).
///
/// No `.other` case, unlike `EquipmentTag`/`KitchenEquipmentTag` -- "Other"
/// here is a repeatable free-text add flow (see GymEquipmentPicker) whose
/// confirmed entries become first-class items in
/// `UserProfile.customGymEquipment`, not a single notes blob, so a user
/// can list several gym-specific things not on this fixed list.
///
/// Mirrored server-side by `_shared/gymEquipmentCatalog.ts`'s
/// `GYM_EQUIPMENT_CATALOG` (same raw values) -- there's no codegen sharing
/// this list structurally, same duplication precedent `EquipmentTag`/
/// `KitchenEquipmentTag` already accept.
enum GymEquipmentTag: String, Codable, CaseIterable, Identifiable {
    case abMats = "ab_mats"
    case adjustableBenches = "adjustable_benches"
    case adjustableDumbbells = "adjustable_dumbbells"
    case airBikesFanBikes = "air_bikes_fan_bikes"
    case ankleStrapsCableMachines = "ankle_straps_cable_machines"
    case armBlasters = "arm_blasters"
    case abdominalCrunchMachines = "abdominal_crunch_machines"
    case backExtensionBenches = "back_extension_benches"
    case barbells = "barbells"
    case battleRopes = "battle_ropes"
    case bumperPlates = "bumper_plates"
    case cableAttachments = "cable_attachments"
    case cableCrossFunctionalTrainers = "cable_cross_functional_trainers"
    case castIronWeightPlates = "cast_iron_weight_plates"
    case chestFlyPecDeckMachines = "chest_fly_pec_deck_machines"
    case chestPressMachines = "chest_press_machines"
    case curvedManualTreadmills = "curved_manual_treadmills"
    case dipBarsDipStations = "dip_bars_dip_stations"
    case dumbbells = "dumbbells"
    case ellipticals = "ellipticals"
    case ezCurlBars = "ez_curl_bars"
    case fabricHipBands = "fabric_hip_bands"
    case flatBenches = "flat_benches"
    case foamRollers = "foam_rollers"
    case fractionalMicroWeightPlates = "fractional_micro_weight_plates"
    case gymnasticRings = "gymnastic_rings"
    case hackSquatMachines = "hack_squat_machines"
    case halfRacks = "half_racks"
    case hipThrustMachines = "hip_thrust_machines"
    case inclineBenches = "incline_benches"
    case inclineTrainers = "incline_trainers"
    case ironWeightPlates = "iron_weight_plates"
    case jacobsLadder = "jacobs_ladder"
    case jumpRopesSpeedRopes = "jump_ropes_speed_ropes"
    case kettlebells = "kettlebells"
    case kneeSleeves = "knee_sleeves"
    case lacrosseBallsMassageBalls = "lacrosse_balls_massage_balls"
    case latPulldownMachines = "lat_pulldown_machines"
    case lateralRaiseMachines = "lateral_raise_machines"
    case legCurlMachines = "leg_curl_machines"
    case legExtensionMachines = "leg_extension_machines"
    case legPressMachines = "leg_press_machines"
    case liftingStraps = "lifting_straps"
    case liquidChalkChalkBlocks = "liquid_chalk_chalk_blocks"
    case longLoopResistanceBands = "long_loop_resistance_bands"
    case medicineBalls = "medicine_balls"
    case miniLoopResistanceBands = "mini_loop_resistance_bands"
    case olympicBenchPressRacks = "olympic_bench_press_racks"
    case parallettes = "parallettes"
    case plyoBoxes = "plyo_boxes"
    case powerCagesPowerRacks = "power_cages_power_racks"
    case preacherCurlBenches = "preacher_curl_benches"
    case recumbentBikes = "recumbent_bikes"
    case resistanceTubesWithHandles = "resistance_tubes_with_handles"
    case rotaryTorsoMachines = "rotary_torso_machines"
    case rowingMachines = "rowing_machines"
    case safetySquatBars = "safety_squat_bars"
    case sandbags = "sandbags"
    case seatedCableRowMachines = "seated_cable_row_machines"
    case shoulderPressMachines = "shoulder_press_machines"
    case slamBalls = "slam_balls"
    case sledsProwlers = "sleds_prowlers"
    case smithMachines = "smith_machines"
    case spinBikes = "spin_bikes"
    case squatStands = "squat_stands"
    case stairClimbersStepmills = "stair_climbers_stepmills"
    case standingCalfRaiseMachines = "standing_calf_raise_machines"
    case suspensionTrainersTRX = "suspension_trainers_trx"
    case swissBarsMultiGripBars = "swiss_bars_multi_grip_bars"
    case treadmills = "treadmills"
    case trapBarsHexBars = "trap_bars_hex_bars"
    case uprightExerciseBikes = "upright_exercise_bikes"
    case verticalLegPressMachines = "vertical_leg_press_machines"
    case wallBalls = "wall_balls"
    case weightliftingBelts = "weightlifting_belts"
    case weightedVests = "weighted_vests"
    case wristWraps = "wrist_wraps"
    case yogaMats = "yoga_mats"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .abMats: String(localized: "gymEquipmentTag.abMats", defaultValue: "Ab Mats", comment: "Gym equipment tag label")
        case .adjustableBenches: String(localized: "gymEquipmentTag.adjustableBenches", defaultValue: "Adjustable Benches", comment: "Gym equipment tag label")
        case .adjustableDumbbells: String(localized: "gymEquipmentTag.adjustableDumbbells", defaultValue: "Adjustable Dumbbells", comment: "Gym equipment tag label")
        case .airBikesFanBikes: String(localized: "gymEquipmentTag.airBikesFanBikes", defaultValue: "Air Bikes / Fan Bikes", comment: "Gym equipment tag label")
        case .ankleStrapsCableMachines: String(localized: "gymEquipmentTag.ankleStrapsCableMachines", defaultValue: "Ankle Straps for Cable Machines", comment: "Gym equipment tag label")
        case .armBlasters: String(localized: "gymEquipmentTag.armBlasters", defaultValue: "Arm Blasters", comment: "Gym equipment tag label")
        case .abdominalCrunchMachines: String(localized: "gymEquipmentTag.abdominalCrunchMachines", defaultValue: "Abdominal Crunch Machines", comment: "Gym equipment tag label")
        case .backExtensionBenches: String(localized: "gymEquipmentTag.backExtensionBenches", defaultValue: "Back Extension Benches / Hyperextension Benches", comment: "Gym equipment tag label")
        case .barbells: String(localized: "gymEquipmentTag.barbells", defaultValue: "Barbells (Standard, Olympic)", comment: "Gym equipment tag label")
        case .battleRopes: String(localized: "gymEquipmentTag.battleRopes", defaultValue: "Battle Ropes", comment: "Gym equipment tag label")
        case .bumperPlates: String(localized: "gymEquipmentTag.bumperPlates", defaultValue: "Bumper Plates", comment: "Gym equipment tag label")
        case .cableAttachments: String(localized: "gymEquipmentTag.cableAttachments", defaultValue: "Cable Attachments (V-Bars, Tricep Ropes, Straight Bars, Stirrup Handles)", comment: "Gym equipment tag label")
        case .cableCrossFunctionalTrainers: String(localized: "gymEquipmentTag.cableCrossFunctionalTrainers", defaultValue: "Cable Cross / Functional Trainers", comment: "Gym equipment tag label")
        case .castIronWeightPlates: String(localized: "gymEquipmentTag.castIronWeightPlates", defaultValue: "Cast Iron Weight Plates", comment: "Gym equipment tag label")
        case .chestFlyPecDeckMachines: String(localized: "gymEquipmentTag.chestFlyPecDeckMachines", defaultValue: "Chest Fly / Pec Deck Machines", comment: "Gym equipment tag label")
        case .chestPressMachines: String(localized: "gymEquipmentTag.chestPressMachines", defaultValue: "Chest Press Machines", comment: "Gym equipment tag label")
        case .curvedManualTreadmills: String(localized: "gymEquipmentTag.curvedManualTreadmills", defaultValue: "Curved Manual Treadmills", comment: "Gym equipment tag label")
        case .dipBarsDipStations: String(localized: "gymEquipmentTag.dipBarsDipStations", defaultValue: "Dip Bars / Dip Stations", comment: "Gym equipment tag label")
        case .dumbbells: String(localized: "gymEquipmentTag.dumbbells", defaultValue: "Dumbbells", comment: "Gym equipment tag label")
        case .ellipticals: String(localized: "gymEquipmentTag.ellipticals", defaultValue: "Ellipticals", comment: "Gym equipment tag label")
        case .ezCurlBars: String(localized: "gymEquipmentTag.ezCurlBars", defaultValue: "EZ Curl Bars", comment: "Gym equipment tag label")
        case .fabricHipBands: String(localized: "gymEquipmentTag.fabricHipBands", defaultValue: "Fabric Hip Bands", comment: "Gym equipment tag label")
        case .flatBenches: String(localized: "gymEquipmentTag.flatBenches", defaultValue: "Flat Benches", comment: "Gym equipment tag label")
        case .foamRollers: String(localized: "gymEquipmentTag.foamRollers", defaultValue: "Foam Rollers", comment: "Gym equipment tag label")
        case .fractionalMicroWeightPlates: String(localized: "gymEquipmentTag.fractionalMicroWeightPlates", defaultValue: "Fractional / Micro Weight Plates", comment: "Gym equipment tag label")
        case .gymnasticRings: String(localized: "gymEquipmentTag.gymnasticRings", defaultValue: "Gymnastic Rings", comment: "Gym equipment tag label")
        case .hackSquatMachines: String(localized: "gymEquipmentTag.hackSquatMachines", defaultValue: "Hack Squat Machines", comment: "Gym equipment tag label")
        case .halfRacks: String(localized: "gymEquipmentTag.halfRacks", defaultValue: "Half Racks", comment: "Gym equipment tag label")
        case .hipThrustMachines: String(localized: "gymEquipmentTag.hipThrustMachines", defaultValue: "Hip Thrust Machines", comment: "Gym equipment tag label")
        case .inclineBenches: String(localized: "gymEquipmentTag.inclineBenches", defaultValue: "Incline Benches", comment: "Gym equipment tag label")
        case .inclineTrainers: String(localized: "gymEquipmentTag.inclineTrainers", defaultValue: "Incline Trainers", comment: "Gym equipment tag label")
        case .ironWeightPlates: String(localized: "gymEquipmentTag.ironWeightPlates", defaultValue: "Iron Weight Plates", comment: "Gym equipment tag label")
        case .jacobsLadder: String(localized: "gymEquipmentTag.jacobsLadder", defaultValue: "Jacob's Ladder", comment: "Gym equipment tag label")
        case .jumpRopesSpeedRopes: String(localized: "gymEquipmentTag.jumpRopesSpeedRopes", defaultValue: "Jump Ropes / Speed Ropes", comment: "Gym equipment tag label")
        case .kettlebells: String(localized: "gymEquipmentTag.kettlebells", defaultValue: "Kettlebells", comment: "Gym equipment tag label")
        case .kneeSleeves: String(localized: "gymEquipmentTag.kneeSleeves", defaultValue: "Knee Sleeves", comment: "Gym equipment tag label")
        case .lacrosseBallsMassageBalls: String(localized: "gymEquipmentTag.lacrosseBallsMassageBalls", defaultValue: "Lacrosse Balls / Massage Balls", comment: "Gym equipment tag label")
        case .latPulldownMachines: String(localized: "gymEquipmentTag.latPulldownMachines", defaultValue: "Lat Pulldown Machines", comment: "Gym equipment tag label")
        case .lateralRaiseMachines: String(localized: "gymEquipmentTag.lateralRaiseMachines", defaultValue: "Lateral Raise Machines", comment: "Gym equipment tag label")
        case .legCurlMachines: String(localized: "gymEquipmentTag.legCurlMachines", defaultValue: "Leg Curl Machines (Seated, Lying)", comment: "Gym equipment tag label")
        case .legExtensionMachines: String(localized: "gymEquipmentTag.legExtensionMachines", defaultValue: "Leg Extension Machines", comment: "Gym equipment tag label")
        case .legPressMachines: String(localized: "gymEquipmentTag.legPressMachines", defaultValue: "Leg Press Machines", comment: "Gym equipment tag label")
        case .liftingStraps: String(localized: "gymEquipmentTag.liftingStraps", defaultValue: "Lifting Straps", comment: "Gym equipment tag label")
        case .liquidChalkChalkBlocks: String(localized: "gymEquipmentTag.liquidChalkChalkBlocks", defaultValue: "Liquid Chalk / Chalk Blocks", comment: "Gym equipment tag label")
        case .longLoopResistanceBands: String(localized: "gymEquipmentTag.longLoopResistanceBands", defaultValue: "Long Loop Resistance Bands", comment: "Gym equipment tag label")
        case .medicineBalls: String(localized: "gymEquipmentTag.medicineBalls", defaultValue: "Medicine Balls", comment: "Gym equipment tag label")
        case .miniLoopResistanceBands: String(localized: "gymEquipmentTag.miniLoopResistanceBands", defaultValue: "Mini Loop Resistance Bands", comment: "Gym equipment tag label")
        case .olympicBenchPressRacks: String(localized: "gymEquipmentTag.olympicBenchPressRacks", defaultValue: "Olympic Bench Press Racks", comment: "Gym equipment tag label")
        case .parallettes: String(localized: "gymEquipmentTag.parallettes", defaultValue: "Parallettes", comment: "Gym equipment tag label")
        case .plyoBoxes: String(localized: "gymEquipmentTag.plyoBoxes", defaultValue: "Plyo Boxes", comment: "Gym equipment tag label")
        case .powerCagesPowerRacks: String(localized: "gymEquipmentTag.powerCagesPowerRacks", defaultValue: "Power Cages / Power Racks", comment: "Gym equipment tag label")
        case .preacherCurlBenches: String(localized: "gymEquipmentTag.preacherCurlBenches", defaultValue: "Preacher Curl Benches", comment: "Gym equipment tag label")
        case .recumbentBikes: String(localized: "gymEquipmentTag.recumbentBikes", defaultValue: "Recumbent Bikes", comment: "Gym equipment tag label")
        case .resistanceTubesWithHandles: String(localized: "gymEquipmentTag.resistanceTubesWithHandles", defaultValue: "Resistance Tubes with Handles", comment: "Gym equipment tag label")
        case .rotaryTorsoMachines: String(localized: "gymEquipmentTag.rotaryTorsoMachines", defaultValue: "Rotary Torso Machines", comment: "Gym equipment tag label")
        case .rowingMachines: String(localized: "gymEquipmentTag.rowingMachines", defaultValue: "Rowing Machines", comment: "Gym equipment tag label")
        case .safetySquatBars: String(localized: "gymEquipmentTag.safetySquatBars", defaultValue: "Safety Squat Bars", comment: "Gym equipment tag label")
        case .sandbags: String(localized: "gymEquipmentTag.sandbags", defaultValue: "Sandbags", comment: "Gym equipment tag label")
        case .seatedCableRowMachines: String(localized: "gymEquipmentTag.seatedCableRowMachines", defaultValue: "Seated Cable Row Machines", comment: "Gym equipment tag label")
        case .shoulderPressMachines: String(localized: "gymEquipmentTag.shoulderPressMachines", defaultValue: "Shoulder Press Machines", comment: "Gym equipment tag label")
        case .slamBalls: String(localized: "gymEquipmentTag.slamBalls", defaultValue: "Slam Balls", comment: "Gym equipment tag label")
        case .sledsProwlers: String(localized: "gymEquipmentTag.sledsProwlers", defaultValue: "Sleds / Prowlers", comment: "Gym equipment tag label")
        case .smithMachines: String(localized: "gymEquipmentTag.smithMachines", defaultValue: "Smith Machines", comment: "Gym equipment tag label")
        case .spinBikes: String(localized: "gymEquipmentTag.spinBikes", defaultValue: "Spin Bikes", comment: "Gym equipment tag label")
        case .squatStands: String(localized: "gymEquipmentTag.squatStands", defaultValue: "Squat Stands", comment: "Gym equipment tag label")
        case .stairClimbersStepmills: String(localized: "gymEquipmentTag.stairClimbersStepmills", defaultValue: "Stair Climbers / Stepmills", comment: "Gym equipment tag label")
        case .standingCalfRaiseMachines: String(localized: "gymEquipmentTag.standingCalfRaiseMachines", defaultValue: "Standing Calf Raise Machines", comment: "Gym equipment tag label")
        case .suspensionTrainersTRX: String(localized: "gymEquipmentTag.suspensionTrainersTRX", defaultValue: "Suspension Trainers / TRX", comment: "Gym equipment tag label; TRX is a brand name, keep untranslated")
        case .swissBarsMultiGripBars: String(localized: "gymEquipmentTag.swissBarsMultiGripBars", defaultValue: "Swiss Bars / Multi-Grip Bars", comment: "Gym equipment tag label")
        case .treadmills: String(localized: "gymEquipmentTag.treadmills", defaultValue: "Treadmills", comment: "Gym equipment tag label")
        case .trapBarsHexBars: String(localized: "gymEquipmentTag.trapBarsHexBars", defaultValue: "Trap Bars / Hex Bars", comment: "Gym equipment tag label")
        case .uprightExerciseBikes: String(localized: "gymEquipmentTag.uprightExerciseBikes", defaultValue: "Upright Exercise Bikes", comment: "Gym equipment tag label")
        case .verticalLegPressMachines: String(localized: "gymEquipmentTag.verticalLegPressMachines", defaultValue: "Vertical Leg Press Machines", comment: "Gym equipment tag label")
        case .wallBalls: String(localized: "gymEquipmentTag.wallBalls", defaultValue: "Wall Balls", comment: "Gym equipment tag label")
        case .weightliftingBelts: String(localized: "gymEquipmentTag.weightliftingBelts", defaultValue: "Weightlifting Belts", comment: "Gym equipment tag label")
        case .weightedVests: String(localized: "gymEquipmentTag.weightedVests", defaultValue: "Weighted Vests", comment: "Gym equipment tag label")
        case .wristWraps: String(localized: "gymEquipmentTag.wristWraps", defaultValue: "Wrist Wraps", comment: "Gym equipment tag label")
        case .yogaMats: String(localized: "gymEquipmentTag.yogaMats", defaultValue: "Yoga Mats", comment: "Gym equipment tag label")
        }
    }

    /// Reused across similar items rather than hunting for 78 distinct SF
    /// Symbols -- same "not a goal" precedent KitchenEquipmentTag already
    /// sets for its own smaller list.
    var systemImageName: String {
        switch self {
        case .barbells, .adjustableDumbbells, .dumbbells, .ezCurlBars, .safetySquatBars,
             .swissBarsMultiGripBars, .trapBarsHexBars, .bumperPlates, .castIronWeightPlates,
             .ironWeightPlates, .fractionalMicroWeightPlates:
            "dumbbell.fill"
        case .kettlebells:
            "figure.strengthtraining.functional"
        case .abdominalCrunchMachines, .backExtensionBenches, .chestFlyPecDeckMachines,
             .chestPressMachines, .hackSquatMachines, .hipThrustMachines, .latPulldownMachines,
             .lateralRaiseMachines, .legCurlMachines, .legExtensionMachines, .legPressMachines,
             .rotaryTorsoMachines, .seatedCableRowMachines, .shoulderPressMachines,
             .smithMachines, .standingCalfRaiseMachines, .verticalLegPressMachines:
            "figure.strengthtraining.traditional"
        case .cableAttachments, .cableCrossFunctionalTrainers, .ankleStrapsCableMachines:
            "cable.connector"
        case .adjustableBenches, .flatBenches, .inclineBenches, .preacherCurlBenches,
             .olympicBenchPressRacks:
            "rectangle.portrait.fill"
        case .halfRacks, .powerCagesPowerRacks, .squatStands:
            "square.stack.3d.up.fill"
        case .airBikesFanBikes, .curvedManualTreadmills, .ellipticals, .inclineTrainers,
             .jacobsLadder, .recumbentBikes, .rowingMachines, .spinBikes,
             .stairClimbersStepmills, .treadmills, .uprightExerciseBikes:
            "figure.run"
        case .battleRopes:
            "waveform.path"
        case .dipBarsDipStations, .gymnasticRings, .parallettes, .suspensionTrainersTRX:
            "figure.gymnastics"
        case .fabricHipBands, .longLoopResistanceBands, .miniLoopResistanceBands,
             .resistanceTubesWithHandles:
            "circle.dashed"
        case .foamRollers, .lacrosseBallsMassageBalls:
            "cylinder.fill"
        case .jumpRopesSpeedRopes:
            "figure.jumprope"
        case .kneeSleeves, .liftingStraps, .liquidChalkChalkBlocks, .weightliftingBelts,
             .wristWraps, .armBlasters:
            "shield.lefthalf.filled"
        case .medicineBalls, .slamBalls, .wallBalls:
            "circle.fill"
        case .plyoBoxes:
            "cube.fill"
        case .sandbags:
            "bag.fill"
        case .sledsProwlers:
            "arrow.left.and.right.square.fill"
        case .weightedVests:
            "shield.fill"
        case .yogaMats, .abMats:
            "rectangle.fill"
        }
    }
}
