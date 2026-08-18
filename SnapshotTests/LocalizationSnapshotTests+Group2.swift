import SnapshotTesting
import SwiftUI
import XCTest
@testable import Soma

/// Group 2: health dashboard, nutrition, and the meal-logging flow.
extension LocalizationSnapshotTests {

    func test_healthDashboard_localizedAcrossLanguages() throws {
        snapshotAcrossLocales(height: 1400, named: "health-dashboard") {
            HealthDashboardView()
        }
    }

    func test_nutrition_localizedAcrossLanguages() throws {
        snapshotAcrossLocales(height: 1200, named: "nutrition") {
            NutritionView()
        }
    }

    func test_logMeal_localizedAcrossLanguages() throws {
        snapshotAcrossLocales(height: 900, named: "log-meal") {
            LogMealView(date: "2026-08-11")
        }
    }

    func test_mealDetail_localizedAcrossLanguages() throws {
        // score/rationale included so the .task's lazy rate() never fires --
        // keeps the snapshot deterministic instead of racing a network call.
        let entry = try decode(MealLogEntry.self, """
        {"id": "m-1", "date": "2026-08-11", "label": "Grilled chicken and rice",
         "calories": 420, "protein_g": 32, "carbs_g": 40, "fat_g": 12,
         "source": "text_ai", "logged_at": "2026-08-11T12:00:00Z",
         "score": 7, "rationale": "Good protein and moderate calories -- fits your goal well."}
        """)
        snapshotAcrossLocales(height: 900, named: "meal-detail") {
            MealDetailView(entry: entry)
        }
    }

    func test_trainingHistory_localizedAcrossLanguages() throws {
        snapshotAcrossLocales(height: 1200, named: "training-history") {
            TrainingHistoryView()
        }
    }
}
