import Foundation

/// Conformance lets any fixed-choice enum plug into the generic
/// SingleSelectQuestionView/MultiSelectQuestionView templates without
/// per-screen boilerplate.
protocol SurveyOption: Identifiable, CaseIterable, Hashable where AllCases: RandomAccessCollection {
    var displayName: String { get }
    var systemImageName: String { get }
    var subtitle: String? { get }
}

extension SurveyOption {
    var subtitle: String? { nil }
}

extension Sex: SurveyOption {}
extension WorkoutFrequency: SurveyOption {}
extension ReferralSource: SurveyOption {}
extension DietType: SurveyOption {
    var systemImageName: String { "leaf.fill" }
}
extension AccomplishmentGoal: SurveyOption {}
extension BlockerTag: SurveyOption {}

extension GoalTag: SurveyOption {
    var systemImageName: String {
        switch self {
        case .loseWeight: "arrow.down.circle.fill"
        case .maintain: "equal.circle.fill"
        case .buildStrength: "figure.strengthtraining.traditional"
        case .gainMuscle: "dumbbell.fill"
        case .leanerToned: "figure.run"
        case .moreSculpted: "figure.core.training"
        case .cardioEndurance: "heart.circle.fill"
        case .improveFlexibility: "figure.flexibility"
        case .betterSleep: "moon.zzz.fill"
        case .generalFitness: "sparkles"
        case .activeRecovery: "figure.walk"
        case .other: "ellipsis.circle.fill"
        }
    }
}
