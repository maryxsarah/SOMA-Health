import Foundation

/// One metric family shown on the Health Dashboard's 3-level drill-down
/// (Level 1 overview -> Level 2 metric detail -> Level 3 single-metric
/// deep dive). Deliberately limited to metrics `DailySnapshotRow` actually
/// stores -- no fabricated body temperature/respiratory rate fields the
/// way Oura's reference screens have, since this app has no real data
/// source for those.
///
/// Intentionally omitted vs. an Oura-style "Vitals" reference design, and
/// why (no data source exists today, not an oversight):
///   - Symptom Radar -- no symptom-logging feature exists in this app.
///   - Resilience -- no field/score/endpoint anywhere.
///   - Body Clock / chronotype -- no bed/wake timestamps stored, only a
///     total-hours sleep duration.
///   - Sleep regularity -- needs multiple nights of real start/end
///     timestamps, not stored.
///   - Sleep debt -- needs a stored sleep-need baseline plus timestamped
///     sessions, neither exists.
///   - Activity Score / Activity goal -- no Oura activity-score or
///     calorie-goal data is ever fetched by this app.
///   - Sleep Score (Oura's composite 0-100) -- not stored; `.sleep`'s real
///     number is the raw `sleep_hours` total, not a synthesized composite.
///   - Body temperature -- no HealthKit read type requested, no
///     wearable field fetched.
/// The one reference-design item that IS real and shown (sleep-stage
/// breakdown, REM/Light/Deep/Awake) -- see `sleepLightHours` etc. on
/// DailySnapshotRow -- because Whoop/HealthKit/Oura all already report it
/// at the source; it was just computed and discarded before persistence,
/// unlike everything in the list above which has no source at all.
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

    /// Typed band behind `qualitativeLabel` -- switch on this, never on the
    /// display string, so rewording a label can't silently change logic.
    enum QualitativeBand: String {
        case high = "High"
        case mediumHigh = "Medium-High"
        case medium = "Medium"
        case low = "Low"
    }

    /// A quick qualitative read, ONLY for Recovery/Readiness -- mirrors the
    /// exact thresholds generate-recommendation/index.ts's bandFromWhoop/
    /// bandFromOura already use to decide the day's category, so this
    /// label is never a fabricated new scale, just those same thresholds
    /// surfaced for display. Every other family has no established
    /// "good/bad" threshold in this app, so shows the raw number only.
    static func qualitativeBand(recoveryOrReadiness value: Double, isWhoopRecovery: Bool) -> QualitativeBand {
        if isWhoopRecovery {
            if value >= 67 { return .high }
            if value >= 34 { return .medium }
            return .low
        } else {
            if value >= 85 { return .high }
            if value >= 70 { return .mediumHigh }
            if value >= 60 { return .medium }
            return .low
        }
    }

    static func qualitativeLabel(recoveryOrReadiness value: Double, isWhoopRecovery: Bool) -> String {
        qualitativeBand(recoveryOrReadiness: value, isWhoopRecovery: isWhoopRecovery).rawValue
    }

    enum TrendDirection {
        case up, down, flat
    }

    /// Today's value vs. the average of prior values in the window --
    /// extracted from MetricDetailView's insightSentence so Level-1's
    /// denser card grid and Level-2's detail page share one implementation
    /// instead of two hand-copies drifting apart (same reasoning as
    /// AxisLabeledTrendChart being shared across levels).
    static func trendDescription(today: Double, priorValues: [Double]) -> (percent: Int, direction: TrendDirection)? {
        guard !priorValues.isEmpty else { return nil }
        let average = priorValues.reduce(0, +) / Double(priorValues.count)
        let diffPercent = average != 0 ? (today - average) / average * 100 : 0
        let direction: TrendDirection = abs(diffPercent) < 5 ? .flat : (diffPercent > 0 ? .up : .down)
        return (percent: Int(abs(diffPercent)), direction: direction)
    }
}
