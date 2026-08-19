import SwiftUI

/// "Forgot password?" sheet, presented from EmailAuthView's Log In mode.
/// Same shape as EmailAuthView's own email field + "check your email"
/// confirmation block -- this is deliberately a thin, single-purpose
/// screen rather than folded into EmailAuthView itself, since it has its
/// own terminal "check your email" state that shouldn't be tangled up
/// with the Log In / Sign Up toggle.
struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss

    @State var email: String
    @State private var isSending = false
    @State private var checkYourEmailMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(String(localized: "forgotPassword.title", defaultValue: "Reset your password", comment: "Headline on the forgot-password sheet"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(SomaTokens.ink)
                    Text(String(localized: "forgotPassword.subtitle", defaultValue: "Enter the email on your account and we'll send you a link to set a new password.", comment: "Subtitle on the forgot-password sheet"))
                        .font(.system(size: 13.5))
                        .foregroundStyle(SomaTokens.ink3)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassCardFlat(cornerRadius: SomaTokens.rRow)
                    .overlay(
                        RoundedRectangle(cornerRadius: SomaTokens.rRow, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                            .allowsHitTesting(false)
                    )
                    .padding(.horizontal, 24)

                if let checkYourEmailMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "envelope.badge.fill")
                            .foregroundStyle(SomaTokens.success)
                        Text(checkYourEmailMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(SomaTokens.ink2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.successSoft))
                    .padding(.horizontal, 24)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(SomaTokens.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                PillButton(
                    title: LocalizedStringKey(String(localized: "forgotPassword.send", defaultValue: "Send reset link", comment: "Button that sends the password-reset email")),
                    isEnabled: !isSending && !email.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    Task { await send() }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 8)
            .somaSheetBackground()
            .navigationTitle(String(localized: "forgotPassword.navTitle", defaultValue: "Forgot Password", comment: "Navigation title of the forgot-password sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .dismissKeyboardOnTap()
        }
    }

    private func send() async {
        errorMessage = nil
        checkYourEmailMessage = nil
        isSending = true
        defer { isSending = false }
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        do {
            try await SupabaseClient.shared.requestPasswordReset(email: trimmedEmail)
            checkYourEmailMessage = String(
                localized: "forgotPassword.checkYourEmail",
                defaultValue: "If an account exists for that email, a reset link is on its way.",
                comment: "Message shown after requesting a password reset, deliberately worded not to confirm whether the account exists"
            )
        } catch {
            errorMessage = String(localized: "signIn.generic.error.somethingWrong", defaultValue: "Something went wrong. Please try again.", comment: "Generic sign-in/sign-up error shown when the underlying error isn't a recognized Supabase request failure")
        }
    }
}

#Preview {
    ForgotPasswordView(email: "")
}
