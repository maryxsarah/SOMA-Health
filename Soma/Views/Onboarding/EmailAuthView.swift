import SwiftUI

/// Email/password sign-in and sign-up, reached via "Continue with Email"
/// on the Onboarding welcome screen. A toggle between the two modes
/// rather than two separate screens, since the fields are identical.
struct EmailAuthView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    private enum Mode {
        case logIn, signUp
    }

    @State private var mode: Mode = .logIn
    @State private var email = ""
    @State private var password = ""
    @State private var checkYourEmailMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Picker("Mode", selection: $mode) {
                    Text("Log In").tag(Mode.logIn)
                    Text("Sign Up").tag(Mode.signUp)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .padding(.top, 12)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 24)

                if let checkYourEmailMessage {
                    Text(checkYourEmailMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                if let error = sessionManager.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                PillButton(
                    title: mode == .logIn ? "Log In" : "Create Account",
                    isEnabled: !sessionManager.isSigningIn && !email.isEmpty && !password.isEmpty
                ) {
                    Task { await submit() }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.top, 8)
            .somaBackground()
            .navigationTitle("Continue with Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .dismissKeyboardOnTap()
        }
    }

    private func submit() async {
        checkYourEmailMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .logIn:
            if await sessionManager.signInWithEmail(email: trimmedEmail, password: password) {
                appState.markSignedIn()
            }
        case .signUp:
            switch await sessionManager.signUpWithEmail(email: trimmedEmail, password: password) {
            case true:
                appState.markSignedIn()
            case false:
                checkYourEmailMessage = String(
                    localized: "email_auth.check_your_email",
                    defaultValue: "Check your email to confirm your account, then log in.",
                    comment: "Message shown after sign-up prompting the user to check their email inbox and then log in"
                )
                mode = .logIn
            case nil:
                break // errorMessage already set by signUpWithEmail
            }
        }
    }
}

#Preview {
    EmailAuthView()
        .environmentObject(AppState())
        .environmentObject(SessionManager())
}
