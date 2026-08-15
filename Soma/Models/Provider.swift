import Foundation

/// The three wearable/health data sources from Screen 2 (Connect Device).
enum Provider: String, CaseIterable, Identifiable {
    case appleHealth
    case whoop
    case oura

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleHealth: return String(localized: "provider.appleHealth", defaultValue: "Apple Health", comment: "Connected-device provider display name; brand name, not translated")
        case .whoop: return String(localized: "provider.whoop", defaultValue: "Whoop", comment: "Connected-device provider display name; brand name, not translated")
        case .oura: return String(localized: "provider.oura", defaultValue: "Oura", comment: "Connected-device provider display name; brand name, not translated")
        }
    }

    var systemImageName: String {
        switch self {
        case .appleHealth: "heart.fill"
        case .whoop: "waveform.path.ecg"
        case .oura: "circle.dashed"
        }
    }

    /// What connecting this source actually buys the user -- shown in
    /// place of a bare "Not connected" on Screen 2 (Connect Device).
    var benefitDescription: String {
        switch self {
        case .appleHealth: String(localized: "provider.appleHealth.benefit", defaultValue: "steps, workouts & weight", comment: "Connect Device screen: what Soma reads from Apple Health once connected")
        case .whoop: String(localized: "provider.whoop.benefit", defaultValue: "recovery & strain", comment: "Connect Device screen: what Soma reads from Whoop once connected")
        case .oura: String(localized: "provider.oura.benefit", defaultValue: "sleep & readiness", comment: "Connect Device screen: what Soma reads from Oura once connected")
        }
    }

    var isAvailable: Bool { true }
}
