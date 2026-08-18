import SwiftUI

/// "Affirmation reminders" (Soma Refresh 16c) -- lives in Profile >
/// Notifications (pushed) and behind the Affirmations sheet's bell
/// (presented in its own NavigationStack). All prefs are local device
/// state on NotificationManager, same posture as quiet hours; every
/// change applies immediately and re-resolves today's pending pushes.
struct AffirmationRemindersView: View {
    @State private var enabled = NotificationManager.shared.affirmationRemindersEnabled
    @State private var perDay = NotificationManager.shared.affirmationRemindersPerDay
    @State private var slotTimes: [Date] = (0..<3).map {
        Self.date(fromMinuteOfDay: NotificationManager.shared.affirmationSlotMinute($0))
    }
    @State private var source = NotificationManager.shared.affirmationSource
    @State private var previewLine: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                toggleCard

                if enabled {
                    eyebrow(String(localized: "affirmationReminders.frequency.eyebrow", defaultValue: "How often", comment: "Eyebrow label above the affirmation reminder frequency chips"))
                    HStack(spacing: 6) {
                        SomaChip(title: LocalizedStringKey(String(localized: "affirmationReminders.frequency.once", defaultValue: "1× a day", comment: "Affirmation reminder frequency chip: one push a day")), isSelected: perDay == 1) { setPerDay(1) }
                        SomaChip(title: LocalizedStringKey(String(localized: "affirmationReminders.frequency.twice", defaultValue: "2× a day", comment: "Affirmation reminder frequency chip: two pushes a day")), isSelected: perDay == 2) { setPerDay(2) }
                        SomaChip(title: LocalizedStringKey(String(localized: "affirmationReminders.frequency.thrice", defaultValue: "3× a day", comment: "Affirmation reminder frequency chip: three pushes a day")), isSelected: perDay == 3) { setPerDay(3) }
                    }

                    VStack(spacing: 8) {
                        ForEach(0..<perDay, id: \.self) { index in
                            slotRow(index)
                        }
                    }

                    eyebrow(String(localized: "affirmationReminders.source.eyebrow", defaultValue: "Draw lines from", comment: "Eyebrow label above the affirmation reminder source chips"))
                    HStack(spacing: 6) {
                        SomaChip(title: LocalizedStringKey(String(localized: "affirmationReminders.source.generated", defaultValue: "Generated", comment: "Affirmation reminder source chip: only AI-generated lines")), isSelected: source == .generated) { setSource(.generated) }
                        SomaChip(title: LocalizedStringKey(String(localized: "affirmationReminders.source.list", defaultValue: "My list", comment: "Affirmation reminder source chip: only the user's own saved lines")), isSelected: source == .list) { setSource(.list) }
                        SomaChip(title: LocalizedStringKey(String(localized: "affirmationReminders.source.both", defaultValue: "Both", comment: "Affirmation reminder source chip: generated and saved lines interleaved")), isSelected: source == .both) { setSource(.both) }
                    }

                    quietHoursNote

                    eyebrow(String(localized: "affirmationReminders.preview.eyebrow", defaultValue: "How it lands", comment: "Eyebrow label above the affirmation notification preview"))
                    previewCard
                }
            }
            .padding(20)
        }
        .somaBackground()
        .navigationTitle(String(localized: "affirmationReminders.title", defaultValue: "Affirmation reminders", comment: "Navigation title of the affirmation reminder settings page"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPreviewLine() }
        .onDisappear {
            Task { await NotificationManager.shared.scheduleAffirmationReminders() }
        }
    }

    // MARK: - Pieces

    private var toggleCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "affirmationReminders.toggle.title", defaultValue: "Send through the day", comment: "Title of the toggle enabling affirmation reminder pushes"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SomaTokens.ink)
                Text(String(localized: "affirmationReminders.toggle.subtitle", defaultValue: "Short pushes, one line each", comment: "Subtitle under the affirmation reminders toggle"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(SomaTokens.ink3)
            }
            Spacer(minLength: 0)
            Toggle(isOn: Binding(get: { enabled }, set: { setEnabled($0) })) { EmptyView() }
                .labelsHidden()
                .tint(SomaTokens.accent)
        }
        .padding(.init(top: 14, leading: 16, bottom: 14, trailing: 16))
        .glassCardFlat(cornerRadius: SomaTokens.rRow)
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .tracking(0.7)
            .textCase(.uppercase)
            .foregroundStyle(SomaTokens.ink4)
            .padding(.leading, 4)
            .padding(.top, 4)
    }

    /// Computed per render, not a cached static -- Profile's own Language
    /// picker can change the active locale while this page is reachable.
    private func slotLabel(_ index: Int) -> String {
        switch index {
        case 0: String(localized: "affirmationReminders.slot.morning", defaultValue: "Morning", comment: "Label for the first affirmation reminder time slot")
        case 1: String(localized: "affirmationReminders.slot.afternoon", defaultValue: "Afternoon", comment: "Label for the second affirmation reminder time slot")
        default: String(localized: "affirmationReminders.slot.evening", defaultValue: "Evening", comment: "Label for the third affirmation reminder time slot")
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    /// 11c's whenRow recipe (LogManualWorkoutView): custom accent pill,
    /// real compact DatePicker composited BEHIND it via .destinationOver
    /// -- native compact style ignores .tint, so the visible pill is ours.
    private func slotRow(_ index: Int) -> some View {
        HStack {
            Text(slotLabel(index))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(SomaTokens.ink)
            Spacer()
            Text(Self.timeFormatter.string(from: slotTimes[index]))
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(SomaTokens.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.55))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                        .overlay(Capsule().stroke(SomaTokens.hairline, lineWidth: 1).padding(-0.5))
                )
        }
        .padding(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
        .glassCardFlat(cornerRadius: SomaTokens.rRow)
        .accessibilityHidden(true)
        .compositingGroup()
        .overlay(
            DatePicker(
                "",
                selection: Binding(
                    get: { slotTimes[index] },
                    set: { setSlotTime($0, at: index) }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .tint(SomaTokens.accent)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 8)
            .blendMode(.destinationOver)
            .accessibilityLabel(slotLabel(index))
            .accessibilityValue(Self.timeFormatter.string(from: slotTimes[index]))
        )
    }

    private var quietHoursNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon")
                .font(.system(size: 12))
                .foregroundStyle(SomaTokens.ink4)
            Text(quietHoursNoteText)
                .font(.system(size: 11.5))
                .foregroundStyle(SomaTokens.ink3)
        }
        .padding(.horizontal, 4)
    }

    private var quietHoursNoteText: String {
        let manager = NotificationManager.shared
        if manager.isQuietHoursEnabled {
            let start = Self.timeFormatter.string(from: Self.date(fromMinuteOfDay: manager.quietHoursStartMinute))
            let end = Self.timeFormatter.string(from: Self.date(fromMinuteOfDay: manager.quietHoursEndMinute))
            return String(localized: "affirmationReminders.quietHours.onNote", defaultValue: "Respects quiet hours · \(start)–\(end), set in Profile", comment: "Note that affirmation pushes respect the configured quiet hours window, showing its start and end time")
        }
        return String(localized: "affirmationReminders.quietHours.offNote", defaultValue: "Respects quiet hours, set in Profile", comment: "Note that affirmation pushes respect quiet hours once enabled in Profile")
    }

    /// 16c "How it lands" -- the real payload: just the line, no filler.
    private var previewCard: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [SomaTokens.accentLight.opacity(0.92), SomaTokens.accent.opacity(0.9)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "heart.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(verbatim: "Soma")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(SomaTokens.ink)
                    Spacer(minLength: 0)
                    Text(String(localized: "affirmationReminders.preview.now", defaultValue: "now", comment: "Timestamp label on the sample notification preview"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(SomaTokens.inkPlaceholder)
                }
                Text(previewLine ?? String(localized: "affirmationReminders.preview.sample", defaultValue: "Show up. The rest follows.", comment: "Sample affirmation line shown in the notification preview when none exists yet"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(SomaTokens.inkRowTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.init(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.75))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                .shadow(color: SomaTokens.shRaisedColor, radius: 12, x: 0, y: 8)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Mutations (apply immediately, like the quiet-hours editor)

    private func setEnabled(_ value: Bool) {
        enabled = value
        NotificationManager.shared.affirmationRemindersEnabled = value
        if value {
            // Same grant path as Profile's Push notifications row -- a
            // first-time opt-in needs the system permission too.
            Task {
                if await !NotificationManager.shared.isAuthorized(), await !NotificationManager.shared.isDenied() {
                    try? await NotificationManager.shared.requestAuthorization()
                }
                await NotificationManager.shared.scheduleAffirmationReminders()
            }
        } else {
            Task { await NotificationManager.shared.scheduleAffirmationReminders() }
        }
    }

    private func setPerDay(_ value: Int) {
        perDay = value
        NotificationManager.shared.affirmationRemindersPerDay = value
    }

    private func setSlotTime(_ date: Date, at index: Int) {
        slotTimes[index] = date
        NotificationManager.shared.setAffirmationSlotMinute(Self.minuteOfDay(from: date), at: index)
    }

    private func setSource(_ value: NotificationManager.AffirmationSource) {
        source = value
        NotificationManager.shared.affirmationSource = value
    }

    private func loadPreviewLine() async {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        if let today = try? await SupabaseClient.shared.fetchTodaysAffirmation(date: formatter.string(from: Date())) {
            previewLine = today.text
            return
        }
        if let first = ((try? await SupabaseClient.shared.fetchAffirmationLines()) ?? []).first(where: \.inRotation) {
            previewLine = first.text
        }
    }

    // MARK: - Minute-of-day conversion (same encoding as quiet hours)

    private static func date(fromMinuteOfDay minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
    }

    private static func minuteOfDay(from date: Date) -> Int {
        Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
    }
}

#Preview {
    NavigationStack {
        AffirmationRemindersView()
    }
}
