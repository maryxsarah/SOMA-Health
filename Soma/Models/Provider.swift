import Foundation

/// The three wearable/health data sources from Screen 2 (Connect Device).
enum Provider: String, CaseIterable, Identifiable {
    case appleHealth
    case whoop
    case oura

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleHealth: "Apple Health"
        case .whoop: "Whoop"
        case .oura: "Oura"
        }
    }

    var systemImageName: String {
        switch self {
        case .appleHealth: "heart.fill"
        case .whoop: "waveform.path.ecg"
        case .oura: "circle.dashed"
        }
    }

    var isAvailable: Bool { true }
}
