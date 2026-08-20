import PhotosUI
import SuperwallKit
import StoreKit
import SwiftUI

/// Settings entry point, presented as a sheet from Home and from
/// MealRecommendationView's kitchen-setup prompt. Redesigned per the "12b"
/// mockup (Soma Refresh, Turn 12 -- "no tabs, a hub of four big cards,
/// each opening its own small page"), replacing the old three-tab dense
/// list (guide 05 / "9d"). All shared field state and load/save logic
/// that used to live directly as @State on this view now lives on
/// `ProfileStore`, owned here via @StateObject and handed down to every
/// subpage -- the four cards below are NavigationLinks pushed inside this
/// view's own NavigationStack, so each subpage gets a native back button
/// for free.
struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var languageManager: LanguageManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    @StateObject private var store = ProfileStore()
    @State private var showSignOutConfirmation = false
    /// 12b plan-line tap while paid: the native manage-subscriptions sheet.
    @State private var showManageSubscriptions = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identityRow

                    if let avatarErrorMessage = store.avatarErrorMessage {
                        Text(avatarErrorMessage)
                            .font(.caption)
                            .foregroundStyle(SomaTokens.danger)
                    }

                    streakSection

                    if !nudges.isEmpty {
                        completionNotice
                    }

                    cardsSection

                    signOutRow
                }
                .padding(20)
            }
            .somaBackground()
            .navigationTitle(String(localized: "profile.settings.navTitle", defaultValue: "Settings", comment: "Navigation title of the Settings hub screen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "profile.doneButton", defaultValue: "Done", comment: "Toolbar button dismissing a settings screen or sheet")) { dismiss() }
                }
            }
        }
        .sheet(isPresented: $store.showStreakShareSheet) {
            StreakShareSheet(
                streakDays: store.completedWorkoutStreak,
                category: appState.currentRecommendation?.category,
                steps: store.todaysSteps
            )
        }
        .onChange(of: store.avatarItem) { _, newItem in
            Task { await store.uploadAvatar(item: newItem) }
        }
        .task {
            await store.load(appState: appState)
        }
        .sheet(isPresented: $showSignOutConfirmation) {
            SignOutConfirmSheet {
                appState.signOut()
            }
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
    }

    // MARK: - Identity row

    /// No display-name field exists anywhere in this app (only contact
    /// email, which is optional and never shown as an identity) -- the
    /// avatar itself is the one piece of real personalization here.
    private var identityRow: some View {
        HStack(spacing: 12) {
            avatarButton
                // 12b: gold crown mini-badge on the avatar -- PAID only
                // (the spec is explicit: promo bonus gets the gold plan
                // line but no avatar badge, trials neither).
                .overlay(alignment: .bottomTrailing) {
                    if subscriptionManager.isSubscribed && !subscriptionManager.isInTrial {
                        avatarCrownBadge
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "profile.yourProfile.title", defaultValue: "Your profile", comment: "Heading label next to the avatar in the identity row"))
                    .font(Theme.display)
                Text(identitySubtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(SomaTokens.ink3)
                planLine
            }
            Spacer(minLength: 0)
        }
    }

    private static let crownGoldLight = Color(red: 0xF5 / 255, green: 0xCD / 255, blue: 0x78 / 255)

    private var avatarCrownBadge: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Self.crownGoldLight.opacity(0.95), SomaTokens.warn.opacity(0.95)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: 20, height: 20)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1))
            // The page-background cutout ring from the mockup.
            .overlay(Circle().stroke(SomaTokens.bgScreenTop, lineWidth: 2).padding(-1))
            .overlay(
                Image(systemName: "crown")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            )
            .offset(x: 3, y: 3)
            .shadow(color: SomaTokens.warn.opacity(0.35), radius: 3, x: 0, y: 2)
            .accessibilityHidden(true)
    }

    /// 12b's plan line under the email -- "Premium shows twice, quietly."
    /// Four states: paid "Soma Premium · renews <date>" (tap -> manage),
    /// trial "Free trial · N days left · Subscribe", promo bonus
    /// "Free access · N days left · Upgrade" (gold, no avatar badge),
    /// free "Free plan · Upgrade" -- the latter three tap into the paywall.
    private var planLine: some View {
        let paid = subscriptionManager.isSubscribed && !subscriptionManager.isInTrial
        return Button {
            if paid {
                showManageSubscriptions = true
            } else if subscriptionManager.isInTrial {
                SuperwallDiagnostics.registerTrialUpgrade { showManageSubscriptions = true }
            } else {
                store.presentPremiumPaywall()
            }
        } label: {
            HStack(spacing: 5) {
                if paid || planLineIsGold {
                    Image(systemName: "crown")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SomaTokens.warn)
                }
                Text(planLineTitle)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(planLineIsGold || paid ? SomaTokens.warn : SomaTokens.ink3)
                Text(planLineSuffix)
                    .font(.system(size: 11.5))
                    .foregroundStyle(SomaTokens.inkPlaceholder)
            }
            .padding(.top, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var planLineIsGold: Bool {
        subscriptionManager.isInTrial || (appState.referralBonusUntil.map { $0 > Date() } ?? false)
    }

    private var planDaysLeft: Int? {
        let target = subscriptionManager.isInTrial ? subscriptionManager.expirationDate : appState.referralBonusUntil
        guard let target, target > Date() else { return nil }
        return max(Int(ceil(target.timeIntervalSinceNow / 86400)), 1)
    }

    private var planLineTitle: String {
        if subscriptionManager.isSubscribed && !subscriptionManager.isInTrial {
            return String(localized: "profile.plan.premium", defaultValue: "Soma Premium", comment: "Plan line under the profile email while subscribed")
        }
        if subscriptionManager.isInTrial {
            if let days = planDaysLeft {
                return String(localized: "profile.plan.trialDays", defaultValue: "Free trial · \(days.formatted()) days left", comment: "Plan line during the free trial, with days remaining")
            }
            return String(localized: "profile.plan.trial", defaultValue: "Free trial", comment: "Plan line during the free trial when days remaining are unknown")
        }
        if let days = planDaysLeft {
            return String(localized: "profile.plan.bonusDays", defaultValue: "Free access · \(days.formatted()) days left", comment: "Plan line while a referral/promo free-access bonus is active, with days remaining")
        }
        return String(localized: "profile.plan.free", defaultValue: "Free plan", comment: "Plan line under the profile email on the free plan")
    }

    private var planLineSuffix: String {
        if subscriptionManager.isSubscribed && !subscriptionManager.isInTrial {
            if let renewal = subscriptionManager.expirationDate {
                return String(localized: "profile.plan.renews", defaultValue: "· renews \(renewal.formatted(date: .abbreviated, time: .omitted))", comment: "Suffix on the Premium plan line showing the next renewal date")
            }
            return ""
        }
        if subscriptionManager.isInTrial {
            return String(localized: "profile.plan.subscribeSuffix", defaultValue: "· Subscribe", comment: "Tappable suffix on the trial plan line leading to the paywall")
        }
        return String(localized: "profile.plan.upgradeSuffix", defaultValue: "· Upgrade", comment: "Tappable suffix on the free/bonus plan line leading to the paywall")
    }

    private var identitySubtitle: String {
        store.contactEmailText.isEmpty ? headerStatusLine : store.contactEmailText
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
        if store.completedWorkoutStreak > 0 {
            parts.append(String(localized: "profile.header.streakDays", defaultValue: "\(store.completedWorkoutStreak)-day streak", comment: "Profile header status line: current workout streak length in days"))
        }
        if let category = appState.currentRecommendation?.category.displayTitle {
            parts.append(category)
        }
        return parts.isEmpty ? String(localized: "profile.header.defaultTagline", defaultValue: "Soma uses this to tailor which workouts it suggests.", comment: "Default profile header subtitle shown before any status fragments are available") : parts.joined(separator: " · ")
    }

    /// Tap opens a menu (Choose Photo / Remove Photo, the latter only
    /// once one exists) rather than jumping straight into the picker --
    /// same discoverable-but-not-cluttered pattern as Contacts/Messages'
    /// own avatar-edit affordance. The small camera badge signals it's
    /// editable without needing separate always-visible chrome.
    private var avatarButton: some View {
        Menu {
            Button {
                store.showAvatarPicker = true
            } label: {
                Label(LocalizedStringKey(String(localized: "profile.avatar.choosePhoto", defaultValue: "Choose Photo", comment: "Menu option to pick a new profile photo")), systemImage: "photo")
            }
            if store.avatarImage != nil {
                Button(role: .destructive) {
                    Task { await store.removeAvatar() }
                } label: {
                    Label(LocalizedStringKey(String(localized: "profile.avatar.removePhoto", defaultValue: "Remove Photo", comment: "Menu option to remove the current profile photo")), systemImage: "trash")
                }
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let avatarImage = store.avatarImage {
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
                .opacity(store.isUploadingAvatar ? 0.4 : 1)

                if store.isUploadingAvatar {
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
        .disabled(store.isUploadingAvatar)
        .photosPicker(isPresented: $store.showAvatarPicker, selection: $store.avatarItem, matching: .images)
    }

    // MARK: - Streak

    /// Visible as soon as Settings opens, above the cards -- the real
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
                        Text(store.completedWorkoutStreak > 0
                            ? String(localized: "profile.header.streakDays", defaultValue: "\(store.completedWorkoutStreak)-day streak", comment: "Profile header status line: current workout streak length in days")
                            : String(localized: "profile.streak.noActiveStreak", defaultValue: "No active streak", comment: "Headline shown when the user has no active workout streak"))
                            .font(.system(size: 16.5, weight: .bold))
                        Text(store.completedWorkoutStreak > 0
                            ? String(localized: "profile.streak.keepShowingUp", defaultValue: "Keep showing up -- consistency compounds.", comment: "Subtitle shown when the user has an active workout streak")
                            : String(localized: "profile.streak.logWorkoutToStart", defaultValue: "Log a workout today to start one.", comment: "Subtitle shown when the user has no active workout streak"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.completedWorkoutStreak > 0 {
                        Button {
                            store.showStreakShareSheet = true
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
        let achieved = milestone.isAchieved(streak: store.completedWorkoutStreak)
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
    /// speculatively on every Settings load.
    // Internal (not private): HomeView's streak tile presents this same
    // sheet -- one share card, not two implementations.
    struct StreakShareSheet: View {
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
                                        Text(String(localized: "profile.streakShare.todaysEffort", defaultValue: "Today's effort — \(category.displayTitle)", comment: "Toggle label including today's training category name on the streak-share sheet"))
                                            .font(.system(size: 14.5, weight: .semibold))
                                    }
                                    .tint(SomaTokens.accent)
                                }
                                if let steps, steps > 0 {
                                    Toggle(isOn: $includeSteps) {
                                        Text(String(localized: "profile.streakShare.stepCountToggle", defaultValue: "Step count — \(steps.formatted()) steps", comment: "Toggle label including today's step count on the streak-share sheet"))
                                            .font(.system(size: 14.5, weight: .semibold))
                                    }
                                    .tint(SomaTokens.accent)
                                }
                            }
                            .padding(14)
                            .glassCardFlat(cornerRadius: SomaTokens.rXL)
                        }
                        .padding(20)
                    }

                    if let shareImage {
                        ShareLink(
                            item: Image(uiImage: shareImage),
                            preview: SharePreview(String(localized: "profile.streakShare.sharePreviewTitle", defaultValue: "My \(streakDays)-day Soma streak", comment: "Share sheet preview title for the exported streak card image"), image: Image(uiImage: shareImage))
                        ) {
                            Label(LocalizedStringKey(String(localized: "profile.streakShare.shareButton", defaultValue: "Share streak", comment: "Button sharing the rendered streak card image")), systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .glassGel(.blue, cornerRadius: SomaTokens.rXL)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }
                }
                .somaBackground()
                .navigationTitle(String(localized: "profile.streakShare.navTitle", defaultValue: "Share your streak", comment: "Navigation title of the streak-share sheet"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "profile.streakShare.cancel", defaultValue: "Cancel", comment: "Cancel button on the streak-share sheet")) { dismiss() }
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
            items.append(Nudge(id: "health", text: String(localized: "profile.nudge.addAppleHealth", defaultValue: "add Apple Health", comment: "Profile completion nudge fragment, lowercase mid-sentence, e.g. 'add Apple Health and set a weekly target to sharpen suggestions.'")))
        }
        // No injury nudge: an empty injury list is a complete, valid
        // answer ("None noted"), not an unfinished profile item.
        if store.weeklySessionTarget == nil {
            items.append(Nudge(id: "target", text: String(localized: "profile.nudge.setWeeklyTarget", defaultValue: "set a weekly target", comment: "Profile completion nudge fragment, lowercase mid-sentence, e.g. 'set a weekly target to sharpen suggestions.'")))
        }
        // Only nudged while the catalog is actually open and no goal is set
        // -- an empty catalog means the feature is off, not unfinished.
        if Config.enableSportGoals, store.sportCatalogAvailable, store.activeSportGoal == nil, store.pausedSportGoal == nil {
            items.append(Nudge(id: "goal", text: String(localized: "profile.nudge.pickGoal", defaultValue: "pick a goal", comment: "Profile completion nudge fragment, lowercase mid-sentence, e.g. 'pick a goal to sharpen suggestions.'")))
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
                Text(String(localized: "profile.completionNotice.toFinishCount", defaultValue: "\(nudges.count) to finish", comment: "Headline on the profile completion notice showing how many items remain"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SomaTokens.warn)
                Text(String(localized: "profile.completionNotice.body", defaultValue: "\(sentenceCased(nudges.map(\.text).joined(separator: " and "))) to sharpen suggestions.", comment: "Body text on the profile completion notice listing the remaining items"))
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

    // MARK: - Cards

    /// Four cards, each a one-line real summary of its page -- "Intermediate
    /// · Full gym, dumbbells · 2 selected" tells you what's missing without
    /// opening it, same spirit as the old per-row summary values, just
    /// rolled up one level. Every clause traces to real state, same rule as
    /// `headerStatusLine` above -- nothing here is placeholder copy lifted
    /// from the mockup's fictional "Vlad" persona.
    private var cardsSection: some View {
        VStack(spacing: 10) {
            settingsCard(icon: "dumbbell.fill", title: LocalizedStringKey(String(localized: "profile.hub.training.title", defaultValue: "Training", comment: "Hub card title and settings page navigation title for Training")), subtitle: trainingCardSubtitle) {
                TrainingSettingsView(store: store)
            }
            settingsCard(icon: "heart.fill", title: LocalizedStringKey(String(localized: "profile.hub.healthSafety.title", defaultValue: "Health & Safety", comment: "Hub card title and settings page navigation title for Health & Safety")), subtitle: healthCardSubtitle) {
                HealthSafetySettingsView(store: store)
            }
            settingsCard(
                icon: "antenna.radiowaves.left.and.right", title: LocalizedStringKey(String(localized: "profile.hub.devicesData.title", defaultValue: "Devices & Data", comment: "Hub card title and settings page navigation title for Devices & Data")), subtitle: devicesCardSubtitle,
                showsStatusDot: !appState.connectedProviders.isEmpty
            ) {
                DevicesSettingsView(store: store)
            }
            settingsCard(icon: "person.fill", title: LocalizedStringKey(String(localized: "profile.hub.account.title", defaultValue: "Account", comment: "Hub card title and settings page navigation title for Account")), subtitle: accountCardSubtitle) {
                AccountSettingsView(store: store)
            }
        }
    }

    private func settingsCard(
        icon: String, title: LocalizedStringKey, subtitle: String, showsStatusDot: Bool = false,
        @ViewBuilder destination: () -> some View
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 13) {
                ZStack {
                    Circle().fill(SomaTokens.surface).frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SomaTokens.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SomaTokens.ink)
                    HStack(spacing: 5) {
                        if showsStatusDot {
                            Circle().fill(SomaTokens.successDot).frame(width: 6, height: 6)
                        }
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(showsStatusDot ? SomaTokens.success : SomaTokens.ink3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SomaTokens.inkPlaceholder)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassCardFlat(cornerRadius: SomaTokens.rRow)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var trainingCardSubtitle: String {
        let equipmentSummary = store.equipment.isEmpty ? store.notSetLabel : EquipmentTag.allCases.filter(store.equipment.contains).map(\.displayName).joined(separator: ", ")
        let goalsSummary = store.goals.isEmpty ? store.notSetLabel : String(localized: "profile.goals.selectedCount", defaultValue: "\(store.goals.count) selected", comment: "Training goals row value: number of goals selected")
        return "\(store.experienceLevel?.displayName ?? store.notSetLabel) · \(equipmentSummary) · \(goalsSummary)"
    }

    private var healthCardSubtitle: String {
        var parts: [String] = []
        parts.append(store.injuryTags.isEmpty
            ? String(localized: "profile.injuries.noneNoted", defaultValue: "None noted", comment: "Injuries row value when no injuries are recorded")
            : store.injuryTags.map(\.displayName).joined(separator: ", "))
        if store.pregnancy == true {
            parts.append(store.pregnancyWeek.map {
                String(localized: "profile.pregnancy.week", defaultValue: "Week \($0)", comment: "Pregnancy row value showing the current week number, e.g. 'Week 12'")
            } ?? String(localized: "profile.pregnancy.yes", defaultValue: "Yes", comment: "Pregnancy row value when pregnant but no week number is set"))
        }
        return parts.joined(separator: " · ")
    }

    private var devicesCardSubtitle: String {
        let connected = Provider.allCases.filter { appState.connectedProviders.contains($0) }
        guard !connected.isEmpty else {
            return String(localized: "profile.hub.devices.none", defaultValue: "No devices connected", comment: "Devices & Data settings card subtitle shown when no wearable/health providers are connected")
        }
        let connectedNames = connected.map(\.displayName).joined(separator: " & ")
        return String(localized: "profile.header.connectedDevices", defaultValue: "\(connectedNames) connected", comment: "Profile header status line naming the connected device providers, e.g. 'Whoop & Oura connected'")
    }

    private var accountCardSubtitle: String {
        let plan = subscriptionStatusText(isSubscribed: subscriptionManager.isSubscribed, referralBonusUntil: appState.referralBonusUntil, locale: languageManager.effectiveLocale)
        let notifications = store.notificationsAuthorized
            ? String(localized: "profile.hub.notifications.on", defaultValue: "Notifications on", comment: "Account settings card subtitle fragment shown when system notifications are authorized")
            : String(localized: "profile.hub.notifications.off", defaultValue: "Notifications off", comment: "Account settings card subtitle fragment shown when system notifications are not authorized")
        return "\(plan) · \(notifications)"
    }

    // MARK: - Sign out

    /// Moved here from the Account page (12b's redline: a centered
    /// sign-out line under the cards, not a full-width danger button
    /// buried inside Account) -- confirmed via `SignOutConfirmSheet`, a
    /// custom glass sheet rather than the bare system confirmationDialog
    /// this used to open.
    private var signOutRow: some View {
        Button {
            showSignOutConfirmation = true
        } label: {
            Text(store.signOutLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SomaTokens.danger)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }
}

/// Replaces the old bare system `.confirmationDialog` with the same glass
/// sheet language every other confirmation surface in this app uses --
/// danger gel primary over a secondary-lens escape hatch, same stacking
/// `GymPhotoWorkoutView`'s "Add to plan"/"Adjust manually" pair uses.
private struct SignOutConfirmSheet: View {
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(SomaTokens.danger)
                .frame(width: 56, height: 56)
                .glassLens(cornerRadius: 28)

            VStack(spacing: 6) {
                Text(String(localized: "profile.signOutSheet.title", defaultValue: "Log out of Soma?", comment: "Title of the custom glass sheet confirming sign-out"))
                    .font(SomaType.sheetTitle)
                Text(String(localized: "profile.signOutSheet.message", defaultValue: "You'll need to sign back in to see your plan and progress.", comment: "Supporting line under the sign-out confirmation sheet's title"))
                    .font(SomaType.sub)
                    .foregroundStyle(SomaTokens.ink3)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                SomaButton(title: LocalizedStringKey(String(localized: "profile.signOutSheet.confirm", defaultValue: "Log Out", comment: "Destructive confirm button on the sign-out sheet")), size: .lg, variant: .danger) {
                    dismiss()
                    onConfirm()
                }
                SomaButton(title: LocalizedStringKey(String(localized: "profile.signOutSheet.cancel", defaultValue: "Cancel", comment: "Cancel button on the sign-out sheet")), size: .lg, variant: .secondary) {
                    dismiss()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .somaSheetBackground()
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - ProfileStore

/// Shared field state and load/save/connect logic for every settings
/// subpage, extracted from what used to be `ProfileView`'s own `@State`
/// when that view was a single tabbed screen. Owned by the hub
/// (`ProfileView`) via `@StateObject`, handed to each subpage via
/// `@ObservedObject` so a value edited on one page is instantly reflected
/// in the hub's card subtitles the moment the user pops back. Methods that
/// need `AppState` (itself only reachable via `@EnvironmentObject`, so
/// unavailable to a plain `ObservableObject`) take it as an explicit
/// parameter instead of storing a reference to it.
@MainActor
final class ProfileStore: ObservableObject {
    @Published var goals: Set<GoalTag> = []
    @Published var equipment: Set<EquipmentTag> = []
    @Published var householdEquipment: Set<KitchenEquipmentTag> = []
    @Published var gymEquipmentItems: Set<GymEquipmentTag> = []
    @Published var customGymEquipment: [String] = []
    /// Catalog + custom items combined -- shown as a count on the
    /// settings row rather than the other rows' comma-joined summary,
    /// which would be unreadable at up to 78 possible selections.
    var gymEquipmentSelectedCount: Int { gymEquipmentItems.count + customGymEquipment.count }
    @Published var injuryTags: Set<InjuryTag> = []
    @Published var injurySeverity: [InjuryTag: InjurySeverity] = [:]
    @Published var injuryType: [InjuryTag: InjuryType] = [:]
    @Published var injuryPainLevel: [InjuryTag: Int] = [:]
    @Published var contactEmailText = ""
    @Published var otherGoalText = ""
    @Published var otherEquipmentText = ""
    @Published var otherHouseholdEquipmentText = ""
    @Published var injuryNotesText = ""
    @Published var experienceLevel: ExperienceLevel?
    @Published var pregnancy: Bool?
    @Published var pregnancyWeek: Int?
    /// Read-only pass-through -- see UserProfile.sex's own doc comment.
    /// Gates the cycle-tracking row's visibility only, never edited here.
    @Published var sex: Sex?
    /// Opt-in cycle-phase tracking (Phase 5: see
    /// docs/coaching-personalization-plan.md) -- Date here (not the wire
    /// string) for DatePicker, same convention as dateOfBirthDate below;
    /// converted via Self.dobFormatter (identical "yyyy-MM-dd" wire format).
    @Published var lastPeriodStartDate: Date?
    @Published var typicalCycleLengthDays: Int?
    @Published var weeklySessionTarget: Int?
    /// Text, not Double, per pattern -- same "let the user type freely,
    /// parse on save" reasoning as LogMealView's numeric fields. A blank
    /// entry for a pattern just means "keep using the estimate for this
    /// one", not zero.
    @Published var knownLiftsText: [LiftPattern: String] = [:]
    /// Pass-through only -- no editor for these three yet (set during
    /// onboarding), but updateProfile writes height_cm/journey_stage/
    /// blockers_notes unconditionally (NSNull if absent). Without loading
    /// and re-sending them, ANY save -- including something as unrelated
    /// as changing region -- silently wiped all three, which in turn
    /// silently broke the Health Dashboard's BMI card (needs height) on
    /// the next load. Loaded once in load(), never mutated by any control.
    @Published var preservedHeightCm: Double?
    @Published var preservedJourneyStage: JourneyStage?
    @Published var preservedBlockersNotes: String?
    /// Unlike the three above, THIS one has a real editor
    /// (dateOfBirthEditor) -- see UserProfile.dateOfBirth's doc comment.
    /// nil means genuinely unset (an account that predates the onboarding
    /// DOB step), distinct from "user picked today's date" which the
    /// DatePicker binding below needs a concrete non-optional default for.
    @Published var dateOfBirthDate: Date?
    @Published var sessionsDoneThisWeek = 0
    // Region (country ISO code + free-text city) -- powers the future
    // nearby gyms/partners suggestions; saved via the normal profile flow.
    @Published var countryCode: String?
    @Published var cityText = ""
    // Weekly anchor sessions (Phase 4: see docs/coaching-personalization-plan.md)
    // -- a real editor, unlike preservedHeightCm/etc above, so these are
    // loaded AND sent back live on every save, same as countryCode/cityText.
    // Item 6 fix: a list (up to 5), not a single name/days pair.
    @Published var anchorSessions: [AnchorSession] = []
    /// Non-nil while the add/edit sub-sheet is open -- a fresh UUID string
    /// not yet in `anchorSessions` means "adding new"; an id that IS in
    /// the list means "editing that one". Draft fields below hold the
    /// in-progress edit until committed, so canceling never mutates
    /// `anchorSessions` itself.
    @Published var editingAnchorId: String?
    @Published var draftAnchorName = ""
    @Published var draftAnchorDays: Set<Int> = []
    @Published var anchorEditError: String?

    var isAddingNewAnchor: Bool {
        guard let editingAnchorId else { return false }
        return !anchorSessions.contains { $0.id == editingAnchorId }
    }

    static let maxAnchorSessions = 5

    func beginAddingAnchor() {
        editingAnchorId = UUID().uuidString
        draftAnchorName = ""
        draftAnchorDays = []
        anchorEditError = nil
    }

    func beginEditingAnchor(_ anchor: AnchorSession) {
        editingAnchorId = anchor.id
        draftAnchorName = anchor.name
        draftAnchorDays = Set(anchor.days)
        anchorEditError = nil
    }

    func cancelAnchorEdit() {
        editingAnchorId = nil
        anchorEditError = nil
    }

    /// Validates (name 1-40 chars, >=1 day) then appends or replaces --
    /// duplicate names are allowed (per spec: two "Gym" entries at
    /// different times is a real scenario), only the day/name shape is
    /// validated.
    func commitAnchorEdit() {
        guard let editingAnchorId else { return }
        let name = draftAnchorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else {
            anchorEditError = String(localized: "profile.anchorSession.error.name", defaultValue: "Give it a short name (1-40 characters).", comment: "Validation error when an anchor session's name is empty or too long")
            return
        }
        guard !draftAnchorDays.isEmpty else {
            anchorEditError = String(localized: "profile.anchorSession.error.days", defaultValue: "Pick at least one day.", comment: "Validation error when an anchor session has no days selected")
            return
        }
        let anchor = AnchorSession(id: editingAnchorId, name: name, days: draftAnchorDays.sorted())
        if let index = anchorSessions.firstIndex(where: { $0.id == editingAnchorId }) {
            anchorSessions[index] = anchor
        } else {
            guard anchorSessions.count < Self.maxAnchorSessions else {
                anchorEditError = String(localized: "profile.anchorSession.error.max", defaultValue: "You can have up to 5 recurring activities.", comment: "Validation error when trying to add more than the maximum allowed anchor sessions")
                return
            }
            anchorSessions.append(anchor)
        }
        self.editingAnchorId = nil
        anchorEditError = nil
    }

    func deleteAnchor(_ id: String) {
        anchorSessions.removeAll { $0.id == id }
    }

    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var savedConfirmation = false

    // Connect-more-devices -- same connect flow (system pop-up:
    // ASWebAuthenticationSession for Whoop/Oura, HealthKit's native sheet
    // for Apple Health) as the onboarding Connect Device screen, reusing
    // the same ProviderCardView for a consistent look.
    @Published var connecting: Set<Provider> = []
    @Published var deviceErrorMessage: String?

    @Published var showTrainingHistory = false
    // Sport goals -- entry renders only when the RLS-gated catalog is
    // non-empty or a goal already exists (server kill switch looks natural).
    @Published var showSportGoals = false
    @Published var sportCatalogAvailable = false
    @Published var activeSportGoal: UserGoal?
    @Published var sportGoalCatalog: SportCatalog?
    @Published var completedSportGoals = 0
    @Published var pausedSportGoal: UserGoal?
    @Published var showHealthDashboard = false
    @Published var completedWorkoutStreak = 0

    // Body photos -- gated by Config.enableBodyPhotoUpload. The actual
    // photos/history/upload UI lives entirely in GoalBodyProgressView (its
    // own destination, not a settings sheet) -- this only needs to know
    // whether to show the entry point at all.
    /// Adult-only gate (App Store 4+ rating) -- fails closed until load()
    /// confirms an 18+ date_of_birth, same posture as PostSetupFlowView's
    /// matching gate on the onboarding version of this same feature.
    @Published var isConfirmedAdultForBodyPhotos = false
    @Published var showGoalBodyProgress = false

    // Profile picture -- avatar_photo_path on `users`, its own private
    // Storage bucket (avatars), same signed-URL pattern as body photos.
    @Published var avatarImage: UIImage?
    @Published var avatarPhotoPath: String?
    @Published var avatarItem: PhotosPickerItem?
    @Published var showAvatarPicker = false
    @Published var isUploadingAvatar = false
    /// Its own state, separate from the Account page's save-flow
    /// errorMessage -- the avatar button lives on the hub, visible before
    /// any page is opened, so its error needs to be visible there too
    /// rather than only surfacing on the Account page.
    @Published var avatarErrorMessage: String?

    // Streak badges + share card -- completedWorkoutStreak above is the
    // real number. Today's steps are fetched purely for the optional
    // share-card chip (best-effort, nil if HealthKit is unavailable/
    // unauthorized -- never blocks anything else here).
    @Published var showStreakShareSheet = false
    @Published var todaysSteps: Int?

    /// Real, queryable local-notification authorization status -- backs
    /// the hub's Account card subtitle. Never guessed/defaulted to "on".
    @Published var notificationsAuthorized = false

    /// Quiet hours -- local device preference (NotificationManager's own
    /// UserDefaults-backed storage, not a synced UserProfile field), so
    /// these apply immediately on change rather than waiting for save().
    /// Date, not raw minute-of-day, purely so the editor sheet can bind a
    /// wheel-style DatePicker the same way dateOfBirthEditor/wake-time do.
    @Published var quietHoursEnabled = false
    @Published var quietHoursStart = Date()
    @Published var quietHoursEnd = Date()

    // Which field editor sheet (if any) is open -- shared across every
    // subpage since only one is ever on screen at a time.
    @Published fileprivate var activeSheet: ProfileSheet?
    @Published var showReferralCodeSheet = false
    /// Refresher entry point for the same tour the onboarding checklist's
    /// "See how Soma works" item opens -- see HowSomaWorksTourView's own
    /// doc comment. No completion write here: this exists precisely for a
    /// user who already completed onboarding, so there's nothing left to
    /// mark.
    @Published var showHowSomaWorks = false
    /// Non-nil right after picking a language different from the current
    /// one -- drives the "restart to finish switching" alert in the
    /// language editor. Holds the newly-picked language (not just a Bool)
    /// so the alert's message can name it.
    @Published var languageNeedingRestartPrompt: AppLanguage?

    /// Shared fallback text for an unset profile field, reused across
    /// every summary row/card so its localization stays consistent.
    var notSetLabel: String {
        String(localized: "profile.notSet", defaultValue: "Not set", comment: "Fallback value shown when a profile field hasn't been set yet")
    }

    /// Lowercase variant used mid-sentence in Stepper titles.
    var notSetLowerLabel: String {
        String(localized: "profile.notSetLower", defaultValue: "not set", comment: "Lowercase 'not set' fallback used mid-sentence in a Stepper title")
    }

    var signOutLabel: String {
        String(localized: "profile.signOut", defaultValue: "Sign out", comment: "Button to sign out of the account")
    }

    /// "Hot Yoga, Tennis league" / "Hot Yoga" / "Not set" -- summary shown
    /// on the Profile hub's row; the sheet itself shows the full list with
    /// days per anchor.
    var anchorSessionRowValue: String {
        guard !anchorSessions.isEmpty else { return notSetLabel }
        return anchorSessions.map(\.name).joined(separator: ", ")
    }

    /// Kill switch: the row exists only when the server-gated catalog has
    /// content, or the user already has goal data to reach.
    var showSportGoalRow: Bool {
        Config.enableSportGoals && (sportCatalogAvailable || activeSportGoal != nil || completedSportGoals > 0 || pausedSportGoal != nil)
    }

    /// Must mirror what the goal screen actually opens to -- a paused goal
    /// still names the row ("Not set" while the hub shows a goal is a lie).
    var sportGoalRowValue: String {
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

    /// Gated on sex, not just the kill switch -- sexAwareGuidance.ts's
    /// underlying guidance only ever fires for sex == "female" (see
    /// describeSexAwareConsiderations), so showing this row to anyone else
    /// would just be collecting sensitive data that can never affect
    /// anything -- worse for data minimization than not showing it at all.
    var cycleTrackingRowVisible: Bool {
        Config.enableCyclePhaseTracking && sex == .female
    }

    var cycleTrackingRowValue: String {
        guard let lastPeriodStartDate else { return notSetLabel }
        let dateText = Self.dobFormatter.string(from: lastPeriodStartDate)
        let lengthLabel = typicalCycleLengthDays.map {
            String(localized: "profile.cycleTracking.lengthLabel", defaultValue: "\($0)d cycle", comment: "Cycle-tracking row value fragment: cycle length in days, e.g. '28d cycle'")
        } ?? String(localized: "profile.cycleTracking.defaultLengthLabel", defaultValue: "~28d cycle", comment: "Cycle-tracking row value fragment shown when no custom cycle length has been set")
        return String(localized: "profile.cycleTracking.summary", defaultValue: "\(dateText) · \(lengthLabel)", comment: "Cycle-tracking row value: last period start date and cycle length, e.g. 'Jan 1, 2024 · 28d cycle'")
    }

    /// Parses knownLiftsText into the wire shape -- a blank or
    /// non-positive entry for a pattern is dropped rather than saved as
    /// 0, so it falls back to the population estimate exactly like never
    /// having entered anything.
    var knownLifts: [String: Double] {
        var result: [String: Double] = [:]
        for (pattern, text) in knownLiftsText {
            if let value = Double(text.trimmingCharacters(in: .whitespaces)), value > 0 {
                result[pattern.rawValue] = value
            }
        }
        return result
    }

    func toggle<T: Hashable>(_ tag: T, in set: inout Set<T>) {
        if set.contains(tag) {
            set.remove(tag)
        } else {
            set.insert(tag)
        }
    }

    /// Writes the current quiet-hours fields to NotificationManager
    /// immediately -- same "no store.save() needed" reasoning as the
    /// language picker: this is a local device preference, not a synced
    /// profile field, so there's nothing for the normal save() flow to do.
    func applyQuietHours() {
        NotificationManager.shared.isQuietHoursEnabled = quietHoursEnabled
        NotificationManager.shared.quietHoursStartMinute = Self.minuteOfDay(from: quietHoursStart)
        NotificationManager.shared.quietHoursEndMinute = Self.minuteOfDay(from: quietHoursEnd)
    }

    private static func date(fromMinuteOfDay minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
    }

    private static func minuteOfDay(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    func load(appState: AppState) async {
        guard let userId = SupabaseClient.shared.currentUserID else { return }
        guard let profile = try? await SupabaseClient.shared.fetchProfile(id: userId) else { return }

        contactEmailText = profile.contactEmail ?? ""
        goals = Set(profile.goals)
        otherGoalText = profile.otherGoalNotes ?? ""
        equipment = Set(profile.equipment)
        otherEquipmentText = profile.otherEquipmentNotes ?? ""
        householdEquipment = Set(profile.householdEquipment)
        otherHouseholdEquipmentText = profile.otherHouseholdEquipmentNotes ?? ""
        gymEquipmentItems = Set(profile.gymEquipmentItems)
        customGymEquipment = profile.customGymEquipment
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
        anchorSessions = profile.anchorSessions
        preservedHeightCm = profile.heightCm
        preservedJourneyStage = profile.journeyStage
        preservedBlockersNotes = profile.blockersNotes
        dateOfBirthDate = profile.dateOfBirth.flatMap(Self.dobFormatter.date(from:))

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
        notificationsAuthorized = await NotificationManager.shared.isAuthorized()
        quietHoursEnabled = NotificationManager.shared.isQuietHoursEnabled
        quietHoursStart = Self.date(fromMinuteOfDay: NotificationManager.shared.quietHoursStartMinute)
        quietHoursEnd = Self.date(fromMinuteOfDay: NotificationManager.shared.quietHoursEndMinute)
        await loadSportGoalState()
        await loadConnectionStatus(appState: appState)

        setSuperwallUserAttributes(profile: profile, appState: appState)
    }

    /// Compresses, uploads, and updates local state so the header shows
    /// the new photo immediately -- same shape as GoalBodyProgressView's
    /// upload(kind:item:).
    func uploadAvatar(item: PhotosPickerItem?) async {
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

    func removeAvatar() async {
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
    /// rows -- delegates to AppState's shared refresh (also used on every
    /// sign-in) rather than duplicating the fetch-and-merge logic here.
    /// See AppState.refreshConnectedProviders's own doc comment.
    func loadConnectionStatus(appState: AppState) async {
        await appState.refreshConnectedProviders()
    }

    /// Best-effort (`try?` throughout): a failed fetch degrades to hidden
    /// entry points, indistinguishable from the server kill switch.
    func loadSportGoalState() async {
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
    func setSuperwallUserAttributes(profile: UserProfile, appState: AppState) {
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
    func presentPremiumPaywall() {
        let handler = SuperwallDiagnostics.handler(placement: "view_premium")
        handler.onDismiss { _, result in
            WinBackOfferManager.maybePresentAfterDecline(result: result)
        }
        Superwall.shared.register(placement: "view_premium", handler: handler)
    }

    func connectDevice(_ provider: Provider, appState: AppState) {
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

    func save() {
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
            gymEquipmentItems: Array(gymEquipmentItems),
            customGymEquipment: customGymEquipment,
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
            anchorSessions: anchorSessions
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
                errorMessage = String(localized: "profile.save.genericError", defaultValue: "Couldn't save profile. Try again.", comment: "Error shown when the profile-fields save request itself fails")
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

    /// "yyyy-MM-dd", matching UserProfile.dateOfBirth's wire format
    /// (same as AgeGate.isAdult's parser).
    static let dobFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    static var defaultDateOfBirth: Date {
        Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    }

    /// ISO region codes sorted by their localized display name -- never a
    /// hand-maintained country list.
    static let countryOptions: [(code: String, name: String)] = Locale.Region.isoRegions
        .map(\.identifier)
        .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
        .compactMap { code in Locale.current.localizedString(forRegionCode: code).map { (code, $0) } }
        .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }

    /// Consecutive days up to and including today with a logged workout --
    /// same underlying data (fetchRecentWorkoutLogDates) as the calendar
    /// strip's crown badges, just aggregated into a streak count here.
    /// Not `private` so StreakMilestoneTests can exercise it directly.
    /// `nonisolated` -- a pure function over its argument, touches no
    /// `@MainActor`-isolated state, so it shouldn't force every synchronous
    /// caller (including the plain XCTestCase methods that unit-test it) to
    /// hop actors just to call it.
    nonisolated static func streak(from dates: Set<String>) -> Int {
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
}

// MARK: - Training page

private struct TrainingSettingsView: View {
    @ObservedObject var store: ProfileStore

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                groupCard(
                    eyebrow: LocalizedStringKey(String(localized: "profile.training.eyebrow", defaultValue: "TRAINING", comment: "All-caps section eyebrow label on the Training settings page")),
                    footnote: String(localized: "profile.training.groupFootnote", defaultValue: "Experience sets block count, supersets and rest. A real lift number beats an estimate.", comment: "Footnote under the Training settings group")
                ) {
                    groupRow(title: LocalizedStringKey(String(localized: "profile.experience.title", defaultValue: "Experience", comment: "Row title opening the experience-level editor")), value: store.experienceLevel?.displayName ?? store.notSetLabel, isSet: store.experienceLevel != nil) { store.activeSheet = .experience }
                    groupDivider
                    groupRow(
                        title: LocalizedStringKey(String(localized: "profile.goals.title", defaultValue: "Goals", comment: "Row title opening the training-goals editor")),
                        value: store.goals.isEmpty ? store.notSetLabel : String(localized: "profile.goals.selectedCount", defaultValue: "\(store.goals.count) selected", comment: "Training goals row value: number of goals selected"),
                        isSet: !store.goals.isEmpty
                    ) { store.activeSheet = .goals }
                    groupDivider
                    groupRow(
                        title: LocalizedStringKey(String(localized: "profile.weeklyTarget.title", defaultValue: "Weekly target", comment: "Row title opening the weekly-target editor")),
                        value: store.weeklySessionTarget.map {
                            String(localized: "profile.weeklyTarget.progress", defaultValue: "\($0)/wk · \(store.sessionsDoneThisWeek) done", comment: "Weekly target row value: target sessions per week and sessions done so far, e.g. '4/wk · 2 done'")
                        } ?? store.notSetLabel,
                        isSet: store.weeklySessionTarget != nil
                    ) { store.activeSheet = .weeklyTarget }
                    groupDivider
                    groupRow(
                        title: LocalizedStringKey(String(localized: "profile.anchorSession.title", defaultValue: "Weekly anchor session", comment: "Row title for the weekly anchor session editor")),
                        value: store.anchorSessionRowValue,
                        isSet: store.anchorSessionRowValue != store.notSetLabel
                    ) { store.activeSheet = .anchorSession }
                    groupDivider
                    groupRow(
                        title: LocalizedStringKey(String(localized: "profile.knownLifts.title", defaultValue: "Your current lifts", comment: "Row title for the known-lifts editor")),
                        value: store.knownLifts.isEmpty ? store.notSetLabel : String(localized: "profile.knownLifts.countLabel", defaultValue: "\(store.knownLifts.count) set", comment: "Known-lifts row value: number of lift patterns with a saved value, e.g. '3 set'"),
                        isSet: !store.knownLifts.isEmpty
                    ) { store.activeSheet = .knownLifts }
                    if store.showSportGoalRow {
                        groupDivider
                        groupRow(title: LocalizedStringKey(String(localized: "profile.sportGoal.rowTitle", defaultValue: "My goal", comment: "Row title opening the sport-goal flow")), value: store.sportGoalRowValue, isSet: store.sportGoalRowValue != store.notSetLabel, tinted: true) {
                            AnalyticsManager.shared.featureUsed(name: "sport_goal_flow")
                            store.showSportGoals = true
                        }
                    }
                }

                groupCard(
                    eyebrow: LocalizedStringKey(String(localized: "profile.equipment.eyebrow", defaultValue: "EQUIPMENT", comment: "All-caps section eyebrow label on the Equipment settings group")),
                    footnote: String(localized: "profile.equipment.groupFootnote", defaultValue: "Suggestions only use what you actually have.", comment: "Footnote under the Equipment settings group")
                ) {
                    groupRow(
                        title: LocalizedStringKey(String(localized: "profile.gymAccess.rowTitle", defaultValue: "Gym & access", comment: "Row title opening the gym/equipment-access editor")),
                        value: store.equipment.isEmpty ? store.notSetLabel : EquipmentTag.allCases.filter(store.equipment.contains).map(\.displayName).joined(separator: ", "),
                        isSet: !store.equipment.isEmpty
                    ) { store.activeSheet = .equipment }
                    groupDivider
                    groupRow(
                        title: LocalizedStringKey(String(localized: "profile.gymEquipment.rowTitle", defaultValue: "Gym equipment", comment: "Row title opening the specific gym-equipment editor")),
                        value: store.gymEquipmentSelectedCount == 0 ? store.notSetLabel : String(localized: "profile.gymEquipment.selectedCount", defaultValue: "\(store.gymEquipmentSelectedCount) selected", comment: "Gym equipment row value: number of items selected (catalog + custom)"),
                        isSet: store.gymEquipmentSelectedCount > 0
                    ) { store.activeSheet = .gymEquipmentDetail }
                    groupDivider
                    groupRow(
                        title: LocalizedStringKey(String(localized: "profile.kitchenEquipment.title", defaultValue: "Kitchen equipment", comment: "Row title for the kitchen-equipment editor")),
                        value: store.householdEquipment.isEmpty ? store.notSetLabel : KitchenEquipmentTag.allCases.filter(store.householdEquipment.contains).map(\.displayName).joined(separator: ", "),
                        isSet: !store.householdEquipment.isEmpty
                    ) { store.activeSheet = .kitchenEquipment }
                }
            }
            .padding(20)
        }
        .somaBackground()
        .navigationTitle(String(localized: "profile.hub.training.title", defaultValue: "Training", comment: "Hub card title and settings page navigation title for Training"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $store.activeSheet) { sheet in
            DetailSheetContent(sheet: sheet, store: store)
        }
        .sheet(isPresented: $store.showSportGoals, onDismiss: {
            Task { await store.loadSportGoalState() }
        }) {
            SportGoalFlowView()
        }
    }
}

// MARK: - Health & Safety page

private struct HealthSafetySettingsView: View {
    @ObservedObject var store: ProfileStore

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                groupCard(
                    eyebrow: LocalizedStringKey(String(localized: "profile.safety.eyebrow", defaultValue: "SAFETY", comment: "All-caps section eyebrow label on the Safety settings group")),
                    footnote: String(localized: "profile.safety.groupFootnote", defaultValue: "Injuries and pregnancy status shape today's intensity and what gets suggested.", comment: "Footnote under the Safety settings group")
                ) {
                    groupRow(
                        title: LocalizedStringKey(String(localized: "profile.injuries.title", defaultValue: "Injuries", comment: "Row title opening the injuries editor")),
                        value: store.injuryTags.isEmpty ? String(localized: "profile.injuries.noneNoted", defaultValue: "None noted", comment: "Injuries row value when no injuries are recorded") : store.injuryTags.map(\.displayName).joined(separator: ", "),
                        isSet: !store.injuryTags.isEmpty
                    ) { store.activeSheet = .injuries }
                    groupDivider
                    groupRow(
                        title: LocalizedStringKey(String(localized: "profile.pregnancy.title", defaultValue: "Pregnancy", comment: "Row title opening the pregnancy editor")),
                        value: store.pregnancy == true
                            ? (store.pregnancyWeek.map { String(localized: "profile.pregnancy.week", defaultValue: "Week \($0)", comment: "Pregnancy row value showing the current week number, e.g. 'Week 12'") } ?? String(localized: "profile.pregnancy.yes", defaultValue: "Yes", comment: "Pregnancy row value when pregnant but no week number is set"))
                            : store.notSetLabel,
                        isSet: store.pregnancy == true
                    ) { store.activeSheet = .pregnancy }

                    if store.cycleTrackingRowVisible {
                        groupDivider
                        groupRow(
                            title: LocalizedStringKey(String(localized: "profile.cycleTracking.title", defaultValue: "Cycle tracking", comment: "Row title for the cycle-tracking editor")),
                            value: store.cycleTrackingRowValue,
                            isSet: store.cycleTrackingRowValue != store.notSetLabel
                        ) { store.activeSheet = .cycleTracking }
                    }

                    if Config.enableBodyPhotoUpload && store.isConfirmedAdultForBodyPhotos {
                        groupDivider
                        groupRow(title: LocalizedStringKey(String(localized: "profile.yourProgress.rowTitle", defaultValue: "Your progress", comment: "Row title opening the Goal Body progress photos page"))) { store.showGoalBodyProgress = true }
                    }
                }

                groupCard(
                    eyebrow: LocalizedStringKey(String(localized: "profile.insights.eyebrow", defaultValue: "INSIGHTS", comment: "All-caps section eyebrow label on the Insights settings group")),
                    footnote: String(localized: "profile.insights.groupFootnote", defaultValue: "Training history and recovery trends, at a glance.", comment: "Footnote under the Insights settings group")
                ) {
                    groupRow(title: LocalizedStringKey(String(localized: "profile.trainingHistory.rowTitle", defaultValue: "Training history", comment: "Row title opening the training-history page"))) {
                        AnalyticsManager.shared.featureUsed(name: "training_history")
                        store.showTrainingHistory = true
                    }
                    groupDivider
                    groupRow(title: LocalizedStringKey(String(localized: "profile.healthDashboard.rowTitle", defaultValue: "Health dashboard", comment: "Row title opening the health-dashboard page"))) {
                        AnalyticsManager.shared.featureUsed(name: "health_dashboard")
                        store.showHealthDashboard = true
                    }
                }
            }
            .padding(20)
        }
        .somaBackground()
        .navigationTitle(String(localized: "profile.hub.healthSafety.title", defaultValue: "Health & Safety", comment: "Hub card title and settings page navigation title for Health & Safety"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $store.activeSheet) { sheet in
            DetailSheetContent(sheet: sheet, store: store)
        }
        .sheet(isPresented: $store.showTrainingHistory) {
            TrainingHistoryView()
        }
        .sheet(isPresented: $store.showHealthDashboard) {
            HealthDashboardView()
        }
        .sheet(isPresented: $store.showGoalBodyProgress) {
            GoalBodyProgressView()
        }
    }
}

// MARK: - Devices & Data page

private struct DevicesSettingsView: View {
    @ObservedObject var store: ProfileStore
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                groupEyebrow(LocalizedStringKey(String(localized: "profile.devices.eyebrow", defaultValue: "CONNECTED DEVICES", comment: "All-caps section eyebrow label above the connected-device rows")))
                VStack(spacing: 0) {
                    ForEach(Array(Provider.allCases.enumerated()), id: \.element) { index, provider in
                        if index > 0 { groupDivider }
                        deviceRow(provider, appState: appState, store: store)
                    }
                }
                .background(SomaTokens.surface3, in: RoundedRectangle(cornerRadius: SomaTokens.rRow, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: SomaTokens.rRow, style: .continuous).strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                Text(String(localized: "profile.devices.groupFootnote", defaultValue: "Grey means not connected, green means connected.", comment: "Footnote under the Connected devices settings group"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(SomaTokens.ink3)
                    .padding(.horizontal, 6)
                if let deviceErrorMessage = store.deviceErrorMessage {
                    Text(deviceErrorMessage)
                        .font(.caption)
                        .foregroundStyle(SomaTokens.danger)
                }
            }
            .padding(20)
        }
        .somaBackground()
        .navigationTitle(String(localized: "profile.hub.devicesData.title", defaultValue: "Devices & Data", comment: "Hub card title and settings page navigation title for Devices & Data"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Account page

private struct AccountSettingsView: View {
    @ObservedObject var store: ProfileStore
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var languageManager: LanguageManager
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    /// Pushed 16c page -- plus a local mirror of its On/Off for the row
    /// value, refreshed on appear since the page edits NotificationManager
    /// directly rather than going through ProfileStore.
    @State private var showAffirmationReminders = false
    @State private var affirmationRemindersOn = NotificationManager.shared.affirmationRemindersEnabled
    /// App Review 5.1.1(v): in-app account deletion, pushed as its own page.
    @State private var showDeleteAccount = false
    /// Identity providers on the current auth user -- gates the "Change
    /// password" row below to email/password accounts only (Apple/Google
    /// -only accounts have no password to change), same call and same
    /// reasoning DeleteAccountView already applies to its own Apple-reauth
    /// step.
    @State private var authProviders: [String] = []
    @State private var showChangePassword = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                groupCard(
                    eyebrow: LocalizedStringKey(String(localized: "profile.about.eyebrow", defaultValue: "ABOUT", comment: "All-caps section eyebrow label on the About settings group")),
                    footnote: String(localized: "profile.about.groupFootnote", defaultValue: "Region powers nearby gym & coach suggestions; date of birth unlocks Goal Body progress photos.", comment: "Footnote under the About settings group")
                ) {
                    groupRow(
                        title: LocalizedStringKey(String(localized: "profile.contactEmail.title", defaultValue: "Contact email", comment: "Row title opening the contact-email editor")),
                        value: store.contactEmailText.isEmpty ? store.notSetLabel : store.contactEmailText,
                        isSet: !store.contactEmailText.isEmpty
                    ) { store.activeSheet = .contactEmail }
                    groupDivider
                    groupRow(
                        title: LocalizedStringKey(String(localized: "profile.region.title", defaultValue: "Region", comment: "Row title opening the region editor")),
                        value: UserProfile.regionDisplay(country: store.countryCode, city: store.cityText) ?? store.notSetLabel,
                        isSet: UserProfile.regionDisplay(country: store.countryCode, city: store.cityText) != nil
                    ) { store.activeSheet = .region }
                    groupDivider
                    groupRow(
                        title: LocalizedStringKey(String(localized: "profile.dateOfBirth.title", defaultValue: "Date of birth", comment: "Row title opening the date-of-birth editor")),
                        value: store.dateOfBirthDate.map { ProfileStore.dobFormatter.string(from: $0) } ?? store.notSetLabel,
                        isSet: store.dateOfBirthDate != nil
                    ) { store.activeSheet = .dateOfBirth }
                }

                groupCard(
                    eyebrow: LocalizedStringKey(String(localized: "profile.preferences.eyebrow", defaultValue: "PREFERENCES", comment: "All-caps section eyebrow label on the Preferences settings group")),
                    footnote: String(localized: "profile.preferences.groupFootnote", defaultValue: "Overrides your device's language just for Soma.", comment: "Footnote under the Preferences settings group")
                ) {
                    groupRow(
                        title: LocalizedStringKey(String(localized: "profile.language.title", defaultValue: "Language", comment: "Row title opening the language editor")),
                        value: languageManager.selected.displayName(locale: languageManager.effectiveLocale),
                        isSet: true
                    ) { store.activeSheet = .language }
                        .accessibilityIdentifier("language-settings-row")
                }

                groupCard(
                    eyebrow: LocalizedStringKey(String(localized: "profile.plan.eyebrow", defaultValue: "PLAN", comment: "All-caps section eyebrow label on the Plan settings group")),
                    footnote: String(localized: "profile.plan.groupFootnote", defaultValue: "Subscription, referral codes, feedback, and a refresher on how Soma works.", comment: "Footnote under the Plan settings group")
                ) {
                    groupRow(
                        title: LocalizedStringKey(String(localized: "profile.subscription.title", defaultValue: "Subscription", comment: "Row title opening the subscription/paywall")),
                        value: subscriptionStatusText(isSubscribed: subscriptionManager.isSubscribed, referralBonusUntil: appState.referralBonusUntil, locale: languageManager.effectiveLocale),
                        isSet: subscriptionManager.isSubscribed
                    ) {
                        if !subscriptionManager.isSubscribed { store.presentPremiumPaywall() }
                    }
                    groupDivider
                    groupRow(title: LocalizedStringKey(String(localized: "profile.referralCode.rowTitle", defaultValue: "Referral code", comment: "Row title opening the referral-code sheet"))) { store.showReferralCodeSheet = true }
                    groupDivider
                    groupRow(title: LocalizedStringKey(String(localized: "profile.redeemOfferCode.rowTitle", defaultValue: "Redeem App Store code", comment: "Row title presenting Apple's offer-code redemption sheet"))) { OfferCodeRedemption.present() }
                    groupDivider
                    groupRow(title: LocalizedStringKey(String(localized: "profile.feedback.rowTitle", defaultValue: "Feedback", comment: "Row title opening the feedback presenter"))) { FeedbackPresenter.present() }
                    groupDivider
                    groupRow(title: LocalizedStringKey(String(localized: "profile.howSomaWorks.title", defaultValue: "How Soma works", comment: "Row title opening the How Soma Works tour refresher"))) {
                        store.showHowSomaWorks = true
                    }
                }

                groupCard(
                    eyebrow: LocalizedStringKey(String(localized: "profile.notifications.eyebrow", defaultValue: "NOTIFICATIONS", comment: "All-caps section eyebrow label on the Notifications settings group")),
                    footnote: String(localized: "profile.notifications.groupFootnote", defaultValue: "Quiet hours delay any notification that would otherwise land inside the window -- nothing is lost, just pushed to when it ends.", comment: "Footnote under the Notifications settings group")
                ) {
                    // Same permission, same call as the onboarding "Enable
                    // notifications" screen and the daily checklist's
                    // .enableNotifications deep link (HomeView.handleChecklistDeepLink)
                    // -- linked to that one existing mechanism rather than a
                    // new one, so Settings has somewhere to see/act on it too.
                    groupRow(
                        title: LocalizedStringKey(String(localized: "profile.notifications.title", defaultValue: "Push notifications", comment: "Row title opening the system notification permission from Account settings")),
                        value: store.notificationsAuthorized
                            ? String(localized: "profile.notifications.onValue", defaultValue: "On", comment: "Push notifications row value when enabled")
                            : String(localized: "profile.notifications.offValue", defaultValue: "Off", comment: "Push notifications row value when disabled"),
                        isSet: store.notificationsAuthorized
                    ) {
                        Task {
                            // iOS never re-shows the system prompt after a
                            // first denial, so a prior "Don't Allow" routes
                            // to Settings instead of silently no-opping.
                            if await NotificationManager.shared.isDenied() {
                                SystemSettings.open()
                                return
                            }
                            do {
                                try await NotificationManager.shared.requestAuthorization()
                                store.notificationsAuthorized = await NotificationManager.shared.isAuthorized()
                                if store.notificationsAuthorized {
                                    AnalyticsManager.shared.notificationsEnabled()
                                    // Same-day coverage, matching NotificationEnablementView's
                                    // grant path -- BackgroundTaskManager's daily refresh won't
                                    // run again until tomorrow.
                                    Task { await NotificationManager.shared.scheduleTodaysEngagementNotifications() }
                                }
                            } catch {
                                store.errorMessage = error.localizedDescription
                            }
                        }
                    }
                    groupDivider
                    groupRow(
                        title: LocalizedStringKey(String(localized: "profile.quietHours.title", defaultValue: "Quiet hours", comment: "Settings row/sheet title for the notification quiet-hours editor")),
                        value: store.quietHoursEnabled
                            ? String(localized: "profile.quietHours.onValue", defaultValue: "On", comment: "Quiet hours row value when enabled")
                            : String(localized: "profile.quietHours.offValue", defaultValue: "Off", comment: "Quiet hours row value when disabled"),
                        isSet: store.quietHoursEnabled
                    ) { store.activeSheet = .quietHours }
                    groupDivider
                    groupRow(
                        title: LocalizedStringKey(String(localized: "profile.affirmationReminders.title", defaultValue: "Affirmation reminders", comment: "Row title opening the affirmation reminder settings page")),
                        value: affirmationRemindersOn
                            ? String(localized: "profile.notifications.onValue", defaultValue: "On", comment: "Push notifications row value when enabled")
                            : String(localized: "profile.notifications.offValue", defaultValue: "Off", comment: "Push notifications row value when disabled"),
                        isSet: affirmationRemindersOn
                    ) { showAffirmationReminders = true }
                }

                if authProviders.contains("email") {
                    groupCard(
                        eyebrow: LocalizedStringKey(String(localized: "profile.security.eyebrow", defaultValue: "SECURITY", comment: "All-caps section eyebrow label on the Security settings group")),
                        footnote: String(localized: "profile.security.groupFootnote", defaultValue: "Applies to email/password sign-in only.", comment: "Footnote under the Security settings group")
                    ) {
                        groupRow(title: LocalizedStringKey(String(localized: "profile.changePassword.title", defaultValue: "Change password", comment: "Row title opening the change-password page"))) {
                            showChangePassword = true
                        }
                    }
                }

                if let errorMessage = store.errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(SomaTokens.danger)
                }
                if store.savedConfirmation {
                    Text(String(localized: "profile.save.confirmation", defaultValue: "Saved.", comment: "Confirmation text shown briefly after a successful profile save")).font(.caption).foregroundStyle(SomaTokens.success)
                }

                // 5.1.1(v): easy to find, in account settings, destructive
                // styling -- same quiet centered-text treatment as the
                // hub's Sign out row, in danger rather than ink.
                Button {
                    showDeleteAccount = true
                } label: {
                    Text(String(localized: "profile.deleteAccount.row", defaultValue: "Delete account", comment: "Row in Account settings opening the account deletion page"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SomaTokens.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(String(localized: "profile.deleteAccount.rowHint", defaultValue: "Opens the page for permanently deleting your account", comment: "VoiceOver hint on the Delete account row")))
            }
            .padding(20)
        }
        .somaBackground()
        .navigationTitle(String(localized: "profile.hub.account.title", defaultValue: "Account", comment: "Hub card title and settings page navigation title for Account"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $store.activeSheet) { sheet in
            DetailSheetContent(sheet: sheet, store: store)
        }
        .sheet(isPresented: $store.showHowSomaWorks) {
            HowSomaWorksTourView(onFinish: { store.showHowSomaWorks = false })
        }
        .sheet(isPresented: $store.showReferralCodeSheet) {
            ReferralCodeSheet()
        }
        .navigationDestination(isPresented: $showAffirmationReminders) {
            AffirmationRemindersView()
        }
        .navigationDestination(isPresented: $showDeleteAccount) {
            DeleteAccountView()
        }
        .navigationDestination(isPresented: $showChangePassword) {
            ChangePasswordView()
        }
        // The 16c page writes straight to NotificationManager -- re-read
        // its On/Off when this page (re)appears so the row value tracks it.
        .onAppear { affirmationRemindersOn = NotificationManager.shared.affirmationRemindersEnabled }
        .task { authProviders = (try? await SupabaseClient.shared.fetchAuthProviders()) ?? [] }
    }

}

/// Three distinct states worth telling apart: paying, on a referral
/// bonus (free, but ending), or neither. Shared by the Account page's own
/// Subscription row and the hub's Account card subtitle so both always
/// agree.
private func subscriptionStatusText(isSubscribed: Bool, referralBonusUntil: Date?, locale: Locale) -> String {
    if isSubscribed {
        return String(localized: "profile.subscription.activeShort", defaultValue: "Active", comment: "Subscription row value when Premium is active")
    }
    if let referralBonusUntil, referralBonusUntil > Date() {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = locale
        let dateText = formatter.string(from: referralBonusUntil)
        return String(localized: "profile.subscription.freeBonusShort", defaultValue: "Free until \(dateText)", comment: "Subscription row value during a temporary referral-bonus free period")
    }
    return String(localized: "profile.subscription.freePlanShort", defaultValue: "Free plan", comment: "Subscription row value on the default free plan")
}

// MARK: - Shared row/card primitives

private func groupEyebrow(_ text: LocalizedStringKey) -> some View {
    Text(text)
        .font(.system(size: 11, weight: .bold))
        .tracking(0.7)
        .foregroundStyle(SomaTokens.ink4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
}

/// 9d's grouped-card container: one glass card per GROUP (vs a card per
/// individual setting), with a group eyebrow above and one shared footnote
/// below instead of a subtitle on every row. Callers place `groupDivider`
/// between `groupRow`s themselves (skip it after the last row) -- explicit
/// beats a private-API variadic trick for something this small.
private func groupCard(eyebrow: LocalizedStringKey, footnote: String, @ViewBuilder rows: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        groupEyebrow(eyebrow)
        VStack(spacing: 0, content: rows)
            .background(SomaTokens.surface3, in: RoundedRectangle(cornerRadius: SomaTokens.rRow, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: SomaTokens.rRow, style: .continuous).strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
        Text(footnote)
            .font(.system(size: 11.5))
            .foregroundStyle(SomaTokens.ink3)
            .padding(.horizontal, 6)
    }
}

private var groupDivider: some View {
    Rectangle()
        .fill(SomaTokens.ink.opacity(0.07))
        .frame(height: 1)
        .padding(.horizontal, 16)
}

/// 46px single-line row for a `groupCard` -- title left, value + chevron
/// right, no inline subtitle. `isSet` drives the design's "set values
/// show in accent, 'Not set' in gray" rule. `tinted` is the Turn 7
/// redline for the sport-goal row -- "tinted to stand apart from the
/// rest" -- a soft accent wash behind just that one row.
private func groupRow(title: LocalizedStringKey, value: String = "", isSet: Bool = false, tinted: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tinted ? SomaTokens.accent : SomaTokens.ink)
            Spacer(minLength: 8)
            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 13, weight: isSet ? .semibold : .regular))
                    .foregroundStyle(isSet ? SomaTokens.accent : SomaTokens.ink4)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tinted ? SomaTokens.accent : SomaTokens.inkPlaceholder)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(tinted ? SomaTokens.accentSoft10 : Color.clear)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}

/// Device rows: status dot, value in success/accent, no chevron --
/// visually distinct from a setting row (guide 05's own distinction).
/// Sized to `groupRow`'s 46px/16pt-padding convention -- the group's
/// shared card background comes from the caller (DevicesSettingsView).
@MainActor
private func deviceRow(_ provider: Provider, appState: AppState, store: ProfileStore) -> some View {
    let isConnected = appState.connectedProviders.contains(provider)
    // Server-verified: the stored refresh token failed (revoked,
    // expired) so the connection is dead even though the local cache
    // still says "connected." Tappable in this state -- unlike a
    // healthy connection, which is only ever disconnected by the
    // provider's own app/website, not from here.
    let needsReconnect = appState.providersNeedingReconnect.contains(provider)
    return Button {
        if !isConnected || needsReconnect { store.connectDevice(provider, appState: appState) }
    } label: {
        HStack(spacing: 10) {
            Circle()
                .fill(needsReconnect ? SomaTokens.warn : (isConnected ? SomaTokens.successDot : SomaTokens.neutralDot))
                .frame(width: 8, height: 8)
            Text(provider.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SomaTokens.ink)
            Spacer()
            if store.connecting.contains(provider) {
                ProgressView()
            } else if needsReconnect {
                Text(String(localized: "profile.device.reconnect", defaultValue: "Reconnect", comment: "Device row value shown when a connected provider needs re-authorization"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SomaTokens.warn)
            } else {
                Text(isConnected
                    ? String(localized: "profile.device.connectedStatus", defaultValue: "Connected", comment: "Device row value shown when a provider is connected")
                    : String(localized: "profile.device.connectAction", defaultValue: "Connect", comment: "Device row value shown when a provider is not yet connected"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isConnected ? SomaTokens.success : SomaTokens.accent)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled((isConnected && !needsReconnect) || store.connecting.contains(provider))
}

// MARK: - Detail sheets (field editors, shared by every page)

private enum ProfileSheet: String, Identifiable {
    case experience, goals, equipment, gymEquipmentDetail, kitchenEquipment, weeklyTarget, injuries, pregnancy, contactEmail, region, knownLifts, dateOfBirth, anchorSession, cycleTracking, language, quietHours
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
        case .experience: localizedString("profile.experience.title", locale: locale)
        case .goals: localizedString("profile.goals.title", locale: locale)
        case .equipment: localizedString("profile.equipmentAccess.sheetTitle", locale: locale)
        case .gymEquipmentDetail: localizedString("profile.gymEquipment.rowTitle", locale: locale)
        case .kitchenEquipment: localizedString("profile.kitchenEquipment.title", locale: locale)
        case .weeklyTarget: localizedString("profile.weeklyTarget.title", locale: locale)
        case .injuries: localizedString("profile.injuries.title", locale: locale)
        case .pregnancy: localizedString("profile.pregnancy.title", locale: locale)
        case .contactEmail: localizedString("profile.contactEmail.title", locale: locale)
        case .region: localizedString("profile.region.title", locale: locale)
        case .knownLifts: localizedString("profile.knownLifts.title", locale: locale)
        case .dateOfBirth: localizedString("profile.dateOfBirth.title", locale: locale)
        case .anchorSession: localizedString("profile.anchorSession.title", locale: locale)
        case .cycleTracking: localizedString("profile.cycleTracking.title", locale: locale)
        case .language: localizedString("profile.language.title", locale: locale)
        case .quietHours: localizedString("profile.quietHours.title", locale: locale)
        }
    }
}

private struct DetailSheetContent: View {
    let sheet: ProfileSheet
    @ObservedObject var store: ProfileStore
    @EnvironmentObject private var languageManager: LanguageManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch sheet {
                    case .experience: experienceEditor
                    case .goals: goalsEditor
                    case .equipment: equipmentEditor
                    case .gymEquipmentDetail: gymEquipmentDetailEditor
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
                    case .quietHours: quietHoursEditor
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
                    Button(String(localized: "profile.doneButton", defaultValue: "Done", comment: "Toolbar button dismissing a settings screen or sheet")) {
                        // Language and quiet hours are local device
                        // preferences applied immediately by their own
                        // editors, not synced profile fields -- skip the
                        // network save() for them.
                        if sheet != .language && sheet != .quietHours { store.save() }
                        store.activeSheet = nil
                    }
                    .disabled(store.isSaving)
                }
            }
        }
    }

    private var experienceEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "profile.experience.explainer", defaultValue: "Adjusts the AI workout plan's structure -- how many blocks, whether it uses supersets, and rest periods.", comment: "Explainer text at top of the experience-level editor sheet"))
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout {
                ForEach(ExperienceLevel.allCases) { level in
                    ChipToggle(title: level.displayName, isSelected: store.experienceLevel == level) {
                        store.experienceLevel = store.experienceLevel == level ? nil : level
                    }
                }
            }
        }
    }

    private var goalsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout {
                ForEach(GoalTag.allCases) { tag in
                    ChipToggle(title: tag.displayName, isSelected: store.goals.contains(tag)) {
                        store.toggle(tag, in: &store.goals)
                    }
                }
            }
            if store.goals.contains(.other) {
                TextField(String(localized: "profile.goals.otherPlaceholder", defaultValue: "What's your goal?", comment: "Placeholder for the free-text 'other goal' field"), text: $store.otherGoalText)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var equipmentEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout {
                ForEach(EquipmentTag.allCases) { tag in
                    ChipToggle(title: tag.displayName, isSelected: store.equipment.contains(tag)) {
                        store.toggle(tag, in: &store.equipment)
                    }
                }
            }
            if store.equipment.contains(.other) {
                TextField(String(localized: "profile.equipment.otherPlaceholder", defaultValue: "What else do you have access to?", comment: "Placeholder for the free-text 'other equipment' field"), text: $store.otherEquipmentText)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var gymEquipmentDetailEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "profile.gymEquipment.explainer", defaultValue: "So we only ever build workouts around gear you actually have.", comment: "Explainer text at top of the gym-equipment editor sheet"))
                .font(.caption)
                .foregroundStyle(.secondary)
            GymEquipmentPicker(selection: $store.gymEquipmentItems, customItems: $store.customGymEquipment)
        }
    }

    private var kitchenEquipmentEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "profile.kitchenEquipment.explainer", defaultValue: "So we only ever suggest recipes you can actually cook.", comment: "Explainer text at top of the kitchen-equipment editor sheet"))
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout {
                ForEach(KitchenEquipmentTag.allCases) { tag in
                    ChipToggle(title: tag.displayName, isSelected: store.householdEquipment.contains(tag)) {
                        store.toggle(tag, in: &store.householdEquipment)
                    }
                }
            }
            if store.householdEquipment.contains(.other) {
                TextField(String(localized: "profile.kitchenEquipment.otherPlaceholder", defaultValue: "What else? (comma-separated)", comment: "Placeholder text for the free-text 'other kitchen equipment' field"), text: $store.otherHouseholdEquipmentText)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var weeklyTargetEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "profile.weeklyTarget.explainer", defaultValue: "A personal tracking goal -- doesn't change what Soma recommends, just what it shows you here.", comment: "Explainer text at top of the weekly-target editor sheet"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper(
                String(localized: "profile.weeklyTarget.stepperTitle", defaultValue: "Target: \(store.weeklySessionTarget.map(String.init) ?? store.notSetLowerLabel) sessions/week", comment: "Stepper title for the weekly session target, e.g. 'Target: 4 sessions/week'"),
                value: Binding(get: { store.weeklySessionTarget ?? 3 }, set: { store.weeklySessionTarget = $0 }),
                in: 1...14
            )
            .font(.caption)
            if store.weeklySessionTarget != nil {
                Text(String(localized: "profile.weeklyTarget.doneThisWeek", defaultValue: "\(store.sessionsDoneThisWeek) done this week so far.", comment: "Text showing sessions completed so far this week"))
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
            Text(String(localized: "profile.knownLifts.explainer", defaultValue: "If you know your comfortable working weight for any of these, Soma uses it directly for the AI plan instead of estimating from your bodyweight and experience level. Leave any blank to keep using the estimate.", comment: "Explainer text at top of the known-lifts editor sheet"))
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(LiftPattern.allCases) { pattern in
                VStack(alignment: .leading, spacing: 4) {
                    Text(pattern.displayName)
                        .font(.system(size: 14.5, weight: .semibold))
                    HStack {
                        TextField(pattern.placeholder, text: Binding(
                            get: { store.knownLiftsText[pattern] ?? "" },
                            set: { store.knownLiftsText[pattern] = $0 }
                        ))
                        .keyboardType(.numberPad)
                        Text(String(localized: "profile.knownLifts.unitKg", defaultValue: "kg", comment: "Unit label shown next to each known-lift weight entry field"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .glassCardFlat(cornerRadius: SomaTokens.rMD)
                }
            }
        }
    }

    private var injuriesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "profile.injuries.explainer", defaultValue: "Any active injury caps today's intensity at Moderate and hides high-impact workouts.", comment: "Explainer text at top of the injuries editor sheet"))
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout {
                ForEach(InjuryTag.allCases) { tag in
                    ChipToggle(title: tag.displayName, isSelected: store.injuryTags.contains(tag)) {
                        store.toggle(tag, in: &store.injuryTags)
                        if store.injuryTags.contains(tag), store.injurySeverity[tag] == nil {
                            store.injurySeverity[tag] = .moderate
                        }
                    }
                }
            }
            ForEach(InjuryTag.allCases.filter { store.injuryTags.contains($0) }) { tag in
                VStack(alignment: .leading, spacing: 4) {
                    Text(tag.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(tag.displayName, selection: Binding(
                        get: { store.injurySeverity[tag] ?? .moderate },
                        set: { store.injurySeverity[tag] = $0 }
                    )) {
                        ForEach(InjurySeverity.allCases) { severity in
                            Text(severity.displayName).tag(severity)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker(String(localized: "profile.injuries.typeLabel", defaultValue: "Type (optional)", comment: "Picker label for the optional injury type"), selection: Binding(
                        get: { store.injuryType[tag] },
                        set: { store.injuryType[tag] = $0 }
                    )) {
                        Text(String(localized: "profile.injuries.typeNotSpecified", defaultValue: "Not specified", comment: "Picker option meaning no injury type was chosen")).tag(InjuryType?.none)
                        ForEach(InjuryType.allCases) { type in
                            Text(type.displayName).tag(InjuryType?.some(type))
                        }
                    }
                    .font(.caption)

                    Stepper(
                        String(localized: "profile.injuries.painLevelStepper", defaultValue: "Pain level: \(store.injuryPainLevel[tag].map(String.init) ?? store.notSetLowerLabel)", comment: "Stepper title for an injury's pain level, e.g. 'Pain level: 3'"),
                        value: Binding(get: { store.injuryPainLevel[tag] ?? 1 }, set: { store.injuryPainLevel[tag] = $0 }),
                        in: 1...10
                    )
                    .font(.caption)

                    if store.injurySeverity[tag] == .moderate || store.injurySeverity[tag] == .severe {
                        Text(String(localized: "profile.injuries.severityWarning", defaultValue: "Given the severity you've selected, consider seeing a physician or physiotherapist before continuing to train this area. Soma's guidance here is informational only, not a diagnosis.", comment: "Warning shown for moderate/severe injuries"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.top, 4)
            }
            TextField(String(localized: "profile.injuries.notesPlaceholder", defaultValue: "Notes (optional)", comment: "Placeholder for the free-text injury notes field"), text: $store.injuryNotesText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)
        }
    }

    private var pregnancyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "profile.pregnancy.explainer", defaultValue: "Optional, and never assumed -- only set if you tell us. Soma will adjust your workouts to your pregnancy stage rather than withhold them. This is general guidance only -- please follow your doctor's or midwife's advice, especially if you have any pregnancy complications.", comment: "Explainer text at top of the pregnancy editor sheet"))
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout {
                ChipToggle(title: String(localized: "profile.pregnancy.currentlyPregnant", defaultValue: "I'm currently pregnant", comment: "Pregnancy chip toggle label"), isSelected: store.pregnancy == true) {
                    store.pregnancy = (store.pregnancy == true) ? nil : true
                    if store.pregnancy != true { store.pregnancyWeek = nil }
                }
            }
            if store.pregnancy == true {
                Stepper(
                    String(localized: "profile.pregnancy.weekStepper", defaultValue: "Week: \(store.pregnancyWeek.map(String.init) ?? store.notSetLowerLabel)", comment: "Stepper title for the current pregnancy week, e.g. 'Week: 12'"),
                    value: Binding(get: { store.pregnancyWeek ?? 1 }, set: { store.pregnancyWeek = $0 }),
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
            Text(String(localized: "profile.cycleTracking.explainer", defaultValue: "Optional, and never assumed -- only set if you tell us. Soma will factor your cycle phase into training suggestions as one general consideration among others. This is general guidance only, not medical advice, and not a fertility or ovulation tracker.", comment: "Explainer text at top of the cycle-tracking editor sheet"))
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker(
                String(localized: "profile.cycleTracking.lastPeriodLabel", defaultValue: "Last period start date", comment: "Date picker label for the start date of the user's last period"),
                selection: Binding(
                    get: { store.lastPeriodStartDate ?? Date() },
                    set: { store.lastPeriodStartDate = $0 }
                ),
                in: ...Date(),
                displayedComponents: .date
            )
            if store.lastPeriodStartDate != nil {
                let lengthText = store.typicalCycleLengthDays.map {
                    String(localized: "profile.cycleTracking.daysCount", defaultValue: "\($0) days", comment: "Number of days shown in the typical-cycle-length stepper, e.g. '28 days'")
                } ?? String(localized: "profile.cycleTracking.stepperDefault", defaultValue: "not set (defaults to 28)", comment: "Shown in the typical-cycle-length stepper title when no custom length has been set yet")
                Stepper(
                    String(localized: "profile.cycleTracking.stepperTitle", defaultValue: "Typical cycle length: \(lengthText)", comment: "Stepper title showing the current typical cycle length setting, e.g. 'Typical cycle length: 28 days'"),
                    value: Binding(get: { store.typicalCycleLengthDays ?? 28 }, set: { store.typicalCycleLengthDays = $0 }),
                    in: 21...35
                )
                .font(.caption)
                Button(String(localized: "profile.cycleTracking.clear", defaultValue: "Clear", comment: "Button clearing the entered cycle-tracking dates")) {
                    store.lastPeriodStartDate = nil
                    store.typicalCycleLengthDays = nil
                }
                .font(.caption)
                .foregroundStyle(SomaTokens.danger)
            }
        }
    }

    private var contactEmailEditor: some View {
        TextField(String(localized: "profile.contactEmail.placeholder", defaultValue: "you@example.com", comment: "Placeholder example text in the contact-email field"), text: $store.contactEmailText)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
    }

    private var regionEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "profile.region.explainer", defaultValue: "Used for future nearby gym and coach partner suggestions.", comment: "Explainer text at top of the region editor sheet"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(String(localized: "profile.region.countryPickerLabel", defaultValue: "Country", comment: "Label for the country picker in the region editor"), selection: $store.countryCode) {
                Text(store.notSetLabel).tag(String?.none)
                ForEach(ProfileStore.countryOptions, id: \.code) { option in
                    Text(option.name).tag(String?.some(option.code))
                }
            }
            .pickerStyle(.menu)
            TextField(String(localized: "profile.region.cityPlaceholder", defaultValue: "City", comment: "Placeholder for the free-text city field in the region editor"), text: $store.cityText)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var languageEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "profile.language.explainer", defaultValue: "Most of Soma updates immediately; the rest applies next time you open the app.", comment: "Explainer text at top of the language picker sheet"))
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        let changed = languageManager.selected != language
                        languageManager.selected = language
                        // Only worth interrupting the user when the choice
                        // actually changed -- re-tapping the already-active
                        // language shouldn't nag them with a restart prompt
                        // for a no-op.
                        if changed {
                            store.languageNeedingRestartPrompt = language
                        }
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
        // A passive caption is easy to skim past -- this makes the "you'll
        // need to reopen the app" tradeoff an explicit, hard-to-miss step
        // right when it's actually relevant, instead of leaving someone
        // wondering why half the screen didn't change language. Apple's own
        // guidance is that an app should never terminate itself
        // programmatically (no exit(0) auto-relaunch) -- this just tells
        // the user plainly and lets them close the app themselves.
        .alert(
            String(localized: "profile.language.restartAlert.title", defaultValue: "Restart Soma to finish switching", comment: "Alert title shown after picking a new app language"),
            isPresented: Binding(
                get: { store.languageNeedingRestartPrompt != nil },
                set: { if !$0 { store.languageNeedingRestartPrompt = nil } }
            )
        ) {
            Button(String(localized: "profile.language.restartAlert.confirm", defaultValue: "Got it", comment: "Dismiss button on the language-restart alert")) {
                store.languageNeedingRestartPrompt = nil
            }
        } message: {
            if let language = store.languageNeedingRestartPrompt {
                Text(String(localized: "profile.language.restartAlert.message", defaultValue: "Most of the app already switched. Close Soma (swipe it away from the app switcher) and reopen it to see everything in \(language.displayName(locale: languageManager.effectiveLocale)).", comment: "Alert message telling the user to manually close and reopen the app to finish a language switch; placeholder is the newly-selected language's own display name"))
            }
        }
    }

    /// Same field pair as onboarding's AnchorSessionQuestionView, same
    /// WeekdayMiniPicker component -- lets someone who skipped it at
    /// onboarding set it later, or fix the wrong day.
    /// Item 6 fix: a list (up to 5), not a single name/days form -- real
    /// feedback is that anyone with a weekly schedule almost always has
    /// more than one recurring commitment. Add/edit happens in its own
    /// small sub-sheet (anchorSessionEditForm) rather than sharing this
    /// screen, so the day picker and keyboard never fight this list for
    /// space.
    private var anchorSessionEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "profile.anchorSession.explainer", defaultValue: "Recurring classes or activities (e.g. a Tuesday hot yoga class) the rest of your week gets built around.", comment: "Explainer text at top of the weekly anchor sessions list"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if store.anchorSessions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "profile.anchorSession.emptyState", defaultValue: "A regular class or activity the rest of the week gets built around.", comment: "Empty-state description shown when no anchor sessions are set yet"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "profile.anchorSession.emptyStateExample", defaultValue: "For example: \"Hot Yoga\" every Tuesday.", comment: "Empty-state example shown under the anchor sessions explainer"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.anchorSessions) { anchor in
                        Button {
                            store.beginEditingAnchor(anchor)
                        } label: {
                            HStack {
                                Text(anchor.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(anchor.days.sorted().map(WeekdayMiniPicker.shortName(forValue:)).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if anchor.id != store.anchorSessions.last?.id {
                            Divider()
                        }
                    }
                }
            }

            if store.anchorSessions.count < ProfileStore.maxAnchorSessions {
                Button {
                    store.beginAddingAnchor()
                } label: {
                    Label(String(localized: "profile.anchorSession.addButton", defaultValue: "Add activity", comment: "Button that opens the add-anchor-session sub-sheet"), systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SomaTokens.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: Binding(
            get: { store.editingAnchorId != nil },
            set: { if !$0 { store.cancelAnchorEdit() } }
        )) {
            anchorSessionEditForm
        }
    }

    /// Add/edit sub-sheet -- own NavigationStack/toolbar (Cancel/Save,
    /// plus Delete when editing an existing anchor), separate from the
    /// list screen's own Done button above.
    private var anchorSessionEditForm: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField(String(localized: "profile.anchorSession.namePlaceholder", defaultValue: "e.g. \"Hot Yoga\", \"Tennis league\"", comment: "Placeholder text for the anchor session name field"), text: $store.draftAnchorName)
                    .textFieldStyle(.roundedBorder)
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "profile.anchorSession.dayPrompt", defaultValue: "Which day(s) is it usually on?", comment: "Prompt above the weekday picker for the anchor session"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    WeekdayMiniPicker(selected: $store.draftAnchorDays)
                }
                if let anchorEditError = store.anchorEditError {
                    Text(anchorEditError)
                        .font(.caption)
                        .foregroundStyle(SomaTokens.danger)
                }
                Spacer()
                if !store.isAddingNewAnchor, let editingAnchorId = store.editingAnchorId {
                    Button(role: .destructive) {
                        store.deleteAnchor(editingAnchorId)
                        store.cancelAnchorEdit()
                    } label: {
                        Text(String(localized: "profile.anchorSession.deleteButton", defaultValue: "Delete", comment: "Button that removes an anchor session"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(SomaTokens.danger)
                }
            }
            .padding(20)
            .somaBackground()
            .navigationTitle(store.isAddingNewAnchor
                ? String(localized: "profile.anchorSession.addTitle", defaultValue: "Add activity", comment: "Navigation title for the add-anchor-session sub-sheet")
                : String(localized: "profile.anchorSession.editTitle", defaultValue: "Edit activity", comment: "Navigation title for the edit-anchor-session sub-sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "profile.anchorSession.cancelButton", defaultValue: "Cancel", comment: "Cancel button on the add/edit anchor session sub-sheet")) {
                        store.cancelAnchorEdit()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "profile.anchorSession.saveButton", defaultValue: "Save", comment: "Save button on the add/edit anchor session sub-sheet")) {
                        store.commitAnchorEdit()
                    }
                }
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
            Text(String(localized: "profile.dateOfBirth.explainer", defaultValue: "Confirms you're 18+ to unlock Goal Body progress photos. Never shown to other users.", comment: "Explainer text at top of the date-of-birth editor sheet"))
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker(
                String(localized: "profile.dateOfBirth.title", defaultValue: "Date of birth", comment: "Row title opening the date-of-birth editor; also used as this hidden DatePicker's accessibility label"),
                selection: Binding(
                    get: { store.dateOfBirthDate ?? ProfileStore.defaultDateOfBirth },
                    set: { store.dateOfBirthDate = $0 }
                ),
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
        }
    }

    /// Local device preference (NotificationManager's own UserDefaults),
    /// applied immediately on every change -- same "no store.save()"
    /// pattern as languageEditor, so there's no separate save step for the
    /// two time pickers below.
    private var quietHoursEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "profile.quietHours.explainer", defaultValue: "Soma won't schedule new notifications inside this window -- anything that would've landed here waits until it ends.", comment: "Explainer text at top of the quiet-hours editor sheet"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(String(localized: "profile.quietHours.enable", defaultValue: "Quiet hours", comment: "Toggle label enabling/disabling quiet hours"), isOn: Binding(
                get: { store.quietHoursEnabled },
                set: { store.quietHoursEnabled = $0; store.applyQuietHours() }
            ))
            if store.quietHoursEnabled {
                DatePicker(
                    String(localized: "profile.quietHours.start", defaultValue: "Starts", comment: "Quiet hours start time picker label"),
                    selection: Binding(
                        get: { store.quietHoursStart },
                        set: { store.quietHoursStart = $0; store.applyQuietHours() }
                    ),
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    String(localized: "profile.quietHours.end", defaultValue: "Ends", comment: "Quiet hours end time picker label"),
                    selection: Binding(
                        get: { store.quietHoursEnd },
                        set: { store.quietHoursEnd = $0; store.applyQuietHours() }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }
        }
    }
}

/// Thin wrapper over `SomaChip` -- keeps this file's `String`-typed call
/// sites (editor tag lists) unchanged while picking up the shared glass
/// chip styling (gel fill selected, lens unselected) in one place.
private struct ChipToggle: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        SomaChip(title: LocalizedStringKey(title), isSelected: isSelected, action: action)
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppState())
}
