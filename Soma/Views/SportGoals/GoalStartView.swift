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
    // Scheduling -- same fields/UI as CustomGoalFormView's, minus the
    // duration-weeks stepper (presets get their horizon from the band).
    @State private var frequencyPerWeek = 3
    @State private var scheduleRule: GoalScheduleRule?
    @State private var scheduleDays: Set<Int> = []
    @State private var courtDays: Set<Int> = []
    @State private var showFrequencySheet = false

    /// `seedStage` is for SomaSnapshotTests only -- renders the milestone
    /// target block without a tap.
    init(goal: SportGoal, sport: Sport?, prefillBaseline: Double? = nil, seedStage: String? = nil, onCreated: @escaping () async -> Void) {
        self.goal = goal
        self.sport = sport
        self.prefillBaseline = prefillBaseline
        self.onCreated = onCreated
        let range = goal.entryRange
        let mid = (range.lowerBound + range.upperBound) / 2
        _baselineValue = State(initialValue: prefillBaseline ?? mid.rounded())
        _hasEnteredValue = State(initialValue: prefillBaseline != nil)
        _selectedStage = State(initialValue: seedStage)
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
                    scheduleCard
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
                    SomaButton(title: LocalizedStringKey(isCreating
                        ? String(localized: "goalCreation.button.starting", defaultValue: "Starting…", comment: "Label on the primary CTA button while a goal creation request is in flight")
                        : String(localized: "goalCreation.button.startBlock", defaultValue: "Start the block", comment: "Label on the primary CTA button that creates and starts the goal block")
                    ), size: .lg, variant: .primary, isEnabled: !isCreating) {
                        Task { await create(acknowledged: false) }
                    }
                    Text(String(localized: "goalStart.footer.startsTomorrow", defaultValue: "Your goal block starts with tomorrow's plan.", comment: "Footer note under the Start the block button, explaining the block begins with tomorrow's scheduled plan"))
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
        // Attached here, not inside ScheduleFrequencyPicker -- scheduleCard
        // only renders once `hasBaseline` is true (see body above), and a
        // `.sheet` attached to a view inside a conditional `if` branch is
        // unreliable in SwiftUI. This root ScrollView is unconditional.
        .sheet(isPresented: $showFrequencySheet) {
            ScheduleRulesSheet(scheduleRule: $scheduleRule, scheduleDays: $scheduleDays, courtDays: $courtDays)
        }
        .onChange(of: showFrequencySheet) { old, new in
            NSLog("DIAG showFrequencySheet %@ -> %@", old ? "true" : "false", new ? "true" : "false")
        }
        .onChange(of: hasBaseline) { old, new in
            NSLog("DIAG hasBaseline %@ -> %@", old ? "true" : "false", new ? "true" : "false")
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
                Text(String(localized: "goalStart.protocolCard.title", defaultValue: "How to measure", comment: "Card heading above the numbered list of steps for measuring the goal's baseline"))
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
                // Chips carry the raw ladder key (what the server stores);
                // only their titles are display copy.
                if !goal.stageLadder.isEmpty {
                    FlowLayout {
                        ForEach(goal.stageLadder, id: \.self) { key in
                            SomaChip(title: LocalizedStringKey(SportGoal.stageDisplayName(key)), isSelected: selectedStage == key) {
                                selectedStage = key
                            }
                        }
                    }
                } else if goal.stageLabels.isEmpty {
                    ruler
                } else {
                    FlowLayout {
                        ForEach(goal.stageLabels, id: \.self) { stage in
                            SomaChip(title: LocalizedStringKey(stage), isSelected: selectedStage == stage) {
                                selectedStage = stage
                            }
                        }
                    }
                }
            case .qualitative:
                TextField(String(localized: "goalStart.qualitativeTarget.placeholder", defaultValue: "Your target, in your own words", comment: "Placeholder text in the multi-line field where the user describes their qualitative goal target"), text: $qualitativeTarget, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassCardFlat(cornerRadius: SomaTokens.rXL)
            default:
                ruler
            }
        }
    }

    private var entryTitle: String {
        switch goal.kind {
        case .milestone: String(localized: "goalStart.entryTitle.milestone", defaultValue: "Where are you today?", comment: "Heading above the entry field for a milestone-based goal, asking the user's current stage")
        case .qualitative: String(localized: "goalStart.entryTitle.qualitative", defaultValue: "What does done look like?", comment: "Heading above the entry field for a qualitative goal, asking the user to describe their target")
        default: String(localized: "goalStart.entryTitle.metric", defaultValue: "Your baseline today", comment: "Heading above the entry field for a metric-based goal, asking for the user's current baseline value")
        }
    }

    private var ruler: some View {
        RulerNumberPicker(value: $baselineValue, range: goal.entryRange, unit: SportGoalFormat.localizedUnit(goal.unit))
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
                Text(String(localized: "goalStart.targetBlock.title", defaultValue: "A realistic target", comment: "Small kicker heading above the revealed target range for a metric or milestone goal"))
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(SomaTokens.ink3)
                if let programName = band.programName {
                    Text(programName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SomaTokens.ink)
                }
                Text(SportGoalFormat.gainRange(low: gainLow, high: gainHigh, unit: goal.unit))
                    .font(Theme.display)
                    .foregroundStyle(SomaTokens.accent)
                Text(String(localized: "goalStart.targetBlock.metricSubtitle", defaultValue: "in \(weeksLow)–\(weeksHigh) weeks · re-test around \(retestRange(weeksLow: weeksLow, weeksHigh: weeksHigh))", comment: "Subtitle under the target range: the week range to reach it, and the date range to re-test. weeksLow/weeksHigh are integers, the last value is an already-formatted date range string"))
                    .font(.system(size: 14))
                    .foregroundStyle(SomaTokens.ink2)
                GoalPhaseStrip(current: nil)
                    .padding(.top, 4)
                Text(String(localized: "goalStart.targetBlock.confirmNote", defaultValue: "In ~5 days we'll confirm your baseline — second attempts usually score higher.", comment: "Small note explaining the baseline will be re-confirmed a few days in"))
                    .font(.system(size: 12))
                    .foregroundStyle(SomaTokens.ink3)
            }
        } else if goal.kind == .milestone, let selectedStage,
                  let index = goal.stageIndex(of: selectedStage),
                  goal.stageLadder.indices.contains(index + 1) {
            // The next rung of the ladder IS the target -- honest horizon
            // from the evidence band, never a number (guide 03 milestone row).
            CardView {
                Text(String(localized: "goalStart.targetBlock.title", defaultValue: "A realistic target", comment: "Small kicker heading above the revealed target range for a metric or milestone goal"))
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(SomaTokens.ink3)
                Text(SportGoal.stageDisplayName(goal.stageLadder[index + 1]))
                    .font(Theme.display)
                    .foregroundStyle(SomaTokens.accent)
                if let band = goal.band(forLevel: experienceLevel),
                   let weeksLow = band.weeksLow, let weeksHigh = band.weeksHigh {
                    Text(String(localized: "goalStart.targetBlock.milestoneSubtitle", defaultValue: "next stage · usually \(weeksLow)–\(weeksHigh) weeks", comment: "Subtitle under the next milestone stage name, showing the typical week range to reach it. weeksLow/weeksHigh are integers"))
                        .font(.system(size: 14))
                        .foregroundStyle(SomaTokens.ink2)
                } else {
                    Text(String(localized: "goalStart.targetBlock.milestoneFallback", defaultValue: "the next stage on the ladder", comment: "Fallback subtitle under the next milestone stage name when no typical timeframe is available"))
                        .font(.system(size: 14))
                        .foregroundStyle(SomaTokens.ink2)
                }
                Text(String(localized: "goalStart.targetBlock.milestoneCaption", defaultValue: "Stage-based — no numbers needed.", comment: "Small caption clarifying this milestone target has no numeric target"))
                    .font(.system(size: 12))
                    .foregroundStyle(SomaTokens.ink3)
            }
        } else if goal.kind == .qualitative {
            CardView {
                Text(String(localized: "goalStart.targetBlock.qualitativeTitle", defaultValue: "Your target", comment: "Small kicker heading above the user's own written target for a qualitative goal"))
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(SomaTokens.ink3)
                Text(qualitativeTarget)
                    .font(SomaType.metric(20))
                Text(String(localized: "goalStart.targetBlock.qualitativeCaption", defaultValue: "Progress here is sessions done plus your own check-in — no invented numbers.", comment: "Small caption clarifying how progress is tracked for a qualitative goal"))
                    .font(.system(size: 12))
                    .foregroundStyle(SomaTokens.ink3)
            }
        } else {
            // Baseline recorded but the evidence table has no band for it
            // -- record honestly, promise nothing.
            CardView {
                Text(String(localized: "goalStart.targetBlock.recordedTitle", defaultValue: "Baseline recorded", comment: "Small kicker heading shown when a baseline was entered but no evidence band matched it"))
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(SomaTokens.ink3)
                Text(baselineText)
                    .font(Theme.display)
                Text(String(localized: "goalStart.targetBlock.confirmNote", defaultValue: "In ~5 days we'll confirm your baseline — second attempts usually score higher.", comment: "Small note explaining the baseline will be re-confirmed a few days in"))
                    .font(.system(size: 12))
                    .foregroundStyle(SomaTokens.ink3)
            }
        }
    }

    private var baselineText: String {
        if goal.kind == .milestone, let selectedStage { return SportGoal.stageDisplayName(selectedStage) }
        return SportGoalFormat.value(baselineValue, unit: goal.unit)
    }

    private func retestRange(weeksLow: Int, weeksHigh: Int) -> String {
        let cal = Calendar.current
        let lo = cal.date(byAdding: .day, value: weeksLow * 7, to: Date()) ?? Date()
        let hi = cal.date(byAdding: .day, value: weeksHigh * 7, to: Date()) ?? Date()
        return SportGoalFormat.dateRange(lo, hi)
    }

    // MARK: - Schedule

    private var scheduleCard: some View {
        CardView {
            Text(String(localized: "goalCreation.schedule.title", defaultValue: "Schedule", comment: "Card heading above the frequency/schedule picker for a goal block"))
                .font(.body.bold())
            ScheduleFrequencyPicker(
                frequencyPerWeek: $frequencyPerWeek,
                scheduleRule: $scheduleRule,
                scheduleDays: $scheduleDays,
                courtDays: $courtDays,
                showFrequencySheet: $showFrequencySheet
            )
        }
    }

    private var effectiveFrequency: Int {
        ScheduleFrequencyPicker.effectiveFrequency(
            frequencyPerWeek: frequencyPerWeek,
            scheduleRule: scheduleRule,
            scheduleDays: scheduleDays,
            courtDays: courtDays
        )
    }

    // MARK: - Create

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
        request.frequencyPerWeek = effectiveFrequency
        request.scheduleRule = scheduleRule
        if scheduleRule == .weekdays { request.scheduleDays = scheduleDays.sorted() }
        if scheduleRule == .beforeCourtDays { request.courtDays = courtDays.sorted() }

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
                errorMessage = String(localized: "goalCreation.error.baselineFailed", defaultValue: "Your goal started, but the baseline couldn't be saved — tap the button again to retry.", comment: "Error shown when goal creation succeeded but saving the baseline measurement failed")
            }
        } catch {
            errorMessage = String(localized: "goalCreation.error.startFailed", defaultValue: "Couldn't start the goal. Try again.", comment: "Generic error shown when starting a goal fails")
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
