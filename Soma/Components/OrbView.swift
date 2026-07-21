import SwiftUI

/// Exactly two states per spec: `.idle` (slow, subtle animation) and
/// `.newMessage` (one brighter pulse when a new recommendation arrives).
/// No listening/voice states -- V1 has no voice input.
enum OrbState: Equatable {
    case idle
    case newMessage
}

/// The single reusable "orb" component used on every screen: overlapping
/// blurred RadialGradient blobs inside a lighter circular glow, animated
/// via TimelineView(.animation).
struct OrbView: View {
    var state: OrbState = .idle
    var size: CGFloat = 220

    @State private var pulsing = false

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.orbPrimary.opacity(0.22), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.78
                        )
                    )
                    .frame(width: size * 1.6, height: size * 1.6)
                    .blur(radius: 24)

                blob(color: Theme.orbPrimary, t: t, phase: 0)
                blob(color: Theme.orbSecondary, t: t, phase: .pi)
            }
            .scaleEffect(pulsing ? 1.12 : 1.0)
            .brightness(pulsing ? 0.08 : 0)
        }
        .frame(width: size * 1.6, height: size * 1.6)
        .onChange(of: state) { _, newValue in
            guard newValue == .newMessage else { return }
            triggerPulse()
        }
    }

    private func triggerPulse() {
        withAnimation(.easeOut(duration: 0.5)) {
            pulsing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.9)) {
                pulsing = false
            }
        }
    }

    private func blob(color: Color, t: TimeInterval, phase: Double) -> some View {
        let speed = 0.15
        let dx = CGFloat(sin(t * speed + phase)) * size * 0.12
        let dy = CGFloat(cos(t * speed * 0.8 + phase)) * size * 0.12
        let scale = 1.0 + CGFloat(sin(t * speed * 0.5 + phase)) * 0.06

        return Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.9), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                )
            )
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .offset(x: dx, y: dy)
            .blur(radius: 18)
    }
}

#Preview {
    OrbView()
        .somaBackground()
}
