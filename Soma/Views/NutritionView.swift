import SwiftUI

/// Daily calorie/macro targets (computed deterministically from the
/// goal-photo comparison, see nutrition_targets) plus a simple manual log
/// so the bars actually fill through the day rather than only ever
/// showing a static target. Opened from Home's compact entry point.
struct NutritionView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var target: NutritionTargets?
    @State private var entries: [MealLogEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showLogSheet = false
    @State private var showGoalBodyProgress = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isLoading {
                        SomaLoadingBar(barWidth: 200)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else if let target {
                        let progress = NutritionDayProgress.compute(entries: entries, target: target)
                        progressSection(progress)
                        logSection
                    } else {
                        emptyStateSection
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .somaBackground()
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if target != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showLogSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showLogSheet, onDismiss: {
            Task { await loadEntries() }
        }) {
            LogMealView(date: Self.todayDateString())
        }
        .sheet(isPresented: $showGoalBodyProgress, onDismiss: {
            Task { await load() }
        }) {
            GoalBodyProgressView()
        }
    }

    // MARK: - Empty state (no target computed yet)

    private var emptyStateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Get your daily targets.")
                .font(Theme.display)
            Text("Add a goal photo and a current photo -- Soma uses them to work out a calorie and macro target that actually fits where you are today and where you're headed.")
                .font(.body)
                .foregroundStyle(.secondary)
            Button {
                showGoalBodyProgress = true
            } label: {
                Label("Set up your goal photos", systemImage: "camera.fill")
                    .font(.subheadline.bold())
            }
        }
    }

    // MARK: - Targets + today's progress

    private func progressSection(_ progress: NutritionDayProgress) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            CardView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Today")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("\(progress.caloriesRemaining) kcal left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    macroBar(
                        label: "Calories", consumed: progress.consumedCalories, target: progress.targetCalories,
                        unit: "kcal", fraction: progress.calorieFraction, color: SomaTokens.accent, isPrimary: true
                    )
                    macroBar(
                        label: "Protein", consumed: progress.consumedProteinG, target: progress.targetProteinG,
                        unit: "g", fraction: progress.proteinFraction, color: Self.proteinColor
                    )
                    macroBar(
                        label: "Carbs", consumed: progress.consumedCarbsG, target: progress.targetCarbsG,
                        unit: "g", fraction: progress.carbsFraction, color: Self.carbsColor
                    )
                    macroBar(
                        label: "Fat", consumed: progress.consumedFatG, target: progress.targetFatG,
                        unit: "g", fraction: progress.fatFraction, color: Self.fatColor
                    )
                }
            }
            Text("A deterministic estimate based on your weight, height, activity, and goal direction -- not a strict prescription. Adjust to how you actually feel.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private static let proteinColor = Color(red: 0.90, green: 0.35, blue: 0.40)
    private static let carbsColor = Color(red: 0.95, green: 0.65, blue: 0.20)
    private static let fatColor = Color(red: 0.35, green: 0.55, blue: 0.90)

    private func macroBar(label: String, consumed: Int, target: Int, unit: String, fraction: Double, color: Color, isPrimary: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(isPrimary ? .subheadline.bold() : .caption.bold())
                Spacer()
                Text("\(consumed) / \(target) \(unit)")
                    .font(isPrimary ? .subheadline.bold() : .caption)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SomaTokens.surface3)
                    Capsule()
                        .fill(color)
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: isPrimary ? 12 : 8)
            .clipShape(Capsule())
        }
    }

    // MARK: - Today's log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Logged today")
                .font(.subheadline.bold())
            if entries.isEmpty {
                Text("Nothing logged yet -- tap + to add what you've eaten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    logRow(entry)
                }
            }
        }
    }

    private func logRow(_ entry: MealLogEntry) -> some View {
        CardView {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.label?.isEmpty == false ? entry.label! : "Logged food")
                        .font(.system(size: 14.5, weight: .semibold))
                    Text(macroSummary(entry))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await delete(entry) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func macroSummary(_ entry: MealLogEntry) -> String {
        var parts = ["\(entry.calories) kcal", "\(entry.proteinG)g protein"]
        if let carbsG = entry.carbsG { parts.append("\(carbsG)g carbs") }
        if let fatG = entry.fatG { parts.append("\(fatG)g fat") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Data loading

    private func load() async {
        isLoading = true
        errorMessage = nil
        target = try? await SupabaseClient.shared.fetchNutritionTargets()
        if target != nil {
            await loadEntries()
        }
        isLoading = false
    }

    private func loadEntries() async {
        entries = (try? await SupabaseClient.shared.fetchMealLogs(date: Self.todayDateString())) ?? []
    }

    private func delete(_ entry: MealLogEntry) async {
        errorMessage = nil
        do {
            try await SupabaseClient.shared.deleteMealLog(id: entry.id)
            entries.removeAll { $0.id == entry.id }
        } catch {
            errorMessage = "Couldn't remove that entry. Try again."
        }
    }

    static func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}

#Preview {
    NutritionView()
}
