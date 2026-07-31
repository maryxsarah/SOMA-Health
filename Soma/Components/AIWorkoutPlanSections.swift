import SwiftUI

/// Renders an AIWorkoutPlan's focus/warm-up/blocks/cool-down -- shared by
/// RecommendationDetailView (AI-generated workout card) and
/// GymPhotoWorkoutView (gym-photo result screen), so both consume the same
/// AIWorkoutPlan/AIWorkoutBlock/AIExercise shape without bespoke UI.
struct AIWorkoutPlanView: View {
    let plan: AIWorkoutPlan

    @State private var selectedExercise: AIExercise?

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
            ForEach(plan.blocks) { block in
                aiBlockSection(block)
            }
            aiPhaseSection(title: "Cool-down", exercises: plan.coolDown)
        }
        .sheet(item: $selectedExercise) { exercise in
            ExerciseDetailView(exercise: exercise)
        }
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
        Button {
            selectedExercise = exercise
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(exercise.name)
                        .font(.subheadline.bold())
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
}
