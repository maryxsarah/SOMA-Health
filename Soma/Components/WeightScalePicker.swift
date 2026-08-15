import SwiftUI

/// A horizontal draggable ruler with a fixed center indicator, matching
/// the "scroll like a scale" pattern common in weight-entry onboarding
/// flows: big number on top, tick marks below that scroll under your
/// finger, settling on release. Ticks are drawn via Canvas rather than
/// individual views since a wide kg range would otherwise mean hundreds
/// of child views.
struct WeightScalePicker: View {
    @Binding var weightKg: Double
    var range: ClosedRange<Double> = 30...200

    private let pointsPerKg: CGFloat = 14
    @State private var dragStartWeight: Double?

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", weightKg))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text("kg")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ZStack {
                Canvas { context, size in
                    let midX = size.width / 2
                    let midY = size.height / 2
                    var value = floor(range.lowerBound)
                    while value <= range.upperBound {
                        let offset = CGFloat(value - weightKg) * pointsPerKg
                        let x = midX + offset
                        if x > -20, x < size.width + 20 {
                            let isMajor = value.truncatingRemainder(dividingBy: 5) == 0
                            let tickHeight: CGFloat = isMajor ? 30 : 16
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: midY - tickHeight / 2))
                            path.addLine(to: CGPoint(x: x, y: midY + tickHeight / 2))
                            context.stroke(
                                path,
                                with: .color(isMajor ? .primary.opacity(0.55) : .secondary.opacity(0.3)),
                                lineWidth: isMajor ? 2 : 1
                            )
                        }
                        value += 1
                    }
                }

                Rectangle()
                    .fill(Theme.pillFill)
                    .frame(width: 3, height: 46)
                    .clipShape(Capsule())
            }
            .frame(height: 72)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartWeight == nil { dragStartWeight = weightKg }
                        let delta = Double(value.translation.width / pointsPerKg)
                        let newValue = (dragStartWeight ?? weightKg) - delta
                        weightKg = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        dragStartWeight = nil
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            weightKg = (weightKg * 10).rounded() / 10
                        }
                    }
            )
        }
        // Ticks off a whole-kg crossing, same feel as Apple Health's own
        // scale picker -- fires on every integer, not every 0.1 snap.
        .sensoryFeedback(.selection, trigger: Int(weightKg.rounded()))
    }
}

#Preview {
    WeightScalePicker(weightKg: .constant(72.4))
}
