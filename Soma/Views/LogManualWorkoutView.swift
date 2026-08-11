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

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Soccer training, Hot yoga, Volleyball", text: $title)
                    Picker("Focus", selection: $bodyPart) {
                        ForEach(Self.focusOptions, id: \.self) { part in
                            Text(part.displayName).tag(part)
                        }
                    }
                    Picker("Effort", selection: $category) {
                        ForEach(Self.intensityOptions, id: \.self) { intensity in
                            Text(intensity.displayTitle).tag(intensity)
                        }
                    }
                } header: {
                    Text("What did you do?")
                } footer: {
                    Text("Effort helps Soma calibrate tomorrow's plan around today's real training load.")
                }

                Section {
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    DatePicker("Start time", selection: $startTime, displayedComponents: .hourAndMinute)
                    Stepper(value: $durationMinutes, in: 5...300, step: 5) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(Self.durationLabel(durationMinutes))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("When")
                } footer: {
                    Text("Used to pull your real heart rate for this exact window from Apple Health or a connected wearable, if one reported it.")
                }

                Section("Notes (optional)") {
                    TextField("Anything worth remembering", text: $notes, axis: .vertical)
                        .lineLimit(1...3)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(SomaTokens.danger)
                }
            }
            .navigationTitle("Log an activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
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
            errorMessage = "Couldn't log that activity. Try again."
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
        if hours == 0 { return "\(mins) min" }
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)m"
    }
}

#Preview {
    LogManualWorkoutView()
}
