import Foundation

/// The one shared start-a-goal sequence (request → conflicts → created →
/// baseline insert → onCreated) -- used by BOTH GoalStartView and
/// CustomGoalFormView so neither drifts from the other.
enum GoalCreationFlow {
    enum Outcome {
        /// Needs the explicit-acknowledgment pass before anything is written.
        case conflicts([GoalSafetyConflict])
        /// Goal created (and baseline saved, when one was given); onCreated ran.
        case started
        /// Goal created but the chart's first point wasn't -- the caller must
        /// surface this and let the user retry via `retrying:`.
        case baselineFailed(created: UserGoal)
    }

    /// Pass `retrying` (a goal from a previous `.baselineFailed`) to retry
    /// just the baseline insert without re-creating the goal.
    static func start(
        _ request: CreateGoalRequest,
        retrying: UserGoal? = nil,
        onCreated: () async -> Void
    ) async throws -> Outcome {
        let goal: UserGoal
        if let retrying {
            goal = retrying
        } else {
            switch try await SupabaseClient.shared.createGoal(request) {
            case .conflicts(let found):
                return .conflicts(found)
            case .created(let created):
                goal = created
            }
        }
        // The baseline is the chart's first real data point -- a failure here
        // is surfaced, never swallowed into a silently empty chart.
        if let value = request.baselineValue {
            do {
                try await SupabaseClient.shared.insertMeasurement(userGoalId: goal.id, kind: .baseline, value: value)
            } catch {
                return .baselineFailed(created: goal)
            }
        }
        await onCreated()
        return .started
    }
}
