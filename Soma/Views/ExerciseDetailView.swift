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
                        Text(exercise.name)
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
                        if !entry.instructions.isEmpty {
                            instructionsSection(entry)
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
        } else {
            noMediaPlaceholder
        }
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

    private var noMediaPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(String(localized: "exerciseDetail.noMedia", defaultValue: "No reference photo for this exercise", comment: "Shown when an exercise has no reference photo/media"))
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private func instructionsSection(_ entry: ExerciseLibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "exerciseDetail.howToPerform", defaultValue: "How to perform it", comment: "Header above the numbered exercise-library instructions"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(Array(entry.instructions.enumerated()), id: \.offset) { index, step in
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
        // A failed lookup collapses to the same "no reference photo" state
        // as a genuine no-match -- there's no useful distinct error UI for
        // a background media lookup that isn't blocking the actual workout.
        entry = try? await SupabaseClient.shared.fetchExerciseLibraryEntry(
            libraryId: exercise.libraryId,
            name: exercise.name
        )
        isLoading = false
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
