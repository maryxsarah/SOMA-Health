import SwiftUI

/// "Time to generate your first custom plan!" -- percentage counter +
/// progress bar + rotating status line + a checklist that fills in as
/// progress advances. This is a fixed-duration perceived-personalization
/// animation; the real generate-recommendation call happens once, in
/// parallel, via `onAppear`.
struct GeneratingPlanStepView: View {
    @EnvironmentObject private var appState: AppState
    let onFinished: () -> Void

    @State private var percent = 0
    @State private var checkedCount = 0
    @State private var statusIndex = 0
    @State private var didStartWork = false

    private let statusMessages = [
        "Customizing your health plan...",
        "Analyzing your recovery data...",
        "Tailoring today's workout...",
        "Finalizing your results...",
    ]
    private let checklist = ["Movement", "Health Score", "Workout", "Active Recovery"]

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 4) {
                Text("All done!")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Text("Time to generate your first custom plan!")
                    .font(Theme.display)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            Text("\(percent)%")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .contentTransition(.numericText())

            Text("We're setting everything up for you")
                .font(.body)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule()
                        .fill(
                            LinearGradient(colors: [.orange, Theme.pillFill], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geo.size.width * CGFloat(percent) / 100)
                }
            }
            .frame(height: 8)
            .padding(.horizontal, 40)

            Text(statusMessages[min(statusIndex, statusMessages.count - 1)])
                .font(.caption)
                .foregroundStyle(.secondary)
                .animation(.easeInOut, value: statusIndex)

            CardView {
                Text("Daily recommendation for")
                    .font(.body.bold())
                ForEach(Array(checklist.enumerated()), id: \.offset) { index, item in
                    HStack {
                        Text(item)
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: index < checkedCount ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(index < checkedCount ? Theme.pillFill : Color(.systemGray4))
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .somaBackground()
        .onAppear {
            guard !didStartWork else { return }
            didStartWork = true
            runSequence()
        }
        .task {
            await generateFirstRecommendation()
        }
    }

    /// Runs in parallel with the fixed-duration loading animation above --
    /// whichever finishes last determines when the user actually sees the
    /// plan summary next, but the animation always plays out in full so
    /// this doesn't feel like a network spinner.
    private func generateFirstRecommendation() async {
        let snapshot = HealthKitManager.isAvailable
            ? await HealthKitManager.shared.fetchTodaysMetrics()
            : nil
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let today = formatter.string(from: Date())

        if let recommendation = try? await SupabaseClient.shared.invokeGenerateRecommendation(date: today, healthkit: snapshot) {
            appState.currentRecommendation = recommendation
            NotificationManager.shared.markSentToday()
        }
    }

    private func runSequence() {
        let totalDuration = 3.2
        let steps = 100
        let interval = totalDuration / Double(steps)

        for step in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(step)) {
                percent = step
                statusIndex = min(step / (100 / statusMessages.count), statusMessages.count - 1)
                checkedCount = min(step / (100 / checklist.count), checklist.count)
                if step == steps {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        onFinished()
                    }
                }
            }
        }
    }
}
