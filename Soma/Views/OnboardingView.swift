import SwiftUI

/// Screen 1 -- Onboarding / Welcome.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfService = false
    @State private var showingEmailAuth = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 10) {
                    Text("Your health journey starts now")
                        .font(Theme.eyebrow)
                        .foregroundStyle(.secondary)

                    Text("Find your next best day")
                        .font(Theme.display)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Know exactly what to do today. Soma reads your wearable data — Apple Health, Whoop, or Oura — and sends one clear notification each morning telling you exactly how hard to train. No guesswork, no chat, just a plan for today.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.top, 16)

                OrbView(state: .idle)
                    .frame(height: 90)
                    .allowsHitTesting(false)

                howItWorksRow

                VStack(spacing: 6) {
                    Text("Consistency compounds")
                        .font(.subheadline.bold())
                    UpwardTrendChartView(xAxisLabels: ["Month 1", "Month 3", "Month 6"], chartHeight: 90)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 12)
        }
        .somaBackground()
        .onAppear {
            AnalyticsManager.shared.onboardingStarted()
        }
        // Pinned below the scroll area -- the sign-up CTA must always be
        // reachable without scrolling, even on a compact device where the
        // content above ends up scrollable (guide feedback: "this should
        // be in one screen").
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if let error = sessionManager.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)

                    if sessionManager.needsAppleIDSetup {
                        Button("Open Settings") {
                            SystemSettings.open()
                        }
                        .font(.caption.bold())
                    }
                }

                PillButton(title: "Continue with Apple", isEnabled: !sessionManager.isSigningIn) {
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

                Button {
                    Task {
                        if await sessionManager.signInWithGoogle() {
                            appState.markSignedIn()
                        }
                    }
                } label: {
                    Text("Continue with Google")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(sessionManager.isSigningIn)

                Button {
                    showingEmailAuth = true
                } label: {
                    Text("Continue with Email")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(sessionManager.isSigningIn)

                HStack(spacing: 8) {
                    Button("Privacy Policy") { showingPrivacyPolicy = true }
                    Text("·")
                    Button("Terms of Service") { showingTermsOfService = true }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 20)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            LegalDocumentView(title: LegalContent.privacyPolicyTitle, text: LegalContent.privacyPolicyBody)
        }
        .sheet(isPresented: $showingTermsOfService) {
            LegalDocumentView(title: LegalContent.termsOfServiceTitle, text: LegalContent.termsOfServiceBody)
        }
        .sheet(isPresented: $showingEmailAuth) {
            EmailAuthView()
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

    private func stepIcon(_ systemName: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.subheadline)
                .foregroundStyle(Theme.pillFill)
                .frame(width: 36, height: 36)
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
