import SwiftUI

/// Straight-segment line through normalized points (x: 0...1, y: 0...1,
/// where y=1 is the top of the drawing rect). Used with `.trim(from:to:)`
/// for the draw-in animation on every trend chart below.
struct TrendLineShape: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        func scale(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * rect.width, y: (1 - p.y) * rect.height)
        }
        path.move(to: scale(first))
        for point in points.dropFirst() {
            path.addLine(to: scale(point))
        }
        return path
    }
}

/// Single upward trend line -- "you're right on track" (survey) and the
/// plan-summary screen both reuse this.
struct UpwardTrendChartView: View {
    var xAxisLabels: [String] = ["3 Days", "7 Days", "30 Days"]
    /// Compact call sites (e.g. the welcome screen, which must fit without
    /// scrolling) pass a shorter height than the default.
    var chartHeight: CGFloat = 160
    /// The welcome screen's chart is decorative trivia, not an earned
    /// achievement -- no trophy badge there, matching the "8a" mockup.
    var showsBadge: Bool = true
    @State private var drawProgress: CGFloat = 0
    @State private var showBadge = false

    private let points: [CGPoint] = [
        CGPoint(x: 0, y: 0.15), CGPoint(x: 0.33, y: 0.35), CGPoint(x: 0.66, y: 0.6), CGPoint(x: 1.0, y: 0.9),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                TrendAreaShape(points: points)
                    .fill(LinearGradient(colors: [SomaTokens.accentSoft14, SomaTokens.accentSoft14.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .opacity(drawProgress)

                TrendLineShape(points: points)
                    .trim(from: 0, to: drawProgress)
                    .stroke(
                        LinearGradient(colors: [SomaTokens.accentLighter, SomaTokens.accent], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )

                GeometryReader { geometry in
                    Circle()
                        .fill(.white)
                        .overlay(Circle().strokeBorder(SomaTokens.accentLighter, lineWidth: 2))
                        .frame(width: 8, height: 8)
                        .position(x: 0, y: (1 - points[0].y) * geometry.size.height)
                        .opacity(drawProgress)
                }

                if showsBadge && showBadge {
                    Image(systemName: "trophy")
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .glassGel(.blue, cornerRadius: 19)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: chartHeight)

            HStack {
                ForEach(xAxisLabels, id: \.self) { label in
                    Text(LocalizedStringKey(label)).font(.caption2).foregroundStyle(.secondary)
                    if label != xAxisLabels.last { Spacer() }
                }
            }
        }
        .padding(chartHeight < 160 ? 14 : 20)
        .glassCard(cornerRadius: 20)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4)) { drawProgress = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { showBadge = true }
            }
        }
    }
}

/// The user's own real weight trajectory -- start/today and goal, plotted
/// on a real calendar timeline (today -> today + estimatedMonths) -- in
/// place of a decorative always-upward curve. Direction is honest: the
/// line slopes down for a weight-loss goal, up for a gain goal, flat for
/// maintain, because it plots the real kg values rather than an abstract
/// "progress" curve that looked identical for every user regardless of
/// what they'd actually answered. Two labeled anchor points only --
/// "Today" and "Goal" -- never a fabricated third waypoint in between;
/// see each call site for why start and today are the same point during
/// onboarding (no weigh-in history exists yet).
struct GoalTrajectoryChartView: View {
    let startWeightKg: Double?
    let goalWeightKg: Double?
    let estimatedMonths: Int
    var chartHeight: CGFloat = 150

    @State private var drawProgress: CGFloat = 0
    @State private var markersVisible = false

    private var points: [CGPoint] {
        guard let start = startWeightKg, let goal = goalWeightKg else { return [] }
        // Padding keeps the line off the top/bottom edges even when the
        // goal delta is tiny; a flat (maintain) line still reads as a
        // real, centered line rather than one glued to an edge.
        let range = max(abs(goal - start), 0.6)
        let pad = range * 0.4
        let valMin = min(start, goal) - pad
        let span = max((max(start, goal) + pad) - valMin, 0.01)
        func normalize(_ value: Double) -> Double { (value - valMin) / span }
        return [CGPoint(x: 0, y: normalize(start)), CGPoint(x: 1, y: normalize(goal))]
    }

    private var goalDate: Date {
        Calendar.current.date(byAdding: .month, value: max(estimatedMonths, 1), to: Date()) ?? Date()
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    var body: some View {
        Group {
            if let start = startWeightKg, let goal = goalWeightKg {
                let linePoints = points
                ZStack {
                    TrendAreaShape(points: linePoints)
                        .fill(
                            LinearGradient(
                                colors: [SomaTokens.accentSoft, SomaTokens.accentSoft.opacity(0)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .opacity(drawProgress)

                    TrendLineShape(points: linePoints)
                        .trim(from: 0, to: drawProgress)
                        .stroke(Theme.pillFill, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                    GeometryReader { geometry in
                        marker(tag: Self.todayTagText, weightKg: start, date: Date(), point: linePoints[0], geometry: geometry)
                        marker(tag: Self.goalTagText, weightKg: goal, date: goalDate, point: linePoints[1], geometry: geometry)
                    }
                    .opacity(markersVisible ? 1 : 0)
                }
                .frame(height: chartHeight)
                .onAppear {
                    withAnimation(.spring(response: 0.75, dampingFraction: 0.75)) { drawProgress = 1 }
                    withAnimation(.easeOut(duration: 0.3).delay(0.5)) { markersVisible = true }
                }
            } else if let start = startWeightKg {
                // Partial data (no goal weight set yet) -- an honest
                // single reading rather than fabricating a goal line.
                VStack(spacing: 6) {
                    Text(String(localized: "onboardingCharts.trajectory.currentWeightToday", defaultValue: "\(Self.formattedWeight(start)) kg today", comment: "Shown when only a current weight is known yet (no goal weight set); placeholder is a formatted kg amount like '72.5'"))
                        .font(.system(.title3, design: .serif, weight: .semibold).italic())
                    Text(String(localized: "onboardingCharts.trajectory.setGoalWeightPrompt", defaultValue: "Set a goal weight to see your projected timeline.", comment: "Shown under the current weight reading when no goal weight has been set yet"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: chartHeight)
            } else {
                Text(String(localized: "onboardingCharts.trajectory.addWeightPrompt", defaultValue: "Add your weight to see your projected timeline.", comment: "Shown when neither a current nor a goal weight is set yet"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: chartHeight)
            }
        }
    }

    /// Pre-resolved (not LocalizedStringKey) since `tag` is a plain String
    /// parameter -- Text(tag) below can't do its own catalog lookup.
    private static let todayTagText = String(localized: "TODAY", comment: "Marker label on the weight-trajectory chart for the 'today' anchor point")
    private static let goalTagText = String(localized: "onboardingCharts.trajectory.goalTag", defaultValue: "GOAL", comment: "Marker label on the weight-trajectory chart for the 'goal' anchor point")

    private func marker(tag: String, weightKg: Double, date: Date, point: CGPoint, geometry: GeometryProxy) -> some View {
        VStack(spacing: 1) {
            Text(tag)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(Theme.pillFill)
            Text(String(localized: "onboardingCharts.trajectory.markerWeight", defaultValue: "\(Self.formattedWeight(weightKg)) kg", comment: "Weight value shown under a TODAY/GOAL marker on the trajectory chart; placeholder is a formatted kg amount"))
                .font(.system(.subheadline, design: .serif, weight: .semibold).italic())
            Text(Self.monthFormatter.string(from: date))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .position(
            x: min(max(geometry.size.width * point.x, 40), geometry.size.width - 40),
            y: max(24, geometry.size.height * (1 - point.y) - 32)
        )
    }

    private static func formattedWeight(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

/// "Highlights of your plan" -- 3-4 lines built only from answers actually
/// collected this onboarding session. Renders nothing at all (not a
/// generic fallback line) when nothing real has been collected yet, so a
/// screen shown before those questions are asked never presents a claim
/// unearned by an unset field.
struct PlanHighlightsListView: View {
    let items: [String]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "onboardingCharts.planHighlights.title", defaultValue: "Highlights of your plan", comment: "Title above the list of plan-highlight bullet lines"))
                    .font(.body.bold())
                ForEach(Array(items.enumerated()), id: \.offset) { _, text in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Theme.pillFill)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    /// Priority order: the goal itself first, then journey/blockers/diet
    /// context -- each line skipped outright when its field is nil/empty,
    /// never backfilled with a generic claim. `maxItems` lets a tighter
    /// mid-survey screen (no ScrollView) cap to 3 while the final summary
    /// screen (which scrolls) can show all 4.
    static func build(
        goalTags: Set<GoalTag>, journeyStage: JourneyStage?,
        blockers: Set<BlockerTag>, dietType: DietType?, maxItems: Int = 4
    ) -> [String] {
        var lines: [String] = []
        if !goalTags.isEmpty {
            let names = goalTags.map(\.displayName).sorted().prefix(3).joined(separator: ", ")
            lines.append(String(localized: "onboardingCharts.planHighlights.goal", defaultValue: "Built around your goal: \(names)", comment: "Plan-highlights bullet line naming the user's selected goal(s); placeholder is a comma-separated list of goal names"))
        }
        if let journeyStage {
            lines.append(String(localized: "onboardingCharts.planHighlights.journeyStage", defaultValue: "Paced for where you are: \(journeyStage.displayName.lowercased())", comment: "Plan-highlights bullet line naming the user's journey stage; placeholder is the lowercased journey stage name"))
        }
        if !blockers.isEmpty {
            let names = blockers.map(\.displayName).sorted().prefix(2).joined(separator: ", ")
            lines.append(String(localized: "onboardingCharts.planHighlights.blockers", defaultValue: "Designed around what's gotten in the way: \(names)", comment: "Plan-highlights bullet line naming the user's selected blockers; placeholder is a comma-separated list of blocker names"))
        }
        if let dietType {
            lines.append(String(localized: "onboardingCharts.planHighlights.dietType", defaultValue: "Nutrition guidance tuned to: \(dietType.displayName)", comment: "Plan-highlights bullet line naming the user's diet type; placeholder is the diet type name"))
        }
        return Array(lines.prefix(maxItems))
    }
}
