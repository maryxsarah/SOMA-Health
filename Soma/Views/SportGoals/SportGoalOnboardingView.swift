import SwiftUI

/// First-tap onboarding popup for the sport-goals beta (guide 08 / PROMPT
/// §2): a 4-slide swipeable gallery in a modal card over a 40% scrim.
/// Shown once; later taps on the Home card go straight to the sport list.
struct SportGoalOnboardingView: View {
    /// "Pick a goal" on the last slide — the caller opens S1.
    let onPickGoal: () -> Void
    /// X or "Skip — I'll find it later".
    let onClose: () -> Void

    @State private var slide = 0
    private let slideCount = 4

    var body: some View {
        ZStack {
            Color(red: 18 / 255, green: 20 / 255, blue: 31 / 255).opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 16) {
                header
                gallery
                dots
                SomaButton(title: slide == slideCount - 1 ? "Pick a goal" : "Next", size: .lg, variant: .primary) {
                    if slide == slideCount - 1 {
                        onPickGoal()
                    } else {
                        withAnimation(.easeOut(duration: 0.38)) { slide += 1 }
                    }
                }
                Button("Skip — I'll find it later") { onClose() }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink3)
                    .buttonStyle(.plain)
            }
            .padding(.top, 22)
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
            .glassCard(cornerRadius: 26)
            .padding(.horizontal, 24)
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text("NEW")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(SomaTokens.accent))
            Text("SPORT GOALS")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(SomaTokens.ink4)
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink3)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var gallery: some View {
        TabView(selection: $slide) {
            slideView(vignette: whereToFindVignette,
                      title: "Where to find it",
                      sub: "Start from this Home card — or anytime via Profile → Training → My goal. The beta switch lives in Account.",
                      subIsBold: true)
                .tag(0)
            slideView(vignette: flowVignette,
                      title: "Sport first, then a goal in it",
                      sub: "Named, measurable presets like \"Jump higher\" — or your own custom goal from a coach. One at a time.")
                .tag(1)
            slideView(vignette: targetVignette,
                      title: "Get an honest target — and train it",
                      sub: "A real range, never a promise. A 10–20 min goal block joins your daily plan, matched to readiness.")
                .tag(2)
            slideView(vignette: coachVignette,
                      title: "Or bring your coach's task",
                      sub: "Attach the assignment as photo or text, do the work in Soma, show your coach the progress.")
                .tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // 288, not 268: slide 1's two-line subtitle plus its three-row
        // vignette need the extra height (268 truncated the subtitle).
        .frame(height: 288)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func slideView(vignette: some View, title: LocalizedStringKey, sub: LocalizedStringKey, subIsBold: Bool = false) -> some View {
        VStack(spacing: 14) {
            vignette
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                Text(sub)
                    .font(.system(size: 13, weight: subIsBold ? .semibold : .regular))
                    .foregroundStyle(subIsBold ? SomaTokens.ink2 : SomaTokens.ink3)
                    .multilineTextAlignment(.center)
                    // The gallery's fixed height was compressing this to a
                    // single truncated line ("…or anytime via P…") -- claim
                    // the real height and let the vignette shrink instead.
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<slideCount, id: \.self) { index in
                Button {
                    withAnimation(.easeOut(duration: 0.38)) { slide = index }
                } label: {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(index == slide ? SomaTokens.accent : SomaTokens.hairline)
                        .frame(width: index == slide ? 22 : 7, height: 7)
                }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.28), value: slide)
            }
        }
    }

    // MARK: - Slide 1: where to find it

    private var whereToFindVignette: some View {
        VStack(spacing: 8) {
            pathRow(icon: "target", accent: true, text: "Home → Train for your sport")
            pathRow(icon: "person", accent: false, text: "Profile → Training → My goal → Pick a goal")
            pathRow(icon: "gearshape", accent: false, text: "Account → Sport goals (beta)", trailingToggle: true)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SomaTokens.surface3))
    }

    private func pathRow(icon: String, accent: Bool, text: LocalizedStringKey, trailingToggle: Bool = false) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent ? SomaTokens.accentSoft : SomaTokens.surface4)
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent ? SomaTokens.accent : SomaTokens.ink2)
                )
            Text(text)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(SomaTokens.ink)
                .lineLimit(1)
                // 0.85 still ellipsized the two long paths ("…My goa…");
                // these are decorative mini-rows, smaller beats truncated.
                .minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            if trailingToggle {
                Capsule()
                    .fill(SomaTokens.accent)
                    .frame(width: 26, height: 16)
                    .overlay(alignment: .trailing) {
                        Circle().fill(.white).frame(width: 12, height: 12).padding(2)
                    }
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink5)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SomaTokens.surface)
                .shadow(color: SomaTokens.ink.opacity(0.06), radius: 2, y: 1)
        )
    }

    // MARK: - Slide 2: sport → goals flow

    private var flowVignette: some View {
        VStack(spacing: 7) {
            miniRow(icon: "figure.volleyball", plate: SomaTokens.accentSoft, iconColor: SomaTokens.accent,
                    text: "Volleyball", badge: nil, indented: false)
            miniRow(icon: "arrow.up", plate: SomaTokens.accentSoft, iconColor: SomaTokens.accent,
                    text: "Jump higher", badge: ("sportGoal.kindBadge.metric", true), indented: true)
            miniRow(icon: "list.clipboard", plate: SomaTokens.heartSoft, iconColor: SomaTokens.heart,
                    text: "Coach's task", badge: ("sportGoal.kindBadge.custom", false), indented: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SomaTokens.surface3))
    }

    private func miniRow(icon: String, plate: Color, iconColor: Color, text: LocalizedStringKey, badge: (LocalizedStringKey, Bool)?, indented: Bool) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(plate)
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(iconColor)
                )
            Text(text)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(SomaTokens.ink)
            Spacer(minLength: 4)
            if let (badgeText, isAccent) = badge {
                Text(badgeText)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(isAccent ? SomaTokens.accent : SomaTokens.ink2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(isAccent ? SomaTokens.accentSoft : SomaTokens.surface4))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink5)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SomaTokens.surface)
                .shadow(color: SomaTokens.ink.opacity(0.06), radius: 2, y: 1)
        )
        .padding(.leading, indented ? 18 : 0)
    }

    // MARK: - Slide 3: honest target + trend

    private var targetVignette: some View {
        VStack(spacing: 6) {
            VStack(spacing: 2) {
                Text("+3–6 cm")
                    .font(SomaType.sheetTitle)
                Text("in 10–12 weeks — an honest range")
                    .font(.system(size: 10.5))
                    .foregroundStyle(SomaTokens.ink4)
            }
            OnboardingTrendGraphic()
                .frame(height: 58)
            Text("41 → 44 cm · week 6")
                .font(.system(size: 11))
                .foregroundStyle(SomaTokens.ink4)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SomaTokens.surface3))
    }

    // MARK: - Slide 4: coach's task

    private var coachVignette: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SomaTokens.heartSoft)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "list.clipboard")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SomaTokens.heart)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Coach's task · photo attached")
                    .font(.system(size: 13.5, weight: .semibold))
                Text("Sessions & measurements export as one card")
                    .font(.system(size: 11.5))
                    .foregroundStyle(SomaTokens.ink4)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SomaTokens.surface3))
    }
}

/// The slide-3 vignette chart -- decorative illustration with fixed sample
/// numbers matching its caption, not user data.
private struct OnboardingTrendGraphic: View {
    /// Canvas-space points from the design (viewBox 260×58).
    private let points: [CGPoint] = [CGPoint(x: 10, y: 46), CGPoint(x: 90, y: 40), CGPoint(x: 250, y: 14)]

    var body: some View {
        GeometryReader { geo in
            let scaleX = geo.size.width / 260
            let scaleY = geo.size.height / 58
            let scaled = points.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) }

            ZStack {
                Path { p in
                    p.move(to: scaled[0])
                    scaled.dropFirst().forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: scaled[2].x, y: geo.size.height))
                    p.addLine(to: CGPoint(x: scaled[0].x, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(
                    colors: [SomaTokens.accent.opacity(0.18), SomaTokens.accent.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                ))
                Path { p in
                    p.move(to: scaled[0])
                    scaled.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(SomaTokens.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Circle()
                    .fill(.white)
                    .stroke(SomaTokens.accent, lineWidth: 2)
                    .frame(width: 8, height: 8)
                    .position(scaled[0])
                Circle()
                    .fill(SomaTokens.accent)
                    .stroke(.white, lineWidth: 1.5)
                    .frame(width: 9, height: 9)
                    .position(scaled[2])
            }
        }
    }
}

#Preview {
    SportGoalOnboardingView(onPickGoal: {}, onClose: {})
}
