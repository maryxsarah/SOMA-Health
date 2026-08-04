import PhotosUI
import SuperwallKit
import SwiftUI

/// Editable profile: contact email (display-only, never a login credential
/// -- the app still signs in only via Sign in with Apple), training goals,
/// available equipment/access, and injuries. Feeds into workout-suggestion
/// filtering (RecommendationDetailView) and the injury-based intensity cap
/// (generate-recommendation Edge Function).
///
/// Guide 05 of the handoff: three tabs (Training / Health & Safety /
/// Account), each field collapsed to a summary row (label / one-line
/// consequence / current value / chevron) that taps through to a detail
/// sheet -- replacing the previous expand-in-place DisclosureGroup rows.
/// The editor content inside each sheet is unchanged from before; only the
/// container changed.
struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    /// True when HomeView's goal-progress card opened this sheet directly --
    /// jumps straight to the body photos detail sheet instead of landing on
    /// the plain Training tab, so "see your progress" is actually one tap,
    /// not "open profile, then find the row yourself."
    var openBodyPhotosOnAppear = false

    @State private var section: ProfileSection = .training
    @State private var activeSheet: ProfileSheet?
    @State private var showReferralCodeSheet = false

    // Plain @State strings bound directly via `$` (not a computed
    // Binding(get:set:) built inline in the view body) -- the latter
    // recreates a new closure identity on every keystroke-driven body
    // re-evaluation, which is what was causing the keyboard to dismiss
    // after each character typed. These get folded into `profile` only
    // when loading/saving.
    @State private var goals: Set<GoalTag> = []
    @State private var equipment: Set<EquipmentTag> = []
    @State private var injuryTags: Set<InjuryTag> = []
    @State private var injurySeverity: [InjuryTag: InjurySeverity] = [:]
    @State private var injuryType: [InjuryTag: InjuryType] = [:]
    @State private var injuryPainLevel: [InjuryTag: Int] = [:]
    @State private var contactEmailText = ""
    @State private var otherGoalText = ""
    @State private var otherEquipmentText = ""
    @State private var injuryNotesText = ""
    @State private var experienceLevel: ExperienceLevel?
    @State private var pregnancy: Bool?
    @State private var pregnancyWeek: Int?
    @State private var weeklySessionTarget: Int?
    @State private var sessionsDoneThisWeek = 0
    // Region (country ISO code + free-text city) -- powers the future
    // nearby gyms/partners suggestions; saved via the normal profile flow.
    @State private var countryCode: String?
    @State private var cityText = ""
    // Beta opt-in -- reflects the user's own beta_optins row.
    @State private var betaOptIn = false

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedConfirmation = false

    // Connect-more-devices section -- same connect flow (system pop-up:
    // ASWebAuthenticationSession for Whoop/Oura, HealthKit's native sheet
    // for Apple Health) as the onboarding Connect Device screen, reusing
    // the same ProviderCardView for a consistent look.
    @State private var connecting: Set<Provider> = []
    @State private var deviceErrorMessage: String?

    @State private var showSignOutConfirmation = false
    @State private var showTrainingHistory = false
    // Sport goals -- entry renders only when the RLS-gated catalog is
    // non-empty or a goal already exists (server kill switch looks natural).
    @State private var showSportGoals = false
    @State private var sportCatalogAvailable = false
    @State private var activeSportGoal: UserGoal?
    @State private var sportGoalCatalog: SportCatalog?
    @State private var completedSportGoals = 0
    @State private var pausedSportGoal: UserGoal?
    @State private var showHealthDashboard = false
    @State private var completedWorkoutStreak = 0

    // Body photos -- gated by Config.enableBodyPhotoUpload, see the
    // "Goal & Current Photos" row below.
    @State private var goalBodyPhotoPath: String?
    @State private var currentBodyPhotoPath: String?
    @State private var goalBodyPhotoImage: UIImage?
    @State private var currentBodyPhotoImage: UIImage?
    @State private var goalPhotoItem: PhotosPickerItem?
    @State private var currentPhotoItem: PhotosPickerItem?
    @State private var goalPhotoHistory: [BodyPhotoEntry] = []
    @State private var currentPhotoHistory: [BodyPhotoEntry] = []
    @State private var showingPhotoComparison = false
    @State private var isUploadingGoalPhoto = false
    @State private var isUploadingCurrentPhoto = false
    /// Adult-only gate (App Store 4+ rating) -- fails closed until load()
    /// confirms an 18+ date_of_birth, same posture as PostSetupFlowView's
    /// matching gate on the onboarding version of this same feature.
    @State private var isConfirmedAdultForBodyPhotos = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if !nudges.isEmpty {
                    completionNotice
                }

                SomaSegmentedControl(selection: $section) { $0.title }

                switch section {
                case .training: trainingSection
                case .healthSafety: healthSafetySection
                case .account: accountSection
                }
            }
            .padding(20)
        }
        .somaBackground()
        .sheet(item: $activeSheet) { sheet in
            detailSheet(for: sheet)
        }
        .sheet(isPresented: $showReferralCodeSheet) {
            ReferralCodeSheet()
        }
        .sheet(isPresented: $showTrainingHistory) {
            TrainingHistoryView()
        }
        .sheet(isPresented: $showSportGoals, onDismiss: {
            Task { await loadSportGoalState() }
        }) {
            SportGoalFlowView()
        }
        .sheet(isPresented: $showHealthDashboard) {
            HealthDashboardView()
        }
        .task {
            await load()
            // Gated the same way the row itself is (feature flag + adult
            // confirmation) -- a deep link can't bypass either check.
            if openBodyPhotosOnAppear && Config.enableBodyPhotoUpload && isConfirmedAdultForBodyPhotos {
                activeSheet = .bodyPhotos
            }
        }
        .onChange(of: goalPhotoItem) { _, newItem in
            Task { await uploadBodyPhoto(kind: .goal, item: newItem) }
        }
        .onChange(of: currentPhotoItem) { _, newItem in
            Task { await uploadBodyPhoto(kind: .current, item: newItem) }
        }
        .confirmationDialog(
            "Log out of Soma?",
            isPresented: $showSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Log Out", role: .destructive) {
                appState.signOut()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Header

    /// No display-name field exists anywhere in this app (only contact
    /// email, which is optional and never shown as an identity) -- a
    /// generic icon here rather than fabricated initials.
    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(SomaTokens.accentSoft)
                .frame(width: 52, height: 52)
                .overlay(Image(systemName: "person.fill").foregroundStyle(SomaTokens.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text("Your profile")
                    .font(Theme.display)
                Text(headerStatusLine)
                    .font(.system(size: 12.5))
                    .foregroundStyle(SomaTokens.ink3)
            }
        }
        .padding(.bottom, 4)
    }

    /// Every clause here is real, currently-known data -- connected
    /// providers, an actual completed-workout streak (same source as the
    /// calendar strip's crown badges), and today's real category. No
    /// placeholder/fabricated clause is added just to match a reference
    /// design's copy.
    private var headerStatusLine: String {
        var parts: [String] = []
        let connected = Provider.allCases.filter { appState.connectedProviders.contains($0) }
        if !connected.isEmpty {
            parts.append(connected.map(\.displayName).joined(separator: " & ") + " connected")
        }
        if completedWorkoutStreak > 0 {
            parts.append("\(completedWorkoutStreak)-day streak")
        }
        if let category = appState.currentRecommendation?.category.displayTitle {
            parts.append(category)
        }
        return parts.isEmpty ? "Soma uses this to tailor which workouts it suggests." : parts.joined(separator: " · ")
    }

    // MARK: - Completion notice

    private struct Nudge: Identifiable {
        let id: String
        let text: String
    }

    /// A short, real checklist -- not fixed placeholder copy. Only ever
    /// names things that are actually true right now. Shown only while
    /// something is missing (guide 05's own rule).
    private var nudges: [Nudge] {
        var items: [Nudge] = []
        if !appState.connectedProviders.contains(.appleHealth) {
            items.append(Nudge(id: "health", text: "add Apple Health"))
        }
        // No injury nudge: an empty injury list is a complete, valid
        // answer ("None noted"), not an unfinished profile item.
        if weeklySessionTarget == nil {
            items.append(Nudge(id: "target", text: "set a weekly target"))
        }
        // Only nudged while the catalog is actually open and no goal is set
        // -- an empty catalog means the feature is off, not unfinished.
        if Config.enableSportGoals, sportCatalogAvailable, activeSportGoal == nil, pausedSportGoal == nil {
            items.append(Nudge(id: "goal", text: "pick a goal"))
        }
        return items
    }

    /// Uppercases only the first letter -- .capitalized would title-case
    /// every word ("Add Apple Health And Confirm...").
    private func sentenceCased(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private var completionNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(SomaTokens.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(nudges.count) to finish")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SomaTokens.warn)
                Text("\(sentenceCased(nudges.map(\.text).joined(separator: " and "))) to sharpen suggestions.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(SomaTokens.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous)
                .fill(SomaTokens.warnSoft)
                .overlay(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).stroke(SomaTokens.warnLine, lineWidth: 1))
        )
    }

    // MARK: - Training tab

    private var trainingSection: some View {
        VStack(spacing: 10) {
            summaryRow(
                title: "Experience",
                consequence: "Sets block count, supersets and rest",
                value: experienceLevel?.displayName ?? "Not set"
            ) { activeSheet = .experience }

            summaryRow(
                title: "Goals",
                consequence: "Prioritizes which workouts are suggested first",
                value: goals.isEmpty ? "Not set" : "\(goals.count) selected"
            ) { activeSheet = .goals }

            summaryRow(
                title: "Equipment & access",
                consequence: "Only suggests workouts you can actually do",
                value: equipment.isEmpty ? "Not set" : equipment.map(\.displayName).joined(separator: ", ")
            ) { activeSheet = .equipment }

            summaryRow(
                title: "Weekly target",
                consequence: "Personal tracking goal only -- doesn't change suggestions",
                value: weeklySessionTarget.map { "\($0)/wk · \(sessionsDoneThisWeek) done" } ?? "Not set"
            ) { activeSheet = .weeklyTarget }

            if showSportGoalRow {
                summaryRow(
                    title: "My goal",
                    consequence: "Adds goal work to your daily plan",
                    value: sportGoalRowValue
                ) {
                    AnalyticsManager.shared.featureUsed(name: "sport_goal_flow")
                    showSportGoals = true
                }
            }
        }
    }

    /// Kill switch: the row exists only when the server-gated catalog has
    /// content, or the user already has goal data to reach.
    private var showSportGoalRow: Bool {
        Config.enableSportGoals && (sportCatalogAvailable || activeSportGoal != nil || completedSportGoals > 0 || pausedSportGoal != nil)
    }

    /// Must mirror what the goal screen actually opens to -- a paused goal
    /// still names the row ("Not set" while the hub shows a goal is a lie).
    private var sportGoalRowValue: String {
        let doneSuffix = completedSportGoals > 0 ? " · \(completedSportGoals) done" : ""
        if let activeSportGoal {
            return activeSportGoal.displayName(in: sportGoalCatalog) + doneSuffix
        }
        if let pausedSportGoal {
            return pausedSportGoal.displayName(in: sportGoalCatalog) + " · paused"
        }
        if completedSportGoals > 0 { return "\(completedSportGoals) done" }
        return "Not set"
    }

    // MARK: - Health & Safety tab

    private var healthSafetySection: some View {
        VStack(spacing: 10) {
            groupEyebrow("SAFETY")

            summaryRow(
                title: "Injuries",
                consequence: injuryTags.isEmpty ? "None noted" : "Caps today's intensity at Moderate, hides high impact",
                value: injuryTags.isEmpty ? "None noted" : injuryTags.map(\.displayName).joined(separator: ", "),
                valueColor: injuryTags.isEmpty ? nil : SomaTokens.danger
            ) { activeSheet = .injuries }

            summaryRow(
                title: "Pregnancy",
                consequence: "Withholds generated workouts until confirmed",
                value: pregnancy == true ? (pregnancyWeek.map { "Week \($0)" } ?? "Yes") : "Not set"
            ) { activeSheet = .pregnancy }

            if Config.enableBodyPhotoUpload && isConfirmedAdultForBodyPhotos {
                summaryRow(
                    title: "Body photos",
                    consequence: "Helps personalize your plan toward your goal",
                    value: "\(goalPhotoHistory.count) goal, \(currentPhotoHistory.count) current"
                ) { activeSheet = .bodyPhotos }
            }

            groupEyebrow("INSIGHTS")

            summaryRow(title: "Training history", consequence: "Every logged workout", value: "") {
                AnalyticsManager.shared.featureUsed(name: "training_history")
                showTrainingHistory = true
            }
            summaryRow(title: "Health dashboard", consequence: "Recovery, sleep, HRV trends", value: "") {
                AnalyticsManager.shared.featureUsed(name: "health_dashboard")
                showHealthDashboard = true
            }
        }
    }

    // MARK: - Account tab

    private var accountSection: some View {
        VStack(spacing: 10) {
            summaryRow(
                title: "Contact email",
                consequence: "Never used to sign in -- display only",
                value: contactEmailText.isEmpty ? "Not set" : contactEmailText
            ) { activeSheet = .contactEmail }

            summaryRow(
                title: "Region",
                consequence: "Powers nearby gym & coach suggestions",
                value: UserProfile.regionDisplay(country: countryCode, city: cityText) ?? "Not set"
            ) { activeSheet = .region }

            groupEyebrow("EARLY ACCESS")
            betaOptInRow

            groupEyebrow("CONNECTED DEVICES")
            ForEach(Provider.allCases) { provider in
                deviceRow(provider)
            }
            if let deviceErrorMessage {
                Text(deviceErrorMessage)
                    .font(.caption)
                    .foregroundStyle(SomaTokens.danger)
            }

            groupEyebrow("PLAN")
            summaryRow(title: "Subscription", consequence: subscriptionStatusText, value: "") {
                if !subscriptionManager.isSubscribed { presentPremiumPaywall() }
            }
            summaryRow(title: "Referral code", consequence: "Redeem a code for free access", value: "") {
                showReferralCodeSheet = true
            }
            summaryRow(title: "Feedback", consequence: "Spotted a bug, or have an idea?", value: "") {
                FeedbackPresenter.present()
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(SomaTokens.danger)
            }
            if savedConfirmation {
                Text("Saved.").font(.caption).foregroundStyle(SomaTokens.success)
            }

            SomaButton(title: "Sign out", size: .md, variant: .danger, isBlock: true) {
                showSignOutConfirmation = true
            }
            .padding(.top, 6)
        }
    }

    /// Toggle row styled like a setting row. The write happens in the
    /// binding's setter, so programmatic loads never trigger a write.
    private var betaOptInRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sport goals (beta)")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink)
                Text("Beta features appear automatically while this is on.")
                    .font(.system(size: 12))
                    .foregroundStyle(SomaTokens.ink3)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { betaOptIn },
                set: { newValue in
                    betaOptIn = newValue
                    Task { await updateBetaOptIn(newValue) }
                }
            ))
            .labelsHidden()
            .tint(SomaTokens.accent)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.surface))
    }

    private func updateBetaOptIn(_ enabled: Bool) async {
        do {
            try await SupabaseClient.shared.setBetaOptIn(enabled)
            errorMessage = nil
            // Refetch the catalog in both directions: ON surfaces the beta
            // rows this session, OFF makes every entry point vanish.
            await loadSportGoalState()
        } catch {
            betaOptIn = !enabled
            errorMessage = "Couldn't update beta access. Try again."
        }
    }

    // MARK: - Row primitives

    private func groupEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(SomaTokens.ink4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    /// `label / one-line consequence / current value / ›` -- guide 05's
    /// row shape. Tapping presents whatever detail the caller wired up
    /// (usually `activeSheet = .someCase`).
    private func summaryRow(title: String, consequence: String, value: String, valueColor: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(SomaTokens.ink)
                    Text(consequence)
                        .font(.system(size: 12))
                        .foregroundStyle(SomaTokens.ink3)
                        .lineLimit(1)
                }
                Spacer()
                if !value.isEmpty {
                    Text(value)
                        .font(.system(size: 13))
                        .foregroundStyle(valueColor ?? SomaTokens.ink2)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink5)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.surface))
        }
        .buttonStyle(.plain)
    }

    /// Device rows: status dot, value in success/accent, no chevron --
    /// visually distinct from a setting row (guide 05's own distinction).
    private func deviceRow(_ provider: Provider) -> some View {
        let isConnected = appState.connectedProviders.contains(provider)
        // Server-verified: the stored refresh token failed (revoked,
        // expired) so the connection is dead even though the local cache
        // still says "connected." Tappable in this state -- unlike a
        // healthy connection, which is only ever disconnected by the
        // provider's own app/website, not from here.
        let needsReconnect = appState.providersNeedingReconnect.contains(provider)
        return Button {
            if !isConnected || needsReconnect { connectDevice(provider) }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(needsReconnect ? SomaTokens.warn : (isConnected ? SomaTokens.successDot : SomaTokens.neutralDot))
                    .frame(width: 8, height: 8)
                Text(provider.displayName)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink)
                Spacer()
                if connecting.contains(provider) {
                    ProgressView()
                } else if needsReconnect {
                    Text("Reconnect")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SomaTokens.warn)
                } else {
                    Text(isConnected ? "Connected" : "Connect")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isConnected ? SomaTokens.success : SomaTokens.accent)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.surface))
        }
        .buttonStyle(.plain)
        .disabled((isConnected && !needsReconnect) || connecting.contains(provider))
    }

    // MARK: - Detail sheets

    @ViewBuilder
    private func detailSheet(for sheet: ProfileSheet) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch sheet {
                    case .experience: experienceEditor
                    case .goals: goalsEditor
                    case .equipment: equipmentEditor
                    case .weeklyTarget: weeklyTargetEditor
                    case .injuries: injuriesEditor
                    case .pregnancy: pregnancyEditor
                    case .bodyPhotos: bodyPhotosEditor
                    case .contactEmail: contactEmailEditor
                    case .region: regionEditor
                    }
                }
                .padding(20)
                .dismissKeyboardOnTap()
            }
            .scrollDismissesKeyboard(.interactively)
            .somaBackground()
            .navigationTitle(sheet.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save()
                        activeSheet = nil
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private var experienceEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Adjusts the AI workout plan's structure -- how many blocks, whether it uses supersets, and rest periods.")
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout {
                ForEach(ExperienceLevel.allCases) { level in
                    ChipToggle(title: level.displayName, isSelected: experienceLevel == level) {
                        experienceLevel = experienceLevel == level ? nil : level
                    }
                }
            }
        }
    }

    private var goalsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout {
                ForEach(GoalTag.allCases) { tag in
                    ChipToggle(title: tag.displayName, isSelected: goals.contains(tag)) {
                        toggle(tag, in: &goals)
                    }
                }
            }
            if goals.contains(.other) {
                TextField("What's your goal?", text: $otherGoalText)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var equipmentEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout {
                ForEach(EquipmentTag.allCases) { tag in
                    ChipToggle(title: tag.displayName, isSelected: equipment.contains(tag)) {
                        toggle(tag, in: &equipment)
                    }
                }
            }
            if equipment.contains(.other) {
                TextField("What else do you have access to?", text: $otherEquipmentText)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var weeklyTargetEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A personal tracking goal -- doesn't change what Soma recommends, just what it shows you here.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper(
                "Target: \(weeklySessionTarget.map(String.init) ?? "not set") sessions/week",
                value: Binding(get: { weeklySessionTarget ?? 3 }, set: { weeklySessionTarget = $0 }),
                in: 1...14
            )
            .font(.caption)
            if weeklySessionTarget != nil {
                Text("\(sessionsDoneThisWeek) done this week so far.")
                    .font(.caption.bold())
                    .foregroundStyle(SomaTokens.accent)
            }
        }
    }

    private var injuriesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Any active injury caps today's intensity at Moderate and hides high-impact workouts.")
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout {
                ForEach(InjuryTag.allCases) { tag in
                    ChipToggle(title: tag.displayName, isSelected: injuryTags.contains(tag)) {
                        toggle(tag, in: &injuryTags)
                        if injuryTags.contains(tag), injurySeverity[tag] == nil {
                            injurySeverity[tag] = .moderate
                        }
                    }
                }
            }
            ForEach(InjuryTag.allCases.filter { injuryTags.contains($0) }) { tag in
                VStack(alignment: .leading, spacing: 4) {
                    Text(tag.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(tag.displayName, selection: Binding(
                        get: { injurySeverity[tag] ?? .moderate },
                        set: { injurySeverity[tag] = $0 }
                    )) {
                        ForEach(InjurySeverity.allCases) { severity in
                            Text(severity.displayName).tag(severity)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Type (optional)", selection: Binding(
                        get: { injuryType[tag] },
                        set: { injuryType[tag] = $0 }
                    )) {
                        Text("Not specified").tag(InjuryType?.none)
                        ForEach(InjuryType.allCases) { type in
                            Text(type.displayName).tag(InjuryType?.some(type))
                        }
                    }
                    .font(.caption)

                    Stepper(
                        "Pain level: \(injuryPainLevel[tag].map(String.init) ?? "not set")",
                        value: Binding(get: { injuryPainLevel[tag] ?? 1 }, set: { injuryPainLevel[tag] = $0 }),
                        in: 1...10
                    )
                    .font(.caption)

                    if injurySeverity[tag] == .moderate || injurySeverity[tag] == .severe {
                        Text("Given the severity you've selected, consider seeing a physician or physiotherapist before continuing to train this area. Soma's guidance here is informational only, not a diagnosis.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.top, 4)
            }
            TextField("Notes (optional)", text: $injuryNotesText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)
        }
    }

    private var pregnancyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Optional, and never assumed -- only set if you tell us. Soma will adjust your workouts to your pregnancy stage rather than withhold them. This is general guidance only -- please follow your doctor's or midwife's advice, especially if you have any pregnancy complications.")
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout {
                ChipToggle(title: "I'm currently pregnant", isSelected: pregnancy == true) {
                    pregnancy = (pregnancy == true) ? nil : true
                    if pregnancy != true { pregnancyWeek = nil }
                }
            }
            if pregnancy == true {
                Stepper(
                    "Week: \(pregnancyWeek.map(String.init) ?? "not set")",
                    value: Binding(get: { pregnancyWeek ?? 1 }, set: { pregnancyWeek = $0 }),
                    in: 1...42
                )
                .font(.caption)
            }
        }
    }

    private var bodyPhotosEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Optional -- helps personalize your plan toward your goal.")
                .font(.caption)
                .foregroundStyle(.secondary)
            // errorMessage otherwise only renders on the Account tab --
            // a failed remove/upload here would look like a silent no-op.
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 16) {
                bodyPhotoSlot(
                    title: "Goal body",
                    image: goalBodyPhotoImage,
                    isUploading: isUploadingGoalPhoto,
                    selection: $goalPhotoItem,
                    onRemove: { Task { await removeBodyPhoto(kind: .goal) } }
                )
                bodyPhotoSlot(
                    title: "Current body",
                    image: currentBodyPhotoImage,
                    isUploading: isUploadingCurrentPhoto,
                    selection: $currentPhotoItem,
                    onRemove: { Task { await removeBodyPhoto(kind: .current) } }
                )
            }
            if let goalBodyPhotoImage, let currentBodyPhotoImage {
                Button {
                    AnalyticsManager.shared.featureUsed(name: "body_photo_comparison")
                    showingPhotoComparison = true
                } label: {
                    Label("Compare Goal vs. Current", systemImage: "arrow.left.and.right.square")
                        .font(.caption.bold())
                }
                .sheet(isPresented: $showingPhotoComparison) {
                    BodyPhotoComparisonView(goalImage: goalBodyPhotoImage, currentImage: currentBodyPhotoImage)
                }
            }
        }
    }

    private var contactEmailEditor: some View {
        TextField("you@example.com", text: $contactEmailText)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
    }

    /// ISO region codes sorted by their localized display name -- never a
    /// hand-maintained country list.
    private static let countryOptions: [(code: String, name: String)] = Locale.Region.isoRegions
        .map(\.identifier)
        .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
        .compactMap { code in Locale.current.localizedString(forRegionCode: code).map { (code, $0) } }
        .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }

    private var regionEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Used for future nearby gym and coach partner suggestions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Country", selection: $countryCode) {
                Text("Not set").tag(String?.none)
                ForEach(Self.countryOptions, id: \.code) { option in
                    Text(option.name).tag(String?.some(option.code))
                }
            }
            .pickerStyle(.menu)
            TextField("City", text: $cityText)
                .textFieldStyle(.roundedBorder)
        }
    }

    /// Three distinct states worth telling apart: paying, on a referral
    /// bonus (free, but ending), or neither.
    private var subscriptionStatusText: String {
        if subscriptionManager.isSubscribed {
            return "Soma Premium is active."
        }
        if let bonusUntil = appState.referralBonusUntil, bonusUntil > Date() {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "Free until \(formatter.string(from: bonusUntil)) -- tap to subscribe now instead."
        }
        return "Free plan -- today's category and message only."
    }

    private func connectDevice(_ provider: Provider) {
        guard !connecting.contains(provider) else { return }
        connecting.insert(provider)
        deviceErrorMessage = nil

        Task {
            defer { connecting.remove(provider) }
            do {
                switch provider {
                case .appleHealth:
                    try await HealthKitManager.shared.requestAuthorization()
                case .whoop:
                    try await WhoopOAuthManager.shared.connect()
                case .oura:
                    try await OuraOAuthManager.shared.connect()
                }
                appState.markProviderConnected(provider)
            } catch {
                deviceErrorMessage = "Couldn't connect \(provider.displayName): \(error.localizedDescription)"
            }
        }
    }

    private func toggle<T: Hashable>(_ tag: T, in set: inout Set<T>) {
        if set.contains(tag) {
            set.remove(tag)
        } else {
            set.insert(tag)
        }
    }

    private func load() async {
        guard let userId = SupabaseClient.shared.currentUserID else { return }
        guard let profile = try? await SupabaseClient.shared.fetchProfile(id: userId) else { return }

        contactEmailText = profile.contactEmail ?? ""
        goals = Set(profile.goals)
        otherGoalText = profile.otherGoalNotes ?? ""
        equipment = Set(profile.equipment)
        otherEquipmentText = profile.otherEquipmentNotes ?? ""
        injuryTags = Set(profile.injuryTags)
        injurySeverity = Dictionary(uniqueKeysWithValues: profile.injurySeverity.compactMap { key, value in
            InjuryTag(rawValue: key).map { ($0, value) }
        })
        injuryType = Dictionary(uniqueKeysWithValues: profile.injuryType.compactMap { key, value in
            InjuryTag(rawValue: key).map { ($0, value) }
        })
        injuryPainLevel = Dictionary(uniqueKeysWithValues: profile.injuryPainLevel.compactMap { key, value in
            InjuryTag(rawValue: key).map { ($0, value) }
        })
        injuryNotesText = profile.injuryNotes ?? ""
        experienceLevel = profile.experienceLevel
        pregnancy = profile.pregnancy
        pregnancyWeek = profile.pregnancyWeek
        weeklySessionTarget = profile.weeklySessionTarget
        countryCode = profile.country
        cityText = profile.city ?? ""
        betaOptIn = (try? await SupabaseClient.shared.fetchBetaOptIn()) ?? false

        goalBodyPhotoPath = profile.goalBodyPhotoPath
        currentBodyPhotoPath = profile.currentBodyPhotoPath
        isConfirmedAdultForBodyPhotos = AgeGate.isAdult(dobString: profile.dateOfBirth)
        if Config.enableBodyPhotoUpload && isConfirmedAdultForBodyPhotos {
            if let path = profile.goalBodyPhotoPath {
                goalBodyPhotoImage = await loadBodyPhoto(path: path)
            }
            if let path = profile.currentBodyPhotoPath {
                currentBodyPhotoImage = await loadBodyPhoto(path: path)
            }
            goalPhotoHistory = (try? await SupabaseClient.shared.fetchBodyPhotos(kind: .goal)) ?? []
            currentPhotoHistory = (try? await SupabaseClient.shared.fetchBodyPhotos(kind: .current)) ?? []
        }

        completedWorkoutStreak = (try? await SupabaseClient.shared.fetchRecentWorkoutLogDates())
            .map(Self.streak(from:)) ?? 0
        sessionsDoneThisWeek = await Self.workoutsThisWeek()
        await loadSportGoalState()
        await loadConnectionStatus()

        setSuperwallUserAttributes(profile: profile)
    }

    /// Best-effort, server-verified reconnect state -- distinct from
    /// appState.connectedProviders, which never learns about a dead
    /// refresh token on its own. A failed fetch just leaves the previous
    /// (or empty) state, same "degrade to hidden" posture as the rest of
    /// this load path.
    private func loadConnectionStatus() async {
        guard let status = try? await SupabaseClient.shared.fetchConnectionStatus() else { return }
        var needingReconnect: Set<Provider> = []
        if status.whoop.needsReconnect { needingReconnect.insert(.whoop) }
        if status.oura.needsReconnect { needingReconnect.insert(.oura) }
        appState.providersNeedingReconnect = needingReconnect
    }

    /// Best-effort (`try?` throughout): a failed fetch degrades to hidden
    /// entry points, indistinguishable from the server kill switch.
    private func loadSportGoalState() async {
        guard Config.enableSportGoals else { return }
        // All three in parallel -- none depends on another's result.
        async let catalogFetch: SportCatalog? = try? await SupabaseClient.shared.fetchSportCatalog()
        async let activeGoalFetch: UserGoal? = try? await SupabaseClient.shared.fetchActiveGoal()
        async let historyFetch: [UserGoal] = (try? await SupabaseClient.shared.fetchGoalHistory()) ?? []
        let catalog = await catalogFetch
        sportGoalCatalog = catalog
        sportCatalogAvailable = catalog.map { !$0.isEmpty } ?? false
        activeSportGoal = await activeGoalFetch
        let history = await historyFetch
        completedSportGoals = history.filter { $0.status == .completed }.count
        pausedSportGoal = history.first { $0.status == .paused }
        // Mirrors achievements into Superwall attributes for targeting,
        // same real-data-only rule as setSuperwallUserAttributes.
        if completedSportGoals > 0 {
            Superwall.shared.setUserAttributes(["sport_goal_completions": completedSportGoals])
        }
    }

    /// Real, already-collected profile fields only -- for paywall audience
    /// targeting/personalization in the Superwall dashboard (e.g. showing
    /// a different paywall to beginners vs. advanced users, or excluding
    /// someone with an active referral bonus from a campaign). Never
    /// fabricated, matches this app's standing "no decorative data"
    /// convention -- see AnalyticsManager's own doc comment.
    private func setSuperwallUserAttributes(profile: UserProfile) {
        var attributes: [String: Any] = [
            "goals": profile.goals.map(\.rawValue).joined(separator: ","),
            "equipment_count": profile.equipment.count,
            "referral_bonus_active": appState.referralBonusUntil.map { $0 > Date() } ?? false,
        ]
        attributes["experience_level"] = profile.experienceLevel?.rawValue
        attributes["weekly_session_target"] = profile.weeklySessionTarget
        Superwall.shared.setUserAttributes(attributes)
    }

    /// Opened deliberately from "Subscription" -- unlike the gating
    /// placements in HomeView, there's nothing to unlock here (the user is
    /// just browsing premium options), so the feature closure is empty.
    /// Not skipped for an active referral bonus, unlike the gating
    /// placements -- someone who explicitly taps in to see premium options
    /// should see them regardless.
    private func presentPremiumPaywall() {
        Superwall.shared.register(placement: "view_premium")
    }

    /// Consecutive days up to and including today with a logged workout --
    /// same underlying data (fetchRecentWorkoutLogDates) as the calendar
    /// strip's crown badges, just aggregated into a streak count here.
    private static func streak(from dates: Set<String>) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        var count = 0
        var cursor = Date()
        while dates.contains(formatter.string(from: cursor)) {
            count += 1
            cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return count
    }

    private static func workoutsThisWeek() async -> Int {
        let calendar = Calendar.current
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let logs = (try? await SupabaseClient.shared.fetchWorkoutLogs(
            fromDate: formatter.string(from: weekStart),
            toDate: formatter.string(from: Date())
        )) ?? []
        return Set(logs.map(\.date)).count
    }

    private func loadBodyPhoto(path: String) async -> UIImage? {
        guard let url = try? await SupabaseClient.shared.signedBodyPhotoURL(path: path),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }

    private func bodyPhotoSlot(title: String, image: UIImage?, isUploading: Bool, selection: Binding<PhotosPickerItem?>, onRemove: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: selection, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemGray6))
                        .frame(height: 140)
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else if isUploading {
                        ProgressView()
                    } else {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if image != nil {
                Button("Remove photo", role: .destructive, action: onRemove)
                    .font(.caption)
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
            }
        }
    }

    private func uploadBodyPhoto(kind: SupabaseClient.BodyPhotoKind, item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        guard let compressed = ImageCompression.jpeg(image) else {
            errorMessage = "Couldn't process that photo. Try another one."
            return
        }

        if kind == .goal { isUploadingGoalPhoto = true } else { isUploadingCurrentPhoto = true }
        defer {
            if kind == .goal { isUploadingGoalPhoto = false } else { isUploadingCurrentPhoto = false }
        }

        do {
            try await SupabaseClient.shared.uploadBodyPhoto(kind: kind, imageData: compressed)
            if kind == .goal { goalBodyPhotoImage = image } else { currentBodyPhotoImage = image }
            // Upload paths are unique per call now (no more fixed-name
            // overwrite), so the locally-held path/history need a refresh
            // to stay in sync with what removeBodyPhoto will act on next.
            if let userId = SupabaseClient.shared.currentUserID,
               let refreshed = try? await SupabaseClient.shared.fetchProfile(id: userId) {
                goalBodyPhotoPath = refreshed.goalBodyPhotoPath
                currentBodyPhotoPath = refreshed.currentBodyPhotoPath
            }
            // Silent, fire-and-forget -- fires the instant both photos
            // exist, whichever upload just completed the pair. No loading
            // state, no error surfaced: a failed/skipped analysis is
            // invisible by design (see Config.enableBodyPhotoVisionAnalysis).
            if goalBodyPhotoPath != nil, currentBodyPhotoPath != nil {
                Task { try? await SupabaseClient.shared.analyzeBodyPhotos() }
            }
            if kind == .goal {
                goalPhotoHistory = (try? await SupabaseClient.shared.fetchBodyPhotos(kind: .goal)) ?? []
            } else {
                currentPhotoHistory = (try? await SupabaseClient.shared.fetchBodyPhotos(kind: .current)) ?? []
            }
        } catch {
            errorMessage = "Couldn't upload that photo. Try again."
        }
    }

    private func removeBodyPhoto(kind: SupabaseClient.BodyPhotoKind) async {
        let path = kind == .goal ? goalBodyPhotoPath : currentBodyPhotoPath
        guard let path else {
            errorMessage = "No photo to remove."
            return
        }
        errorMessage = nil
        do {
            try await SupabaseClient.shared.deleteBodyPhoto(kind: kind, path: path)
            // Promote the newest remaining upload so repeated Remove taps
            // walk back through the whole history instead of stranding it.
            let history = (try? await SupabaseClient.shared.fetchBodyPhotos(kind: kind)) ?? []
            var next = history.first
            if let candidate = next {
                do {
                    try await SupabaseClient.shared.pinBodyPhoto(kind: kind, path: candidate.storagePath)
                } catch {
                    // Pin failed, so the server pointer is still empty -- showing
                    // the promoted photo anyway would recreate BUG-45's stranded state.
                    next = nil
                    errorMessage = "Photo removed, but the previous one couldn't be restored. Try again."
                }
            }
            let nextImage: UIImage? = if let next { await loadBodyPhoto(path: next.storagePath) } else { nil }
            if kind == .goal {
                goalBodyPhotoImage = nextImage
                goalBodyPhotoPath = next?.storagePath
                goalPhotoHistory = history
            } else {
                currentBodyPhotoImage = nextImage
                currentBodyPhotoPath = next?.storagePath
                currentPhotoHistory = history
            }
            // The old analysis followed the deleted photo out; refresh it
            // silently if a full pair still exists.
            if goalBodyPhotoPath != nil, currentBodyPhotoPath != nil {
                Task { try? await SupabaseClient.shared.analyzeBodyPhotos() }
            }
        } catch {
            errorMessage = "Couldn't remove that photo. Try again."
        }
    }

    private func save() {
        guard let userId = SupabaseClient.shared.currentUserID else { return }
        isSaving = true
        errorMessage = nil
        savedConfirmation = false

        let profile = UserProfile(
            contactEmail: contactEmailText.isEmpty ? nil : contactEmailText,
            goals: Array(goals),
            otherGoalNotes: otherGoalText.isEmpty ? nil : otherGoalText,
            equipment: Array(equipment),
            otherEquipmentNotes: otherEquipmentText.isEmpty ? nil : otherEquipmentText,
            injuryTags: Array(injuryTags),
            injuryNotes: injuryNotesText.isEmpty ? nil : injuryNotesText,
            experienceLevel: experienceLevel,
            pregnancy: pregnancy,
            pregnancyWeek: pregnancy == true ? pregnancyWeek : nil,
            weeklySessionTarget: weeklySessionTarget,
            country: countryCode,
            city: cityText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : cityText.trimmingCharacters(in: .whitespaces)
        )

        let currentInjuryTags = Array(injuryTags)
        let currentInjurySeverity = injurySeverity
        let currentInjuryType = injuryType
        let currentInjuryPainLevel = injuryPainLevel

        Task {
            defer { isSaving = false }
            do {
                try await SupabaseClient.shared.updateProfile(id: userId, profile: profile)
                try await SupabaseClient.shared.reportInjury(
                    tags: currentInjuryTags,
                    severity: currentInjurySeverity,
                    type: currentInjuryType,
                    painLevel: currentInjuryPainLevel
                )
                savedConfirmation = true
            } catch {
                errorMessage = "Couldn't save profile. Try again."
            }
        }
    }
}

private enum ProfileSection: String, CaseIterable, Identifiable {
    case training, healthSafety, account
    var id: String { rawValue }
    var title: String {
        switch self {
        case .training: "Training"
        case .healthSafety: "Health & Safety"
        case .account: "Account"
        }
    }
}

private enum ProfileSheet: String, Identifiable {
    case experience, goals, equipment, weeklyTarget, injuries, pregnancy, bodyPhotos, contactEmail, region
    var id: String { rawValue }
    var title: String {
        switch self {
        case .experience: "Experience"
        case .goals: "Goals"
        case .equipment: "Equipment & access"
        case .weeklyTarget: "Weekly target"
        case .injuries: "Injuries"
        case .pregnancy: "Pregnancy"
        case .bodyPhotos: "Body photos"
        case .contactEmail: "Contact email"
        case .region: "Region"
        }
    }
}

private struct ChipToggle: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(isSelected ? SomaTokens.accent : Color(.systemGray6)))
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppState())
}
