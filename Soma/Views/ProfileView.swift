import PhotosUI
import SwiftUI

/// Editable profile: contact email (display-only, never a login credential
/// -- the app still signs in only via Sign in with Apple), training goals,
/// available equipment/access, and injuries. Feeds into workout-suggestion
/// filtering (RecommendationDetailView) and the injury-based intensity cap
/// (generate-recommendation Edge Function).
struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    @State private var showPaywall = false

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
    @State private var contactEmailText = ""
    @State private var otherGoalText = ""
    @State private var otherEquipmentText = ""
    @State private var injuryNotesText = ""
    @State private var experienceLevel: ExperienceLevel?
    @State private var pregnancy: Bool?

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
    @State private var showHealthDashboard = false

    // Body photos -- gated by Config.enableBodyPhotoUpload, see the
    // "Goal & Current Photos" card below.
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Profile")
                        .font(Theme.display)
                    Text("Soma uses this to tailor which workouts it suggests, and to keep intensity safer if you have an active injury.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Connect more devices")
                        .font(.body.bold())
                        .padding(.horizontal, 4)
                    ForEach(Provider.allCases) { provider in
                        ProviderCardView(
                            provider: provider,
                            isConnected: appState.connectedProviders.contains(provider),
                            isConnecting: connecting.contains(provider),
                            action: { connectDevice(provider) }
                        )
                    }
                    if let deviceErrorMessage {
                        Text(deviceErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 4)
                    }
                }

                CardView {
                    Text("Contact email")
                        .font(.body.bold())
                    TextField("you@example.com", text: $contactEmailText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                }

                CardView {
                    Text("Training experience")
                        .font(.body.bold())
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

                CardView {
                    Text("Goals")
                        .font(.body.bold())
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
                            .padding(.top, 4)
                    }
                }

                CardView {
                    Text("Equipment & access")
                        .font(.body.bold())
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
                            .padding(.top, 4)
                    }
                }

                CardView {
                    Text("Injuries")
                        .font(.body.bold())
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
                    // One severity picker per selected tag -- defaults to
                    // .moderate the moment a tag is toggled on, above.
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
                        }
                        .padding(.top, 4)
                    }
                    TextField("Notes (optional)", text: $injuryNotesText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                }

                CardView {
                    Text("Pregnancy")
                        .font(.body.bold())
                    // States the actual consequence rather than a vague
                    // "keeps things safe" -- this setting does not soften
                    // the generated workout, it withholds it entirely, and
                    // a user who discovers that only after setting it will
                    // reasonably feel misled.
                    Text("Optional, and never assumed -- only set if you tell us. While this is on, Soma won't auto-generate workouts for you and will point you to a qualified professional instead. Your daily recommendation keeps working as normal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FlowLayout {
                        ChipToggle(title: "I'm currently pregnant", isSelected: pregnancy == true) {
                            pregnancy = (pregnancy == true) ? nil : true
                        }
                    }
                }

                if Config.enableBodyPhotoUpload {
                    CardView {
                        Text("Goal & Current Photos")
                            .font(.body.bold())
                        Text("Optional -- helps personalize your plan toward your goal.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                        if !goalPhotoHistory.isEmpty || !currentPhotoHistory.isEmpty {
                            Text("\(goalPhotoHistory.count) goal photo(s), \(currentPhotoHistory.count) current photo(s) saved")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let goalBodyPhotoImage, let currentBodyPhotoImage {
                            Button {
                                showingPhotoComparison = true
                            } label: {
                                Label("Compare Goal vs. Current", systemImage: "arrow.left.and.right.square")
                                    .font(.caption.bold())
                            }
                            .padding(.top, 4)
                            .sheet(isPresented: $showingPhotoComparison) {
                                BodyPhotoComparisonView(goalImage: goalBodyPhotoImage, currentImage: currentBodyPhotoImage)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if savedConfirmation {
                    Text("Saved.")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                PillButton(title: "Save Profile", isEnabled: !isSaving, action: save)

                CardView {
                    Text("Insights")
                        .font(.body.bold())
                    PillButton(title: "Training History") {
                        showTrainingHistory = true
                    }
                    PillButton(title: "Health Dashboard") {
                        showHealthDashboard = true
                    }
                }

                // The only place to subscribe on purpose. Both other
                // paywall presentations are gates that dismiss themselves
                // while a referral bonus is active, so without this a user
                // on a 14-day bonus who wants to pay early simply cannot.
                CardView {
                    Text("Subscription")
                        .font(.body.bold())
                    Text(subscriptionStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !subscriptionManager.isSubscribed {
                        PillButton(title: "View Soma Premium") {
                            showPaywall = true
                        }
                    }
                }

                // Discoverable twin of the shake gesture -- shake works
                // everywhere, but nothing advertises it; this card does.
                CardView {
                    Text("Feedback")
                        .font(.body.bold())
                    Text("Spotted a bug or have an idea? You can also shake your phone anywhere in the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PillButton(title: "Send Feedback") {
                        // Same presenter as the shake path -- one route,
                        // and it dedupes against an already-open sheet.
                        FeedbackPresenter.present()
                    }
                }

                CardView {
                    Text("Account")
                        .font(.body.bold())
                    PillButton(title: "Log Out") {
                        showSignOutConfirmation = true
                    }
                }
            }
            .padding(20)
            .dismissKeyboardOnTap()
        }
        .scrollDismissesKeyboard(.interactively)
        .somaBackground()
        .sheet(isPresented: $showPaywall) {
            // autoDismissIfBonusActive: false -- opened deliberately, so it
            // must not close itself just because a bonus is running.
            PaywallView(autoDismissIfBonusActive: false)
        }
        .sheet(isPresented: $showTrainingHistory) {
            TrainingHistoryView()
        }
        .sheet(isPresented: $showHealthDashboard) {
            HealthDashboardView()
        }
        .task {
            await load()
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
            return "Free access until \(formatter.string(from: bonusUntil)). You can subscribe now if you'd rather not wait for it to end."
        }
        return "You're on the free plan -- today's category and message only."
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
        injuryNotesText = profile.injuryNotes ?? ""
        experienceLevel = profile.experienceLevel
        pregnancy = profile.pregnancy

        goalBodyPhotoPath = profile.goalBodyPhotoPath
        currentBodyPhotoPath = profile.currentBodyPhotoPath
        if Config.enableBodyPhotoUpload {
            if let path = profile.goalBodyPhotoPath {
                goalBodyPhotoImage = await loadBodyPhoto(path: path)
            }
            if let path = profile.currentBodyPhotoPath {
                currentBodyPhotoImage = await loadBodyPhoto(path: path)
            }
            goalPhotoHistory = (try? await SupabaseClient.shared.fetchBodyPhotos(kind: .goal)) ?? []
            currentPhotoHistory = (try? await SupabaseClient.shared.fetchBodyPhotos(kind: .current)) ?? []
        }
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
        guard let path else { return }
        do {
            try await SupabaseClient.shared.deleteBodyPhoto(kind: kind, path: path)
            if kind == .goal {
                goalBodyPhotoImage = nil
                goalBodyPhotoPath = nil
                goalPhotoHistory = (try? await SupabaseClient.shared.fetchBodyPhotos(kind: .goal)) ?? []
            } else {
                currentBodyPhotoImage = nil
                currentBodyPhotoPath = nil
                currentPhotoHistory = (try? await SupabaseClient.shared.fetchBodyPhotos(kind: .current)) ?? []
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
            pregnancy: pregnancy
        )

        let currentInjuryTags = Array(injuryTags)
        let currentInjurySeverity = injurySeverity

        Task {
            defer { isSaving = false }
            do {
                try await SupabaseClient.shared.updateProfile(id: userId, profile: profile)
                try await SupabaseClient.shared.reportInjury(tags: currentInjuryTags, severity: currentInjurySeverity)
                savedConfirmation = true
            } catch {
                errorMessage = "Couldn't save profile. Try again."
            }
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
                .background(Capsule().fill(isSelected ? Theme.pillFill : Color(.systemGray6)))
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppState())
}
