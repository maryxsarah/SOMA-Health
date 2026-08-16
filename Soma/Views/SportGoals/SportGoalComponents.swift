import SwiftUI

/// The three named training phases -- fixed product vocabulary, rendered
/// as a thin strip (design §6a note 6).
enum GoalPhase: String, CaseIterable {
    case foundation, build, peak

    var displayName: String {
        switch self {
        case .foundation: String(localized: "sportGoal.phase.foundation", defaultValue: "Foundation", comment: "Sport-goal training phase name (periodization: base-building phase)")
        case .build: String(localized: "sportGoal.phase.build", defaultValue: "Build", comment: "Sport-goal training phase name (periodization: build/development phase), noun")
        case .peak: String(localized: "sportGoal.phase.peak", defaultValue: "Peak", comment: "Sport-goal training phase name (periodization: peak phase), noun")
        }
    }
}

/// Thin inline phase strip: Foundation → Build → Peak, current one filled.
struct GoalPhaseStrip: View {
    /// Nil highlights nothing (pre-start preview).
    var current: GoalPhase?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(GoalPhase.allCases, id: \.self) { phase in
                let isCurrent = phase == current
                VStack(spacing: 4) {
                    Capsule()
                        .fill(isCurrent ? SomaTokens.accent : SomaTokens.surface4)
                        .frame(height: 4)
                    Text(phase.displayName)
                        .font(.system(size: 10.5, weight: isCurrent ? .bold : .medium))
                        .foregroundStyle(isCurrent ? SomaTokens.accent : SomaTokens.ink4)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

extension UserGoal {
    /// Server-set phase wins; otherwise derived from elapsed fraction of
    /// the horizon -- deterministic, never guessed past the data.
    var currentPhase: GoalPhase? {
        if let phase, let known = GoalPhase(rawValue: phase) { return known }
        guard let startDate else { return nil }
        let endDate = etaStart.flatMap(SportGoalFormat.parseDay)
            ?? recheckDate.flatMap(SportGoalFormat.parseDay)
        guard let endDate, endDate > startDate else { return nil }
        let fraction = Date().timeIntervalSince(startDate) / endDate.timeIntervalSince(startDate)
        if fraction < 1.0 / 3.0 { return .foundation }
        if fraction < 2.0 / 3.0 { return .build }
        return .peak
    }
}

/// Uppercase capsule badge for a goal's kind. METRIC / MILESTONE read as
/// accent (the honest, measured kinds); CUSTOM / IN WORDS stay neutral.
struct GoalKindBadge: View {
    let text: String
    let isAccent: Bool

    init(kind: SportGoalKind) {
        switch kind {
        case .metric: text = String(localized: "sportGoal.kindBadge.metric", defaultValue: "METRIC", comment: "Uppercase goal-kind badge: goal has a numeric/measurable target"); isAccent = true
        case .milestone: text = String(localized: "sportGoal.kindBadge.milestone", defaultValue: "MILESTONE", comment: "Uppercase goal-kind badge: goal is a milestone/checkpoint target"); isAccent = true
        case .qualitative: text = String(localized: "sportGoal.kindBadge.qualitative", defaultValue: "IN WORDS", comment: "Uppercase goal-kind badge: goal is described qualitatively in free text"); isAccent = false
        case .unknown: text = ""; isAccent = false
        }
    }

    private init(text: String, isAccent: Bool) {
        self.text = text
        self.isAccent = isAccent
    }

    static let custom = GoalKindBadge(text: String(localized: "sportGoal.kindBadge.custom", defaultValue: "CUSTOM", comment: "Uppercase goal-kind badge: user's own custom/coach-assigned goal, not a preset"), isAccent: false)

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(isAccent ? SomaTokens.accent : SomaTokens.ink2)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(isAccent ? SomaTokens.accentSoft : SomaTokens.surface3))
                .overlay(Capsule().strokeBorder(isAccent ? SomaTokens.accentSoft22 : SomaTokens.hairline, lineWidth: 1))
        }
    }
}

/// Seven toggle circles, displayed Monday-first but EMITTING the server's
/// weekday values (0=Sunday..6=Saturday, JS getUTCDay -- create-goal validates 0..6).
struct WeekdayMiniPicker: View {
    @Binding var selected: Set<Int>

    /// Monday-first display order mapped to server weekday values.
    static let dayValuesInDisplayOrder = [1, 2, 3, 4, 5, 6, 0]
    private static let labels = ["M", "T", "W", "T", "F", "S", "S"]

    /// "Mon"-style label for a server weekday value (0=Sunday..6=Saturday).
    static func shortName(forValue value: Int) -> String {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        guard names.indices.contains(value) else { return "?" }
        return names[value]
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                let day = Self.dayValuesInDisplayOrder[index]
                let isOn = selected.contains(day)
                Button {
                    if isOn { selected.remove(day) } else { selected.insert(day) }
                } label: {
                    Group {
                        if isOn {
                            Text(Self.labels[index])
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .glassGel(.blue, cornerRadius: 17)
                        } else {
                            Text(Self.labels[index])
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SomaTokens.ink3)
                                .frame(width: 34, height: 34)
                                .glassLens(cornerRadius: 17)
                        }
                    }
                }
                .buttonStyle(.plain)
                // Labels alone are ambiguous ("T"/"S" repeat) -- a stable
                // per-day target for tests.
                .accessibilityIdentifier("weekday-\(day)")
            }
        }
    }
}

/// The frequency chips (2x/3x/4x a week, or a custom rule via a sheet) --
/// shared by GoalStartView and CustomGoalFormView, which were otherwise
/// carrying two byte-for-byte copies of this. Owns its own sheet
/// presentation; callers embed it in whatever card/stepper context they
/// need (a preset goal has no duration-weeks stepper, a custom one does).
struct ScheduleFrequencyPicker: View {
    @Binding var frequencyPerWeek: Int
    @Binding var scheduleRule: GoalScheduleRule?
    @Binding var scheduleDays: Set<Int>
    @Binding var courtDays: Set<Int>
    /// Owned by the parent screen, like every other field here -- this is
    /// itself the fix for a real bug: the "Custom…" sheet silently failed
    /// to present when this picker sits inside a conditionally-rendered
    /// branch (`if hasBaseline { ... }` in GoalStartView) -- a `.sheet`
    /// modifier attached to a view inside an `if` branch is unreliable in
    /// SwiftUI even once its underlying `isPresented` binding is provably
    /// correct (confirmed: hoisting this from local `@State` to a `@Binding`
    /// alone did NOT fix it, and it was never a race with the async `.task`
    /// either -- the actual fix is presenting from a stable, unconditional
    /// ancestor; see `ScheduleRulesSheet` below and its two call sites).
    @Binding var showFrequencySheet: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout {
                ForEach([2, 3, 4], id: \.self) { count in
                    SomaChip(title: LocalizedStringKey(String(localized: "sportGoal.schedule.timesPerWeek", defaultValue: "\(count)× a week", comment: "Schedule frequency chip label: a plain weekly session count, e.g. '3× a week'")), isSelected: scheduleRule == nil && frequencyPerWeek == count) {
                        scheduleRule = nil
                        frequencyPerWeek = count
                    }
                }
                SomaChip(title: LocalizedStringKey(customChipTitle), isSelected: scheduleRule != nil, isOneOff: scheduleRule == nil) {
                    showFrequencySheet = true
                }
            }
            Text(String(localized: "sportGoal.scheduleFrequency.readinessNote", defaultValue: "Sessions still defer to your readiness for placement — low days shift, the workout itself is never rewritten.", comment: "Schedule frequency picker: reassuring note that low-readiness days still shift placement"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static let customLabel = String(localized: "sportGoal.schedule.customLabel", defaultValue: "Custom…", comment: "Default label for the schedule frequency chip before a custom rule is chosen")

    private var customChipTitle: String {
        switch scheduleRule {
        case .weekdays: scheduleDays.isEmpty ? Self.customLabel : Self.weekdaysLabel(scheduleDays)
        case .everyOtherDay: String(localized: "sportGoal.scheduleRule.everyOtherDay.title", defaultValue: "Every other day", comment: "Schedule rule: alternating training day / rest day pattern")
        case .beforeCourtDays: String(localized: "sportGoal.scheduleRule.beforeCourtDays.title", defaultValue: "Before court days", comment: "Schedule rule: sessions are placed the day before the user's court/match days")
        case .readiness: String(localized: "sportGoal.scheduleRule.whenReadinessAllows.title", defaultValue: "When readiness allows", comment: "Schedule rule: app places sessions on the user's better-readiness days rather than fixed days")
        case .unknown, nil: Self.customLabel
        }
    }

    private static func weekdaysLabel(_ days: Set<Int>) -> String {
        // Monday-first, using the picker's server-value convention (0=Sunday).
        WeekdayMiniPicker.dayValuesInDisplayOrder
            .filter(days.contains)
            .map(WeekdayMiniPicker.shortName(forValue:))
            .joined(separator: " · ")
    }

    /// Pure, so create()/submit logic in either caller can compute the
    /// actual session count without needing a live picker instance.
    static func effectiveFrequency(
        frequencyPerWeek: Int,
        scheduleRule: GoalScheduleRule?,
        scheduleDays: Set<Int>,
        courtDays: Set<Int>
    ) -> Int {
        switch scheduleRule {
        case .weekdays where !scheduleDays.isEmpty: scheduleDays.count
        case .everyOtherDay: 3
        case .beforeCourtDays where !courtDays.isEmpty: courtDays.count
        default: frequencyPerWeek
        }
    }
}

/// The "Custom…" chip's rule picker -- split out from `ScheduleFrequencyPicker`
/// so callers can `.sheet(isPresented:)` it from their own stable root instead
/// of from wherever the picker itself happens to live. Presenting a `.sheet`
/// from a view inside a conditionally-rendered (`if`) branch is unreliable in
/// SwiftUI; both `GoalStartView` (schedule sits behind `if hasBaseline`) and
/// `CustomGoalFormView` (schedule is unconditional, but kept consistent) now
/// attach this at their own top level.
struct ScheduleRulesSheet: View {
    @Binding var scheduleRule: GoalScheduleRule?
    @Binding var scheduleDays: Set<Int>
    @Binding var courtDays: Set<Int>
    @Environment(\.dismiss) private var dismiss

    /// "Before court days" reveals a static court-days mini-picker inline;
    /// no calendar integration.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ruleRow(.weekdays,
                            title: String(localized: "sportGoal.scheduleRule.specificWeekdays.title", defaultValue: "Specific weekdays", comment: "Schedule rule row title: train on fixed weekdays chosen by the user"),
                            subtitle: String(localized: "sportGoal.scheduleRule.specificWeekdays.subtitle", defaultValue: "Train on fixed days", comment: "Schedule rule row subtitle for 'Specific weekdays'"),
                            icon: "calendar")
                    if scheduleRule == .weekdays {
                        WeekdayMiniPicker(selected: $scheduleDays)
                            .padding(.leading, 4)
                    }
                    ruleRow(.everyOtherDay,
                            title: String(localized: "sportGoal.scheduleRule.everyOtherDay.title", defaultValue: "Every other day", comment: "Schedule rule: alternating training day / rest day pattern"),
                            subtitle: String(localized: "sportGoal.scheduleRule.everyOtherDay.subtitle", defaultValue: "A steady one-on, one-off rhythm", comment: "Schedule rule row subtitle for 'Every other day'"),
                            icon: "arrow.left.arrow.right")
                    ruleRow(.beforeCourtDays,
                            title: String(localized: "sportGoal.scheduleRule.beforeCourtDays.title", defaultValue: "Before court days", comment: "Schedule rule: sessions are placed the day before the user's court/match days"),
                            subtitle: String(localized: "sportGoal.scheduleRule.beforeCourtDays.subtitle", defaultValue: "Sessions land the day before you play", comment: "Schedule rule row subtitle for 'Before court days'"),
                            icon: "figure.tennis")
                    if scheduleRule == .beforeCourtDays {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "sportGoal.scheduleRule.myCourtDays", defaultValue: "My court days", comment: "Label above the court-days mini weekday picker in the schedule-rules sheet"))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            WeekdayMiniPicker(selected: $courtDays)
                        }
                        .padding(.leading, 4)
                    }
                    ruleRow(.readiness,
                            title: String(localized: "sportGoal.scheduleRule.whenReadinessAllows.title", defaultValue: "When readiness allows", comment: "Schedule rule: app places sessions on the user's better-readiness days rather than fixed days"),
                            subtitle: String(localized: "sportGoal.scheduleRule.whenReadinessAllows.subtitle", defaultValue: "Soma places sessions on your better days", comment: "Schedule rule row subtitle for 'When readiness allows'"),
                            icon: "waveform.path.ecg")
                }
                .padding(20)
            }
            .somaBackground()
            .navigationTitle(String(localized: "sportGoal.scheduleRulesSheet.title", defaultValue: "Frequency", comment: "Navigation title for the schedule-rules sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "sportGoal.scheduleRulesSheet.done", defaultValue: "Done", comment: "Button closing the schedule-rules sheet")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func ruleRow(_ rule: GoalScheduleRule, title: String, subtitle: String, icon: String) -> some View {
        SurveyOptionRow(title: title, subtitle: subtitle, systemImageName: icon, isSelected: scheduleRule == rule) {
            scheduleRule = rule
        }
    }
}

/// Calm inline safety-conflict warning (warnSoft, never red, never a
/// block) with the explicit acknowledgment control.
struct GoalConflictWarningView: View {
    let conflicts: [GoalSafetyConflict]
    let onAcknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(SomaTokens.warn)
                Text(String(localized: "sportGoal.conflictWarning.title", defaultValue: "Worth a look before you start", comment: "Safety-conflict warning card title"))
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(SomaTokens.warn)
            }
            ForEach(conflicts) { conflict in
                Text(conflict.message)
                    .font(.system(size: 13))
                    .foregroundStyle(SomaTokens.ink2)
            }
            if conflicts.contains(where: \.isPregnancyRelated) {
                Text(String(localized: "sportGoal.conflictWarning.pregnancyNote", defaultValue: "Please discuss this plan with your care provider before continuing.", comment: "Safety-conflict warning: extra note shown when a pregnancy-related conflict is present"))
                    .font(.system(size: 13))
                    .foregroundStyle(SomaTokens.ink2)
            }
            Button(action: onAcknowledge) {
                Text(String(localized: "sportGoal.conflictWarning.acknowledge", defaultValue: "My coach knows my situation — continue", comment: "Button acknowledging a safety conflict and proceeding anyway"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(SomaTokens.warn)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .glassCardFlat(cornerRadius: SomaTokens.rXL)
                    .overlay(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).strokeBorder(SomaTokens.warnLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous)
                .fill(SomaTokens.warnSoft)
                .overlay(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).stroke(SomaTokens.warnLine, lineWidth: 1))
        )
    }
}
