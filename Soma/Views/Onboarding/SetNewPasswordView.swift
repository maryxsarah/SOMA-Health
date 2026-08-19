import SwiftUI

/// Lands as a full-screen cover after the password-reset email's universal
/// link opens the app (see SomaApp.handlePasswordRecovery) -- presented
/// over whatever screen the user happens to be on, since unlike the
/// signup-confirmation link this one can be tapped by an already-signed-in
/// user (a returning user resetting a forgotten password from a second
/// device, for instance) as easily as a signed-out one.
struct SetNewPasswordView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isPasswordVisible = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !isSaving && !newPassword.isEmpty && newPassword == confirmPassword
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(String(localized: "setNewPassword.title", defaultValue: "Set a new password", comment: "Headline on the set-new-password screen reached from the reset email"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(SomaTokens.ink)
                    Text(String(localized: "setNewPassword.subtitle", defaultValue: "Choose a new password for your Soma account.", comment: "Subtitle on the set-new-password screen"))
                        .font(.system(size: 13.5))
                        .foregroundStyle(SomaTokens.ink3)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                VStack(spacing: 12) {
                    passwordField(placeholder: String(localized: "setNewPassword.newField", defaultValue: "New password", comment: "Placeholder for the new-password field"), text: $newPassword, showToggle: true)
                    passwordField(placeholder: String(localized: "setNewPassword.confirmField", defaultValue: "Confirm new password", comment: "Placeholder for the confirm-new-password field"), text: $confirmPassword, showToggle: false)

                    if !confirmPassword.isEmpty && newPassword != confirmPassword {
                        Text(String(localized: "setNewPassword.mismatch", defaultValue: "Passwords don't match.", comment: "Inline error shown when the new-password fields don't match"))
                            .font(.caption)
                            .foregroundStyle(SomaTokens.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 24)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(SomaTokens.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                PillButton(
                    title: LocalizedStringKey(String(localized: "setNewPassword.save", defaultValue: "Save new password", comment: "Button that saves the new password")),
                    isEnabled: canSubmit
                ) {
                    Task { await save() }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 8)
            .somaSheetBackground()
            .navigationTitle(String(localized: "setNewPassword.navTitle", defaultValue: "New Password", comment: "Navigation title of the set-new-password screen"))
            .navigationBarTitleDisplayMode(.inline)
            .dismissKeyboardOnTap()
            .interactiveDismissDisabled()
        }
    }

    private func passwordField(placeholder: String, text: Binding<String>, showToggle: Bool) -> some View {
        HStack(spacing: 8) {
            Group {
                if isPasswordVisible {
                    TextField(placeholder, text: text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField(placeholder, text: text)
                }
            }
            if showToggle {
                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .foregroundStyle(SomaTokens.ink5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCardFlat(cornerRadius: SomaTokens.rRow)
        .overlay(
            RoundedRectangle(cornerRadius: SomaTokens.rRow, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                .allowsHitTesting(false)
        )
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await SupabaseClient.shared.updatePassword(newPassword: newPassword)
            sessionManager.pendingPasswordRecovery = false
            // A recovery session is a real, signed-in session -- same next
            // step every other sign-in path takes.
            await appState.markSignedIn()
        } catch {
            errorMessage = String(localized: "signIn.generic.error.passwordRequirements", defaultValue: "That password doesn't meet the requirements -- try a longer one.", comment: "Sign-up error shown when the password fails Supabase's own validation")
        }
    }
}

#Preview {
    SetNewPasswordView()
        .environmentObject(AppState())
        .environmentObject(SessionManager())
}
