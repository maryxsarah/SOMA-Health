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
    @EnvironmentObject private var languageManager: LanguageManager
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    @State private var section: ProfileSection = .training
    @State private var activeSheet: ProfileSheet?
    @State private var showReferralCodeSheet = false
    /// Refresher entry point for the same tour the onboarding checklist's
    /// "See how Soma works" item opens -- see HowSomaWorksTourView's own
    /// doc comment. No completion write here: this row exists precisely
    /// for a user who has already completed onboarding, so there's
    /// nothing left to mark.
    @State private var showHowSomaWorks = false

    // Plain @State strings bound directly via `$` (not a computed
    // Binding(get:set:) built inline in the view body) -- the latter
    // recreates a new closure identity on every keystroke-driven body
    // re-evaluation, which is what was causing the keyboard to dismiss
    // after each character typed. These get folded into `profile` only
    // when loading/saving.
    @State private var goals: Set<GoalTag> = []
    @State private var equipment: Set<EquipmentTag> = []
    @State private var householdEquipment: Set<KitchenEquipmentTag> = []
    @State private var injuryTags: Set<InjuryTag> = []
    @State private var injurySeverity: [InjuryTag: InjurySeverity] = [:]
    @State private var injuryType: [InjuryTag: InjuryType] = [:]
    @State private var injuryPainLevel: [InjuryTag: Int] = [:]
    @State private var contactEmailText = ""
    @State private var otherGoalText = ""
    @State private var otherEquipmentText = ""
    @State private var otherHouseholdEquipmentText = ""
    @State private var injuryNotesText = ""
    @State private var experienceLevel: ExperienceLevel?
    @State private var pregnancy: Bool?
    @State private var pregnancyWeek: Int?
    /// Read-only pass-through -- see UserProfile.sex's own doc comment.
    /// Gates the cycle-tracking row's visibility only, never edited here.
    @State private var sex: Sex?
    /// Opt-in cycle-phase tracking (Phase 5: see
    /// docs/coaching-personalization-plan.md) -- Date here (not the wire
    /// string) for DatePicker, same convention as dateOfBirthDate below;
    /// converted via Self.dobFormatter (identical "yyyy-MM-dd" wire format).
    @State private var lastPeriodStartDate: Date?
    @State private var typicalCycleLengthDays: Int?
    @State private var weeklySessionTarget: Int?
    /// Text, not Double, per pattern -- same "let the user type freely,
    /// parse on save" reasoning as LogMealView's numeric fields. A blank
    /// entry for a pattern just means "keep using the estimate for this
    /// one", not zero.
    @State private var knownLiftsText: [LiftPattern: String] = [:]
    /// Pass-through only -- this screen has no editor for these three yet
    /// (set during onboarding), but updateProfile writes height_cm/
    /// journey_stage/blockers_notes unconditionally (NSNull if absent).
    /// Without loading and re-sending them, ANY save from this screen --
    /// including something as unrelated as changing region -- silently
    /// wiped all three, which in turn silently broke the Health
    /// Dashboard's BMI card (needs height) on the next load. Loaded once
    /// in load(), never mutated by any control here, sent back unchanged.
    @State private var preservedHeightCm: Double?
    @State private var preservedJourneyStage: JourneyStage?
    @State private var preservedBlockersNotes: String?
    /// Unlike the three above, THIS one now has a real editor
    /// (dateOfBirthEditor) -- see UserProfile.dateOfBirth's doc comment.
    /// nil means genuinely unset (an account that predates the onboarding
    /// DOB step), distinct from "user picked today's date" which the
    /// DatePicker binding below needs a concrete non-optional default for.
    @State private var dateOfBirthDate: Date?
    @State private var sessionsDoneThisWeek = 0
    // Region (country ISO code + free-text city) -- powers the future
    // nearby gyms/partners suggestions; saved via the normal profile flow.
    @State private var countryCode: String?
    @State private var cityText = ""
    // Weekly anchor session (Phase 4: see docs/coaching-personalization-plan.md)
    // -- a real editor, unlike preservedHeightCm/etc above, so these are
    // loaded AND sent back live on every save, same as countryCode/cityText.
    @State private var anchorSessionName = ""
    @State private var anchorSessionDays: Set<Int> = []
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

    // Body photos -- gated by Config.enableBodyPhotoUpload. The actual
    // photos/history/upload UI now lives entirely in GoalBodyProgressView
    // (its own destination, not a Profile settings sheet) -- this row only
    // needs to know whether to show the entry point at all.
    /// Adult-only gate (App Store 4+ rating) -- fails closed until load()
    /// confirms an 18+ date_of_birth, same posture as PostSetupFlowView's
    /// matching gate on the onboarding version of this same feature.
    @State private var isConfirmedAdultForBodyPhotos = false
    @State private var showGoalBodyProgress = false

    // Profile picture -- avatar_photo_path on `users`, its own private
    // Storage bucket (avatars), same signed-URL pattern as body photos.
    @State private var avatarImage: UIImage?
    @State private var avatarPhotoPath: String?
    @State private var avatarItem: PhotosPickerItem?
    @State private var showAvatarPicker = false
    @State private var isUploadingAvatar = false
    /// Its own state, separate from the Account tab's save-flow
    /// errorMessage -- the avatar button lives in the header, visible on
    /// every tab, so its error needs to be visible there too rather than
    /// only surfacing if the user happens to be on the Account tab.
    @State private var avatarErrorMessage: String?

    // Streak badges + share card -- completedWorkoutStreak above is the
    // real number. Today's steps are fetched purely for the optional
    // share-card chip (best-effort, nil if HealthKit is unavailable/
    // unauthorized -- never blocks anything else on this screen).
    @State private var showStreakShareSheet = false
    @State private var todaysSteps: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let avatarErrorMessage {
                    Text(avatarErrorMessage)
                        .font(.caption)
                        .foregroundStyle(SomaTokens.danger)
                }

                streakSection

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
        .sheet(isPresented: $showHowSomaWorks) {
            HowSomaWorksTourView(onFinish: { showHowSomaWorks = false })
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
        .sheet(isPresented: $showGoalBodyProgress) {
            GoalBodyProgressView()
        }
        .sheet(isPresented: $showStreakShareSheet) {
            StreakShareSheet(
                streakDays: completedWorkoutStreak,
                category: appState.currentRecommendation?.category,
                steps: todaysSteps
            )
        }
        .onChange(of: avatarItem) { _, newItem in
            Task { await uploadAvatar(item: newItem) }
        }
        .task {
            await load()
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
    /// email, which is optional and never shown as an identity) -- the
    /// avatar itself is the one piece of real personalization here.
    private var header: some View {
        HStack(spacing: 12) {
            avatarButton
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

    /// Tap opens a menu (Choose Photo / Remove Photo, the latter only
    /// once one exists) rather than jumping straight into the picker --
    /// same discoverable-but-not-cluttered pattern as Contacts/Messages'
    /// own avatar-edit affordance. The small camera badge signals it's
    /// editable without needing separate always-visible chrome.
    private var avatarButton: some View {
        Menu {
            Button {
                showAvatarPicker = true
            } label: {
                Label("Choose Photo", systemImage: "photo")
            }
            if avatarImage != nil {
                Button(role: .destructive) {
                    Task { await removeAvatar() }
                } label: {
                    Label("Remove Photo", systemImage: "trash")
                }
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let avatarImage {
                        Image(uiImage: avatarImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Circle()
                            .fill(SomaTokens.accentSoft)
                            .overlay(Image(systemName: "person.fill").foregroundStyle(SomaTokens.accent))
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .overlay(Circle().stroke(SomaTokens.hairline, lineWidth: 1))
                .opacity(isUploadingAvatar ? 0.4 : 1)

                if isUploadingAvatar {
                    ProgressView()
                        .frame(width: 52, height: 52)
                } else {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Circle().fill(SomaTokens.accent))
                        .overlay(Circle().stroke(SomaTokens.surface, lineWidth: 2))
                }
            }
        }
        .disabled(isUploadingAvatar)
        .photosPicker(isPresented: $showAvatarPicker, selection: $avatarItem, matching: .images)
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
            let connectedNames = connected.map(\.displayName).joined(separator: " & ")
            parts.append(String(localized: "profile.header.connectedDevices", defaultValue: "\(connectedNames) connected", comment: "Profile header status line naming the connected device providers, e.g. 'Whoop & Oura connected'"))
        }
        if completedWorkoutStreak > 0 {
            parts.append(String(localized: "profile.header.streakDays", defaultValue: "\(completedWorkoutStreak)-day streak", comment: "Profile header status line: current workout streak length in days"))
        }
        if let category = appState.currentRecommendation?.category.displayTitle {
            parts.append(category)
        }
        return parts.isEmpty ? String(localized: "profile.header.defaultTagline", defaultValue: "Soma uses this to tailor which workouts it suggests.", comment: "Default profile header subtitle shown before any status fragments are available") : parts.joined(separator: " · ")
    }

    // MARK: - Streak

    /// Visible as soon as Settings opens, above every tab -- the real
    /// completedWorkoutStreak count (same source as the header line and
    /// Home's calendar strip), shown as badges instead of just a number,
    /// plus an Oura-style share card once there's something worth sharing.
    private var streakSection: some View {
        CardView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [SomaTokens.accent, SomaTokens.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 46, height: 46)
                        Image(systemName: "flame.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(completedWorkoutStreak > 0 ? "\(completedWorkoutStreak)-day streak" : "No active streak")
                            .font(.system(size: 16.5, weight: .bold))
                        Text(completedWorkoutStreak > 0 ? "Keep showing up -- consistency compounds." : "Log a workout today to start one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if completedWorkoutStreak > 0 {
                        Button {
                            showStreakShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(SomaTokens.accent)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(SomaTokens.accentSoft))
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(StreakMilestone.allCases) { milestone in
                            streakBadge(milestone)
                        }
                    }
                }
            }
        }
    }

    private func streakBadge(_ milestone: StreakMilestone) -> some View {
        let achieved = milestone.isAchieved(streak: completedWorkoutStreak)
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(achieved
                        ? AnyShapeStyle(LinearGradient(colors: [SomaTokens.accent, SomaTokens.accentDeep], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(SomaTokens.surface3))
                    .frame(width: 42, height: 42)
                Image(systemName: achieved ? "flame.fill" : "lock.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(achieved ? .white : SomaTokens.ink4)
            }
            Text(milestone.title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(achieved ? SomaTokens.ink : SomaTokens.ink4)
        }
        .frame(width: 54)
    }

    /// A branded card rendered off-screen to a real UIImage via
    /// ImageRenderer, then handed to ShareLink -- same idea as Oura's
    /// streak-share card, but transparent outside the rounded card itself
    /// (real alpha, not a white/neutral fill) so it can be dropped onto an
    /// existing Instagram Story or post as an overlay, not just used as a
    /// full-bleed background. The canvas is sized to exactly 1080x1920 at
    /// 3x scale -- Instagram Stories' own native resolution -- so it never
    /// gets stretched or cropped oddly regardless of how it's shared.
    private struct StreakShareCardView: View {
        let streakDays: Int
        var category: RecommendationCategory? = nil
        var steps: Int? = nil

        private var dateLine: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: Date())
        }

        var body: some View {
            ZStack {
                Color.clear

                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [SomaTokens.accentDeep, SomaTokens.accent, SomaTokens.accent.opacity(0.8)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        // Soft spotlight glow, offset toward the flame badge,
                        // for depth -- clipped to the card so it never spills
                        // into the transparent margin around it.
                        RadialGradient(colors: [.white.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 0.32), startRadius: 4, endRadius: 220)
                    )
                    .overlay(
                        VStack(spacing: 0) {
                            Image("SomaWordmark")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.white)
                                .frame(width: 92)
                                .padding(.top, 36)

                            Spacer()

                            ZStack {
                                Circle().fill(.white.opacity(0.15)).frame(width: 116, height: 116)
                                Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5).frame(width: 116, height: 116)
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.white)
                            }

                            Text("\(streakDays)")
                                .font(.system(size: 76, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.top, 12)
                            Text(streakDays == 1
                                ? String(localized: "profile.dayStreakLabel", defaultValue: "DAY STREAK", comment: "Label under the big streak count number (singular)")
                                : String(localized: "profile.dayStreakLabelPlural", defaultValue: "DAY STREAKS", comment: "Label under the big streak count number (plural)"))
                                .font(.system(size: 16, weight: .bold))
                                .tracking(4)
                                .foregroundStyle(.white.opacity(0.92))

                            if category != nil || steps != nil {
                                HStack(spacing: 8) {
                                    if let category {
                                        chip(icon: categoryIcon(category), text: category.displayTitle)
                                    }
                                    if let steps {
                                        chip(icon: "figure.walk", text: String(localized: "profile.streakShare.stepsChip", defaultValue: "\(steps.formatted()) steps", comment: "Step count chip shown on the shareable streak card image"))
                                    }
                                }
                                .padding(.top, 16)
                            }

                            Spacer()

                            Text(dateLine)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.bottom, 24)
                        }
                        .padding(.horizontal, 18)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                    .frame(width: 300, height: 470)
                    .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 14)
            }
            .frame(width: 360, height: 640)
        }

        private func chip(icon: String, text: String) -> some View {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11.5, weight: .bold))
                Text(text).font(.system(size: 12.5, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(.white.opacity(0.16)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
        }

        private func categoryIcon(_ category: RecommendationCategory) -> String {
            switch category {
            case .pushHard: "flame.fill"
            case .moderate: "bolt.fill"
            case .light: "leaf.fill"
            case .rest: "moon.zzz.fill"
            }
        }
    }

    /// Lets the user pick what to include before sharing -- today's effort
    /// (push hard / moderate / light / rest, same category as the rest of
    /// the app) and step count, both real and both optional, rather than
    /// always baking them in. Live preview so toggling actually shows what
    /// changes; the final image is only rendered once (here), not
    /// speculatively on every Profile load.
    private struct StreakShareSheet: View {
        let streakDays: Int
        let category: RecommendationCategory?
        let steps: Int?
        @Environment(\.dismiss) private var dismiss

        @State private var includeEffort: Bool
        @State private var includeSteps: Bool
        @State private var shareImage: UIImage?

        init(streakDays: Int, category: RecommendationCategory?, steps: Int?) {
            self.streakDays = streakDays
            self.category = category
            self.steps = steps
            _includeEffort = State(initialValue: category != nil)
            _includeSteps = State(initialValue: (steps ?? 0) > 0)
        }

        var body: some View {
            NavigationStack {
                VStack(spacing: 20) {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Checkerboard-free "this is transparent" cue --
                            // a plain neutral preview backdrop, purely for
                            // on-screen preview; never part of the exported
                            // image itself.
                            StreakShareCardView(
                                streakDays: streakDays,
                                category: includeEffort ? category : nil,
                                steps: includeSteps ? steps : nil
                            )
                            .scaleEffect(0.62)
                            .frame(width: 360 * 0.62, height: 640 * 0.62)
                            .padding(.top, 12)

                            VStack(spacing: 10) {
                                if let category {
                                    Toggle(isOn: $includeEffort) {
                                        Text("Today's effort — \(category.displayTitle)")
                                            .font(.system(size: 14.5, weight: .semibold))
                                    }
                                    .tint(SomaTokens.accent)
                                }
                                if let steps, steps > 0 {
                                    Toggle(isOn: $includeSteps) {
                                        Text("Step count — \(steps.formatted()) steps")
                                            .font(.system(size: 14.5, weight: .semibold))
                                    }
                                    .tint(SomaTokens.accent)
                                }
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.surface))
                        }
                        .padding(20)
                    }

                    if let shareImage {
                        ShareLink(
                            item: Image(uiImage: shareImage),
                            preview: SharePreview("My \(streakDays)-day Soma streak", image: Image(uiImage: shareImage))
                        ) {
                            Label("Share streak", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.accent))
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }
                }
                .somaBackground()
                .navigationTitle("Share your streak")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .onAppear { renderImage() }
            .onChange(of: includeEffort) { renderImage() }
            .onChange(of: includeSteps) { renderImage() }
        }

        /// Synchronous on the main actor -- a static branded card renders
        /// in well under a frame, so no loading state is needed here.
        /// isOpaque = false is what actually preserves the transparent
        /// margin in the exported PNG (SwiftUI's default composites onto
        /// an opaque backing otherwise).
        private func renderImage() {
            let renderer = ImageRenderer(content: StreakShareCardView(
                streakDays: streakDays,
                category: includeEffort ? category : nil,
                steps: includeSteps ? steps : nil
            ))
            renderer.scale = 3
            renderer.isOpaque = false
            shareImage = renderer.uiImage
        }
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
                value: experienceLevel?.displayName ?? notSetLabel
            ) { activeSheet = .experience }

            summaryRow(
                title: "Your current lifts",
                consequence: "Optional -- a real number beats an estimated one",
                value: knownLifts.isEmpty ? "Not set" : "\(knownLifts.count) set"
            ) { activeSheet = .knownLifts }

            summaryRow(
                title: "Goals",
                consequence: "Prioritizes which workouts are suggested first",
                value: goals.isEmpty ? notSetLabel : String(localized: "profile.goals.selectedCount", defaultValue: "\(goals.count) selected", comment: "Training goals row value: number of goals selected")
            ) { activeSheet = .goals }

            summaryRow(
                title: "Equipment & access",
                consequence: "Only suggests workouts you can actually do",
                value: equipment.isEmpty ? notSetLabel : EquipmentTag.allCases.filter(equipment.contains).map(\.displayName).joined(separator: ", ")
            ) { activeSheet = .equipment }

            summaryRow(
                title: "Kitchen equipment",
                consequence: "Only suggests recipes you can actually cook",
                value: householdEquipment.isEmpty ? "Not set" : KitchenEquipmentTag.allCases.filter(householdEquipment.contains).map(\.displayName).joined(separator: ", ")
            ) { activeSheet = .kitchenEquipment }

            summaryRow(
                title: "Weekly target",
                consequence: "Personal tracking goal only -- doesn't change suggestions",
                value: weeklySessionTarget.map {
                    String(localized: "profile.weeklyTarget.progress", defaultValue: "\($0)/wk · \(sessionsDoneThisWeek) done", comment: "Weekly target row value: target sessions per week and sessions done so far, e.g. '4/wk · 2 done'")
                } ?? notSetLabel
            ) { activeSheet = .weeklyTarget }

            summaryRow(
                title: "Weekly anchor session",
                consequence: "The rest of your week is built around it",
                value: anchorSessionRowValue
            ) { activeSheet = .anchorSession }

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

    /// "Hot Yoga · Tue" / "Hot Yoga" (no day picked yet) / "Not set".
    private var anchorSessionRowValue: String {
        let name = anchorSessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Not set" }
        guard !anchorSessionDays.isEmpty else { return name }
        let days = anchorSessionDays.sorted().map(WeekdayMiniPicker.shortName(forValue:)).joined(separator: ", ")
        return "\(name) · \(days)"
    }

    /// Kill switch: the row exists only when the server-gated catalog has
    /// content, or the user already has goal data to reach.
    private var showSportGoalRow: Bool {
        Config.enableSportGoals && (sportCatalogAvailable || activeSportGoal != nil || completedSportGoals > 0 || pausedSportGoal != nil)
    }

    /// Must mirror what the goal screen actually opens to -- a paused goal
    /// still names the row ("Not set" while the hub shows a goal is a lie).
    private var sportGoalRowValue: String {
        let doneSuffix = completedSportGoals > 0
            ? String(localized: "profile.sportGoal.doneSuffix", defaultValue: " · \(completedSportGoals) done", comment: "Suffix on an active sport goal's name showing completed-goal count")
            : ""
        if let activeSportGoal {
            return activeSportGoal.displayName(in: sportGoalCatalog) + doneSuffix
        }
        if let pausedSportGoal {
            let goalName = pausedSportGoal.displayName(in: sportGoalCatalog)
            return String(localized: "profile.sportGoal.paused", defaultValue: "\(goalName) · paused", comment: "Sport goal row value showing a paused goal's name")
        }
        if completedSportGoals > 0 {
            return String(localized: "profile.sportGoal.doneCount", defaultValue: "\(completedSportGoals) done", comment: "Sport goal row value: count of completed goals with no active/paused goal")
        }
        return notSetLabel
    }

    // MARK: - Health & Safety tab

    /// Gated on sex, not just the kill switch -- sexAwareGuidance.ts's
    /// underlying guidance only ever fires for sex == "female" (see
    /// describeSexAwareConsiderations), so showing this row to anyone else
    /// would just be collecting sensitive data that can never affect
    /// anything -- worse for data minimization than not showing it at all.
    private var cycleTrackingRowVisible: Bool {
        Config.enableCyclePhaseTracking && sex == .female
    }

    private var cycleTrackingRowValue: String {
        guard let lastPeriodStartDate else { return "Not set" }
        let lengthLabel = typicalCycleLengthDays.map { "\($0)d cycle" } ?? "~28d cycle"
        return "\(Self.dobFormatter.string(from: lastPeriodStartDate)) · \(lengthLabel)"
    }

    private var healthSafetySection: some View {
        VStack(spacing: 10) {
            groupEyebrow("SAFETY")

            summaryRow(
                title: "Injuries",
                consequence: injuryTags.isEmpty ? "None noted" : "Caps today's intensity at Moderate, hides high impact",
                value: injuryTags.isEmpty ? String(localized: "profile.injuries.noneNoted", defaultValue: "None noted", comment: "Injuries row value when no injuries are recorded") : injuryTags.map(\.displayName).joined(separator: ", "),
                valueColor: injuryTags.isEmpty ? nil : SomaTokens.danger
            ) { activeSheet = .injuries }

            summaryRow(
                title: "Pregnancy",
                consequence: "Withholds generated workouts until confirmed",
                value: pregnancy == true
                    ? (pregnancyWeek.map { String(localized: "profile.pregnancy.week", defaultValue: "Week \($0)", comment: "Pregnancy row value showing the current week number, e.g. 'Week 12'") } ?? String(localized: "profile.pregnancy.yes", defaultValue: "Yes", comment: "Pregnancy row value when pregnant but no week number is set"))
                    : notSetLabel
            ) { activeSheet = .pregnancy }

            if cycleTrackingRowVisible {
                summaryRow(
                    title: "Cycle tracking",
                    consequence: "Adds one general training consideration -- opt-in, never assumed",
                    value: cycleTrackingRowValue
                ) { activeSheet = .cycleTracking }
            }

            if Config.enableBodyPhotoUpload && isConfirmedAdultForBodyPhotos {
                summaryRow(
                    title: "Your progress",
                    consequence: "Goal photo, current photo, and how you'll get there",
                    value: ""
                ) { showGoalBodyProgress = true }
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
                value: contactEmailText.isEmpty ? notSetLabel : contactEmailText
            ) { activeSheet = .contactEmail }

            summaryRow(
                title: "Region",
                consequence: "Powers nearby gym & coach suggestions",
                value: UserProfile.regionDisplay(country: countryCode, city: cityText) ?? notSetLabel
            ) { activeSheet = .region }

            summaryRow(
                title: "Date of birth",
                consequence: "Needed to unlock Goal Body progress photos",
                value: dateOfBirthDate.map { Self.dobFormatter.string(from: $0) } ?? notSetLabel
            ) { activeSheet = .dateOfBirth }

            groupEyebrow("PREFERENCES")
            summaryRow(
                title: "Language",
                consequence: "Overrides your device's language just for Soma",
                value: languageManager.selected.displayName(locale: languageManager.effectiveLocale)
            ) { activeSheet = .language }
            .accessibilityIdentifier("language-settings-row")

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
            summaryRow(title: "Subscription", consequence: LocalizedStringKey(subscriptionStatusText), value: "") {
                if !subscriptionManager.isSubscribed { presentPremiumPaywall() }
            }
            summaryRow(title: "Referral code", consequence: "Redeem a code for free access", value: "") {
                showReferralCodeSheet = true
            }
            summaryRow(title: "Feedback", consequence: "Spotted a bug, or have an idea?", value: "") {
                FeedbackPresenter.present()
            }
            summaryRow(title: "How Soma works", consequence: "A quick refresher on what's in the app", value: "") {
                showHowSomaWorks = true
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(SomaTokens.danger)
            }
            if savedConfirmation {
                Text("Saved.").font(.caption).foregroundStyle(SomaTokens.success)
            }

            SomaButton(title: LocalizedStringKey(signOutLabel), size: .md, variant: .danger, isBlock: true) {
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
            errorMessage = String(localized: "profile.betaOptIn.error", defaultValue: "Couldn't update beta access. Try again.", comment: "Error shown when toggling the sport-goals beta opt-in fails")
        }
    }

    // MARK: - Row primitives

    /// Shared fallback text for an unset profile field, reused across
    /// every summary row so its localization stays consistent.
    private var notSetLabel: String {
        String(localized: "profile.notSet", defaultValue: "Not set", comment: "Fallback value shown when a profile field hasn't been set yet")
    }

    /// Lowercase variant used mid-sentence in Stepper titles.
    private var notSetLowerLabel: String {
        String(localized: "profile.notSetLower", defaultValue: "not set", comment: "Lowercase 'not set' fallback used mid-sentence in a Stepper title")
    }

    private var signOutLabel: String {
        String(localized: "profile.signOut", defaultValue: "Sign out", comment: "Button to sign out of the account")
    }

    private func groupEyebrow(_ text: LocalizedStringKey) -> some View {
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
    private func summaryRow(title: LocalizedStringKey, consequence: LocalizedStringKey, value: String, valueColor: Color? = nil, action: @escaping () -> Void) -> some View {
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
                    case .kitchenEquipment: kitchenEquipmentEditor
                    case .weeklyTarget: weeklyTargetEditor
                    case .injuries: injuriesEditor
                    case .pregnancy: pregnancyEditor
                    case .contactEmail: contactEmailEditor
                    case .region: regionEditor
                    case .language: languageEditor
                    case .dateOfBirth: dateOfBirthEditor
                    case .knownLifts: knownLiftsEditor
                    case .anchorSession: anchorSessionEditor
                    case .cycleTracking: cycleTrackingEditor
                    }
                }
                .padding(20)
                .dismissKeyboardOnTap()
            }
            .scrollDismissesKeyboard(.interactively)
            .somaBackground()
            .navigationTitle(sheet.title(locale: languageManager.effectiveLocale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Language is a local display preference (applied
                        // immediately by languageEditor's picker), not a
                        // profile field -- skip the network save() for it.
                        if sheet != .language { save() }
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

    private var kitchenEquipmentEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("So we only ever suggest recipes you can actually cook.")
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout {
                ForEach(KitchenEquipmentTag.allCases) { tag in
                    ChipToggle(title: tag.displayName, isSelected: householdEquipment.contains(tag)) {
                        toggle(tag, in: &householdEquipment)
                    }
                }
            }
            if householdEquipment.contains(.other) {
                TextField("What else? (comma-separated)", text: $otherHouseholdEquipmentText)
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
                "Target: \(weeklySessionTarget.map(String.init) ?? notSetLowerLabel) sessions/week",
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

    /// Real feedback: a self-described non-powerlifter was prescribed
    /// 125-135kg for a barbell deadlift from the population-level
    /// bodyweight-ratio estimate alone. Entirely optional, entirely
    /// separate from experience level -- filling in even one pattern here
    /// makes the AI plan use that real number for that pattern specifically,
    /// leaving the others on the estimate.
    private var knownLiftsEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("If you know your comfortable working weight for any of these, Soma uses it directly for the AI plan instead of estimating from your bodyweight and experience level. Leave any blank to keep using the estimate.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(LiftPattern.allCases) { pattern in
                VStack(alignment: .leading, spacing: 4) {
                    Text(pattern.displayName)
                        .font(.system(size: 14.5, weight: .semibold))
                    HStack {
                        TextField(pattern.placeholder, text: Binding(
                            get: { knownLiftsText[pattern] ?? "" },
                            set: { knownLiftsText[pattern] = $0 }
                        ))
                        .keyboardType(.numberPad)
                        Text("kg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: SomaTokens.rMD, style: .continuous).fill(SomaTokens.surface3))
                }
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
                        "Pain level: \(injuryPainLevel[tag].map(String.init) ?? notSetLowerLabel)",
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
                ChipToggle(title: String(localized: "profile.pregnancy.currentlyPregnant", defaultValue: "I'm currently pregnant", comment: "Pregnancy chip toggle label"), isSelected: pregnancy == true) {
                    pregnancy = (pregnancy == true) ? nil : true
                    if pregnancy != true { pregnancyWeek = nil }
                }
            }
            if pregnancy == true {
                Stepper(
                    "Week: \(pregnancyWeek.map(String.init) ?? notSetLowerLabel)",
                    value: Binding(get: { pregnancyWeek ?? 1 }, set: { pregnancyWeek = $0 }),
                    in: 1...42
                )
                .font(.caption)
            }
        }
    }

    /// Same field pair + "clear resets both" behavior as pregnancyEditor
    /// just above -- Phase 5 (see docs/coaching-personalization-plan.md).
    /// Only ever reachable when sex == .female (see cycleTrackingRowVisible),
    /// so there's no sex picker/gate needed inside the editor itself.
    private var cycleTrackingEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Optional, and never assumed -- only set if you tell us. Soma will factor your cycle phase into training suggestions as one general consideration among others. This is general guidance only, not medical advice, and not a fertility or ovulation tracker.")
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker(
                "Last period start date",
                selection: Binding(
                    get: { lastPeriodStartDate ?? Date() },
                    set: { lastPeriodStartDate = $0 }
                ),
                in: ...Date(),
                displayedComponents: .date
            )
            if lastPeriodStartDate != nil {
                Stepper(
                    "Typical cycle length: \(typicalCycleLengthDays.map { "\($0) days" } ?? "not set (defaults to 28)")",
                    value: Binding(get: { typicalCycleLengthDays ?? 28 }, set: { typicalCycleLengthDays = $0 }),
                    in: 21...35
                )
                .font(.caption)
                Button("Clear") {
                    lastPeriodStartDate = nil
                    typicalCycleLengthDays = nil
                }
                .font(.caption)
                .foregroundStyle(SomaTokens.danger)
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

    /// "yyyy-MM-dd", matching UserProfile.dateOfBirth's wire format
    /// (same as AgeGate.isAdult's parser).
    private static let dobFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    private static var defaultDateOfBirth: Date {
        Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
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

    private var languageEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Most of Soma updates immediately; the rest applies next time you open the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        languageManager.selected = language
                    } label: {
                        HStack {
                            Text(language.displayName(locale: languageManager.effectiveLocale))
                                .foregroundStyle(SomaTokens.ink)
                            Spacer()
                            if languageManager.selected == language {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(SomaTokens.accent)
                            }
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // Stable hook for XCUITest -- displayName is untranslated
                    // (each language shows its own name) and unstable across
                    // locales isn't the issue, but matching by raw value is
                    // still more robust than matching translated text.
                    .accessibilityIdentifier("language-option-\(language.rawValue)")
                    if language != AppLanguage.allCases.last {
                        Divider()
                    }
                }
            }
        }
    }

    /// Same field pair as onboarding's AnchorSessionQuestionView, same
    /// WeekdayMiniPicker component -- lets someone who skipped it at
    /// onboarding set it later, or fix the wrong day.
    private var anchorSessionEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A recurring class or activity (e.g. a Tuesday hot yoga class) the rest of your week gets built around.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("e.g. \"Hot Yoga\", \"Tennis league\"", text: $anchorSessionName)
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 10) {
                Text("Which day(s) is it usually on?")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                WeekdayMiniPicker(selected: $anchorSessionDays)
            }
        }
    }

    /// Real feedback traced to a missing DOB: an account created before
    /// the onboarding DOB step existed has no other way to supply one,
    /// which silently hides the whole Goal Body photo feature -- see
    /// UserProfile.dateOfBirth's doc comment. Same wheel DatePicker as
    /// the onboarding step (DateOfBirthQuestionView) for a consistent feel.
    private var dateOfBirthEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Confirms you're 18+ to unlock Goal Body progress photos. Never shown to other users.")
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker(
                "Date of birth",
                selection: Binding(
                    get: { dateOfBirthDate ?? Self.defaultDateOfBirth },
                    set: { dateOfBirthDate = $0 }
                ),
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
        }
    }

    /// Three distinct states worth telling apart: paying, on a referral
    /// bonus (free, but ending), or neither.
    private var subscriptionStatusText: String {
        if subscriptionManager.isSubscribed {
            return String(localized: "profile.subscription.active", defaultValue: "Soma Premium is active.", comment: "Subscription row consequence text when Premium is active")
        }
        if let bonusUntil = appState.referralBonusUntil, bonusUntil > Date() {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            formatter.locale = languageManager.effectiveLocale
            let dateText = formatter.string(from: bonusUntil)
            return String(localized: "profile.subscription.freeBonus", defaultValue: "Free until \(dateText) -- tap to subscribe now instead.", comment: "Subscription row consequence text during a temporary referral-bonus free period")
        }
        return String(localized: "profile.subscription.freePlan", defaultValue: "Free plan -- today's category and message only.", comment: "Subscription row consequence text on the default free plan")
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
                let providerName = provider.displayName
                let reason = error.localizedDescription
                deviceErrorMessage = String(localized: "profile.device.connectError", defaultValue: "Couldn't connect \(providerName): \(reason)", comment: "Error shown when connecting a wearable device provider fails; includes the provider name and system error text")
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
        householdEquipment = Set(profile.householdEquipment)
        otherHouseholdEquipmentText = profile.otherHouseholdEquipmentNotes ?? ""
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
        sex = profile.sex
        lastPeriodStartDate = profile.lastPeriodStartDate.flatMap(Self.dobFormatter.date(from:))
        typicalCycleLengthDays = profile.typicalCycleLengthDays
        weeklySessionTarget = profile.weeklySessionTarget
        knownLiftsText = Dictionary(uniqueKeysWithValues: (profile.knownLifts ?? [:]).compactMap { key, value in
            LiftPattern(rawValue: key).map { ($0, String(Int(value))) }
        })
        countryCode = profile.country
        cityText = profile.city ?? ""
        anchorSessionName = profile.anchorSessionName ?? ""
        anchorSessionDays = Set(profile.anchorSessionDays)
        preservedHeightCm = profile.heightCm
        preservedJourneyStage = profile.journeyStage
        preservedBlockersNotes = profile.blockersNotes
        dateOfBirthDate = profile.dateOfBirth.flatMap(Self.dobFormatter.date(from:))
        betaOptIn = (try? await SupabaseClient.shared.fetchBetaOptIn()) ?? false

        isConfirmedAdultForBodyPhotos = AgeGate.isAdult(dobString: profile.dateOfBirth)

        avatarPhotoPath = profile.avatarPhotoPath
        if let avatarPhotoPath {
            avatarImage = await SupabaseClient.shared.loadAvatarImage(path: avatarPhotoPath)
        } else {
            avatarImage = nil
        }

        completedWorkoutStreak = (try? await SupabaseClient.shared.fetchRecentWorkoutLogDates())
            .map(Self.streak(from:)) ?? 0
        todaysSteps = await HealthKitManager.shared.fetchTodaysSteps().map { Int($0) }
        sessionsDoneThisWeek = await Self.workoutsThisWeek()
        await loadSportGoalState()
        await loadConnectionStatus()

        setSuperwallUserAttributes(profile: profile)
    }

    /// Compresses, uploads, and updates local state so the header shows
    /// the new photo immediately -- same shape as GoalBodyProgressView's
    /// upload(kind:item:).
    private func uploadAvatar(item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        guard let compressed = ImageCompression.jpeg(image) else {
            avatarErrorMessage = String(localized: "photoUpload.error.processingFailed", defaultValue: "Couldn't process that photo. Try another one.", comment: "Error shown when a selected body photo fails local compression/processing before upload.")
            return
        }
        isUploadingAvatar = true
        avatarErrorMessage = nil
        defer { isUploadingAvatar = false }
        do {
            try await SupabaseClient.shared.uploadAvatar(imageData: compressed)
            avatarImage = image
        } catch {
            avatarErrorMessage = String(localized: "photoUpload.error.uploadFailed", defaultValue: "Couldn't upload that photo. Try again.", comment: "Error shown when the body photo upload request to the backend fails.")
        }
    }

    private func removeAvatar() async {
        guard let avatarPhotoPath else { return }
        avatarErrorMessage = nil
        do {
            try await SupabaseClient.shared.deleteAvatar(path: avatarPhotoPath)
            avatarImage = nil
            self.avatarPhotoPath = nil
        } catch {
            avatarErrorMessage = String(localized: "profile.avatar.error.removeFailed", defaultValue: "Couldn't remove that photo. Try again.", comment: "Error shown when removing the profile avatar photo fails")
        }
    }

    /// Server-verified connected/needs-reconnect state for the device
    /// rows below -- delegates to AppState's shared refresh (also used on
    /// every sign-in) rather than duplicating the fetch-and-merge logic
    /// here. See AppState.refreshConnectedProviders's own doc comment.
    private func loadConnectionStatus() async {
        await appState.refreshConnectedProviders()
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
    /// Not `private` so StreakMilestoneTests can exercise it directly.
    static func streak(from dates: Set<String>) -> Int {
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

    /// Parses knownLiftsText into the wire shape -- a blank or
    /// non-positive entry for a pattern is dropped rather than saved as
    /// 0, so it falls back to the population estimate exactly like never
    /// having entered anything.
    private var knownLifts: [String: Double] {
        var result: [String: Double] = [:]
        for (pattern, text) in knownLiftsText {
            if let value = Double(text.trimmingCharacters(in: .whitespaces)), value > 0 {
                result[pattern.rawValue] = value
            }
        }
        return result
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
            householdEquipment: Array(householdEquipment),
            otherHouseholdEquipmentNotes: otherHouseholdEquipmentText.isEmpty ? nil : otherHouseholdEquipmentText,
            injuryTags: Array(injuryTags),
            injuryNotes: injuryNotesText.isEmpty ? nil : injuryNotesText,
            experienceLevel: experienceLevel,
            pregnancy: pregnancy,
            pregnancyWeek: pregnancy == true ? pregnancyWeek : nil,
            lastPeriodStartDate: lastPeriodStartDate.map(Self.dobFormatter.string(from:)),
            typicalCycleLengthDays: lastPeriodStartDate != nil ? typicalCycleLengthDays : nil,
            weeklySessionTarget: weeklySessionTarget,
            country: countryCode,
            city: cityText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : cityText.trimmingCharacters(in: .whitespaces),
            heightCm: preservedHeightCm,
            journeyStage: preservedJourneyStage,
            blockersNotes: preservedBlockersNotes,
            knownLifts: knownLifts,
            dateOfBirth: dateOfBirthDate.map(Self.dobFormatter.string(from:)),
            anchorSessionName: anchorSessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : anchorSessionName,
            anchorSessionDays: Array(anchorSessionDays)
        )

        let currentInjuryTags = Array(injuryTags)
        let currentInjurySeverity = injurySeverity
        let currentInjuryType = injuryType
        let currentInjuryPainLevel = injuryPainLevel

        Task {
            defer { isSaving = false }
            do {
                try await SupabaseClient.shared.updateProfile(id: userId, profile: profile)
            } catch {
                // Distinct from the injury-report failure below -- real
                // feedback: "when user updates the region, the app showed
                // an error 'Couldn't save profile. Try again.'" One shared
                // catch around both calls meant a reportInjury-only
                // failure (e.g. an invalid legacy severity value) showed
                // this exact message even when the actual field being
                // edited -- like region -- had already saved successfully
                // moments earlier. Bail out here before reportInjury runs,
                // so a genuine profile-fields failure is reported
                // accurately and isn't masked by/blamed on injury state.
                errorMessage = "Couldn't save profile. Try again."
                return
            }
            do {
                try await SupabaseClient.shared.reportInjury(
                    tags: currentInjuryTags,
                    severity: currentInjurySeverity,
                    type: currentInjuryType,
                    painLevel: currentInjuryPainLevel
                )
                savedConfirmation = true
            } catch {
                // Profile fields (region, goals, equipment, etc.) DID save
                // above -- only the injury-tag write failed, say so specifically.
                errorMessage = String(localized: "profile.save.injuryError", defaultValue: "Profile saved, but couldn't update injury info. Try again.", comment: "Error shown when the profile itself saved but the separate injury-tag write failed")
            }
        }
    }
}

private enum ProfileSection: String, CaseIterable, Identifiable {
    case training, healthSafety, account
    var id: String { rawValue }
    // Stays String -- SomaSegmentedControl's shared closure param is
    // String, so each case pre-localizes via String(localized:) instead.
    var title: String {
        switch self {
        case .training: String(localized: "profile.section.training", defaultValue: "Training", comment: "Profile screen segmented tab label")
        case .healthSafety: String(localized: "profile.section.healthSafety", defaultValue: "Health & Safety", comment: "Profile screen segmented tab label")
        case .account: String(localized: "profile.section.account", defaultValue: "Account", comment: "Profile screen segmented tab label")
        }
    }
}

private enum ProfileSheet: String, Identifiable {
    case experience, goals, equipment, kitchenEquipment, weeklyTarget, injuries, pregnancy, contactEmail, region, knownLifts, dateOfBirth, anchorSession, cycleTracking, language
    var id: String { rawValue }

    /// Resolved explicitly against `locale` rather than a bare
    /// `LocalizedStringKey` relying on the ambient `.environment(\.locale)`:
    /// this title lives inside the very sheet whose own Language picker can
    /// change the active locale while the sheet is still on screen, and
    /// `.navigationTitle`'s bridge to `UINavigationItem` doesn't reliably
    /// re-resolve a `LocalizedStringKey` once the view has already
    /// appeared. Uses `LanguageManager.localizedString(_:locale:)` (loads
    /// the target `.lproj` bundle directly) rather than
    /// `String(localized:locale:)`, whose `locale:` parameter did not
    /// reliably override `Bundle.main`'s resolved language in testing.
    func title(locale: Locale) -> String {
        switch self {
        case .experience: localizedString("Experience", locale: locale)
        case .goals: localizedString("Goals", locale: locale)
        case .equipment: localizedString("Equipment & access", locale: locale)
        case .kitchenEquipment: localizedString("Kitchen equipment", locale: locale)
        case .weeklyTarget: localizedString("Weekly target", locale: locale)
        case .injuries: localizedString("Injuries", locale: locale)
        case .pregnancy: localizedString("Pregnancy", locale: locale)
        case .contactEmail: localizedString("Contact email", locale: locale)
        case .region: localizedString("Region", locale: locale)
        case .knownLifts: localizedString("Your current lifts", locale: locale)
        case .dateOfBirth: localizedString("Date of birth", locale: locale)
        case .anchorSession: localizedString("Weekly anchor session", locale: locale)
        case .cycleTracking: localizedString("Cycle tracking", locale: locale)
        case .language: localizedString("Language", locale: locale)
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
