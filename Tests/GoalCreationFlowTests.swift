import XCTest
@testable import Soma

/// SGP-B6: the create/ack/baseline sequencing both goal screens share.
/// Failure mode pinned: BUG-78 -- a failed baseline insert must surface
/// and retry WITHOUT re-creating the goal (a re-create 409s on the
/// one-active-goal index and the chart silently loses its first point).
final class GoalCreationFlowTests: XCTestCase {

    private func decodeGoal(id: String = "ug-1") throws -> UserGoal {
        try JSONDecoder().decode(UserGoal.self, from: Data("""
        {"id": "\(id)", "goal_id": "g-vjump", "kind": "preset",
         "target_kind": "metric", "status": "active", "baseline_value": 42}
        """.utf8))
    }

    private func metricRequest(baseline: Double? = 42) -> CreateGoalRequest {
        var request = CreateGoalRequest(kind: .preset, targetKind: .metric)
        request.goalId = "g-vjump"
        request.baselineValue = baseline
        return request
    }

    private func decodeConflict() throws -> GoalSafetyConflict {
        try JSONDecoder().decode(GoalSafetyConflict.self, from: Data(
            #""This assignment may conflict with a noted knee injury.""#.utf8))
    }

    private struct StubError: Error {}

    func testConflictsShortCircuitBeforeAnyWrite() async throws {
        var inserts = 0
        var onCreatedRuns = 0
        let conflict = try decodeConflict()

        let outcome = try await GoalCreationFlow.start(
            metricRequest(),
            create: { _ in .conflicts([conflict]) },
            insertBaseline: { _, _ in inserts += 1 },
            onCreated: { onCreatedRuns += 1 }
        )

        guard case .conflicts(let found) = outcome else {
            return XCTFail("Expected .conflicts, got \(outcome)")
        }
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(inserts, 0, "Nothing may be written before acknowledgment")
        XCTAssertEqual(onCreatedRuns, 0)
    }

    func testBaselineInsertFailureSurfacesTheCreatedGoal() async throws {
        var onCreatedRuns = 0
        let created = try decodeGoal()

        let outcome = try await GoalCreationFlow.start(
            metricRequest(),
            create: { _ in .created(created) },
            insertBaseline: { _, _ in throw StubError() },
            onCreated: { onCreatedRuns += 1 }
        )

        guard case .baselineFailed(let goal) = outcome else {
            return XCTFail("Expected .baselineFailed, got \(outcome)")
        }
        XCTAssertEqual(goal.id, "ug-1", "The caller needs the created row to retry")
        XCTAssertEqual(onCreatedRuns, 0, "A half-created goal must not read as success")
    }

    func testRetryInsertsBaselineWithoutRecreatingTheGoal() async throws {
        var creates = 0
        var insertedInto: [String] = []
        var onCreatedRuns = 0
        let pending = try decodeGoal(id: "ug-pending")

        let outcome = try await GoalCreationFlow.start(
            metricRequest(),
            retrying: pending,
            create: { _ in creates += 1; return .created(pending) },
            insertBaseline: { goalID, value in
                insertedInto.append(goalID)
                XCTAssertEqual(value, 42)
            },
            onCreated: { onCreatedRuns += 1 }
        )

        guard case .started = outcome else {
            return XCTFail("Expected .started, got \(outcome)")
        }
        XCTAssertEqual(creates, 0, "Retry must NOT re-create — it would 409 on the one-active index (BUG-78)")
        XCTAssertEqual(insertedInto, ["ug-pending"], "Only the baseline insert reruns")
        XCTAssertEqual(onCreatedRuns, 1)
    }

    func testGoalWithoutNumericBaselineSkipsTheInsert() async throws {
        var inserts = 0
        var onCreatedRuns = 0
        let created = try decodeGoal()

        let outcome = try await GoalCreationFlow.start(
            metricRequest(baseline: nil),
            create: { _ in .created(created) },
            insertBaseline: { _, _ in inserts += 1 },
            onCreated: { onCreatedRuns += 1 }
        )

        guard case .started = outcome else {
            return XCTFail("Expected .started, got \(outcome)")
        }
        XCTAssertEqual(inserts, 0, "Stage/words goals have no numeric first point to insert")
        XCTAssertEqual(onCreatedRuns, 1)
    }
}
