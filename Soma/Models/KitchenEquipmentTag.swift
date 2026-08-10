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
        case .stove: "Stove"
        case .oven: "Oven"
        case .microwave: "Microwave"
        case .airFryer: "Air Fryer"
        case .blender: "Blender"
        case .mixer: "Mixer"
        case .thermomix: "Thermomix"
        case .grill: "Grill"
        case .riceCooker: "Rice Cooker"
        case .slowCooker: "Slow Cooker"
        case .pressureCooker: "Pressure Cooker / Instant Pot"
        case .foodProcessor: "Food Processor"
        case .toaster: "Toaster"
        case .other: "Other"
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
