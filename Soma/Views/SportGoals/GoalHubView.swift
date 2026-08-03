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

    @EnvironmentObject private var appState: AppState

    @State private var measurements: [GoalMeasurement] = []
    @State private var sessionsDone = 0
    @State private var retestExpanded = false
    @State private var retestValue: Double = 0
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
        goal.kind == .custom ? goal.customMetricUnit : presetGoal?.unit
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
    }

    private var latestMeasurementDate: Date? {
        measurements.last.flatMap { SportGoalFormat.parseTimestamp($0.measuredAt) }
    }

    /// Resuming (or continuing) after >4 measurement-free weeks means the
    /// starting point moved -- re-measure first (detraining rule).
    private var baselineIsStale: Bool {
        guard let latestMeasurementDate else { return false }
        return Date().timeIntervalSince(latestMeasurementDate) > 28 * 86400
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

                if goal.kind == .custom || presetGoal?.kind == .qualitative {
                    sessionsCard
                }
                if hasMetric {
                    chartCard
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
            if !isPaused {
                GoalPhaseStrip(current: goal.currentPhase)
                    .padding(.vertical, 4)
            }
            etaLines
        }
    }

    private var eyebrowText: String {
        if goal.kind == .custom {
            if let coachName = goal.coachName, !coachName.isEmpty {
                return "\(sportName.uppercased()) · COACH \(coachName.uppercased())"
            }
            return "\(sportName.uppercased()) · COACH'S TASK"
        }
        return "\(sportName.uppercased()) · GOAL"
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
            if let start = goal.startDate,
               Date().timeIntervalSince(start) < 7 * 86400,
               !measurements.contains(where: { $0.kind == .baselineConfirm }) {
                Text("In ~5 days we'll confirm your baseline — second attempts usually score higher.")
                    .font(.system(size: 12))
                    .foregroundStyle(SomaTokens.ink3)
            }
        }
    }

    /// Neutral, factual, never warn-colored.
    private func slipLine(_ days: Int) -> String {
        if let reason = goal.etaSlipReason, !reason.isEmpty {
            return "Moved +\(days) days — \(reason)"
        }
        return "Moved +\(days) days."
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
        .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.surface3))
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
        .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.surface3))
    }

    private func inlineNotice(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(SomaTokens.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.accentSoft))
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

    private var chartCard: some View {
        CardView {
            Text("Progress")
                .font(.body.bold())
            let values = measurements.map { (date: $0.dayString, value: $0.value) }
            if values.count >= 2 {
                AxisLabeledTrendChart(values: values)
            } else if values.count == 1 {
                Text(SportGoalFormat.value(values[0].value, unit: unit))
                    .font(.system(size: 24, design: .serif).italic())
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

    private var nextEvent: RetestEvent? {
        guard goal.status == .active else { return nil }
        if baselineIsStale || resumeNeedsRebaseline { return .rebaseline }
        let hasBaseline = measurements.contains { $0.kind == .baseline }
        let hasConfirm = measurements.contains { $0.kind == .baselineConfirm }
        let hasCheckpoint = measurements.contains { $0.kind == .checkpoint }
        if !hasBaseline { return .rebaseline }
        if !hasConfirm { return .baselineConfirm }
        if !hasCheckpoint { return .checkpoint }
        return .final
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
                SomaButton(title: retestButtonTitle(event), size: .md, variant: .primary) {
                    retestValue = officialBaseline ?? presetGoal?.entryRange.lowerBound ?? 0
                    attempts = []
                    retestExpanded = true
                }
            }
        }
    }

    private func retestButtonTitle(_ event: RetestEvent) -> String {
        switch event {
        case .rebaseline: "Re-measure your baseline"
        case .baselineConfirm: "Confirm your baseline"
        case .checkpoint: "Mid-block re-test"
        case .final: "Final re-test"
        }
    }

    private func lockedRow(daysLeft: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SomaTokens.ink4)
            Text(daysLeft >= 14 ? "Re-test opens in \(Int((Double(daysLeft) / 7).rounded())) weeks" : "Re-test opens in \(daysLeft) days")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(SomaTokens.ink3)
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.surface3))
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
        .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.surface3))
    }

    /// A4 entry: one protocol reminder line, ruler, attempt counter --
    /// the result replaces this in place on save.
    private func retestEntryCard(_ event: RetestEvent) -> some View {
        CardView {
            if let reminder = presetGoal?.protocolLines.first {
                Text("Same setup as always: \(reminder.prefix(1).lowercased() + reminder.dropFirst())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                Text("Baseline confirmed")
                    .font(.body.bold())
                Text(SportGoalFormat.value(value, unit: unit))
                    .font(Theme.display)
                Text("This is your official starting point for the block.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                dismissResultButton
            }
        case .noChange:
            CardView {
                Text("No change yet — normal at this stage.")
                    .font(.body.bold())
                Text("The re-test landed within measurement noise. Session data still shows the work happening.")
                    .font(.system(size: 13))
                    .foregroundStyle(SomaTokens.ink2)
                dismissResultButton
            }
        case .progress(let value, let delta):
            CardView {
                Text("Progress")
                    .font(.body.bold())
                Text(SportGoalFormat.delta(delta, unit: unit))
                    .font(Theme.display)
                    .foregroundStyle(SomaTokens.accent)
                Text("Now at \(SportGoalFormat.value(value, unit: unit))\(targetPositionSuffix(delta))")
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
        return " — target \(target)"
    }

    /// The completion moment IS the achievement card, no separate screen.
    private func finalResultCard(achieved: Bool, value: Double, delta: Double) -> some View {
        let dateRange = blockDateRange
        let deltaText = SportGoalFormat.delta(delta, unit: unit)
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
                sessionsLine: goal.committedSessions.map { "\(sessionsDone) of \($0) sessions" } ?? "\(sessionsDone) sessions",
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
        guard let result = past.resultValue, let baseline = past.baselineValue else {
            return .neutral(goalName: name, deltaText: "Block complete", dateRange: range)
        }
        let delta = result - baseline
        let pastUnit = past.kind == .custom ? past.customMetricUnit : past.goalId.flatMap(catalog.goal(id:))?.unit
        let deltaText = SportGoalFormat.delta(delta, unit: pastUnit)
        if let low = past.targetLow, delta >= low {
            return .celebratory(goalName: name, deltaText: deltaText, dateRange: range)
        }
        return .neutral(goalName: name, deltaText: deltaText, dateRange: range)
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
            errorMessage = "Couldn't save the measurement. Try again."
        }
    }

    private func pause() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await SupabaseClient.shared.updateGoalStatus(id: goal.id, status: .paused, pauseReason: .user)
            onChanged()
        } catch {
            errorMessage = "Couldn't pause the goal. Try again."
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
            errorMessage = "Couldn't resume the goal. Try again."
        }
    }

    private func end() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await SupabaseClient.shared.updateGoalStatus(id: goal.id, status: .abandoned)
            onChanged()
        } catch {
            errorMessage = "Couldn't end the goal. Try again."
        }
    }
}
