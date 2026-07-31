import SwiftUI

/// Loading indicator for AI generation (gym-photo analysis/workout build,
/// AI workout plan). No server-side progress signal exists for any of
/// these single-request/response calls, so this is a smoothed, simulated
/// ramp -- not a literal completion percentage -- same honest-estimate
/// pattern most apps use for LLM-backed generation. Ramps toward 90% over
/// a plausible duration and holds there (never claims 100% on its own);
/// the caller just removes this view once the real response arrives.
struct GenerationProgressView: View {
    let message: String
    /// How long the ramp to 90% takes -- tune per call site to roughly
    /// match that flow's typical latency (gym-photo's two-model vision
    /// pass runs longer than a simple text generation).
    var estimatedSeconds: Double = 6

    @State private var progress: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: progress, total: 1.0)
                .tint(Theme.pillFill)
            HStack {
                Text(message)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear {
            withAnimation(.easeOut(duration: estimatedSeconds)) {
                progress = 0.9
            }
        }
    }
}

#Preview {
    GenerationProgressView(message: "Building your plan…")
        .padding()
        .somaBackground()
}
