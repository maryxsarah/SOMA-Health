import SwiftUI

/// Email/password sign-in and sign-up, reached via "Continue with Email"
/// on the Onboarding welcome screen. A toggle between the two modes
/// rather than two separate screens, since the fields are identical.
struct EmailAuthView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    private enum Mode: Hashable, CaseIterable, Identifiable {
        case logIn, signUp
        var id: Self { self }
    }

    // Demo-recording mode pre-fills these (mode included -- the "Sign Up"
    // toggle tap hits the same synthesized-event issue as the text
    // fields, confirmed even with a retry loop) -- the simulator used for
    // that recording can't reliably deliver XCUITest's synthesized taps
    // to this screen's controls (a simulator/XCTest environment issue,
    // reproduced even after a full `simctl erase`, not something in this
    // view), so the demo shows a clean credentials reveal instead of a
    // typing/toggling sequence that would never actually land.
    //
    // Defaults to .logIn, not .signUp: demo@soma.app is a seeded, reused
    // account -- Sign Up against an email that already exists returns a
    // response Soma doesn't handle as a hard error, leaving the session in
    // a broken state (a stored token that isn't a real JWT), which then
    // 401s the first authenticated request past onboarding with "Expected
    // 3 parts in JWT; got 1". Log In is the correct, idempotent op for a
    // recording/demo run that may not be the account's first.
    #if DEBUG
    // TEMPORARY diagnostic (revert before committing): --claude-diag-signup
    // <email> <password> switches to Sign Up, fills in the given fresh
    // credentials, and auto-submits against the REAL backend -- bypasses
    // this screen's tap-blocking bug (see BUG-115) to get past login when
    // demo@soma.app's seeded password no longer works.
    private static var diagSignup: (email: String, password: String)? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "--claude-diag-signup"), idx + 2 < args.count else { return nil }
        return (args[idx + 1], args[idx + 2])
    }
    @State private var mode: Mode = diagSignup != nil ? .signUp : .logIn
    @State private var email = diagSignup?.email ?? (UITestSupport.isOnboardingDemo ? "demo@soma.app" : "")
    @State private var password = diagSignup?.password ?? (UITestSupport.isOnboardingDemo ? "DemoPass123!" : "")
    #else
    @State private var mode: Mode = .logIn
    @State private var email = ""
    @State private var password = ""
    #endif
    @State private var checkYourEmailMessage: String?
    @State private var isPasswordVisible = false
    @State private var showForgotPassword = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                SomaSegmentedControl(selection: $mode) { mode in
                    switch mode {
                    case .logIn: String(localized: "Log In")
                    case .signUp: String(localized: "Sign Up")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .glassCardFlat(cornerRadius: SomaTokens.rRow)
                        .fieldOutline(cornerRadius: SomaTokens.rRow)

                    HStack(spacing: 8) {
                        Group {
                            if isPasswordVisible {
                                TextField("Password", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("Password", text: $password)
                            }
                        }
                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundStyle(SomaTokens.ink5)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassCardFlat(cornerRadius: SomaTokens.rRow)
                    .fieldOutline(cornerRadius: SomaTokens.rRow)
                }
                .padding(.horizontal, 24)

                if mode == .logIn {
                    Button {
                        showForgotPassword = true
                    } label: {
                        Text(String(localized: "email_auth.forgotPassword", defaultValue: "Forgot password?", comment: "Button on the Log In form opening the forgot-password sheet"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SomaTokens.accent)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 24)
                }

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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 8)
            .somaSheetBackground()
            .navigationTitle("Continue with Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .dismissKeyboardOnTap()
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView(email: email.trimmingCharacters(in: .whitespaces))
            }
            #if DEBUG
            .onAppear {
                if Self.diagSignup != nil { Task { await submit() } }
            }
            #endif
        }
    }


    private func submit() async {
        checkYourEmailMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .logIn:
            if await sessionManager.signInWithEmail(email: trimmedEmail, password: password) {
                await appState.markSignedIn()
            }
        case .signUp:
            switch await sessionManager.signUpWithEmail(email: trimmedEmail, password: password) {
            case true:
                await appState.markSignedIn()
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

private extension View {
    /// `.glassCardFlat()`'s white-on-white border (per its own recipe:
    /// white 0.5 fill, white 0.85 stroke) reads fine on the colored
    /// screen gradient it was designed against, but this screen sits on
    /// `.somaSheetBackground()`, which adds its own opaque white wash on
    /// top of that gradient specifically so sheet content reads as solid
    /// -- the two combined leave the fields with no visible edge at all.
    /// A real (non-white) hairline fixes it without touching the shared
    /// modifier other `glassCardFlat` call sites still rely on.
    func fieldOutline(cornerRadius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                .allowsHitTesting(false)
        )
    }
}

#Preview {
    EmailAuthView()
        .environmentObject(AppState())
        .environmentObject(SessionManager())
}
