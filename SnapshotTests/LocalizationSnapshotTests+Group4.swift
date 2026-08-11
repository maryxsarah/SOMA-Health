import SnapshotTesting
import SwiftUI
import XCTest
@testable import Soma

extension LocalizationSnapshotTests {

    func test_recommendationDetail_localizedAcrossLanguages() throws {
        let recommendation = try decode(DailyRecommendation.self, """
        {"date": "2026-08-11", "category": "moderate",
         "message": "Solid day for quality work.",
         "reason": "Your HRV was close to your recent baseline and you slept enough -- a good sign of recovery.",
         "sleep_cap_applied": false, "injury_cap_applied": false, "load_cap_applied": false}
        """)
        let state = try appState()
        snapshotAcrossLocales(height: 1600, named: "recommendation-detail") {
            RecommendationDetailView(recommendation: recommendation)
                .environmentObject(state)
        }
    }

    func test_gymPhotoWorkout_localizedAcrossLanguages() throws {
        snapshotAcrossLocales(height: 1200, named: "gym-photo-workout") {
            GymPhotoWorkoutView(date: "2026-08-11")
        }
    }

    func test_exerciseDetail_localizedAcrossLanguages() throws {
        let exercise = try decode(AIExercise.self, """
        {"name": "Squat", "sets": 3, "reps": "10", "weight_guidance": "Bodyweight",
         "intensity": "moderate", "duration_minutes": 5,
         "instructions": "Keep your back straight."}
        """)
        snapshotAcrossLocales(height: 900, named: "exercise-detail") {
            ExerciseDetailView(exercise: exercise)
        }
    }

    func test_feedback_localizedAcrossLanguages() throws {
        snapshotAcrossLocales(height: 700, named: "feedback") {
            FeedbackView()
        }
    }
}
