import SwiftUI

/// Soft white-to-pale-blue vertical gradient used behind all 4 screens.
struct BackgroundGradientView: View {
    var body: some View {
        LinearGradient(
            colors: [Theme.backgroundTop, Theme.backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
