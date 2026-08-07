import SwiftUI

/// Back button + thin fill-progress bar shown atop every onboarding survey
/// screen, matching the funnel-style pattern of a linear multi-step flow.
struct OnboardingTopBar: View {
    /// 0...1
    let progress: Double
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.bold())
                        .foregroundStyle(Theme.pillFill)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white))
                        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                }
                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    // A real fraction (e.g. ~0.29 on an early step) reads
                    // as "basically empty" at this bar's 6pt height/thin
                    // Capsule shape -- clamp to a visible minimum so the
                    // very first steps still show a legible sliver of
                    // progress, never a bar that looks broken/reset.
                    Capsule()
                        .fill(Theme.pillFill)
                        .frame(width: max(geo.size.width * 0.06, geo.size.width * max(0, min(1, progress))))
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}
