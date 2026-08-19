import XCTest
@testable import Soma

/// Sport-goal models decode server-owned rows whose column set and enum
/// vocabularies keep growing. These pin the forward-compat rules: unknown
/// enum values become `.unknown`, missing columns become nil/defaults --
/// never a thrown decode that blanks a screen.
final class SportGoalsDecodingTests: XCTestCase {

    func testSportGoalDecodesMinimalRow() throws {
        let goal = try JSONDecoder().decode(SportGoal.self, from: Data("""
        {"id": "g1", "sport_id": "s1", "key": "vertical_jump", "name": "Jump higher", "kind": "metric", "unit": "cm"}
        """.utf8))
        XCTAssertEqual(goal.kind, .metric)
        XCTAssertEqual(goal.targetTable, [])
        XCTAssertEqual(goal.promiseLine, "Measurable in cm")
    }

    func testSportGoalUnknownKindDecodesAsUnknown() throws {
        let goal = try JSONDecoder().decode(SportGoal.self, from: Data("""
        {"id": "g1", "sport_id": "s1", "key": "k", "name": "N", "kind": "streak"}
        """.utf8))
        XCTAssertEqual(goal.kind, .unknown)
    }

    func testTargetTableArrayAndBandLookup() throws {
        let goal = try JSONDecoder().decode(SportGoal.self, from: Data("""
        {"id": "g1", "sport_id": "s1", "key": "k", "name": "N", "kind": "metric", "unit": "cm",
         "target_table": [
           {"min": 0, "max": 40, "gain_low": 4, "gain_high": 8, "weeks_low": 8, "weeks_high": 10},
           {"min": 40, "max": 60, "gain_low": 3, "gain_high": 6, "weeks_low": 10, "weeks_high": 12}
         ]}
        """.utf8))
        let band = goal.band(forBaseline: 45)
        XCTAssertEqual(band?.gainLow, 3)
        XCTAssertEqual(band?.weeksHigh, 12)
        XCTAssertTrue(band?.hasHonestTarget ?? false)
    }

    func testTargetTableDictKeyedByStageLabels() throws {
        let goal = try JSONDecoder().decode(SportGoal.self, from: Data("""
        {"id": "g1", "sport_id": "s1", "key": "k", "name": "Crow pose", "kind": "milestone",
         "target_table": {"Never tried": {"weeks_low": 8, "weeks_high": 10}, "Feet lift": {"weeks_low": 4, "weeks_high": 6}}}
        """.utf8))
        XCTAssertEqual(Set(goal.stageLabels), ["Never tried", "Feet lift"])
        XCTAssertNotNil(goal.band(forStage: "Feet lift"))
    }

    func testTargetTableSeededWrapperShapeAndLevelLookup() throws {
        // Byte-for-byte the shape 20260803130000_seed_sport_goal_catalog.sql
        // ships: a wrapper object, level-keyed bands, horizon_weeks_* names.
        let goal = try JSONDecoder().decode(SportGoal.self, from: Data("""
        {"id": "g1", "sport_id": "s1", "key": "k", "name": "Jump higher", "kind": "metric", "unit": "cm",
         "measurement_protocol": "1. Chalk fingertips. 2. Jump and mark. 3. Same wall every time.",
         "target_table": {
           "unit": "cm",
           "bands": {
             "novice": {"gain_low": 3, "gain_high": 6, "gain_pct": "8-15", "horizon_weeks_low": 10, "horizon_weeks_high": 12},
             "advanced": {"gain_low": 1, "gain_high": 2, "horizon_weeks_low": 8, "horizon_weeks_high": 12}
           },
           "dose": "2-3 sessions/wk",
           "source_note": "Markovic 2007"
         }}
        """.utf8))
        XCTAssertEqual(goal.targetTable.count, 2)
        XCTAssertFalse(goal.protocolLines.isEmpty)
        // Level-keyed bands carry no min/max, so baseline lookup must miss
        // and the experience-level fallback must hit.
        XCTAssertNil(goal.band(forBaseline: 45))
        let novice = goal.band(forLevel: nil)
        XCTAssertEqual(novice?.gainLow, 3)
        XCTAssertEqual(novice?.weeksLow, 10)
        XCTAssertTrue(novice?.hasHonestTarget ?? false)
        XCTAssertEqual(goal.band(forLevel: .advanced)?.gainHigh, 2)
    }

    func testUserGoalDecodesWithUnknownStatusAndMissingColumns() throws {
        let goal = try JSONDecoder().decode(UserGoal.self, from: Data("""
        {"id": "u1", "kind": "preset", "target_kind": "metric", "status": "archived"}
        """.utf8))
        XCTAssertEqual(goal.status, .unknown)
        XCTAssertNil(goal.baselineValue)
        XCTAssertNil(goal.horizonWeeks)
        XCTAssertNil(goal.weekLine)
    }

    func testUserGoalCustomFieldsAndCommitment() throws {
        let goal = try JSONDecoder().decode(UserGoal.self, from: Data("""
        {"id": "u1", "kind": "custom", "target_kind": "commitment", "status": "active",
         "duration_weeks": 8, "frequency_per_week": 3, "coach_name": "Elena",
         "schedule_rule": "before_court_days", "court_days": [2, 5]}
        """.utf8))
        XCTAssertEqual(goal.committedSessions, 24)
        XCTAssertEqual(goal.scheduleRule, .beforeCourtDays)
        XCTAssertEqual(goal.displayName(in: nil), "Coach Elena's task")
    }

    func testMeasurementUnknownKindAndDayString() throws {
        let m = try JSONDecoder().decode(GoalMeasurement.self, from: Data("""
        {"id": "m1", "user_goal_id": "u1", "kind": "warmup_check", "value": 41.5, "measured_at": "2026-08-03T09:15:00Z"}
        """.utf8))
        XCTAssertEqual(m.kind, .unknown)
        XCTAssertEqual(m.dayString.count, 10)
        XCTAssertTrue(m.dayString.hasPrefix("2026-08-0"))
    }

    func testConflictDecodesBothStringAndObjectShapes() throws {
        struct Wrapper: Decodable { let conflicts: [GoalSafetyConflict] }
        let decoded = try JSONDecoder().decode(Wrapper.self, from: Data("""
        {"conflicts": ["includes depth jumps — you have a knee injury noted", {"message": "hot-room work", "pregnancy": true}]}
        """.utf8))
        XCTAssertEqual(decoded.conflicts.count, 2)
        XCTAssertFalse(decoded.conflicts[0].isPregnancyRelated)
        XCTAssertTrue(decoded.conflicts[1].isPregnancyRelated)
    }

    func testAIWorkoutPlanDecodesGoalBlockMarker() throws {
        let plan = try JSONDecoder().decode(AIWorkoutPlan.self, from: Data("""
        {"focus": "F", "warm_up": [], "blocks": [], "cool_down": [],
         "goal_block": {"kind": "preset", "focus": "hangs", "optional": true, "text": "hangs: dead hangs"}}
        """.utf8))
        XCTAssertEqual(plan.goalBlock?.kind, "preset")
        XCTAssertEqual(plan.goalBlock?.text, "hangs: dead hangs")
    }

    func testAIWorkoutPlanGoalBlockAbsentOrNullMeansNoMarker() throws {
        let absent = try JSONDecoder().decode(AIWorkoutPlan.self, from: Data("""
        {"focus": "F", "warm_up": [], "blocks": [], "cool_down": []}
        """.utf8))
        XCTAssertNil(absent.goalBlock)
        let null = try JSONDecoder().decode(AIWorkoutPlan.self, from: Data("""
        {"focus": "F", "warm_up": [], "blocks": [], "cool_down": [], "goal_block": null}
        """.utf8))
        XCTAssertNil(null.goalBlock)
    }

    /// generate-gym-workout's response shape (unchanged by the body-part-
    /// targeting fix -- `bodyPart` was already a top-level field before it;
    /// only which value it resolves to changed) decodes into
    /// `templateBodyPart`, which AIWorkoutPlanSections.swift now reads to
    /// show "Today: Lower Body" above a gym-photo plan's focus line.
    func testAIWorkoutPlanDecodesTemplateBodyPart() throws {
        let plan = try JSONDecoder().decode(AIWorkoutPlan.self, from: Data("""
        {"focus": "F", "warm_up": [], "blocks": [], "cool_down": [], "bodyPart": "lower_body"}
        """.utf8))
        XCTAssertEqual(plan.templateBodyPart, "lower_body")
    }

    /// The normal (non-gym-photo) suggestion flow never sends `bodyPart` at
    /// all -- see generate-workout-plan/index.ts, which never sets it on
    /// its response. Absent-means-nil is what keeps the new "Today: ..."
    /// label from showing on that flow's AI-plan card.
    func testAIWorkoutPlanTemplateBodyPartAbsentMeansNilForTheSuggestionFlow() throws {
        let plan = try JSONDecoder().decode(AIWorkoutPlan.self, from: Data("""
        {"focus": "F", "warm_up": [], "blocks": [], "cool_down": []}
        """.utf8))
        XCTAssertNil(plan.templateBodyPart)
    }

    func testGainRangeFormatting() {
        XCTAssertEqual(SportGoalFormat.gainRange(low: 3, high: 6, unit: "cm"), "+3–6 cm")
        XCTAssertEqual(SportGoalFormat.delta(-1, unit: "cm"), "−1 cm")
        XCTAssertEqual(SportGoalFormat.delta(5, unit: nil), "+5")
    }
}
