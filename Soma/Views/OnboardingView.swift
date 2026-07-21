import SwiftUI

/// Screen 1 -- Onboarding / Welcome.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfService = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Text("Your health journey starts now")
                    .font(Theme.eyebrow)
                    .foregroundStyle(.secondary)

                Text("Find your next best day")
                    .font(Theme.display)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Know exactly what to do today. Soma reads your wearable data — Apple Health, Whoop, or Oura — and sends one clear notification each morning telling you exactly how hard to train. No guesswork, no chat, just a plan for today.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            OrbView(state: .idle)
                .padding(.vertical, 16)
                .allowsHitTesting(false)

            Spacer()

            VStack(spacing: 12) {
                if let error = sessionManager.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                PillButton(title: "Get Started", isEnabled: !sessionManager.isSigningIn) {
                    Task {
                        await sessionManager.signInWithApple()
                        if sessionManager.errorMessage == nil {
                            appState.markSignedIn()
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button("Privacy Policy") { showingPrivacyPolicy = true }
                    Text("·")
                    Button("Terms of Service") { showingTermsOfService = true }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .somaBackground()
        .sheet(isPresented: $showingPrivacyPolicy) {
            LegalDocumentView(title: LegalContent.privacyPolicyTitle, text: LegalContent.privacyPolicyBody)
        }
        .sheet(isPresented: $showingTermsOfService) {
            LegalDocumentView(title: LegalContent.termsOfServiceTitle, text: LegalContent.termsOfServiceBody)
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
        .environmentObject(SessionManager())
}
