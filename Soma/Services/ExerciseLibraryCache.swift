import Foundation
import UIKit

/// Session-lifetime in-memory cache for exercise_library rows AND their
/// decoded reference images. Previously the image half of this only
/// issued a blind URLSession request hoping URLCache/AsyncImage's shared
/// session would honor whatever cache-control Supabase Storage happens to
/// send -- unverified, and not something this app controls. Storing the
/// actual decoded UIImage here instead guarantees a warm repeat-load
/// regardless of server headers: CachedExerciseImage checks this cache
/// FIRST, so a prefetched exercise renders instantly with no network
/// round trip and no spinner at all.
///
/// Not persisted across app launches: this is a shared reference library,
/// not per-user data, so a clean cache on relaunch is a fine tradeoff for
/// not having to think about invalidation or memory pressure eviction.
actor ExerciseLibraryCache {
    static let shared = ExerciseLibraryCache()

    private var entries: [String: ExerciseLibraryEntry] = [:]
    private var images: [URL: UIImage] = [:]
    /// In-flight image downloads, keyed by URL -- a plan's warm-up, main
    /// blocks, and cool-down can all reference the same exercise (e.g. a
    /// stretch used in both warm-up and cool-down), so without this a
    /// prefetch and a concurrent ExerciseDetailView open could both start
    /// their own download of the same URL at once.
    private var inFlightImageLoads: [URL: Task<UIImage?, Never>] = [:]

    func cached(for key: String) -> ExerciseLibraryEntry? {
        entries[key]
    }

    func store(_ entry: ExerciseLibraryEntry, for key: String) {
        entries[key] = entry
    }

    func cachedImage(for url: URL) -> UIImage? {
        images[url]
    }

    /// Downloads (or joins an in-flight download of) `url`, decodes it,
    /// and caches the result. The single entry point both the plan-load
    /// prefetch and ExerciseDetailView's own on-demand load use, so
    /// there's exactly one code path for "get this image" and exactly one
    /// place a request can be in flight.
    func image(for url: URL) async -> UIImage? {
        if let cached = images[url] { return cached }
        if let inFlight = inFlightImageLoads[url] { return await inFlight.value }

        let task = Task<UIImage?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return UIImage(data: data)
        }
        inFlightImageLoads[url] = task
        let image = await task.value
        inFlightImageLoads[url] = nil
        if let image { images[url] = image }
        return image
    }
}

extension SupabaseClient {
    /// Cache-key format shared with fetchExerciseLibraryEntry's own lookup
    /// logic -- id when available (generate-gym-workout's hand-verified
    /// library_id), else exact name.
    static func exerciseLibraryCacheKey(libraryId: String?, name: String) -> String {
        if let libraryId, !libraryId.isEmpty {
            return "id:\(libraryId)"
        }
        return "name:\(name)"
    }

    /// Fire-and-forget prefetch for every exercise in a freshly-rendered
    /// plan -- called once from AIWorkoutPlanView.task so most detail-sheet
    /// opens hit a warm row+image cache instead of starting cold. Errors
    /// are swallowed: this is purely a perceived-latency optimization, the
    /// normal fetch-on-open path still works unmodified if this fails.
    func prefetchExerciseLibraryEntries(for exercises: [AIExercise]) async {
        await withTaskGroup(of: Void.self) { group in
            for exercise in exercises {
                group.addTask {
                    guard let entry = try? await self.fetchExerciseLibraryEntry(
                        libraryId: exercise.libraryId,
                        name: exercise.name
                    ), let firstURL = entry.imageURLs.first else { return }
                    _ = await ExerciseLibraryCache.shared.image(for: firstURL)
                }
            }
        }
    }
}
