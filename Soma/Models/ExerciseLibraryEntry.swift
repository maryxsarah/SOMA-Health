import Foundation

/// One row from exercise_library (Free Exercise DB import, The Unlicense /
/// public domain -- see 20260731090000_add_exercise_library.sql). Read-only
/// reference data, fetched either by exact id (generate-gym-workout's
/// hand-verified library_id) or exact name (generate-workout-plan's `name`
/// is schema-constrained to a real library name, see
/// _shared/exerciseLibraryMatch.ts) -- never fuzzy-matched client-side.
struct ExerciseLibraryEntry: Decodable, Identifiable {
    let id: String
    let name: String
    let force: String?
    let level: String?
    let mechanic: String?
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let instructions: [String]
    let category: String?
    let imagePaths: [String]
    /// Non-nil only for the handful of rows sourced under an attribution-
    /// required license (e.g. CC BY) instead of the bulk Free Exercise DB
    /// import (public domain, no credit needed) -- shown near the photo
    /// when present, per the license's own terms.
    let imageCredit: String?

    enum CodingKeys: String, CodingKey {
        case id, name, force, level, mechanic, equipment, category
        case primaryMuscles = "primary_muscles"
        case secondaryMuscles = "secondary_muscles"
        case instructions = "instructions"
        case imagePaths = "image_paths"
        case imageCredit = "image_credit"
    }

    /// Public storage URLs (exercise-media is a public bucket -- generic
    /// freely-licensed stock photos, not personal user content, so no
    /// signed-URL round trip is needed).
    var imageURLs: [URL] {
        imagePaths.compactMap { path in
            URL(string: "\(Config.supabaseURL.absoluteString)/storage/v1/object/public/exercise-media/\(path)")
        }
    }
}
