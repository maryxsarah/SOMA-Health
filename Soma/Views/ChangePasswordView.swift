import SwiftUI

/// Pushed from Profile -> Account's "Change password" row (email/password
/// accounts only -- see AccountSettingsView's authProviders gate).
/// Re-authenticates with the current password before applying the new
/// one -- same "confirm you are who you say you are before a sensitive
/// change" shape DeleteAccountView already uses for its SIWA re-auth step,
/// just via signInWithEmail instead of Sign in with Apple.
struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isCurrentPasswordVisible = false
    @State private var isNewPasswordVisible = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSavedConfirmation = false

    private var canSubmit: Bool {
        !isSaving && !currentPassword.isEmpty && !newPassword.isEmpty && newPassword == confirmPassword
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    passwordField(String(localized: "changePassword.currentField", defaultValue: "Current password", comment: "Placeholder for the current-password field"), text: $currentPassword, isVisible: $isCurrentPasswordVisible)
                    Rectangle().fill(SomaTokens.ink.opacity(0.07)).frame(height: 1)
                    passwordField(String(localized: "changePassword.newField", defaultValue: "New password", comment: "Placeholder for the new-password field"), text: $newPassword, isVisible: $isNewPasswordVisible)
                    Rectangle().fill(SomaTokens.ink.opacity(0.07)).frame(height: 1)
                    passwordField(String(localized: "changePassword.confirmField", defaultValue: "Confirm new password", comment: "Placeholder for the confirm-new-password field"), text: $confirmPassword, isVisible: $isNewPasswordVisible)
                }
                .padding(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                .glassCardFlat(cornerRadius: SomaTokens.rRow)

                if !confirmPassword.isEmpty && newPassword != confirmPassword {
                    Text(String(localized: "setNewPassword.mismatch", defaultValue: "Passwords don't match.", comment: "Inline error shown when the new-password fields don't match"))
                        .font(.system(size: 12))
                        .foregroundStyle(SomaTokens.danger)
                        .padding(.horizontal, 4)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(SomaTokens.danger)
                        .padding(.horizontal, 4)
                }

                SomaButton(
                    title: LocalizedStringKey(String(localized: "changePassword.save", defaultValue: "Save new password", comment: "Button that saves the new password")),
                    size: .lg,
                    isEnabled: canSubmit
                ) {
                    Task { await save() }
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .somaBackground()
        .navigationTitle(String(localized: "changePassword.title", defaultValue: "Change password", comment: "Navigation title of the change-password page"))
        .navigationBarTitleDisplayMode(.inline)
        .dismissKeyboardOnTap()
        .alert(
            String(localized: "changePassword.done.title", defaultValue: "Password updated", comment: "Title of the alert confirming the password was changed"),
            isPresented: $showSavedConfirmation
        ) {
            Button(String(localized: "deleteAccount.done.ok", defaultValue: "OK", comment: "OK button on the deletion-complete alert")) {
                dismiss()
            }
        }
    }

    private func passwordField(_ placeholder: String, text: Binding<String>, isVisible: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Group {
                if isVisible.wrappedValue {
                    TextField(placeholder, text: text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField(placeholder, text: text)
                }
            }
            .font(.system(size: 14))
            Button {
                isVisible.wrappedValue.toggle()
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                    .foregroundStyle(SomaTokens.ink5)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            guard let email = try await SupabaseClient.shared.fetchCurrentAuthEmail() else {
                errorMessage = String(localized: "signIn.generic.error.somethingWrong", defaultValue: "Something went wrong. Please try again.", comment: "Generic sign-in/sign-up error shown when the underlying error isn't a recognized Supabase request failure")
                return
            }
            // Re-authenticating rotates the stored session's tokens to a
            // fresh pair for `email`/`currentPassword` -- exactly the
            // check we want (wrong current password fails right here,
            // before any change is applied) and it doubles as the valid
            // access token updatePassword needs next.
            try await SupabaseClient.shared.signInWithEmail(email: email, password: currentPassword)
        } catch {
            errorMessage = String(localized: "changePassword.wrongCurrent", defaultValue: "Your current password isn't right. Try again.", comment: "Error shown when re-authentication with the current password fails")
            return
        }
        do {
            try await SupabaseClient.shared.updatePassword(newPassword: newPassword)
            showSavedConfirmation = true
        } catch {
            errorMessage = String(localized: "signIn.generic.error.passwordRequirements", defaultValue: "That password doesn't meet the requirements -- try a longer one.", comment: "Sign-up error shown when the password fails Supabase's own validation")
        }
    }
}

#Preview {
    NavigationStack {
        ChangePasswordView()
    }
}
