import SwiftUI

/// White rounded-rectangle card with soft shadow, per spec. Screen-specific
/// content (headline + subtext + button) is composed inside it.
struct CardView<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
