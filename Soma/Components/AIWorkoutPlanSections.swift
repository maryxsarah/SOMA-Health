import SwiftUI

/// Renders an AIWorkoutPlan's focus/warm-up/blocks/cool-down -- shared by
/// RecommendationDetailView (AI-generated workout card) and
/// GymPhotoWorkoutView (gym-photo result screen), so both consume the same
/// AIWorkoutPlan/AIWorkoutBlock/AIExercise shape without bespoke UI.
///
/// 13a folded what used to be a permanent wall of text (every exercise's
/// full coaching cue, always expanded, for all 13+ items): each row's cue
/// now lives behind a tap -- one row open at a time, same chevron-rotate
/// language as SomaDisclosure -- the meta line collapses sets/weight/
/// intensity/rest into one quiet "·"-joined string (dropping a bare "N/A"
/// weight guidance and the word "sets"), and block/phase headers carry
/// their duration or rounds inline on the trailing edge instead of a
/// second full-width line.
struct AIWorkoutPlanView: View {
    let plan: AIWorkoutPlan
    /// e.g. "VERTICAL JUMP · GOAL BLOCK" -- rendered over the first block
    /// when the caller has an active sport goal. Nil everywhere else.
    var goalEyebrow: String? = nil
    /// 13c: once today's workout is logged, every row reads as done
    /// (checked, strikethrough) regardless of this session's own taps --
    /// reopening an already-completed day shouldn't show a blank,
    /// all-unchecked plan just because `checkedExerciseIDs` never saw this
    /// session's taps. Also locks the per-row toggle -- a completed day's
    /// checklist is a record, not something left editable.
    var isCompletedToday: Bool = false

    @State private var selectedExercise: AIExercise?
    /// Local, session-only completion tracking -- lets a user check off
    /// exercises as they work through the plan (real feedback: "give the
    /// user a better experience when working out"). Keyed by AIExercise.id
    /// (== name), which planValidation's duplicate-prevention now keeps
    /// unique across an entire session, warm-up/blocks/cool-down included.
    @State private var checkedExerciseIDs: Set<String> = []
    /// Accordion, not a set -- at most one row's coaching cue is open at
    /// once, the whole point of folding being a shorter scroll.
    @State private var expandedExerciseID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(plan.focus)
                .font(.subheadline.bold())
                .padding(.top, 4)
            if let actualDurationMinutes = plan.actualDurationMinutes {
                Text("~\(actualDurationMinutes) min total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let weatherNote = plan.weatherNote {
                Text(String(localized: "aiWorkoutPlan.weatherNote", defaultValue: "🌡️ \(weatherNote) Today's plan sticks to indoor cardio.", comment: "Weather-driven note shown above the plan when today's session was moved indoors; placeholder is a free-text weather reason"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
            }
            aiPhaseSection(title: "Warm-up", exercises: plan.warmUp)
            ForEach(Array(plan.blocks.enumerated()), id: \.element.id) { index, block in
                // Only when this plan really carries a goal block -- an
                // active goal alone must not badge a goal-free day.
                if index == 0, let goalEyebrow, plan.goalBlock != nil {
                    Text(goalEyebrow)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(SomaTokens.accent)
                        .padding(.top, 10)
                }
                aiBlockSection(block)
            }
            aiPhaseSection(title: "Cool-down", exercises: plan.coolDown)

            // 13a: the RPE explainer folds into the same sentence/icon as
            // the conservative-weights note -- was two separate footnotes
            // (this one here, "Weights start conservative" a second one
            // RecommendationDetailView drew on its own right below this
            // view). Still always-visible, no interaction needed -- someone
            // who's never seen "RPE 7/10" before shouldn't be left guessing
            // what it means (real user feedback this addressed originally).
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SomaTokens.success)
                    .padding(.top, 1)
                Text(weightsAndRPEFootnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        }
        .sheet(item: $selectedExercise) { exercise in
            ExerciseDetailView(exercise: exercise)
        }
        // Fire-and-forget: warms ExerciseLibraryCache for every exercise in
        // the plan as soon as it renders, so tapping into any of them
        // later (ExerciseDetailView) usually finds a cache hit instead of
        // starting cold. Never blocks the plan itself from rendering.
        .task(id: plan.focus) {
            await SupabaseClient.shared.prefetchExerciseLibraryEntries(for: allExercises)
        }
    }

    private var weightsAndRPEFootnote: String {
        String(localized: "aiWorkoutPlan.weightsAndRPEFootnote", defaultValue: "Weights start conservative — Soma adjusts from what you actually lift. RPE = how hard a set feels, 1 easy · 10 max.", comment: "Combined footnote under the workout plan: reassures weight suggestions adapt, then defines RPE, in one sentence")
    }

    private var allExercises: [AIExercise] {
        plan.warmUp + plan.blocks.flatMap(\.exercises) + plan.coolDown
    }

    /// 11d: exercises arrive numbered in one continuous sequence spanning
    /// warm-up/blocks/cool-down, not restarting per phase.
    private var exerciseNumbers: [String: Int] {
        // uniquingKeysWith, not uniqueKeysWithValues: the backend's dedup is
        // only best-effort, so a repeated exercise name (== AIExercise.id)
        // across warm-up/blocks/cool-down must not crash the plan's render.
        Dictionary(allExercises.enumerated().map { ($1.id, $0 + 1) }, uniquingKeysWith: { first, _ in first })
    }

    private func aiPhaseSection(title: LocalizedStringKey, exercises: [AIExercise]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(durationText(exercises))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
            ForEach(exercises) { exercise in
                aiExerciseRow(exercise)
            }
        }
    }

    private func aiBlockSection(_ block: AIWorkoutBlock) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(block.name)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                // Clearly optional/skippable -- the finisher used to be
                // mandatory ("no exceptions") on every plan; it's now
                // included deterministically only on eligible days (see
                // finisherCatalog.ts's decideFinisher), and this badge is
                // the one place that distinction is visible to the user.
                if block.isFinisher {
                    Text(finisherBadgeText)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(SomaTokens.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassCardFlat(cornerRadius: SomaTokens.rPill)
                } else if block.rounds > 1 {
                    Text(roundsRestText(block))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(durationText(block.exercises))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 10)
            ForEach(block.exercises) { exercise in
                aiExerciseRow(exercise)
            }
        }
    }

    private var finisherBadgeText: String {
        plan.exceptionalFinisher
            ? String(localized: "aiWorkoutBlock.finisher.recovered", defaultValue: "Optional — you're well recovered", comment: "Short pill badge on the optional finisher block header, shown when today's readiness allows the full version")
            : String(localized: "aiWorkoutBlock.finisher.skip", defaultValue: "Optional — skip freely", comment: "Short pill badge on the optional finisher block header, inviting the user to skip it with no penalty")
    }

    private func roundsRestText(_ block: AIWorkoutBlock) -> String {
        String(localized: "aiWorkoutBlock.roundsRest", defaultValue: "\(block.rounds) rounds · rest \(block.restBetweenRounds)", comment: "Block header meta: number of rounds and rest between them, e.g. '3 rounds · rest 60s'")
    }

    private func durationText(_ exercises: [AIExercise]) -> String {
        let total = exercises.reduce(0) { $0 + $1.durationMinutes }
        return String(localized: "aiWorkoutPlan.phaseDuration", defaultValue: "\(total) min", comment: "Total duration shown next to a workout phase/block header, e.g. '4 min'")
    }

    /// 13a's compact meta line -- sets × reps, then whichever of weight
    /// guidance/rest are actually present, joined with "·". Weight
    /// guidance is dropped entirely when the backend sent a bare "N/A"
    /// (its own literal value for stretches/bodyweight moves -- see
    /// generate-workout-plan's prompt) rather than showing that word to
    /// the user.
    private func compactMetaLine(for exercise: AIExercise) -> String {
        let weight = exercise.weightGuidance.trimmingCharacters(in: .whitespacesAndNewlines)
        let showWeight = !weight.isEmpty && weight.caseInsensitiveCompare("N/A") != .orderedSame
        switch (showWeight, exercise.restLabel) {
        case (true, let restLabel?):
            return String(localized: "aiExercise.metaLine.weightRest", defaultValue: "\(exercise.sets) × \(exercise.reps) · \(weight) · \(exercise.intensity) · \(restLabel)", comment: "Compact exercise row meta line: sets × reps, weight guidance, intensity, and rest, e.g. '3 × 12 · 2×8kg dumbbells · RPE 6 · 45s rest'")
        case (true, nil):
            return String(localized: "aiExercise.metaLine.weight", defaultValue: "\(exercise.sets) × \(exercise.reps) · \(weight) · \(exercise.intensity)", comment: "Compact exercise row meta line: sets × reps, weight guidance, and intensity, no rest data, e.g. '3 × 12 · 2×8kg dumbbells · RPE 6'")
        case (false, let restLabel?):
            return String(localized: "aiExercise.metaLine.rest", defaultValue: "\(exercise.sets) × \(exercise.reps) · \(exercise.intensity) · \(restLabel)", comment: "Compact exercise row meta line: sets × reps, intensity, and rest, no weight guidance, e.g. '3 × 12 · RPE 6 · 45s rest'")
        case (false, nil):
            return String(localized: "aiExercise.metaLine.plain", defaultValue: "\(exercise.sets) × \(exercise.reps) · \(exercise.intensity)", comment: "Compact exercise row meta line: sets × reps and intensity only, no weight guidance or rest data, e.g. '3 × 12 · RPE 6'")
        }
    }

    private func aiExerciseRow(_ exercise: AIExercise) -> some View {
        let isDone = isCompletedToday || checkedExerciseIDs.contains(exercise.id)
        let isExpanded = expandedExerciseID == exercise.id
        let number = exerciseNumbers[exercise.id] ?? 1
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    guard !isCompletedToday else { return }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if isDone {
                            checkedExerciseIDs.remove(exercise.id)
                        } else {
                            checkedExerciseIDs.insert(exercise.id)
                        }
                    }
                } label: {
                    // 11d: unchecked = a numbered glass lens badge (position
                    // in the plan); checked = the same green checkmark as
                    // before. 13a adds a third look -- unchecked but this
                    // row's cue is open -- the same filled/gel badge a
                    // selected day/streak uses elsewhere in the app, so an
                    // open row reads as "active" even before you finish it.
                    if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 21))
                            .foregroundStyle(SomaTokens.success)
                    } else if isExpanded {
                        Text("\(number)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .glassGel(.blue, cornerRadius: SomaTokens.rPill)
                    } else {
                        Text("\(number)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SomaTokens.accent)
                            .frame(width: 26, height: 26)
                            .glassLens(cornerRadius: SomaTokens.rPill)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        expandedExerciseID = isExpanded ? nil : exercise.id
                    }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(exercise.name)
                                .font(.subheadline.bold())
                                .strikethrough(isDone, color: SomaTokens.success)
                                .foregroundStyle(isDone ? SomaTokens.ink3 : (isExpanded ? SomaTokens.accent : SomaTokens.ink))
                            Text(compactMetaLine(for: exercise))
                                .font(.caption)
                                .foregroundStyle(Theme.pillFill)
                            // Only populated by the gym-photo-workout flow --
                            // nil for the normal generate-workout-plan flow.
                            if let targetArea = exercise.targetArea {
                                Text(String(localized: "aiWorkoutPlan.targetArea", defaultValue: "Targets: \(targetArea)", comment: "Gym-photo workout exercise row: which equipment/body area this exercise targets"))
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SomaTokens.ink4)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .padding(.top, 3)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    if !exercise.instructions.isEmpty {
                        Text(exercise.instructions)
                            .font(.caption)
                            .foregroundStyle(SomaTokens.ink2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 11)
                            .padding(.horizontal, 13)
                            .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.surface3))
                    }
                    // 13a's mockup shows "Swap exercise"/"Too easy or hard"
                    // chips here -- neither has any backend behind it yet
                    // (no swap endpoint, no per-exercise difficulty
                    // feedback), so faking them would just be dead buttons.
                    // This chip does the same real job ExerciseDetailView
                    // already did (photo reference + full library how-to)
                    // instead of inventing UI with nothing behind it.
                    Button {
                        selectedExercise = exercise
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "photo.circle")
                            Text(String(localized: "aiExercise.photosAndGuide", defaultValue: "Photos & full guide", comment: "Chip in an expanded exercise row that opens the full exercise detail sheet (reference photos, full library how-to)"))
                        }
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(SomaTokens.accent)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .glassCardFlat(cornerRadius: SomaTokens.rPill)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 36)
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: SomaTokens.rMD, style: .continuous)
                .fill(isDone ? SomaTokens.successSoft : Color.clear)
        )
        .animation(.easeInOut(duration: 0.18), value: isDone)
    }
}
