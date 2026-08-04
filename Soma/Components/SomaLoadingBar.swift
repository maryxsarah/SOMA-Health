import SwiftUI

/// Shared "still working, and it feels good" indicator -- an animated
/// indeterminate progress bar (neither use site has a real percentage to
/// report) with optional rotating supportive text underneath. Same visual
/// language wherever the app has to make someone wait: GoalBodyProgressView's
/// initial load and ExerciseDetailView's media area, so loading reads as
/// one system rather than two different spinners.
struct SomaLoadingBar: View {
    var messages: [String] = []
    /// Caller-controlled width for the bar itself (the text wraps to fit
    /// whatever container it's placed in) -- ExerciseDetailView wants a
    /// narrow bar inside a small media placeholder, GoalBodyProgressView
    /// wants one closer to full-width.
    var barWidth: CGFloat = 160

    @State private var barProgress: CGFloat = 0.12
    @State private var messageIndex = 0

    var body: some View {
        VStack(spacing: 12) {
            bar
            if !messages.isEmpty {
                Text(messages[messageIndex])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260)
                    .id(messageIndex)
                    .transition(.opacity)
            }
        }
        .onAppear {
            // Eases up toward "almost done," never claims to actually
            // finish -- an indeterminate wait dressed as a real one would
            // be worse than a plain spinner the moment it's noticeably
            // wrong. repeatForever ties the animation to this view's own
            // lifetime, so it stops cleanly when the view disappears.
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                barProgress = 0.92
            }
        }
        .task {
            guard messages.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    messageIndex = (messageIndex + 1) % messages.count
                }
            }
        }
    }

    private var bar: some View {
        Capsule()
            .fill(SomaTokens.surface3)
            .frame(width: barWidth, height: 6)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [SomaTokens.accent, SomaTokens.accentDeep],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: barWidth * barProgress, height: 6)
            }
    }
}

extension SomaLoadingBar {
    /// Rotates while GoalBodyProgressView loads -- affirming and forward-
    /// looking, matching that screen's "SOMA is how you get there" framing
    /// rather than generic "please wait" copy.
    static let goalProgressMessages = [
        "You're on track to reach your goal.",
        "Every day you commit is a day you win.",
        "Consistency beats perfection.",
        "Small steps, real progress.",
        "Showing up today is what changes tomorrow.",
        "Your future self is already proud of you.",
    ]
}

#Preview {
    VStack(spacing: 40) {
        SomaLoadingBar(messages: SomaLoadingBar.goalProgressMessages, barWidth: 240)
        SomaLoadingBar(barWidth: 120)
    }
    .padding()
}
