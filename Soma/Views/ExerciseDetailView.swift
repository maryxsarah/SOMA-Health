import SwiftUI
import UIKit

/// "What does this exercise actually look like" detail sheet -- tapped from
/// any AIExercise row (AIWorkoutPlanSections.swift). Looks the real
/// exercise_library entry up server-side (by id when generate-gym-workout
/// supplied one, otherwise by exact name) rather than trusting anything
/// pre-fetched, since the same exercise name can appear in many plans.
struct ExerciseDetailView: View {
    let exercise: AIExercise

    @State private var entry: ExerciseLibraryEntry?
    @State private var isLoading = true
    /// Library name + how-to steps in the UI language (nil when English,
    /// or while the translation is still in flight) -- see load().
    @State private var translation: SupabaseClient.ExerciseGuideTranslation?
    /// True only when the library lookup itself threw (network/auth/server
    /// error) -- distinct from `entry == nil` after a *successful* lookup
    /// that genuinely found no row or an empty `image_paths`. Both used to
    /// collapse into the same "no reference photo" placeholder, which read
    /// as "every exercise is missing media" during a transient blip (e.g.
    /// an expired/refreshing session) instead of "retry this one." See
    /// mediaArea below.
    @State private var lookupFailed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                // Everything the user picked/was told to do (name, sets,
                // reps, weight, intensity, the AI's own coaching cue) comes
                // straight from `exercise` -- already in memory, no fetch
                // needed -- so it renders on the very first frame. Only the
                // media/tags/library-instructions area (which DOES need a
                // network round trip) shows its own small loading state,
                // instead of the whole sheet blocking behind one spinner
                // until that round trip finishes.
                VStack(alignment: .leading, spacing: 16) {
                    mediaArea
                    if let credit = entry?.imageCredit, !credit.isEmpty {
                        Text(credit)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(translation?.name ?? exercise.name)
                            .font(.title3.bold())
                        Text(exercise.restLabel.map { restLabel in
                            String(localized: "exerciseDetail.summary.withRest", defaultValue: "\(exercise.sets) sets × \(exercise.reps) — \(exercise.weightGuidance) — \(exercise.intensity) — \(restLabel)", comment: "Exercise detail: sets/reps/weight/intensity/rest summary line, with a rest period")
                        } ?? String(localized: "exerciseDetail.summary.noRest", defaultValue: "\(exercise.sets) sets × \(exercise.reps) — \(exercise.weightGuidance) — \(exercise.intensity)", comment: "Exercise detail: sets/reps/weight/intensity summary line, no rest period"))
                            .font(.subheadline)
                            .foregroundStyle(Theme.pillFill)
                        // Always-visible, no interaction needed -- someone
                        // opening this detail view directly (not having
                        // seen the plan list's own footnote) shouldn't be
                        // left guessing what "RPE 7/10" means.
                        if exercise.intensity.localizedCaseInsensitiveContains("rpe") {
                            Text(String(localized: "exerciseDetail.rpeExplainer", defaultValue: "RPE = Rate of Perceived Exertion, how hard a set feels (1 = very easy, 10 = maximum effort).", comment: "Explainer for RPE shown when an exercise's intensity mentions RPE"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !exercise.instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "exerciseDetail.coachingCue", defaultValue: "Coaching cue", comment: "Header above the AI's own coaching cue text for this exercise"))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(exercise.instructions)
                                .font(.subheadline)
                        }
                    }

                    if let entry {
                        tagsRow(entry)
                        // Translated steps replace the library's English
                        // ones whenever the UI language isn't English.
                        let steps = (translation?.instructions.isEmpty == false) ? translation!.instructions : entry.instructions
                        if !steps.isEmpty {
                            instructionsSection(steps)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(String(localized: "exerciseDetail.navigationTitle", defaultValue: "Exercise", comment: "Navigation title for the exercise detail sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "exerciseDetail.done", defaultValue: "Done", comment: "Button closing the exercise detail sheet")) { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var mediaArea: some View {
        if let entry, !entry.imagePaths.isEmpty {
            imagePager(entry)
        } else if isLoading {
            // A lightweight placeholder, not a full-sheet blocker -- the
            // rest of the sheet (name/sets/reps/coaching cue above) is
            // already visible and interactive while this resolves.
            Color.clear
                .frame(height: 220)
                .glassCard(cornerRadius: SomaTokens.r2XL)
                .overlay(SomaLoadingBar())
        } else if lookupFailed {
            retryPlaceholder
        } else {
            noMediaPlaceholder
        }
    }

    /// Shown only when the lookup itself errored (network/auth/server) --
    /// tapping retries the same lookup rather than leaving the user stuck
    /// on a placeholder that looks identical to "this exercise genuinely
    /// has no photo on file."
    private var retryPlaceholder: some View {
        Button {
            isLoading = true
            lookupFailed = false
            Task { await load() }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(String(localized: "exerciseDetail.photoRetry", defaultValue: "Couldn't load photo, tap to retry", comment: "Placeholder button shown when the exercise photo lookup failed; tapping retries"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(RoundedRectangle(cornerRadius: SomaTokens.r2XL, style: .continuous).fill(Color(.systemGray6)))
        }
        .buttonStyle(.plain)
    }

    private func imagePager(_ entry: ExerciseLibraryEntry) -> some View {
        TabView {
            ForEach(entry.imageURLs, id: \.absoluteString) { url in
                CachedExerciseImage(url: url, placeholder: noMediaPlaceholder)
            }
        }
        .tabViewStyle(.page)
        .frame(height: 260)
        .glassCard(cornerRadius: SomaTokens.r2XL)
        .clipShape(RoundedRectangle(cornerRadius: SomaTokens.r2XL, style: .continuous))
    }

    /// Roughly half of a gym-photo-generated workout is exercises that
    /// genuinely have no real photo anywhere in exercise_library (breathing
    /// drills, in-place cardio, a handful of holds/carries where the closest
    /// library entry would show materially different equipment -- see
    /// generate-gym-workout/templates.ts's CONFIRMED_NO_LIBRARY_EQUIVALENT
    /// for the hand-audited list). Showing the exact same flat "No reference
    /// photo" box for all of them read as one broken feature; this instead
    /// reads target_area (already fixed per exercise, not LLM-guessed -- see
    /// AIExercise.targetArea) to pick a distinct, intentional-looking icon
    /// and tint per exercise family, the same "why, not just what" instinct
    /// the rest of this file already applies to the retry-vs-no-photo split
    /// above. Only generate-gym-workout ever sets targetArea, so an
    /// AI-generated (non-gym-photo) plan -- which the exerciseLibraryMatch.ts
    /// fix already constrains to real-photo exercise names, so this should
    /// be rare there anyway -- always falls into the .strength default.
    private enum MediaFallbackCategory {
        case cardio
        case breathingMobility
        case strength

        var icon: String {
            switch self {
            case .cardio: "figure.run"
            case .breathingMobility: "wind"
            case .strength: "dumbbell.fill"
            }
        }

        var tint: Color {
            switch self {
            case .cardio: SomaTokens.heart
            case .breathingMobility: SomaTokens.accent
            case .strength: SomaTokens.ink2
            }
        }

        var softTint: Color {
            switch self {
            case .cardio: SomaTokens.heartSoft
            case .breathingMobility: SomaTokens.accentSoft
            case .strength: SomaTokens.surface3
            }
        }

        var caption: String {
            switch self {
            case .cardio: String(localized: "exerciseDetail.noMedia.cardio", defaultValue: "No reference photo — this one's about pace and effort, not a position to copy", comment: "Media placeholder caption for a cardio exercise with no reference photo")
            case .breathingMobility: String(localized: "exerciseDetail.noMedia.breathingMobility", defaultValue: "No reference photo — follow the breathing/mobility cue above", comment: "Media placeholder caption for a breathing/mobility exercise with no reference photo")
            case .strength: String(localized: "exerciseDetail.noMedia", defaultValue: "No reference photo for this exercise", comment: "Shown when an exercise has no reference photo/media")
            }
        }
    }

    private var mediaFallbackCategory: MediaFallbackCategory {
        let area = (exercise.targetArea ?? "").lowercased()
        if area.contains("nervous system") { return .breathingMobility }
        if area.contains("cardio") || area.contains("heart rate") { return .cardio }
        return .strength
    }

    private var noMediaPlaceholder: some View {
        let category = mediaFallbackCategory
        return VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(category.softTint)
                    .frame(width: 60, height: 60)
                Image(systemName: category.icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(category.tint)
            }
            Text(category.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .glassCard(cornerRadius: SomaTokens.r2XL)
    }

    private func tagsRow(_ entry: ExerciseLibraryEntry) -> some View {
        let tags = ([entry.equipment] + entry.primaryMuscles).compactMap { $0 }.filter { !$0.isEmpty }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag.capitalized)
                        .font(.caption2.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.pillFill.opacity(0.12)))
                        .foregroundStyle(Theme.pillFill)
                }
            }
        }
    }

    private func instructionsSection(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "exerciseDetail.howToPerform", defaultValue: "How to perform it", comment: "Header above the numbered exercise-library instructions"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Text(step)
                        .font(.subheadline)
                }
            }
        }
    }

    private func load() async {
        // A transient lookup failure (network/auth/server error) now gets
        // its own retry state instead of collapsing into the same "no
        // reference photo" placeholder as a genuine no-match -- see
        // `lookupFailed` and `retryPlaceholder` above.
        do {
            entry = try await SupabaseClient.shared.fetchExerciseLibraryEntry(
                libraryId: exercise.libraryId,
                name: exercise.name
            )
            lookupFailed = false
        } catch {
            entry = nil
            lookupFailed = true
        }
        isLoading = false
        // After the entry is on screen -- English steps showing is a fine
        // intermediate state; a failed translation just stays English.
        if let entry {
            translation = try? await SupabaseClient.shared.translateExerciseGuide(exerciseId: entry.id)
        }
    }
}

/// Checks ExerciseLibraryCache first -- if AIWorkoutPlanView's own-plan
/// prefetch already ran (the common case: this view only opens from a
/// plan already on screen), this renders instantly with no network round
/// trip and no loading state at all. Falls back to a real fetch + the
/// shared SomaLoadingBar otherwise, same as before this cache existed.
private struct CachedExerciseImage<Placeholder: View>: View {
    let url: URL
    let placeholder: Placeholder

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    // The pager's own container is already clipped to
                    // rounded corners, but scaledToFit can still leave the
                    // photo's own square edges visible/near-flush inside
                    // it -- clip the image itself too so it always reads
                    // as rounded, matching the rest of the app's cards.
                    .clipShape(RoundedRectangle(cornerRadius: SomaTokens.r2XL, style: .continuous))
            } else if failed {
                placeholder
            } else {
                SomaLoadingBar()
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .task(id: url) {
            image = await ExerciseLibraryCache.shared.image(for: url)
            failed = image == nil
        }
    }
}
