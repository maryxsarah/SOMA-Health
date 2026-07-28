import SwiftUI

/// Screen 1 -- Onboarding / Welcome.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfService = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
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
                .padding(.top, 32)

                OrbView(state: .idle)
                    .frame(height: 150)
                    .allowsHitTesting(false)

                howItWorksRow

                VStack(spacing: 10) {
                    Text("Consistency compounds")
                        .font(.body.bold())
                    UpwardTrendChartView(xAxisLabels: ["Month 1", "Month 3", "Month 6"])
                }
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    if let error = sessionManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)

                        if sessionManager.needsAppleIDSetup,
                           let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            Button("Open Settings") {
                                UIApplication.shared.open(settingsURL)
                            }
                            .font(.caption.bold())
                        }
                    }

                    PillButton(title: "Get Started", isEnabled: !sessionManager.isSigningIn) {
                        Task {
                            // Branch on the returned value, never on
                            // `errorMessage == nil` -- cancelling is a silent
                            // non-error, so absence of a message no longer
                            // means a session exists.
                            if await sessionManager.signInWithApple() {
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
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .somaBackground()
        .sheet(isPresented: $showingPrivacyPolicy) {
            LegalDocumentView(title: LegalContent.privacyPolicyTitle, text: LegalContent.privacyPolicyBody)
        }
        .sheet(isPresented: $showingTermsOfService) {
            LegalDocumentView(title: LegalContent.termsOfServiceTitle, text: LegalContent.termsOfServiceBody)
        }
    }

    /// "How it actually works" -- devices in, Soma reads it, clear plan
    /// out. Plain and literal on purpose, matching the "as simple as
    /// possible" brief.
    private var howItWorksRow: some View {
        HStack(spacing: 8) {
            stepIcon("applewatch", "Your devices")
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            stepIcon("waveform.path.ecg", "Soma reads it")
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            stepIcon("checkmark.circle.fill", "Clear daily plan")
        }
        .padding(.horizontal, 12)
    }

    private func stepIcon(_ systemName: String, _ label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.title3)
                .foregroundStyle(Theme.pillFill)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color(.systemGray6)))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 74)
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
        .environmentObject(SessionManager())
}
