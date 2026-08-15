import SwiftUI

/// Lets the user log a specific activity Soma never suggested -- a sport
/// session, a class, anything outside the AI-generated plan (real
/// examples from feedback: "2h soccer training", "1h volleyball", "1h
/// hot yoga"). Writes into the same workout_log table as an AI-plan
/// completion, just tagged source: "manual" -- so it counts toward the
/// same streak, calendar crowns, and weekly target, and (since it
/// captures a real start/end window) gets the same WearableSessionSummary
/// heart-rate matching an AI-plan workout does, pulled from whatever
/// health device is connected.
struct LogManualWorkoutView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bodyPart: BodyPartFocus = .cardio
    @State private var category: RecommendationCategory = .moderate
    @State private var date = Date()
    @State private var startTime = Date()
    @State private var durationMinutes = 60
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Logging a completed session as "Rest" doesn't make sense -- that
    /// category is for what Soma recommends on a day off, not something
    /// the user just finished.
    private static let intensityOptions: [RecommendationCategory] = [.pushHard, .moderate, .light]
    private static let focusOptions: [BodyPartFocus] = [.cardio, .fullBody, .upperBody, .lowerBody, .core, .recovery]

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    whatDidYouDoCard
                    whenCard
                    notesCard

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(SomaTokens.danger)
                    }

                    SomaButton(title: LocalizedStringKey(String(localized: "logWorkout.cta.logActivity", defaultValue: "Log activity", comment: "Log-activity form: primary CTA button")), size: .lg, variant: .primary, isEnabled: canSave) {
                        Task { await save() }
                    }
                }
                .padding(20)
            }
            .somaSheetBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 11c: white Cancel pill + centered bold title -> serif
                // italic title + glass Cancel pill, same recipe as 11b's
                // header (GoalBodyProgressView).
                ToolbarItem(placement: .principal) {
                    Text(String(localized: "logWorkout.navigationTitle", defaultValue: "Log an activity", comment: "Log-activity form: navigation title"))
                        .font(.system(size: 28, weight: .bold, design: .serif).italic())
                        .foregroundStyle(SomaTokens.ink)
                }
                // Design puts Cancel on the trailing edge (title left→center,
                // action right) -- same convention as 11b's GoalBodyProgressView
                // "Done", which uses .confirmationAction, not .cancellationAction
                // (the latter renders leading and put this on the wrong side).
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(SomaTokens.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .glassLens(cornerRadius: SomaTokens.rPill)
                }
            }
        }
    }

    // MARK: - What did you do?

    private var whatDidYouDoCard: some View {
        CardView {
            Text(String(localized: "logWorkout.section.whatDidYouDo", defaultValue: "What did you do?", comment: "Log-activity form: header for the activity/focus/effort section"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(SomaTokens.ink)

            TextField(String(localized: "logWorkout.title.placeholder", defaultValue: "e.g. Soccer training, Hot yoga, Volleyball", comment: "Log-activity form: placeholder for the activity title text field"), text: $title)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "logWorkout.focus.label", defaultValue: "Focus", comment: "Log-activity form: label for the body-part-focus picker"))
                    .font(SomaType.eyebrow)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(SomaTokens.ink3)
                FlowLayout {
                    ForEach(Self.focusOptions, id: \.self) { part in
                        SomaChip(title: LocalizedStringKey(part.displayName), isSelected: bodyPart == part) {
                            bodyPart = part
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Effort")
                    .font(SomaType.eyebrow)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(SomaTokens.ink3)
                FlowLayout {
                    ForEach(Self.intensityOptions, id: \.self) { intensity in
                        SomaChip(title: LocalizedStringKey(intensity.displayTitle), isSelected: category == intensity) {
                            category = intensity
                        }
                    }
                }
            }

            Text(String(localized: "logWorkout.section.effortFooter", defaultValue: "Effort helps Soma calibrate tomorrow's plan around today's real training load.", comment: "Log-activity form: footer explaining why effort is captured"))
                .font(.system(size: 12))
                .foregroundStyle(SomaTokens.ink3)
        }
    }

    // MARK: - When

    private var whenCard: some View {
        CardView {
            Text(String(localized: "logWorkout.section.when", defaultValue: "When", comment: "Log-activity form: header for the date/time/duration section"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(SomaTokens.ink)

            // 11c: three separate gray system capsules -> one glass card
            // with hairline-divided rows and accent-blue pill values (native
            // DatePicker text ignores .tint in compact style, so the visible
            // pill is custom, with the real picker overlaid near-invisibly
            // for interaction).
            VStack(spacing: 0) {
                whenRow(label: String(localized: "logWorkout.date.label", defaultValue: "Date", comment: "Log-activity form: label for the date picker"), valueText: Self.dateFormatter.string(from: date)) {
                    DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                        .tint(SomaTokens.accent)
                }
                Divider().overlay(SomaTokens.hairline)
                whenRow(label: String(localized: "logWorkout.startTime.label", defaultValue: "Start time", comment: "Log-activity form: label for the start-time picker"), valueText: Self.timeFormatter.string(from: startTime)) {
                    DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                        .tint(SomaTokens.accent)
                }
                Divider().overlay(SomaTokens.hairline)
                durationRow
            }

            Text(String(localized: "logWorkout.section.whenFooter", defaultValue: "Used to pull your real heart rate for this exact window from Apple Health or a connected wearable, if one reported it.", comment: "Log-activity form: footer explaining why start time/duration is captured"))
                .font(.system(size: 12))
                .foregroundStyle(SomaTokens.ink3)
        }
    }

    private func whenRow<Picker: View>(label: String, valueText: String, @ViewBuilder picker: () -> Picker) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SomaTokens.ink)
            Spacer()
            Text(valueText)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SomaTokens.accent)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .glassLens(cornerRadius: SomaTokens.rPill)
        }
        .padding(.vertical, 10)
        .accessibilityHidden(true)
        .compositingGroup()
        .overlay(
            // .destinationOver draws the real picker's own compact chip
            // BEHIND the already-composited row above (unlike a low-opacity
            // hack, which still leaves a faint ghost of its native chip
            // visible) -- trailing-aligned so its chip lands directly under
            // our pill, fully masking it.
            picker()
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .blendMode(.destinationOver)
                .accessibilityLabel(label)
                .accessibilityValue(valueText)
        )
    }

    // 11c: the gray native Stepper's -|+ rocker -> two glass lens circles,
    // same 30pt recipe as RecommendationDetailView's sectionIcon badges.
    private var durationRow: some View {
        HStack {
            Text(String(localized: "logWorkout.duration.label", defaultValue: "Duration", comment: "Log-activity form: label for the duration control"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SomaTokens.ink)
            Spacer()
            Text(Self.durationLabel(durationMinutes))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SomaTokens.ink)
            durationStepButton(systemName: "minus", disabled: durationMinutes <= 5) {
                durationMinutes = max(5, durationMinutes - 5)
            }
            durationStepButton(systemName: "plus", disabled: durationMinutes >= 300) {
                durationMinutes = min(300, durationMinutes + 5)
            }
        }
        .padding(.vertical, 10)
    }

    private func durationStepButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(disabled ? SomaTokens.ink4 : SomaTokens.accent)
                .frame(width: 30, height: 30)
                .glassLens(cornerRadius: SomaTokens.rPill)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Notes

    private var notesCard: some View {
        CardView {
            Text("Notes (optional)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(SomaTokens.ink)
            TextField(String(localized: "logWorkout.notes.placeholder", defaultValue: "Anything worth remembering", comment: "Log-activity form: placeholder for the optional free-text notes field"), text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let startedAt = Self.combine(date: date, time: startTime)
        let endedAt = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: startedAt) ?? startedAt

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = .current

        do {
            try await SupabaseClient.shared.logWorkout(
                date: dateFormatter.string(from: date),
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                bodyPart: bodyPart.rawValue,
                category: category.rawValue,
                feedback: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
                startedAt: startedAt,
                endedAt: endedAt,
                source: "manual"
            )
            dismiss()
        } catch {
            errorMessage = String(localized: "logWorkout.error.saveFailed", defaultValue: "Couldn't log that activity. Try again.", comment: "Log-activity form: shown when saving the manually-logged activity fails")
        }
    }

    /// Merges the date-only picker with the time-only picker into one
    /// real Date -- both pickers independently default to "now", so
    /// neither alone carries the actual combined moment the user means.
    private static func combine(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        return calendar.date(from: components) ?? date
    }

    private static func durationLabel(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours == 0 { return String(localized: "logWorkout.duration.minutesOnly", defaultValue: "\(mins) min", comment: "Log-activity form: duration stepper value, minutes only") }
        if mins == 0 { return String(localized: "logWorkout.duration.hoursOnly", defaultValue: "\(hours)h", comment: "Log-activity form: duration stepper value, whole hours only") }
        return String(localized: "logWorkout.duration.hoursAndMinutes", defaultValue: "\(hours)h \(mins)m", comment: "Log-activity form: duration stepper value, hours and minutes")
    }
}

#Preview {
    LogManualWorkoutView()
}
