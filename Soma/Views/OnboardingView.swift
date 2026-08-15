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
                        .tracking(0.7)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    Text("Find your next best day")
                        .font(Theme.display)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Soma reads your wearable — Apple Health, Whoop, or Oura — and sends one clear notification each morning telling you exactly how hard to train. No guesswork, no chat, just a plan for today.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.top, 16)

                WelcomeOrbView()
                    .frame(height: 110)
                    .allowsHitTesting(false)

                featureTilesRow

                VStack(spacing: 6) {
                    Text("Consistency compounds")
                        .font(.subheadline.bold())
                    UpwardTrendChartView(xAxisLabels: ["Month 1", "Month 3", "Month 6"], chartHeight: 64, showsBadge: false)
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

                PillButton(title: "Continue with Apple", icon: Image(systemName: "apple.logo"), isEnabled: !sessionManager.isSigningIn) {
                    Task {
                        // Branch on the returned value, never on
                        // `errorMessage == nil` -- cancelling is a silent
                        // non-error, so absence of a message no longer
                        // means a session exists.
                        if await sessionManager.signInWithApple() {
                            await appState.markSignedIn()
                        }
                    }
                }

                glassAuthButton("Continue with Google", icon: Image("soma.auth.google")) {
                    Task {
                        if await sessionManager.signInWithGoogle() {
                            await appState.markSignedIn()
                        }
                    }
                }

                glassAuthButton("Continue with Email") {
                    showingEmailAuth = true
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

    /// Secondary auth CTA -- glass lens pill matching Apple's pill family,
    /// but never spinning: only one animated CTA (`PillButton`/Apple) per
    /// screen, per the glass system's CTA rule.
    private func glassAuthButton(_ title: LocalizedStringKey, icon: Image? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon?.resizable().aspectRatio(contentMode: .fit).frame(width: 17, height: 17)
                Text(title)
                    .font(.body.bold())
            }
            .foregroundStyle(SomaTokens.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassLens()
        }
        .buttonStyle(.plain)
        .disabled(sessionManager.isSigningIn)
        .opacity(sessionManager.isSigningIn ? 0.45 : 1)
    }

    /// Three feature tiles -- what Soma actually does, one clause each.
    private var featureTilesRow: some View {
        HStack(spacing: 10) {
            featureTile("waveform.path.ecg", "Reads your data")
            featureTile("bandage", "One plan, daily")
            featureTile("chart.line.uptrend.xyaxis", "No guesswork")
        }
        .padding(.horizontal, 20)
    }

    private func featureTile(_ systemName: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(
                        RadialGradient(
                            colors: [
                                Color(red: 143 / 255, green: 174 / 255, blue: 248 / 255),
                                Color(red: 61 / 255, green: 102 / 255, blue: 238 / 255),
                                Color(red: 27 / 255, green: 63 / 255, blue: 201 / 255)
                            ],
                            center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: 22)
                    )
                )
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SomaTokens.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassLens(cornerRadius: 20)
    }
}

/// The welcome screen's hero orb -- a glossy breathing sphere with a
/// slow-spinning highlight ring and soft outer halo. A one-off matching
/// the "8a" welcome-screen mockup exactly, distinct from the shared
/// `OrbView` (used for the assistant/chat presence elsewhere), which this
/// screen was overflowing out of (`OrbView`'s own internal frame renders
/// at a fixed 352x352 regardless of an outer `.frame(height:)` cap).
private struct WelcomeOrbView: View {
    @State private var breathing = false
    @State private var haloPulsing = false
    @State private var spinAngle: Angle = .zero

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 122 / 255, green: 162 / 255, blue: 255 / 255).opacity(0.5),
                            Color(red: 186 / 255, green: 156 / 255, blue: 255 / 255).opacity(0.28),
                            Color(red: 186 / 255, green: 156 / 255, blue: 255 / 255).opacity(0)
                        ],
                        center: .center, startRadius: 0, endRadius: 75)
                )
                .frame(width: 150, height: 150)
                .blur(radius: 2)
                .opacity(haloPulsing ? 0.9 : 0.55)
                .scaleEffect(haloPulsing ? 1.12 : 1)

            Circle()
                .fill(
                    AngularGradient(
                        stops: [
                            .init(color: .white.opacity(0), location: 0),
                            .init(color: .white.opacity(0.8), location: 0.069),
                            .init(color: .white.opacity(0), location: 0.153),
                            .init(color: .white.opacity(0), location: 1)
                        ],
                        center: .center)
                )
                .frame(width: 104, height: 104)
                .opacity(0.7)
                .rotationEffect(spinAngle)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 214 / 255, green: 228 / 255, blue: 255 / 255),
                            Color(red: 125 / 255, green: 162 / 255, blue: 245 / 255),
                            Color(red: 58 / 255, green: 99 / 255, blue: 232 / 255),
                            Color(red: 22 / 255, green: 41 / 255, blue: 126 / 255)
                        ],
                        center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: 60)
                )
                .frame(width: 86, height: 86)
                .overlay(
                    Ellipse()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: 26, height: 16)
                        .blur(radius: 3)
                        .rotationEffect(.degrees(-25))
                        .offset(x: -18, y: -28)
                )
                .shadow(color: SomaTokens.accent.opacity(0.38), radius: 15, x: 0, y: 14)
                .shadow(color: SomaTokens.accent.opacity(0.25), radius: 4, x: 0, y: 2)
                .scaleEffect(breathing ? 1.12 : 1)
                .opacity(breathing ? 1 : 0.9)
        }
        .onAppear {
            // Skipped under XCTest, matching CTAPillButton's own spin --
            // continuous animation makes snapshot captures nondeterministic.
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
            withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) { breathing = true }
            withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) { haloPulsing = true }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { spinAngle = .degrees(360) }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
        .environmentObject(SessionManager())
}
