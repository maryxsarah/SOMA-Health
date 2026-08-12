import Foundation

/// What the user actually owns to cook with -- a hard input to
/// generate-meal-recommendation (a suggested recipe must never call for
/// equipment outside this set). Collected once at onboarding
/// (KitchenEquipmentQuestionView) and editable afterward from ProfileView,
/// same "collect once, edit forever" shape as EquipmentTag (gym/workout
/// access) already uses -- kept as its own enum rather than folded into
/// EquipmentTag since the two answer unrelated questions (what can I train
/// with vs. what can I cook with) and a shared list would force irrelevant
/// options into both pickers.
enum KitchenEquipmentTag: String, Codable, CaseIterable, Identifiable {
    case stove
    case oven
    case microwave
    case airFryer = "air_fryer"
    case blender
    case mixer
    case thermomix
    case grill
    case riceCooker = "rice_cooker"
    case slowCooker = "slow_cooker"
    case pressureCooker = "pressure_cooker"
    case foodProcessor = "food_processor"
    case toaster
    /// Pairs with UserProfile.otherHouseholdEquipmentNotes (free text,
    /// comma-separated) for anything not covered by the fixed list -- same
    /// pairing convention as EquipmentTag.other/otherEquipmentNotes.
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stove: String(localized: "kitchenEquipmentTag.stove", defaultValue: "Stove", comment: "Kitchen equipment tag label")
        case .oven: String(localized: "kitchenEquipmentTag.oven", defaultValue: "Oven", comment: "Kitchen equipment tag label")
        case .microwave: String(localized: "kitchenEquipmentTag.microwave", defaultValue: "Microwave", comment: "Kitchen equipment tag label")
        case .airFryer: String(localized: "kitchenEquipmentTag.airFryer", defaultValue: "Air Fryer", comment: "Kitchen equipment tag label")
        case .blender: String(localized: "kitchenEquipmentTag.blender", defaultValue: "Blender", comment: "Kitchen equipment tag label")
        case .mixer: String(localized: "kitchenEquipmentTag.mixer", defaultValue: "Mixer", comment: "Kitchen equipment tag label")
        case .thermomix: String(localized: "kitchenEquipmentTag.thermomix", defaultValue: "Thermomix", comment: "Kitchen equipment tag label; Thermomix is a brand name, keep untranslated")
        case .grill: String(localized: "kitchenEquipmentTag.grill", defaultValue: "Grill", comment: "Kitchen equipment tag label")
        case .riceCooker: String(localized: "kitchenEquipmentTag.riceCooker", defaultValue: "Rice Cooker", comment: "Kitchen equipment tag label")
        case .slowCooker: String(localized: "kitchenEquipmentTag.slowCooker", defaultValue: "Slow Cooker", comment: "Kitchen equipment tag label")
        case .pressureCooker: String(localized: "kitchenEquipmentTag.pressureCooker", defaultValue: "Pressure Cooker / Instant Pot", comment: "Kitchen equipment tag label")
        case .foodProcessor: String(localized: "kitchenEquipmentTag.foodProcessor", defaultValue: "Food Processor", comment: "Kitchen equipment tag label")
        case .toaster: String(localized: "kitchenEquipmentTag.toaster", defaultValue: "Toaster", comment: "Kitchen equipment tag label")
        case .other: String(localized: "kitchenEquipmentTag.other", defaultValue: "Other", comment: "Kitchen equipment tag label: catch-all option")
        }
    }

    var systemImageName: String {
        switch self {
        case .stove: "flame.fill"
        case .oven: "oven.fill"
        case .microwave: "microwave.fill"
        case .airFryer: "wind"
        case .blender: "tornado"
        case .mixer: "arrow.triangle.2.circlepath"
        case .thermomix: "gearshape.2.fill"
        case .grill: "flame.circle.fill"
        case .riceCooker: "cylinder.fill"
        case .slowCooker: "clock.fill"
        case .pressureCooker: "gauge.high"
        case .foodProcessor: "circle.grid.3x3.fill"
        case .toaster: "rectangle.portrait.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    /// Applied when a user skips kitchen-equipment setup entirely --
    /// either at onboarding (that step is always skippable, never gates
    /// Continue) or via "What can I make?"'s own first-use prompt. The
    /// three appliances a typical kitchen has, so generate-meal-
    /// recommendation always has something real and plausible to work
    /// with instead of an empty set that would make every recipe fail
    /// equipment validation.
    static let skipDefault: Set<KitchenEquipmentTag> = [.stove, .oven, .microwave]
}
