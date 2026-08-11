import SnapshotTesting
import SwiftUI
import XCTest
@testable import Soma

extension LocalizationSnapshotTests {

    func test_metricDetail_localizedAcrossLanguages() throws {
        let snapshot = try decode(DailySnapshotRow.self, #"{"source":"whoop"}"#)
        snapshotAcrossLocales(height: 1200, named: "metric-detail") {
            NavigationStack {
                MetricDetailView(metric: .sleep, recentSnapshots: [snapshot])
            }
        }
    }

    func test_singleMetricDetail_localizedAcrossLanguages() throws {
        // Fetches its own trend data via @State -- empty/loading is fine,
        // this only proves the range picker and static copy localize.
        snapshotAcrossLocales(height: 900, named: "single-metric-detail") {
            NavigationStack {
                SingleMetricDetailView(metric: .hrv)
            }
        }
    }

    func test_dayDetail_localizedAcrossLanguages() throws {
        // Empty recommendations list is valid -- only used for a "best
        // readiness day" check, and the view's own data loads via .task.
        snapshotAcrossLocales(height: 1200, named: "day-detail") {
            DayDetailView(date: "2026-08-11", recentRecommendations: [])
        }
    }

    func test_completedWorkout_localizedAcrossLanguages() throws {
        let log = try decode(WorkoutLogEntry.self, #"""
        {"id":"1","date":"2026-08-11","title":"Push Day","body_part":"upper_body",
         "category":"moderate","completed_at":"2026-08-11T08:00:00Z"}
        """#)
        snapshotAcrossLocales(height: 1200, named: "completed-workout") {
            CompletedWorkoutView(log: log, isBestReadinessDay: false)
        }
    }
}
