import SwiftUI

/// WeightScalePicker's drag-a-ruler idiom, generalized to any unit --
/// baseline entry for cm / seconds / reps and custom coach metrics.
struct RulerNumberPicker: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...120
    var unit: String?
    /// Snap increment on release -- 1 for whole-number counts, 0.5 for cm.
    var step: Double = 1

    private let pointsPerUnit: CGFloat = 14
    @State private var dragStartValue: Double?

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(SportGoalFormat.value(value))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            ZStack {
                Canvas { context, size in
                    let midX = size.width / 2
                    let midY = size.height / 2
                    var tick = floor(range.lowerBound)
                    while tick <= range.upperBound {
                        let x = midX + CGFloat(tick - value) * pointsPerUnit
                        if x > -20, x < size.width + 20 {
                            let isMajor = tick.truncatingRemainder(dividingBy: 5) == 0
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
                        tick += 1
                    }
                }

                Rectangle()
                    .fill(SomaTokens.accent)
                    .frame(width: 3, height: 46)
                    .clipShape(Capsule())
            }
            .frame(height: 68)
            .contentShape(Rectangle())
            // Stable hook for XCUITest drags (see UITests/CASES.md).
            .accessibilityIdentifier("ruler-number-picker")
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if dragStartValue == nil { dragStartValue = value }
                        let delta = Double(drag.translation.width / pointsPerUnit)
                        let newValue = (dragStartValue ?? value) - delta
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        dragStartValue = nil
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            value = (value / step).rounded() * step
                        }
                    }
            )
        }
        // Ticks off a whole-unit crossing, same feel as Apple Health's own
        // scale picker -- fires on every integer, not every `step` snap.
        .sensoryFeedback(.selection, trigger: Int(value.rounded()))
    }
}

#Preview {
    RulerNumberPicker(value: .constant(41), range: 0...100, unit: "cm")
}
