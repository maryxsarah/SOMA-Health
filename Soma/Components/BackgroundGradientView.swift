import SwiftUI

/// Soma Glass screen background -- a soft blue/violet gradient with three
/// ambient blob glows layered on top, per `soma-glass-tokens.css`
/// `--bg-screen`/`--blob-*`. Used behind every screen via `.somaBackground()`.
///
/// The blobs are corner-anchored and bleed off the screen edge, matching
/// the mockup's own technique exactly (e.g. `top:-60px; right:-80px;
/// width:280px`) -- the radial gradient's own 0%→70% falloff is already
/// the entire softness; no extra `.blur()` on top. An earlier version
/// added one, which over-softened three overlapping blobs into a flat,
/// barely-there wash instead of the mockup's visible corner glows.
struct BackgroundGradientView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [SomaTokens.bgScreenTop, SomaTokens.bgScreenMid, SomaTokens.bgScreenBottom],
                startPoint: UnitPoint(x: 0.35, y: 0),
                endPoint: UnitPoint(x: 0.75, y: 1)
            )

            GeometryReader { geo in
                // Top-right, bleeding off the top+right edges.
                blob(SomaTokens.blobBlue, opacity: 0.4, size: geo.size.width * 0.72)
                    .position(x: geo.size.width * 0.846, y: geo.size.height * 0.095)

                // Left-middle, bleeding off the left edge.
                blob(SomaTokens.blobViolet, opacity: 0.28, size: geo.size.width * 0.82)
                    .position(x: geo.size.width * 0.15, y: geo.size.height * 0.59)

                // Bottom-right, bleeding off the bottom+right edges.
                blob(SomaTokens.blobCyan, opacity: 0.32, size: geo.size.width * 0.77)
                    .position(x: geo.size.width * 0.77, y: geo.size.height * 0.92)
            }
        }
        .ignoresSafeArea()
    }

    private func blob(_ color: Color, opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
    }
}

#Preview {
    BackgroundGradientView()
}
