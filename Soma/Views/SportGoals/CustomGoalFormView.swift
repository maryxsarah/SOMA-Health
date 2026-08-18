import PhotosUI
import SwiftUI

/// S3 -- the coach's task. AI can pre-fill from text/photo, but every
/// field stays editable and nothing submits until the user taps Start.
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
    @State private var isParsingAssignment = false
    /// True after a parse came back too unsure to trust -- no field was
    /// touched; this only drives the warning note.
    @State private var assistLowConfidence = false
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
                    Text(String(localized: "customGoalForm.header.title", defaultValue: "Coach's task", comment: "Screen heading for the custom goal form, where a user enters an assignment from their coach"))
                        .font(Theme.display)
                    Text(String(localized: "customGoalForm.header.subtitle", defaultValue: "The original stays attached — your coach sees exactly what you trained against.", comment: "Subtitle under the custom goal form heading, explaining the original assignment stays attached"))
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
                    SomaButton(title: LocalizedStringKey(isCreating
                        ? String(localized: "goalCreation.button.starting", defaultValue: "Starting…", comment: "Label on the primary CTA button while a goal creation request is in flight")
                        : String(localized: "goalCreation.button.startBlock", defaultValue: "Start the block", comment: "Label on the primary CTA button that creates and starts the goal block")
                    ), size: .lg, variant: .primary, isEnabled: canSubmit) {
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
        .navigationTitle(String(localized: "customGoalForm.navigationTitle", defaultValue: "Your own goal", comment: "Navigation bar title for the custom goal form screen"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, newItem in
            Task {
                guard let newItem, let data = try? await newItem.loadTransferable(type: Data.self) else { return }
                photoImage = UIImage(data: data)
            }
        }
        // Attached here, not inside ScheduleFrequencyPicker -- kept
        // consistent with GoalStartView's own root-level attachment (see
        // that file's comment): a `.sheet` belongs on a stable ancestor,
        // not a reused leaf component, regardless of whether this
        // particular call site is itself unconditional.
        .sheet(isPresented: $showFrequencySheet) {
            ScheduleRulesSheet(scheduleRule: $scheduleRule, scheduleDays: $scheduleDays, courtDays: $courtDays)
        }
    }

    // MARK: - Assignment

    private var assignmentCard: some View {
        CardView {
            Text(String(localized: "customGoalForm.assignmentCard.title", defaultValue: "The assignment", comment: "Card heading above the photo/text entry for the coach's assignment"))
                .font(.body.bold())

            PhotosPicker(selection: $photoItem, matching: .images) {
                HStack(spacing: 10) {
                    if let photoImage {
                        Image(uiImage: photoImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: SomaTokens.rMD, style: .continuous))
                        Text(String(localized: "customGoalForm.photo.attachedLabel", defaultValue: "Photo attached — tap to replace", comment: "Label next to the thumbnail once a photo of the assignment has been attached"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SomaTokens.ink2)
                    } else {
                        Image(systemName: "paperclip")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SomaTokens.accent)
                            .frame(width: 36, height: 36)
                            .background(RoundedRectangle(cornerRadius: SomaTokens.rMD, style: .continuous).fill(SomaTokens.accentSoft))
                        Text(String(localized: "customGoalForm.photo.attachLabel", defaultValue: "Attach a photo of the assignment (optional)", comment: "Label prompting the user to attach an optional photo of the coach's assignment"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SomaTokens.ink2)
                    }
                    Spacer()
                }
            }
            if photoImage != nil, !isParsingAssignment {
                assistButton(title: LocalizedStringKey(String(localized: "customGoalForm.assist.readPhoto", defaultValue: "Read photo with AI", comment: "Button that runs AI parsing on the attached assignment photo to auto-fill the form"))) { Task { await autoFillFromPhoto() } }
            }

            TextField(String(localized: "customGoalForm.givenText.placeholder", defaultValue: "What did your coach set as the goal? (optional)", comment: "Placeholder text in the multi-line field where the user optionally types what their coach set as the goal"), text: $givenText, axis: .vertical)
                .lineLimit(2...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassCardFlat(cornerRadius: SomaTokens.rXL)
            TextField(String(localized: "customGoalForm.workoutText.placeholder", defaultValue: "The workout, in your coach's words", comment: "Placeholder text in the multi-line field where the user types the workout as their coach described it"), text: $workoutText, axis: .vertical)
                .lineLimit(3...6)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassCardFlat(cornerRadius: SomaTokens.rXL)
                .accessibilityIdentifier("workoutTextField")
            if !workoutText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isParsingAssignment {
                assistButton(title: LocalizedStringKey(String(localized: "customGoalForm.assist.autoFillText", defaultValue: "Auto-fill with AI", comment: "Button that runs AI parsing on the typed workout text to auto-fill the form"))) { Task { await autoFillFromText() } }
            }
            if isParsingAssignment {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(String(localized: "customGoalForm.assist.readingProgress", defaultValue: "Reading the assignment…", comment: "Progress label shown while AI is parsing the coach's assignment"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if assistLowConfidence {
                Text(String(localized: "customGoalForm.assist.lowConfidence", defaultValue: "Couldn't confidently read an assignment there — check the fields below, or try again.", comment: "Warning shown when AI parsing of the assignment returned low-confidence results"))
                    .font(.caption)
                    .foregroundStyle(SomaTokens.warn)
            }
            TextField(String(localized: "customGoalForm.coachName.placeholder", defaultValue: "Coach's name (optional)", comment: "Placeholder text in the field for the coach's name"), text: $coachName)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassCardFlat(cornerRadius: SomaTokens.rXL)
                .accessibilityIdentifier("coachNameField")
            Text(String(localized: "customGoalForm.coachName.caption", defaultValue: "The name goes on your workouts and the progress card you can send back.", comment: "Caption under the coach's name field explaining where the name is used"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func assistButton(title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "sparkles")
                .font(.system(size: 13, weight: .semibold))
        }
    }

    // MARK: - Schedule

    private var scheduleCard: some View {
        CardView {
            Text(String(localized: "goalCreation.schedule.title", defaultValue: "Schedule", comment: "Card heading above the frequency/schedule picker for a goal block"))
                .font(.body.bold())
            Stepper(String(localized: "customGoalForm.schedule.weeksStepper", defaultValue: "How many weeks did your coach set? \(durationWeeks)", comment: "Stepper label showing the current number of weeks the coach set for this assignment; durationWeeks is an integer"), value: $durationWeeks, in: 1...26)
                .font(.system(size: 13.5))

            ScheduleFrequencyPicker(
                frequencyPerWeek: $frequencyPerWeek,
                scheduleRule: $scheduleRule,
                scheduleDays: $scheduleDays,
                courtDays: $courtDays,
                showFrequencySheet: $showFrequencySheet
            )
        }
    }

    // MARK: - Optional metric

    private var metricCard: some View {
        CardView {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "customGoalForm.metric.title", defaultValue: "Track a measurable (optional)", comment: "Card heading for the optional toggle to track a numeric measurable alongside the custom goal"))
                        .font(.body.bold())
                    Text(String(localized: "customGoalForm.metric.subtitle", defaultValue: "Adds re-tests, the chart, and the progress card.", comment: "Caption explaining what tracking a measurable adds to the goal"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $addMetric)
                    .labelsHidden()
                    .tint(SomaTokens.accent)
            }
            if addMetric {
                TextField(String(localized: "customGoalForm.metric.namePlaceholder", defaultValue: "What are you measuring? e.g. Approach jump", comment: "Placeholder text in the field for naming the custom measurable, with an example"), text: $metricName)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassCardFlat(cornerRadius: SomaTokens.rXL)
                TextField(String(localized: "customGoalForm.metric.unitPlaceholder", defaultValue: "Unit, e.g. cm", comment: "Placeholder text in the field for the measurable's unit, with an example"), text: $metricUnit)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassCardFlat(cornerRadius: SomaTokens.rXL)
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
        case .weekdays where !scheduleDays.isEmpty:
            freq = String(localized: "customGoalForm.commitmentLine.freqWeekdaysCount", defaultValue: "\(scheduleDays.count)× a week", comment: "Frequency phrase: N times per week, count of selected weekdays")
        case .everyOtherDay:
            freq = String(localized: "customGoalForm.commitmentLine.freqEveryOtherDay", defaultValue: "Every other day", comment: "Frequency phrase: training every other day")
        case .beforeCourtDays where !courtDays.isEmpty:
            freq = String(localized: "customGoalForm.commitmentLine.freqBeforeCourtDays", defaultValue: "Before your \(courtDays.count) court days", comment: "Frequency phrase: training before each of N court days, pluralized by count")
        case .readiness:
            freq = String(localized: "customGoalForm.commitmentLine.freqReadiness", defaultValue: "When readiness allows", comment: "Frequency phrase: schedule driven by readiness rather than fixed days")
        default:
            freq = String(localized: "customGoalForm.commitmentLine.freqPerWeekCount", defaultValue: "\(frequencyPerWeek)× a week", comment: "Frequency phrase: fixed N times per week")
        }
        let weeksText = String(
            localized: "customGoalForm.weeksStandalone",
            defaultValue: "\(durationWeeks) weeks",
            comment: "Bare week count, pluralized by count"
        )
        return String(localized: "customGoalForm.commitmentLine.template", defaultValue: "\(freq) for \(weeksText) — re-check with your coach around \(SportGoalFormat.shortDate(recheckDate)).", comment: "Commitment summary line: frequency phrase, duration in weeks (already pluralized), and the re-check date")
    }

    private var effectiveFrequency: Int {
        ScheduleFrequencyPicker.effectiveFrequency(
            frequencyPerWeek: frequencyPerWeek,
            scheduleRule: scheduleRule,
            scheduleDays: scheduleDays,
            courtDays: courtDays
        )
    }

    // MARK: - AI assist

    private func autoFillFromText() async {
        await runAssignmentParse { try await SupabaseClient.shared.parseGoalAssignment(text: workoutText) }
    }

    private func autoFillFromPhoto() async {
        guard let photoImage, let compressed = ImageCompression.jpeg(photoImage) else { return }
        await runAssignmentParse { try await SupabaseClient.shared.parseGoalAssignment(imageData: compressed) }
    }

    private func runAssignmentParse(_ call: () async throws -> GoalAssignmentParseResult) async {
        errorMessage = nil
        assistLowConfidence = false
        isParsingAssignment = true
        defer { isParsingAssignment = false }
        do {
            let result = try await call()
            if let parsed = result.parsed {
                applyParsed(parsed)
            } else {
                assistLowConfidence = true
            }
        } catch {
            errorMessage = String(localized: "customGoalForm.error.parseFailed", defaultValue: "Couldn't read that — try again, or fill in the fields yourself.", comment: "Error shown when AI parsing of a photographed or typed coach assignment fails")
        }
    }

    /// Only overwrites a field the parse actually found something for --
    /// never blanks out text the user already typed themselves.
    private func applyParsed(_ parsed: ParsedAssignment) {
        if let given = parsed.givenText { givenText = given }
        if let workout = parsed.workoutText { workoutText = workout }
        if let coach = parsed.coachName { coachName = coach }
        if let weeks = parsed.durationWeeks { durationWeeks = weeks }
        if let rule = parsed.scheduleRule {
            scheduleRule = rule
            scheduleDays = Set(parsed.scheduleDays ?? [])
            courtDays = Set(parsed.courtDays ?? [])
        } else if let freq = parsed.frequencyPerWeek {
            scheduleRule = nil
            frequencyPerWeek = freq
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
                errorMessage = String(localized: "goalCreation.error.baselineFailed", defaultValue: "Your goal started, but the baseline couldn't be saved — tap the button again to retry.", comment: "Error shown when goal creation succeeded but saving the baseline measurement failed")
            }
        } catch {
            errorMessage = String(localized: "goalCreation.error.startFailed", defaultValue: "Couldn't start the goal. Try again.", comment: "Generic error shown when starting a goal fails")
        }
    }
}
