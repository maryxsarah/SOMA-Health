import SwiftUI

/// A3 -- the goal hub: header + phase strip + ETA, chart, re-test (A4,
/// expanding in place), block history, quiet pause/end. All lifecycle
/// states are variants of this one screen.
struct GoalHubView: View {
    let goal: UserGoal
    let catalog: SportCatalog
    let history: [UserGoal]
    let onChanged: () -> Void
    let onPickNewGoal: () -> Void
    let onNextBlock: (_ goalID: String, _ prefillBaseline: Double?) -> Void
    /// Non-nil only from SomaSnapshotTests: pre-seeds the fetched state so a
    /// lifecycle variant can render without a network round-trip.
    private let seededMeasurements: [GoalMeasurement]?

    init(
        goal: UserGoal,
        catalog: SportCatalog,
        history: [UserGoal],
        onChanged: @escaping () -> Void,
        onPickNewGoal: @escaping () -> Void,
        onNextBlock: @escaping (_ goalID: String, _ prefillBaseline: Double?) -> Void,
        seedMeasurements: [GoalMeasurement]? = nil,
        seedSessionsDone: Int = 0,
        seedNoChangeResult: Bool = false
    ) {
        self.goal = goal
        self.catalog = catalog
        self.history = history
        self.onChanged = onChanged
        self.onPickNewGoal = onPickNewGoal
        self.onNextBlock = onNextBlock
        seededMeasurements = seedMeasurements
        _measurements = State(initialValue: seedMeasurements ?? [])
        _sessionsDone = State(initialValue: seedSessionsDone)
        _retestResult = State(initialValue: seedNoChangeResult ? .noChange : nil)
    }

    @EnvironmentObject private var appState: AppState

    @State private var measurements: [GoalMeasurement] = []
    @State private var sessionsDone = 0
    @State private var retestExpanded = false
    @State private var retestValue: Double = 0
    @State private var retestStage: String?
    @State private var attempts: [Double] = []
    @State private var retestResult: RetestResult?
    @State private var showEndDialog = false
    @State private var resumeNeedsRebaseline = false
    @State private var errorMessage: String?
    @State private var isWorking = false

    private enum RetestEvent {
        case baselineConfirm, checkpoint, final, rebaseline
    }

    private enum RetestResult {
        case confirmed(Double)
        case progress(value: Double, delta: Double)
        case noChange
        case finalResult(achieved: Bool, value: Double, delta: Double)
    }

    // MARK: - Derived

    private var presetGoal: SportGoal? {
        goal.goalId.flatMap(catalog.goal(id:))
    }

    private var unit: String? {
        SportGoalFormat.localizedUnit(goal.kind == .custom ? goal.customMetricUnit : presetGoal?.unit)
    }

    private var noiseBand: Double {
        presetGoal?.noiseBand ?? 0
    }

    /// A preset goal whose sport went dark server-side -- data stays
    /// readable, re-tests and goal blocks stop.
    private var isUnavailable: Bool {
        goal.kind == .preset && goal.goalId != nil && presetGoal == nil
    }

    private var isPaused: Bool { goal.status == .paused }

    // MARK: - Milestone (stage ladder)

    private var isMilestone: Bool { presetGoal?.kind == .milestone }

    /// Raw ladder keys; measurements for a milestone goal store the index
    /// into this ladder -- stages, never invented numbers.
    private var ladder: [String] { presetGoal?.stageLadder ?? [] }

    /// The starting stage as a ladder index (the stored stage is the
    /// milestone counterpart of `baselineValue`).
    private var milestoneBaselineIndex: Double? {
        guard isMilestone, let stage = goal.baselineStage else { return nil }
        return presetGoal?.stageIndex(of: stage).map(Double.init)
    }

    /// Latest known stage: last measurement wins, else the stored baseline.
    private var currentStageIndex: Int? {
        guard isMilestone else { return nil }
        if let last = measurements.last?.value { return Int(last.rounded()) }
        return milestoneBaselineIndex.map(Int.init)
    }

    /// Stage name for a stored measurement value; numeric formatting for
    /// everything that isn't a milestone goal.
    private func measurementText(_ value: Double) -> String {
        guard isMilestone, !ladder.isEmpty else { return SportGoalFormat.value(value, unit: unit) }
        let index = Int(value.rounded())
        guard ladder.indices.contains(index) else { return SportGoalFormat.value(value) }
        return SportGoal.stageDisplayName(ladder[index])
    }

    /// Metric machinery exists for presets with a unit and customs that
    /// defined their own measurable.
    private var hasMetric: Bool {
        if goal.kind == .custom { return goal.customMetricName != nil }
        return presetGoal?.kind == .metric || presetGoal?.kind == .milestone
    }

    /// The confirmed week-1 baseline wins over the first attempt.
    private var officialBaseline: Double? {
        measurements.last(where: { $0.kind == .baselineConfirm })?.value
            ?? measurements.first(where: { $0.kind == .baseline })?.value
            ?? goal.baselineValue
            ?? milestoneBaselineIndex
    }

    private var latestMeasurementDate: Date? {
        measurements.last.flatMap { SportGoalFormat.parseTimestamp($0.measuredAt) }
    }

    /// Detraining rule: the starting point moved only when a re-test sat
    /// OPEN for >4 measurement-free weeks. A long quiet stretch between the
    /// checkpoint and a far-off final is the normal cadence, not staleness
    /// -- keying off "days since last measurement" alone forced a
    /// re-baseline on every on-schedule final.
    private var baselineIsStale: Bool {
        guard let latestMeasurementDate,
              Date().timeIntervalSince(latestMeasurementDate) > 28 * 86400,
              let scheduled = scheduledEvent else { return false }
        return daysUntilOpen(scheduled) <= -28
    }

    private var readinessAllowsMaxTest: Bool {
        let category = appState.currentRecommendation?.category
        return category == .moderate || category == .pushHard
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isUnavailable {
                    unavailableBanner
                } else if isPaused {
                    pausedBanner
                }
                if resumeNeedsRebaseline {
                    inlineNotice("Your starting point moved — we'll re-measure first.")
                }

                header

                baselineConfirmNote

                if !isPaused, !isUnavailable {
                    upcomingCard
                }

                if goal.kind == .custom || presetGoal?.kind == .qualitative {
                    sessionsCard
                }
                if hasMetric {
                    if isMilestone {
                        stageCard
                    } else {
                        chartCard
                    }
                    if !isPaused, !isUnavailable {
                        retestSection
                    }
                }
                if goal.kind == .custom, sessionsDone > 0 {
                    coachShareCard
                }

                if !completedHistory.isEmpty {
                    historySection
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(SomaTokens.danger)
                }

                footer
            }
            .padding(20)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("End this goal", role: .destructive) { showEndDialog = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(SomaTokens.ink3)
                        .accessibilityLabel("Goal options")
                }
            }
        }
        .confirmationDialog(
            "End this goal?",
            isPresented: $showEndDialog,
            titleVisibility: .visible
        ) {
            Button("Pause instead") { Task { await pause() } }
            Button("End this goal", role: .destructive) { Task { await end() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your measurements stay in your history.")
        }
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrowText)
                .font(.system(size: 12, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(SomaTokens.ink3)
            Text(goal.displayName(in: catalog))
                .font(Theme.display)
            if let programName = goal.programName {
                Text(programName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SomaTokens.accent)
            }
            if !isPaused {
                GoalPhaseStrip(current: goal.currentPhase)
                    .padding(.vertical, 4)
            }
            etaLines
        }
    }

    /// Custom goals carry no catalog sport, so the sport segment (and its
    /// separator) must vanish cleanly rather than render "· COACH REYES".
    private var eyebrowText: String {
        let trailing: String = if goal.kind == .custom {
            if let coachName = goal.coachName, !coachName.isEmpty {
                String(localized: "goalHub.eyebrow.coachNamed", defaultValue: "COACH \(coachName.uppercased())", comment: "Goal hub eyebrow badge for a custom goal assigned by a named coach, all caps; placeholder is the coach's name, already uppercased")
            } else {
                String(localized: "goalHub.eyebrow.coachTask", defaultValue: "COACH'S TASK", comment: "Goal hub eyebrow badge label for a custom goal with no named coach, all caps")
            }
        } else {
            String(localized: "goalHub.eyebrow.goal", defaultValue: "GOAL", comment: "Goal hub eyebrow badge label for a preset goal, all caps")
        }
        let sport = sportName.uppercased()
        return sport.isEmpty ? trailing : "\(sport) · \(trailing)"
    }

    private var sportName: String {
        presetGoal.flatMap(catalog.sport(for:))?.name ?? ""
    }

    /// Custom goals get the fixed re-check date; presets the sliding ETA
    /// range with a calm slip note.
    @ViewBuilder
    private var etaLines: some View {
        if goal.kind == .custom {
            if let recheck = goal.recheckDate.flatMap(SportGoalFormat.parseDay) {
                Text("Re-check with your coach around \(SportGoalFormat.shortDate(recheck))")
                    .font(.system(size: 14))
                    .foregroundStyle(SomaTokens.ink2)
            }
        } else {
            if let target = goal.targetRangeText(unit: unit),
               let lo = goal.etaStart.flatMap(SportGoalFormat.parseDay),
               let hi = goal.etaEnd.flatMap(SportGoalFormat.parseDay) {
                Text("≈ \(target) by \(SportGoalFormat.dateRange(lo, hi))")
                    .font(.system(size: 14))
                    .foregroundStyle(SomaTokens.ink2)
            }
            // Milestone target: the next rung, an honest window, no numbers.
            if isMilestone, let index = currentStageIndex, ladder.indices.contains(index + 1) {
                let next = SportGoal.stageDisplayName(ladder[index + 1])
                if let horizon = goal.horizonWeeks {
                    Text("\(next) — next stage · usually \(horizon.low)–\(horizon.high) weeks")
                        .font(.system(size: 14))
                        .foregroundStyle(SomaTokens.ink2)
                } else {
                    Text("\(next) — the next stage on the ladder")
                        .font(.system(size: 14))
                        .foregroundStyle(SomaTokens.ink2)
                }
            }
            // A goal "in words" shows the words themselves as its target.
            if presetGoal?.kind == .qualitative, let words = goal.targetText, !words.isEmpty {
                Text("“\(words)”")
                    .font(SomaType.metric(20))
                Text("Progress is sessions done plus your own check-in — no invented numbers.")
                    .font(.system(size: 12))
                    .foregroundStyle(SomaTokens.ink3)
            }
            if let weekLine = goal.weekLine {
                Text(weekLine.prefix(1).uppercased() + weekLine.dropFirst())
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink3)
            }
            if let slip = goal.etaSlipDays, slip > 0 {
                Text(slipLine(slip))
                    .font(.system(size: 12.5))
                    .foregroundStyle(SomaTokens.ink3)
            }
        }
    }

    /// Week-1 double-baseline explainer -- guide 04 renders it as its own
    /// note CARD, not as a third gray line jammed into the header.
    @ViewBuilder
    private var baselineConfirmNote: some View {
        if goal.kind != .custom,
           let start = goal.startDate,
           Date().timeIntervalSince(start) < 7 * 86400,
           !measurements.contains(where: { $0.kind == .baselineConfirm }) {
            Text("Confirm your baseline in ~5 days — second attempts usually score higher. The better of the two becomes your starting point.")
                .font(.system(size: 12.5))
                .foregroundStyle(SomaTokens.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .glassCardFlat(cornerRadius: SomaTokens.rXL)
        }
    }

    /// Neutral, factual, never warn-colored.
    private func slipLine(_ days: Int) -> String {
        if let reason = goal.etaSlipReason, !reason.isEmpty {
            return String(localized: "goalHub.eta.slipWithReason", defaultValue: "Moved +\(days) days — \(reason)", comment: "ETA slip notice with a reason; first placeholder is days moved (always positive), second is a free-text reason")
        }
        return String(localized: "goalHub.eta.slip", defaultValue: "Moved +\(days) days.", comment: "ETA slip notice with no reason given; placeholder is number of days moved (always positive)")
    }

    // MARK: - Banners

    private var unavailableBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Temporarily unavailable")
                .font(.system(size: 13.5, weight: .bold))
            Text("This goal's program is offline right now. Your measurements and history stay right here.")
                .font(.system(size: 13))
                .foregroundStyle(SomaTokens.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCardFlat(cornerRadius: SomaTokens.rXL)
    }

    /// Two calm variants: user pause and safety pause. Never alarm-red.
    private var pausedBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            if goal.pauseReason == .safety {
                Text("Safely paused")
                    .font(.system(size: 13.5, weight: .bold))
                Text("This goal's training isn't recommended for you right now, so it's safely paused. Your data stays put.")
                    .font(.system(size: 13))
                    .foregroundStyle(SomaTokens.ink2)
                Button("Switch to a safe goal") { onPickNewGoal() }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(SomaTokens.accent)
                    .buttonStyle(.plain)
            } else {
                Text("On hold — not counting. Resume anytime.")
                    .font(.system(size: 13.5, weight: .bold))
                HStack(spacing: 16) {
                    Button(isWorking ? "Resuming…" : "Resume") { Task { await resume() } }
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(SomaTokens.accent)
                        .buttonStyle(.plain)
                        .disabled(isWorking)
                    Button("Start a different goal") { onPickNewGoal() }
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(SomaTokens.ink3)
                        .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCardFlat(cornerRadius: SomaTokens.rXL)
    }

    private func inlineNotice(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(SomaTokens.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.accentSoft))
    }

    // MARK: - Upcoming

    /// weekdays/beforeCourtDays get real forward dates; every other rule
    /// gets an honest description instead of a guessed one (see UpcomingSessions).
    private var upcomingCard: some View {
        CardView {
            Text("Upcoming")
                .font(.body.bold())
            switch UpcomingSessions.display(scheduleRule: goal.scheduleRule, scheduleDays: goal.scheduleDays, courtDays: goal.courtDays) {
            case .dates(let dates):
                Text(dates.map(SportGoalFormat.weekdayShort).joined(separator: " · "))
                    .font(.system(size: 15, weight: .semibold))
            case .qualitative(let description):
                Text(description)
                    .font(.system(size: 15, weight: .semibold))
            }
        }
    }

    // MARK: - Sessions (custom & qualitative)

    private var sessionsCard: some View {
        CardView {
            Text("Sessions")
                .font(.body.bold())
            if let committed = goal.committedSessions {
                Text("\(sessionsDone) of \(committed)")
                    .font(Theme.display)
                let fraction = min(Double(sessionsDone) / Double(max(committed, 1)), 1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(SomaTokens.surface4)
                        Capsule().fill(SomaTokens.accent).frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 6)
            } else {
                Text("\(sessionsDone) done since you started")
                    .font(.system(size: 15, weight: .semibold))
            }
        }
    }

    // MARK: - Chart

    /// Milestone progress is the ladder, not a line -- charting stage
    /// indices would dress ordinals up as measurements (copy rule 2).
    private var stageCard: some View {
        CardView {
            Text("Progress")
                .font(.body.bold())
            if let index = currentStageIndex, ladder.indices.contains(index) {
                Text(SportGoal.stageDisplayName(ladder[index]))
                    .font(SomaType.metric(24))
                Text("Stage \(index + 1) of \(ladder.count) — stage-based, no numbers needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No stage recorded yet — your starting stage begins the ladder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chartCard: some View {
        CardView {
            Text("Progress")
                .font(.body.bold())
            let values = measurements.map { (date: $0.dayString, value: $0.value) }
            if values.count >= 2 {
                AxisLabeledTrendChart(values: values)
            } else if values.count == 1 {
                Text(SportGoalFormat.value(values[0].value, unit: unit))
                    .font(SomaType.metric(24))
                Text("Only one data point so far.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No measurements yet — your baseline starts the chart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Re-test (A4, in place)

    /// The ladder position by schedule alone -- staleness is applied on top
    /// in `nextEvent` (and consulted by `baselineIsStale`, so no cycle).
    private var scheduledEvent: RetestEvent? {
        guard goal.status == .active else { return nil }
        // A milestone goal's stored starting stage IS its baseline.
        let hasBaseline = measurements.contains { $0.kind == .baseline } || milestoneBaselineIndex != nil
        let hasConfirm = measurements.contains { $0.kind == .baselineConfirm }
        let hasCheckpoint = measurements.contains { $0.kind == .checkpoint }
        if !hasBaseline { return .rebaseline }
        if !hasConfirm { return .baselineConfirm }
        if !hasCheckpoint { return .checkpoint }
        return .final
    }

    private var nextEvent: RetestEvent? {
        guard let scheduled = scheduledEvent else { return nil }
        if baselineIsStale || resumeNeedsRebaseline { return .rebaseline }
        return scheduled
    }

    /// Days until the next event opens; 0 or negative means it's open now.
    private func daysUntilOpen(_ event: RetestEvent) -> Int {
        guard let start = goal.startDate else { return 0 }
        let cal = Calendar.current
        let elapsed = cal.dateComponents([.day], from: start, to: Date()).day ?? 0
        switch event {
        case .rebaseline: return 0
        case .baselineConfirm: return 5 - elapsed
        case .checkpoint: return 28 - elapsed
        case .final:
            let dueDate = goal.kind == .custom
                ? goal.recheckDate.flatMap(SportGoalFormat.parseDay)
                : goal.etaStart.flatMap(SportGoalFormat.parseDay)
            guard let dueDate else { return 0 }
            return cal.dateComponents([.day], from: Date(), to: dueDate).day ?? 0
        }
    }

    @ViewBuilder
    private var retestSection: some View {
        if let result = retestResult {
            retestResultCard(result)
        } else if let event = nextEvent {
            let daysLeft = daysUntilOpen(event)
            if daysLeft > 0 {
                lockedRow(daysLeft: daysLeft)
            } else if !readinessAllowsMaxTest {
                deferredRow
            } else if retestExpanded {
                retestEntryCard(event)
            } else {
                SomaButton(title: LocalizedStringKey(retestButtonTitle(event)), size: .md, variant: .primary) {
                    retestValue = officialBaseline ?? presetGoal?.entryRange.lowerBound ?? 0
                    retestStage = currentStageIndex.flatMap { ladder.indices.contains($0) ? ladder[$0] : nil }
                    attempts = []
                    retestExpanded = true
                }
            }
        }
    }

    private func retestButtonTitle(_ event: RetestEvent) -> String {
        if isMilestone {
            return switch event {
            case .rebaseline: "Re-check your stage"
            case .baselineConfirm: "Confirm your stage"
            case .checkpoint: "Mid-block check-in"
            case .final: "Final check-in"
            }
        }
        return switch event {
        case .rebaseline: "Re-measure your baseline"
        case .baselineConfirm: "Confirm your baseline"
        case .checkpoint: "Mid-block re-test"
        case .final: "Final re-test"
        }
    }

    private func lockedRowText(daysLeft: Int) -> String {
        if daysLeft >= 14 {
            return String(
                localized: "goalHub.retest.opensInWeeks",
                defaultValue: "Re-test opens in \(Int((Double(daysLeft) / 7).rounded())) weeks",
                comment: "Locked re-test row, pluralized by week count"
            )
        }
        return String(
            localized: "goalHub.retest.opensInDays",
            defaultValue: "Re-test opens in \(daysLeft) days",
            comment: "Locked re-test row, pluralized by day count"
        )
    }

    private func lockedRow(daysLeft: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SomaTokens.ink4)
            Text(lockedRowText(daysLeft: daysLeft))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(SomaTokens.ink3)
            Spacer()
        }
        .padding(14)
        .glassCardFlat(cornerRadius: SomaTokens.rXL)
    }

    private var deferredRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Not today — recovery is low.")
                .font(.system(size: 13.5, weight: .semibold))
            Text("A max test on a depleted day under-reads you. It'll open on your next moderate or better day.")
                .font(.system(size: 12.5))
                .foregroundStyle(SomaTokens.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCardFlat(cornerRadius: SomaTokens.rXL)
    }

    /// A4 entry: one protocol reminder line, then a ruler + attempts for
    /// metric goals or stage chips for milestone goals -- the result
    /// replaces this in place on save.
    private func retestEntryCard(_ event: RetestEvent) -> some View {
        CardView {
            if let reminder = presetGoal?.protocolLines.first {
                Text("Same setup as always: \(reminder.prefix(1).lowercased() + reminder.dropFirst())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isMilestone, !ladder.isEmpty {
                FlowLayout {
                    ForEach(ladder, id: \.self) { key in
                        SomaChip(title: LocalizedStringKey(SportGoal.stageDisplayName(key)), isSelected: retestStage == key) {
                            retestStage = key
                        }
                    }
                }
                SomaButton(
                    title: isWorking ? "Saving…" : "Save \(retestStage.map(SportGoal.stageDisplayName) ?? "your stage")",
                    size: .md,
                    variant: .primary,
                    isEnabled: !isWorking && retestStage != nil
                ) {
                    guard let retestStage, let index = ladder.firstIndex(of: retestStage) else { return }
                    Task { await saveRetest(event, value: Double(index)) }
                }
            } else {
                RulerNumberPicker(
                    value: $retestValue,
                    range: presetGoal?.entryRange ?? 0...200,
                    unit: unit
                )
                HStack {
                    Text(attempts.isEmpty ? "Best of 3 counts" : "Attempts: \(attempts.map { SportGoalFormat.value($0) }.joined(separator: " · "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if attempts.count < 3 {
                        Button("Record attempt \(attempts.count + 1)") {
                            attempts.append(retestValue)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SomaTokens.accent)
                        .buttonStyle(.plain)
                    }
                }
                let best = attempts.max() ?? retestValue
                SomaButton(
                    title: isWorking ? "Saving…" : "Save \(SportGoalFormat.value(best, unit: unit))",
                    size: .md,
                    variant: .primary,
                    isEnabled: !isWorking
                ) {
                    Task { await saveRetest(event, value: best) }
                }
            }
            Button("Not now") { retestExpanded = false }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SomaTokens.ink3)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func retestResultCard(_ result: RetestResult) -> some View {
        switch result {
        case .confirmed(let value):
            CardView {
                Text(isMilestone ? "Stage confirmed" : "Baseline confirmed")
                    .font(.body.bold())
                Text(measurementText(value))
                    .font(Theme.display)
                Text("This is your official starting point for the block.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                dismissResultButton
            }
        case .noChange:
            CardView {
                Text(isMilestone ? "Same stage — normal at this point." : "No change yet — normal at this stage.")
                    .font(.body.bold())
                Text(isMilestone
                    ? "Stages take time to unlock. Session data still shows the work happening."
                    : "The re-test landed within measurement noise. Session data still shows the work happening.")
                    .font(.system(size: 13))
                    .foregroundStyle(SomaTokens.ink2)
                dismissResultButton
            }
        case .progress(let value, let delta):
            CardView {
                Text(isMilestone ? (delta > 0 ? "New stage" : "Stage recorded") : "Progress")
                    .font(.body.bold())
                Text(isMilestone ? measurementText(value) : SportGoalFormat.delta(delta, unit: unit))
                    .font(Theme.display)
                    .foregroundStyle(SomaTokens.accent)
                Text(isMilestone
                    ? (delta > 0
                        ? "Up from \(measurementText(value - delta))."
                        : "An earlier stage than last time — stages wobble, the work still counts.")
                    : "Now at \(SportGoalFormat.value(value, unit: unit))\(targetPositionSuffix(delta))")
                    .font(.system(size: 13))
                    .foregroundStyle(SomaTokens.ink2)
                dismissResultButton
            }
        case .finalResult(let achieved, let value, let delta):
            finalResultCard(achieved: achieved, value: value, delta: delta)
        }
    }

    private func targetPositionSuffix(_ delta: Double) -> String {
        guard let target = goal.targetRangeText(unit: unit) else { return "" }
        return String(localized: "goalHub.retest.targetSuffix", defaultValue: " — target \(target)", comment: "Appended to a re-test progress line to show the target range, e.g. ' — target +3–6 cm'; placeholder is the target range text. Leading text includes a leading em dash and space.")
    }

    /// The completion moment IS the achievement card, no separate screen.
    private func finalResultCard(achieved: Bool, value: Double, delta: Double) -> some View {
        let dateRange = blockDateRange
        let deltaText = isMilestone ? measurementText(value) : SportGoalFormat.delta(delta, unit: unit)
        let name = goal.displayName(in: catalog)
        return VStack(alignment: .leading, spacing: 12) {
            AchievementCardView(variant: achieved
                ? .celebratory(goalName: name, deltaText: deltaText, dateRange: dateRange)
                : .neutral(goalName: name, deltaText: deltaText, dateRange: dateRange))
            HStack {
                AchievementCardShareLink(variant: achieved
                    ? .celebratory(goalName: name, deltaText: deltaText, dateRange: dateRange)
                    : .neutral(goalName: name, deltaText: deltaText, dateRange: dateRange))
                Spacer()
            }
            if achieved {
                Text("1 session a week keeps your gains.")
                    .font(.system(size: 12))
                    .foregroundStyle(SomaTokens.ink3)
                if let goalId = goal.goalId {
                    SomaButton(title: "Next block", size: .md, variant: .primary) {
                        onNextBlock(goalId, value)
                    }
                }
                SomaButton(title: "New goal", size: .md, variant: .secondary) {
                    onPickNewGoal()
                }
            } else {
                if let goalId = goal.goalId {
                    SomaButton(title: "Extend the block", size: .md, variant: .primary) {
                        onNextBlock(goalId, value)
                    }
                }
                SomaButton(title: "New goal", size: .md, variant: .secondary) {
                    onPickNewGoal()
                }
            }
        }
    }

    private var dismissResultButton: some View {
        Button("Done") {
            retestResult = nil
            retestExpanded = false
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(SomaTokens.accent)
        .buttonStyle(.plain)
    }

    private var blockDateRange: String {
        let start = goal.startDate ?? Date()
        return SportGoalFormat.monthRange(start, Date())
    }

    // MARK: - Coach export

    private var coachShareCard: some View {
        CardView {
            Text("For your coach")
                .font(.body.bold())
            Text("Sessions done and your measurements as one card — send it back to \(goal.coachName.map { "Coach \($0)" } ?? "your coach").")
                .font(.caption)
                .foregroundStyle(.secondary)
            AchievementCardShareLink(variant: .coachExport(
                goalName: goal.displayName(in: catalog),
                sessionsLine: goal.committedSessions.map {
                    String(localized: "goalHub.coachShare.sessionsLine.withTotal", defaultValue: "\(sessionsDone) of \($0) sessions", comment: "Coach export share card: sessions done vs. committed total; placeholders are sessions done and total committed sessions")
                } ?? String(localized: "goalHub.coachShare.sessionsLine.noTotal", defaultValue: "\(sessionsDone) sessions", comment: "Coach export share card: sessions done with no committed total; placeholder is sessions done count"),
                coachName: goal.coachName,
                chartValues: measurements.map { (date: $0.dayString, value: $0.value) },
                dateRange: blockDateRange
            ))
        }
    }

    // MARK: - History

    private var completedHistory: [UserGoal] {
        history.filter { $0.status == .completed }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BLOCK HISTORY")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(SomaTokens.ink4)
            ForEach(completedHistory) { past in
                if let variant = achievementVariant(for: past) {
                    AchievementCardView(variant: variant)
                }
            }
        }
    }

    /// Celebration is earned: only a delta at or above the target's low
    /// end gets the accent card.
    private func achievementVariant(for past: UserGoal) -> AchievementCardVariant? {
        let name = past.displayName(in: catalog)
        let start = past.startDate ?? Date()
        let end = past.completedAt.flatMap(SportGoalFormat.parseTimestamp) ?? start
        let range = SportGoalFormat.monthRange(start, end)
        let pastGoal = past.goalId.flatMap(catalog.goal(id:))
        // A milestone block's baseline is its stored starting stage.
        let pastBaseline = past.baselineValue
            ?? past.baselineStage.flatMap { pastGoal?.stageIndex(of: $0).map(Double.init) }
        guard let result = past.resultValue, let baseline = pastBaseline else {
            return .neutral(goalName: name, deltaText: blockCompleteFallback, dateRange: range)
        }
        let delta = result - baseline
        // Past milestone blocks read as their reached stage, not "+1".
        if pastGoal?.kind == .milestone, !(pastGoal?.stageLadder.isEmpty ?? true) {
            let ladder = pastGoal?.stageLadder ?? []
            let index = Int(result.rounded())
            let stageText = ladder.indices.contains(index) ? SportGoal.stageDisplayName(ladder[index]) : blockCompleteFallback
            return delta >= 1
                ? .celebratory(goalName: name, deltaText: stageText, dateRange: range)
                : .neutral(goalName: name, deltaText: stageText, dateRange: range)
        }
        let pastUnit = past.kind == .custom ? past.customMetricUnit : pastGoal?.unit
        let deltaText = SportGoalFormat.delta(delta, unit: pastUnit)
        if let low = past.targetLow, delta >= low {
            return .celebratory(goalName: name, deltaText: deltaText, dateRange: range)
        }
        return .neutral(goalName: name, deltaText: deltaText, dateRange: range)
    }

    /// Fallback delta label for a completed block with no numeric result or
    /// reached stage to show.
    private var blockCompleteFallback: String {
        String(localized: "goalHub.history.blockComplete", defaultValue: "Block complete", comment: "Fallback label for a completed goal block with no numeric result or reached stage to show")
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if goal.status == .active {
            Button(isWorking ? "Pausing…" : "Pause goal") { Task { await pause() } }
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(SomaTokens.ink3)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .disabled(isWorking)
        }
    }

    // MARK: - Actions

    private func load() async {
        guard seededMeasurements == nil else { return }
        measurements = (try? await SupabaseClient.shared.fetchGoalMeasurements(userGoalId: goal.id)) ?? []
        await loadSessions()
    }

    /// Real logged-workout days since the block started -- the honest
    /// session counter, nothing simulated.
    private func loadSessions() async {
        guard let start = goal.startDate else { return }
        let logs = (try? await SupabaseClient.shared.fetchWorkoutLogs(
            fromDate: SportGoalFormat.dayString(start),
            toDate: SportGoalFormat.dayString(Date())
        )) ?? []
        sessionsDone = Set(logs.map(\.date)).count
    }

    private func saveRetest(_ event: RetestEvent, value: Double) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        let kind: GoalMeasurementKind = switch event {
        case .rebaseline: .baseline
        case .baselineConfirm: .baselineConfirm
        case .checkpoint: .checkpoint
        case .final: .final
        }
        do {
            try await SupabaseClient.shared.insertMeasurement(userGoalId: goal.id, kind: kind, value: value)
            let previousBaseline = officialBaseline
            measurements = (try? await SupabaseClient.shared.fetchGoalMeasurements(userGoalId: goal.id)) ?? measurements
            resumeNeedsRebaseline = false
            switch event {
            case .rebaseline, .baselineConfirm:
                retestResult = .confirmed(value)
            case .checkpoint:
                let delta = value - (previousBaseline ?? value)
                retestResult = abs(delta) <= noiseBand ? .noChange : .progress(value: value, delta: delta)
            case .final:
                let delta = value - (previousBaseline ?? value)
                let achieved = goal.targetLow.map { delta >= $0 } ?? (delta > noiseBand)
                try await SupabaseClient.shared.updateGoalStatus(id: goal.id, status: .completed, resultValue: value)
                retestResult = .finalResult(achieved: achieved, value: value, delta: delta)
            }
        } catch {
            errorMessage = String(localized: "goalHub.error.saveMeasurement", defaultValue: "Couldn't save the measurement. Try again.", comment: "Error shown when saving a re-test/baseline measurement fails")
        }
    }

    private func pause() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await SupabaseClient.shared.updateGoalStatus(id: goal.id, status: .paused, pauseReason: .user)
            onChanged()
        } catch {
            errorMessage = String(localized: "goalHub.error.pause", defaultValue: "Couldn't pause the goal. Try again.", comment: "Error shown when pausing a goal fails")
        }
    }

    private func resume() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await SupabaseClient.shared.updateGoalStatus(id: goal.id, status: .active)
            resumeNeedsRebaseline = baselineIsStale
            onChanged()
        } catch {
            errorMessage = String(localized: "goalHub.error.resume", defaultValue: "Couldn't resume the goal. Try again.", comment: "Error shown when resuming a paused goal fails")
        }
    }

    private func end() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await SupabaseClient.shared.updateGoalStatus(id: goal.id, status: .abandoned)
            onChanged()
        } catch {
            errorMessage = String(localized: "goalHub.error.end", defaultValue: "Couldn't end the goal. Try again.", comment: "Error shown when ending/abandoning a goal fails")
        }
    }
}
