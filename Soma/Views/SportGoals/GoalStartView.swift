import SwiftUI

/// A2 -- protocol, baseline entry, and the live target reveal on ONE
/// screen. The target block appearing after entry IS the emotional peak.
struct GoalStartView: View {
    let goal: SportGoal
    let sport: Sport?
    /// Non-nil when chaining a next/extension block from a finished one.
    let prefillBaseline: Double?
    let onCreated: () async -> Void

    @State private var baselineValue: Double
    @State private var hasEnteredValue: Bool
    @State private var selectedStage: String?
    @State private var qualitativeTarget = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var conflicts: [GoalSafetyConflict] = []
    @State private var experienceLevel: ExperienceLevel?
    /// Set when the goal was created but its baseline insert failed --
    /// the next tap retries only the baseline (see GoalCreationFlow).
    @State private var pendingBaselineGoal: UserGoal?

    init(goal: SportGoal, sport: Sport?, prefillBaseline: Double? = nil, onCreated: @escaping () async -> Void) {
        self.goal = goal
        self.sport = sport
        self.prefillBaseline = prefillBaseline
        self.onCreated = onCreated
        let range = goal.entryRange
        let mid = (range.lowerBound + range.upperBound) / 2
        _baselineValue = State(initialValue: prefillBaseline ?? mid.rounded())
        _hasEnteredValue = State(initialValue: prefillBaseline != nil)
    }

    private var hasBaseline: Bool {
        switch goal.kind {
        case .metric: hasEnteredValue
        case .milestone: selectedStage != nil
        case .qualitative: !qualitativeTarget.trimmingCharacters(in: .whitespaces).isEmpty
        case .unknown: false
        }
    }

    /// The evidence band matching the entered baseline -- the ONLY source
    /// of any promised number. Seeded bands are level-keyed, so the profile's
    /// experience level is the fallback lookup.
    private var matchedBand: SportGoalTargetBand? {
        switch goal.kind {
        case .metric:
            hasEnteredValue
                ? (goal.band(forBaseline: baselineValue) ?? goal.band(forLevel: experienceLevel))
                : nil
        case .milestone: selectedStage.flatMap(goal.band(forStage:))
        default: nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                protocolCard
                entryCard
                if hasBaseline {
                    targetBlock
                }
                if !conflicts.isEmpty {
                    GoalConflictWarningView(conflicts: conflicts) {
                        Task { await create(acknowledged: true) }
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(SomaTokens.danger)
                }
                if hasBaseline, conflicts.isEmpty {
                    SomaButton(title: isCreating ? "Starting…" : "Start the block", size: .lg, variant: .primary, isEnabled: !isCreating) {
                        Task { await create(acknowledged: false) }
                    }
                    Text("Your goal block starts with tomorrow's plan.")
                        .font(.system(size: 12))
                        .foregroundStyle(SomaTokens.ink3)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard experienceLevel == nil,
                  let userId = SupabaseClient.shared.currentUserID,
                  let profile = try? await SupabaseClient.shared.fetchProfile(id: userId) else { return }
            experienceLevel = profile.experienceLevel
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sport {
                Text(sport.name.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(SomaTokens.ink3)
            }
            Text(goal.name)
                .font(Theme.display)
        }
    }

    @ViewBuilder
    private var protocolCard: some View {
        let lines = goal.protocolLines
        if !lines.isEmpty {
            CardView {
                Text("How to measure")
                    .font(.body.bold())
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(SomaTokens.accent)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(SomaTokens.accentSoft))
                        Text(line)
                            .font(.system(size: 13.5))
                            .foregroundStyle(SomaTokens.ink2)
                    }
                }
            }
        }
    }

    private var entryCard: some View {
        CardView {
            Text(entryTitle)
                .font(.body.bold())
            switch goal.kind {
            case .milestone:
                if goal.stageLabels.isEmpty {
                    ruler
                } else {
                    FlowLayout {
                        ForEach(goal.stageLabels, id: \.self) { stage in
                            SomaChip(title: stage, isSelected: selectedStage == stage) {
                                selectedStage = stage
                            }
                        }
                    }
                }
            case .qualitative:
                TextField("Your target, in your own words", text: $qualitativeTarget, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            default:
                ruler
            }
        }
    }

    private var entryTitle: String {
        switch goal.kind {
        case .milestone: "Where are you today?"
        case .qualitative: "What does done look like?"
        default: "Your baseline today"
        }
    }

    private var ruler: some View {
        RulerNumberPicker(value: $baselineValue, range: goal.entryRange, unit: goal.unit)
            .onChange(of: baselineValue) { _, _ in hasEnteredValue = true }
    }

    /// The live reveal: an honest range straight from the evidence table --
    /// never rendered without a matching band.
    @ViewBuilder
    private var targetBlock: some View {
        if let band = matchedBand, band.hasHonestTarget,
           let gainLow = band.gainLow, let gainHigh = band.gainHigh,
           let weeksLow = band.weeksLow, let weeksHigh = band.weeksHigh {
            CardView {
                Text("A realistic target")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(SomaTokens.ink3)
                Text(SportGoalFormat.gainRange(low: gainLow, high: gainHigh, unit: goal.unit))
                    .font(Theme.display)
                    .foregroundStyle(SomaTokens.accent)
                Text("in \(weeksLow)–\(weeksHigh) weeks · re-test around \(retestRange(weeksLow: weeksLow, weeksHigh: weeksHigh))")
                    .font(.system(size: 14))
                    .foregroundStyle(SomaTokens.ink2)
                GoalPhaseStrip(current: nil)
                    .padding(.top, 4)
                Text("In ~5 days we'll confirm your baseline — second attempts usually score higher.")
                    .font(.system(size: 12))
                    .foregroundStyle(SomaTokens.ink3)
            }
        } else if goal.kind == .qualitative {
            CardView {
                Text("Your target")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(SomaTokens.ink3)
                Text(qualitativeTarget)
                    .font(.system(size: 20, design: .serif).italic())
                Text("Progress here is sessions done plus your own check-in — no invented numbers.")
                    .font(.system(size: 12))
                    .foregroundStyle(SomaTokens.ink3)
            }
        } else {
            // Baseline recorded but the evidence table has no band for it
            // -- record honestly, promise nothing.
            CardView {
                Text("Baseline recorded")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(SomaTokens.ink3)
                Text(baselineText)
                    .font(Theme.display)
                Text("In ~5 days we'll confirm your baseline — second attempts usually score higher.")
                    .font(.system(size: 12))
                    .foregroundStyle(SomaTokens.ink3)
            }
        }
    }

    private var baselineText: String {
        if goal.kind == .milestone, let selectedStage { return selectedStage }
        return SportGoalFormat.value(baselineValue, unit: goal.unit)
    }

    private func retestRange(weeksLow: Int, weeksHigh: Int) -> String {
        let cal = Calendar.current
        let lo = cal.date(byAdding: .day, value: weeksLow * 7, to: Date()) ?? Date()
        let hi = cal.date(byAdding: .day, value: weeksHigh * 7, to: Date()) ?? Date()
        return SportGoalFormat.dateRange(lo, hi)
    }

    private func create(acknowledged: Bool) async {
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        var request = CreateGoalRequest(kind: .preset, targetKind: targetKind)
        request.goalId = goal.id
        request.acknowledgeConflicts = acknowledged
        switch goal.kind {
        case .metric: request.baselineValue = baselineValue
        case .milestone:
            request.baselineStage = selectedStage
            if goal.stageLabels.isEmpty { request.baselineValue = baselineValue }
        case .qualitative: request.targetText = qualitativeTarget
        case .unknown: break
        }

        do {
            switch try await GoalCreationFlow.start(request, retrying: pendingBaselineGoal, onCreated: onCreated) {
            case .conflicts(let found):
                conflicts = found
            case .started:
                conflicts = []
                pendingBaselineGoal = nil
            case .baselineFailed(let created):
                conflicts = []
                pendingBaselineGoal = created
                errorMessage = "Your goal started, but the baseline couldn't be saved — tap the button again to retry."
            }
        } catch {
            errorMessage = "Couldn't start the goal. Try again."
        }
    }

    private var targetKind: GoalTargetKind {
        switch goal.kind {
        case .metric: .metric
        case .milestone: .milestone
        case .qualitative: .qualitative
        case .unknown: .metric
        }
    }
}
