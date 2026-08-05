import SwiftUI

/// Renders an AIWorkoutPlan's focus/warm-up/blocks/cool-down -- shared by
/// RecommendationDetailView (AI-generated workout card) and
/// GymPhotoWorkoutView (gym-photo result screen), so both consume the same
/// AIWorkoutPlan/AIWorkoutBlock/AIExercise shape without bespoke UI.
struct AIWorkoutPlanView: View {
    let plan: AIWorkoutPlan
    /// e.g. "VERTICAL JUMP · GOAL BLOCK" -- rendered over the first block
    /// when the caller has an active sport goal. Nil everywhere else.
    var goalEyebrow: String? = nil

    @State private var selectedExercise: AIExercise?
    /// Local, session-only completion tracking -- lets a user check off
    /// exercises as they work through the plan (real feedback: "give the
    /// user a better experience when working out"). Keyed by AIExercise.id
    /// (== name), which planValidation's duplicate-prevention now keeps
    /// unique across an entire session, warm-up/blocks/cool-down included.
    @State private var checkedExerciseIDs: Set<String> = []

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

            // Always-visible, no interaction needed -- users who don't
            // already know what RPE means otherwise see "RPE 7/10" on
            // every single exercise with zero context (real user
            // feedback: "some users might not even know what RPE means").
            Text("RPE = Rate of Perceived Exertion, how hard a set feels (1 = very easy, 10 = maximum effort).")
                .font(.caption2)
                .foregroundStyle(.secondary)
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

    private var allExercises: [AIExercise] {
        plan.warmUp + plan.blocks.flatMap(\.exercises) + plan.coolDown
    }

    private func aiPhaseSection(title: String, exercises: [AIExercise]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
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
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                if block.rounds > 1 {
                    Text("\(block.rounds) rounds, rest \(block.restBetweenRounds)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 10)
            // Clearly optional/skippable -- the finisher used to be
            // mandatory ("no exceptions") on every plan; it's now included
            // deterministically only on eligible days (see
            // finisherCatalog.ts's decideFinisher), and this badge is the
            // one place that distinction is visible to the user.
            if block.isFinisher {
                Text(plan.exceptionalFinisher ? "Optional finisher — you're well recovered today" : "Optional finisher — skip it without any penalty")
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.pillFill)
                    .padding(.top, 2)
            }
            ForEach(block.exercises) { exercise in
                aiExerciseRow(exercise)
            }
        }
    }

    private func aiExerciseRow(_ exercise: AIExercise) -> some View {
        let isDone = checkedExerciseIDs.contains(exercise.id)
        return HStack(alignment: .top, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isDone {
                        checkedExerciseIDs.remove(exercise.id)
                    } else {
                        checkedExerciseIDs.insert(exercise.id)
                    }
                }
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(isDone ? SomaTokens.success : SomaTokens.ink4)
            }
            .buttonStyle(.plain)
            .padding(.top, 7)

            Button {
                selectedExercise = exercise
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(exercise.name)
                            .font(.subheadline.bold())
                            .strikethrough(isDone, color: SomaTokens.success)
                            .foregroundStyle(isDone ? SomaTokens.ink3 : SomaTokens.ink)
                        Image(systemName: "photo.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(exercise.durationMinutes) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(exercise.sets) sets × \(exercise.reps) — \(exercise.weightGuidance) — \(exercise.intensity)")
                        .font(.caption)
                        .foregroundStyle(Theme.pillFill)
                    // Only populated by the gym-photo-workout flow -- nil for the
                    // normal generate-workout-plan flow.
                    if let targetArea = exercise.targetArea {
                        Text("Targets: \(targetArea)")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                    Text(exercise.instructions)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: SomaTokens.rMD, style: .continuous)
                .fill(isDone ? SomaTokens.successSoft : Color.clear)
        )
        .animation(.easeInOut(duration: 0.18), value: isDone)
    }
}
