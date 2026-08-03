import PhotosUI
import SwiftUI

/// S3 -- the coach's task. No model parsing: the photo is an attachment,
/// the user fills the fields by hand, Soma schedules and tracks honestly.
struct CustomGoalFormView: View {
    let sport: Sport
    let onCreated: () async -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var photoImage: UIImage?
    @State private var givenText = ""
    @State private var workoutText = ""
    @State private var coachName = ""
    @State private var durationWeeks = 8
    @State private var frequencyPerWeek = 3
    @State private var scheduleRule: GoalScheduleRule?
    @State private var scheduleDays: Set<Int> = []
    @State private var courtDays: Set<Int> = []
    @State private var showFrequencySheet = false
    @State private var addMetric = false
    @State private var metricName = ""
    @State private var metricUnit = ""
    @State private var metricBaseline: Double = 20
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var conflicts: [GoalSafetyConflict] = []
    /// Cached so the acknowledge-and-resend pass doesn't upload twice.
    @State private var uploadedPhotoPath: String?
    /// Set when the goal was created but its baseline insert failed --
    /// the next tap retries only the baseline (see GoalCreationFlow).
    @State private var pendingBaselineGoal: UserGoal?

    private var canSubmit: Bool {
        !workoutText.trimmingCharacters(in: .whitespaces).isEmpty && !isCreating
    }

    private var recheckDate: Date {
        Calendar.current.date(byAdding: .day, value: durationWeeks * 7, to: Date()) ?? Date()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sport.name.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(SomaTokens.ink3)
                    Text("Coach's task")
                        .font(Theme.display)
                    Text("The original stays attached — your coach sees exactly what you trained against.")
                        .font(.system(size: 13))
                        .foregroundStyle(SomaTokens.ink2)
                }

                assignmentCard
                scheduleCard
                metricCard

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

                if conflicts.isEmpty {
                    SomaButton(title: isCreating ? "Starting…" : "Start the block", size: .lg, variant: .primary, isEnabled: canSubmit) {
                        Task { await create(acknowledged: false) }
                    }
                }
                Text(commitmentLine)
                    .font(.system(size: 12))
                    .foregroundStyle(SomaTokens.ink3)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
            .dismissKeyboardOnTap()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Your own goal")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFrequencySheet) {
            frequencySheet
        }
        .onChange(of: photoItem) { _, newItem in
            Task {
                guard let newItem, let data = try? await newItem.loadTransferable(type: Data.self) else { return }
                photoImage = UIImage(data: data)
            }
        }
    }

    // MARK: - Assignment

    private var assignmentCard: some View {
        CardView {
            Text("The assignment")
                .font(.body.bold())

            PhotosPicker(selection: $photoItem, matching: .images) {
                HStack(spacing: 10) {
                    if let photoImage {
                        Image(uiImage: photoImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: SomaTokens.rMD, style: .continuous))
                        Text("Photo attached — tap to replace")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SomaTokens.ink2)
                    } else {
                        Image(systemName: "paperclip")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SomaTokens.accent)
                            .frame(width: 36, height: 36)
                            .background(RoundedRectangle(cornerRadius: SomaTokens.rMD, style: .continuous).fill(SomaTokens.accentSoft))
                        Text("Attach a photo of the assignment (optional)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SomaTokens.ink2)
                    }
                    Spacer()
                }
            }

            TextField("What did your coach set as the goal? (optional)", text: $givenText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            TextField("The workout, in your coach's words", text: $workoutText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
            TextField("Coach's name (optional)", text: $coachName)
                .textFieldStyle(.roundedBorder)
            Text("The name goes on your workouts and the progress card you can send back.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Schedule

    private var scheduleCard: some View {
        CardView {
            Text("Schedule")
                .font(.body.bold())
            Stepper("How many weeks did your coach set? \(durationWeeks)", value: $durationWeeks, in: 1...26)
                .font(.system(size: 13.5))

            FlowLayout {
                ForEach([2, 3, 4], id: \.self) { count in
                    SomaChip(title: "\(count)× a week", isSelected: scheduleRule == nil && frequencyPerWeek == count) {
                        scheduleRule = nil
                        frequencyPerWeek = count
                    }
                }
                SomaChip(title: customChipTitle, isSelected: scheduleRule != nil, isOneOff: scheduleRule == nil) {
                    showFrequencySheet = true
                }
            }
            Text("Sessions still defer to your readiness for placement — low days shift, the workout itself is never rewritten.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var customChipTitle: String {
        switch scheduleRule {
        case .weekdays: scheduleDays.isEmpty ? "Custom…" : Self.weekdaysLabel(scheduleDays)
        case .everyOtherDay: "Every other day"
        case .beforeCourtDays: "Before court days"
        case .readiness: "When readiness allows"
        case .unknown, nil: "Custom…"
        }
    }

    private static func weekdaysLabel(_ days: Set<Int>) -> String {
        // Monday-first, using the picker's server-value convention (0=Sunday).
        WeekdayMiniPicker.dayValuesInDisplayOrder
            .filter(days.contains)
            .map(WeekdayMiniPicker.shortName(forValue:))
            .joined(separator: " · ")
    }

    /// S3a -- the frequency rules sheet. "Before court days" reveals a
    /// static court-days mini-picker inline; no calendar integration.
    private var frequencySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ruleRow(.weekdays, title: "Specific weekdays", subtitle: "Train on fixed days", icon: "calendar")
                    if scheduleRule == .weekdays {
                        WeekdayMiniPicker(selected: $scheduleDays)
                            .padding(.leading, 4)
                    }
                    ruleRow(.everyOtherDay, title: "Every other day", subtitle: "A steady one-on, one-off rhythm", icon: "arrow.left.arrow.right")
                    ruleRow(.beforeCourtDays, title: "Before court days", subtitle: "Sessions land the day before you play", icon: "figure.tennis")
                    if scheduleRule == .beforeCourtDays {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("My court days")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            WeekdayMiniPicker(selected: $courtDays)
                        }
                        .padding(.leading, 4)
                    }
                    ruleRow(.readiness, title: "When readiness allows", subtitle: "Soma places sessions on your better days", icon: "waveform.path.ecg")
                }
                .padding(20)
            }
            .somaBackground()
            .navigationTitle("Frequency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFrequencySheet = false }
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

    // MARK: - Optional metric

    private var metricCard: some View {
        CardView {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Track a measurable (optional)")
                        .font(.body.bold())
                    Text("Adds re-tests, the chart, and the progress card.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $addMetric)
                    .labelsHidden()
                    .tint(SomaTokens.accent)
            }
            if addMetric {
                TextField("What are you measuring? e.g. Approach jump", text: $metricName)
                    .textFieldStyle(.roundedBorder)
                TextField("Unit, e.g. cm", text: $metricUnit)
                    .textFieldStyle(.roundedBorder)
                RulerNumberPicker(value: $metricBaseline, range: 0...200, unit: metricUnit.isEmpty ? nil : metricUnit)
                    .padding(.top, 4)
            }
        }
    }

    /// The target IS the commitment -- stated plainly, with the fixed
    /// re-check date. Never an app-invented range.
    private var commitmentLine: String {
        var freq: String
        switch scheduleRule {
        case .weekdays where !scheduleDays.isEmpty: freq = "\(scheduleDays.count)× a week"
        case .everyOtherDay: freq = "Every other day"
        case .beforeCourtDays where !courtDays.isEmpty: freq = "Before your \(courtDays.count) court days"
        case .readiness: freq = "When readiness allows"
        default: freq = "\(frequencyPerWeek)× a week"
        }
        return "\(freq) for \(durationWeeks) weeks — re-check with your coach around \(SportGoalFormat.shortDate(recheckDate))."
    }

    private var effectiveFrequency: Int {
        switch scheduleRule {
        case .weekdays where !scheduleDays.isEmpty: scheduleDays.count
        case .everyOtherDay: 3
        case .beforeCourtDays where !courtDays.isEmpty: courtDays.count
        default: frequencyPerWeek
        }
    }

    // MARK: - Create

    private func create(acknowledged: Bool) async {
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        var request = CreateGoalRequest(kind: .custom, targetKind: addMetric && !metricName.isEmpty ? .metric : .commitment)
        request.acknowledgeConflicts = acknowledged
        request.givenText = givenText.isEmpty ? nil : givenText
        request.workoutText = workoutText
        request.coachName = coachName.isEmpty ? nil : coachName
        request.durationWeeks = durationWeeks
        request.frequencyPerWeek = effectiveFrequency
        request.scheduleRule = scheduleRule
        if scheduleRule == .weekdays { request.scheduleDays = scheduleDays.sorted() }
        if scheduleRule == .beforeCourtDays { request.courtDays = courtDays.sorted() }
        if addMetric, !metricName.isEmpty {
            request.customMetricName = metricName
            request.customMetricUnit = metricUnit.isEmpty ? nil : metricUnit
            request.baselineValue = metricBaseline
        }

        do {
            if uploadedPhotoPath == nil, let photoImage,
               let compressed = ImageCompression.jpeg(photoImage) {
                uploadedPhotoPath = try? await SupabaseClient.shared.uploadAssignmentPhoto(imageData: compressed)
            }
            request.assignmentPhotoPath = uploadedPhotoPath
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
}
