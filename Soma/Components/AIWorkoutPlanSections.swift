import SwiftUI

/// Renders an AIWorkoutPlan's focus/warm-up/blocks/cool-down -- shared by
/// RecommendationDetailView (AI-generated workout card) and
/// GymPhotoWorkoutView (gym-photo result screen), so both consume the same
/// AIWorkoutPlan/AIWorkoutBlock/AIExercise shape without bespoke UI.
struct AIWorkoutPlanView: View {
    let plan: AIWorkoutPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(plan.focus)
                .font(.subheadline.bold())
                .padding(.top, 4)
            aiPhaseSection(title: "Warm-up", exercises: plan.warmUp)
            ForEach(plan.blocks) { block in
                aiBlockSection(block)
            }
            aiPhaseSection(title: "Cool-down", exercises: plan.coolDown)
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
            ForEach(block.exercises) { exercise in
                aiExerciseRow(exercise)
            }
        }
    }

    private func aiExerciseRow(_ exercise: AIExercise) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(exercise.name)
                    .font(.subheadline.bold())
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
    }
}
