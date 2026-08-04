import Foundation

/// Session-lifetime in-memory cache for exercise_library rows and a warm-up
/// prefetch for their reference images -- ExerciseDetailView used to
/// re-fetch the row (and AsyncImage re-fetch the image) from scratch on
/// EVERY open, even for an exercise already viewed earlier in the same
/// plan/session. Not persisted across app launches: this is a shared
/// reference library, not per-user data, so a clean cache on relaunch is a
/// fine tradeoff for not having to think about invalidation.
actor ExerciseLibraryCache {
    static let shared = ExerciseLibraryCache()

    private var entries: [String: ExerciseLibraryEntry] = [:]
    /// Only tracks "have we already kicked off a prefetch for this URL",
    /// not the bytes themselves -- the actual caching happens in
    /// URLSession/URLCache, which AsyncImage's default session also reads
    /// from. This just prevents prefetching the same image twice.
    private var prefetchedImageURLs: Set<URL> = []

    func cached(for key: String) -> ExerciseLibraryEntry? {
        entries[key]
    }

    func store(_ entry: ExerciseLibraryEntry, for key: String) {
        entries[key] = entry
    }

    /// Warms URLCache for one image (the first in the pager -- the one
    /// most likely to actually be seen) by issuing the same request
    /// AsyncImage will later make. Best-effort: a failed/slow prefetch
    /// just means the detail view falls back to its own normal load, no
    /// worse than before this existed.
    func prefetchFirstImage(_ url: URL?) async {
        guard let url, !prefetchedImageURLs.contains(url) else { return }
        prefetchedImageURLs.insert(url)
        _ = try? await URLSession.shared.data(from: url)
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
                    ) else { return }
                    await ExerciseLibraryCache.shared.prefetchFirstImage(entry.imageURLs.first)
                }
            }
        }
    }
}
