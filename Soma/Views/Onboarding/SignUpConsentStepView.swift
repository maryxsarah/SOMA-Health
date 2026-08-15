import SwiftUI

/// Terms/Privacy acceptance + marketing consent. Sign in with Apple
/// itself already happened at the very start of onboarding (screen 1) --
/// Soma's backend ties every table to auth.uid() via RLS, so
/// authenticating before Connect Device (rather than deferring it to the
/// end, as some competitor funnels do) is what lets device connections
/// and the survey answers actually save as the user goes. This screen is
/// the legal/consent checkpoint that stands in for a literal "sign up"
/// step.
struct SignUpConsentStepView: View {
    let onContinue: (Bool) -> Void

    @State private var acceptedTerms = false
    @State private var marketingOptIn = false
    @State private var showError = false
    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfService = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("Save your progress")
                    .font(Theme.display)
                Text("Just a couple of things before we continue.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 16) {
                consentRow(
                    isOn: $acceptedTerms,
                    text: "I agree to Soma's Terms of Service and Privacy Policy, and understand Soma's recommendations are not medical advice."
                )
                HStack(spacing: 16) {
                    Button("View Privacy Policy") { showingPrivacyPolicy = true }
                    Button("View Terms of Service") { showingTermsOfService = true }
                }
                .font(.caption)
                .foregroundStyle(Theme.pillFill)
                .padding(.leading, 34)

                consentRow(
                    isOn: $marketingOptIn,
                    text: "Send me tips, new features, and personalized offers from Soma Health."
                )

                if showError {
                    Text("You must accept the Terms of Service and Privacy Policy to continue.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(20)
            .glassCard(cornerRadius: 20)
            .padding(.horizontal, 24)

            Spacer()

            PillButton(title: "Continue") {
                if acceptedTerms {
                    onContinue(marketingOptIn)
                } else {
                    showError = true
                }
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

    private func consentRow(isOn: Binding<Bool>, text: LocalizedStringKey) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: SomaTokens.rCheck, style: .continuous)
                    .strokeBorder(isOn.wrappedValue ? SomaTokens.accent : Color(.systemGray4), lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: SomaTokens.rCheck, style: .continuous).fill(isOn.wrappedValue ? SomaTokens.accent : .clear))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .opacity(isOn.wrappedValue ? 1 : 0)
                    )
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
    }
}
