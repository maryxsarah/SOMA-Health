import Foundation

/// parse-goal-assignment's response. `parsed` is nil whenever
/// lowConfidence is true -- CustomGoalFormView must not touch any field
/// in that case.
struct GoalAssignmentParseResult: Decodable {
    let parsed: ParsedAssignment?
    let confidence: Double
    let lowConfidence: Bool
}

struct ParsedAssignment: Decodable {
    let givenText: String?
    let workoutText: String?
    let coachName: String?
    let durationWeeks: Int?
    let frequencyPerWeek: Int?
    let scheduleRule: GoalScheduleRule?
    let scheduleDays: [Int]?
    let courtDays: [Int]?
}
