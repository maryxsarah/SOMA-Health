import SwiftUI

/// Generic static legal document viewer, used for both Privacy Policy and
/// Terms of Service. Fixed copy only -- no chat, no freeform generation.
struct LegalDocumentView: View {
    let title: String
    let text: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(Theme.display)
                Text(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .font(.body.bold())
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .somaBackground()
    }
}

#Preview {
    LegalDocumentView(title: LegalContent.privacyPolicyTitle, text: LegalContent.privacyPolicyBody)
}
