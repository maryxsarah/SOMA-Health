import SwiftUI

/// Editable profile: contact email (display-only, never a login credential
/// -- the app still signs in only via Sign in with Apple), training goals,
/// available equipment/access, and injuries. Feeds into workout-suggestion
/// filtering (RecommendationDetailView) and the injury-based intensity cap
/// (generate-recommendation Edge Function).
struct ProfileView: View {
    @EnvironmentObject private var appState: AppState

    // Plain @State strings bound directly via `$` (not a computed
    // Binding(get:set:) built inline in the view body) -- the latter
    // recreates a new closure identity on every keystroke-driven body
    // re-evaluation, which is what was causing the keyboard to dismiss
    // after each character typed. These get folded into `profile` only
    // when loading/saving.
    @State private var goals: Set<GoalTag> = []
    @State private var equipment: Set<EquipmentTag> = []
    @State private var injuryTags: Set<InjuryTag> = []
    @State private var contactEmailText = ""
    @State private var otherGoalText = ""
    @State private var otherEquipmentText = ""
    @State private var injuryNotesText = ""
    @State private var experienceLevel: ExperienceLevel?

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
                            }
                        }
                    }
                    TextField("Notes (optional)", text: $injuryNotesText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
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
        injuryNotesText = profile.injuryNotes ?? ""
        experienceLevel = profile.experienceLevel
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
            experienceLevel: experienceLevel
        )

        Task {
            defer { isSaving = false }
            do {
                try await SupabaseClient.shared.updateProfile(id: userId, profile: profile)
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
