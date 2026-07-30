import Foundation

/// One metric family shown on the Health Dashboard's 3-level drill-down
/// (Level 1 overview -> Level 2 metric detail -> Level 3 single-metric
/// deep dive). Deliberately limited to metrics `DailySnapshotRow` actually
/// stores -- no fabricated body temperature/respiratory rate/sleep-stage
/// fields the way Oura's reference screens have, since this app has no
/// real data source for those.
enum HealthMetricFamily: String, CaseIterable, Identifiable {
    case recoveryReadiness
    case hrv
    case restingHR
    case sleep
    case strain
    case stress

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .recoveryReadiness: "Recovery / Readiness"
        case .hrv: "HRV"
        case .restingHR: "Resting HR"
        case .sleep: "Sleep"
        case .strain: "Strain"
        case .stress: "Stress"
        }
    }

    var unit: String {
        switch self {
        case .recoveryReadiness: ""
        case .hrv: "ms"
        case .restingHR: "bpm"
        case .sleep: "h"
        case .strain: ""
        case .stress: "min"
        }
    }

    /// Pulls this family's value out of a snapshot row, if that source
    /// reported it -- mirrors HealthDashboardView's existing `trendMetrics`
    /// coalescing (recovery/readiness share one family since they're the
    /// same underlying "how ready is today" concept, just different
    /// wearables' names for it).
    func value(from row: DailySnapshotRow) -> Double? {
        switch self {
        case .recoveryReadiness: row.recoveryScore ?? row.readinessScore
        case .hrv: row.hrvMs
        case .restingHR: row.restingHr
        case .sleep: row.sleepHours
        case .strain: row.strainScore
        case .stress: row.stressScore
        }
    }

    /// Only Recovery/Readiness and Sleep have real sub-contributors this
    /// app can actually show -- tied directly to what bandFromWhoop/
    /// bandFromOura/assessHealthKit (generate-recommendation) and the
    /// sleep safety cap actually use as inputs, not an invented generic
    /// list. Every other family is already atomic.
    var contributors: [HealthMetricFamily] {
        switch self {
        case .recoveryReadiness: [.hrv, .restingHR, .sleep]
        case .sleep: [.hrv, .restingHR, .strain]
        case .hrv, .restingHR, .strain, .stress: []
        }
    }

    /// A quick qualitative read, ONLY for Recovery/Readiness -- mirrors the
    /// exact thresholds generate-recommendation/index.ts's bandFromWhoop/
    /// bandFromOura already use to decide the day's category, so this
    /// label is never a fabricated new scale, just those same thresholds
    /// surfaced for display. Every other family has no established
    /// "good/bad" threshold in this app, so shows the raw number only.
    static func qualitativeLabel(recoveryOrReadiness value: Double, isWhoopRecovery: Bool) -> String {
        if isWhoopRecovery {
            if value >= 67 { return "High" }
            if value >= 34 { return "Medium" }
            return "Low"
        } else {
            if value >= 85 { return "High" }
            if value >= 70 { return "Medium-High" }
            if value >= 60 { return "Medium" }
            return "Low"
        }
    }
}
