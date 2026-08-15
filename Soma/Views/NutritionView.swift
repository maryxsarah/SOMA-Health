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
    @State private var showMealRecommendation = false
    @State private var selectedEntry: MealLogEntry?
    /// Guards against firing a second rate-meal call for the same entry
    /// while one is already in flight (loadEntries() re-runs the
    /// unrated-entry sweep every time it's called).
    @State private var ratingInFlight: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isLoading {
                        SomaLoadingBar(barWidth: 200)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else {
                        // logSection used to live inside the `target != nil`
                        // branch, so a meal logged before targets exist was
                        // invisible forever -- "Log a meal instead" led
                        // nowhere. It's unconditional now so anything
                        // logged always shows, target or not.
                        if let target {
                            let progress = NutritionDayProgress.compute(entries: entries, target: target)
                            progressSection(progress)
                            mealIdeaCard(progress)
                        } else {
                            emptyStateSection
                        }
                        logSection
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(SomaTokens.danger)
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
                // Not gated on `target != nil` -- logging a meal never
                // depended on targets being computed yet (LogMealView only
                // needs a date), and gating it here was a dead end for
                // anyone who skipped goal-photo setup: no target, no "+",
                // no way to log at all.
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showLogSheet = true
                    } label: {
                        Image(systemName: "plus")
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
        .sheet(isPresented: $showMealRecommendation, onDismiss: {
            // Picks up a meal logged via "Log this meal" in there.
            Task { await loadEntries() }
        }) {
            MealRecommendationView(remaining: target.map { NutritionDayProgress.compute(entries: entries, target: $0) })
        }
        .sheet(item: $selectedEntry, onDismiss: {
            // Picks up a score/rationale MealDetailView may have just
            // computed lazily (an older, never-rated entry).
            Task { await loadEntries() }
        }) { entry in
            MealDetailView(entry: entry)
        }
    }

    // MARK: - Empty state (no target computed yet)

    /// Reached only once the silent weight-only attempt in load() has
    /// already come back empty -- i.e. weight/height/goal-weight aren't
    /// all on file (normally collected at onboarding, so this is the
    /// rare case, not the common one). Copy reflects that photos are one
    /// option now, not a requirement.
    private var emptyStateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Get your daily targets.")
                .font(Theme.display)
            Text(String(localized: "nutrition.emptyState.body", defaultValue: "Soma computes this from your weight, height, and goal weight -- normally already on file from onboarding. Add goal photos for an even more tailored target, or make sure those numbers are filled in.", comment: "Explains how nutrition targets are computed, shown when no target exists yet"))
                .font(.body)
                .foregroundStyle(.secondary)
            SomaButton(title: "Set up your goal photos", size: .lg, variant: .primary) {
                showGoalBodyProgress = true
            }
            Button("Log a meal instead") {
                showLogSheet = true
            }
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity)
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
                        Text(String(localized: "nutrition.today.caloriesRemaining", defaultValue: "\(progress.caloriesRemaining) kcal left", comment: "Calories remaining today, e.g. '450 kcal left'"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    macroBar(
                        label: "Calories", consumed: progress.consumedCalories, target: progress.targetCalories,
                        unit: String(localized: "kcal", comment: "Unit abbreviation for kilocalories, shown next to a macro progress value"), fraction: progress.calorieFraction, color: SomaTokens.accent, isPrimary: true
                    )
                    macroBar(
                        label: "Protein", consumed: progress.consumedProteinG, target: progress.targetProteinG,
                        unit: String(localized: "g", comment: "Unit abbreviation for grams, shown next to a macro progress value"), fraction: progress.proteinFraction, color: Self.proteinColor
                    )
                    macroBar(
                        label: "Carbs", consumed: progress.consumedCarbsG, target: progress.targetCarbsG,
                        unit: String(localized: "g", comment: "Unit abbreviation for grams, shown next to a macro progress value"), fraction: progress.carbsFraction, color: Self.carbsColor
                    )
                    macroBar(
                        label: "Fat", consumed: progress.consumedFatG, target: progress.targetFatG,
                        unit: String(localized: "g", comment: "Unit abbreviation for grams, shown next to a macro progress value"), fraction: progress.fatFraction, color: Self.fatColor
                    )
                }
            }
            Text("A deterministic estimate based on your weight, height, activity, and goal direction -- not a strict prescription. Adjust to how you actually feel.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// "What can I make?" entry point -- sits right under today's bars so
    /// the remaining-macro numbers it feeds MealRecommendationView are
    /// visibly the same ones just shown above, not a disconnected feature.
    private func mealIdeaCard(_ progress: NutritionDayProgress) -> some View {
        Button {
            showMealRecommendation = true
        } label: {
            CardView {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(SomaTokens.accentSoft).frame(width: 40, height: 40)
                        Image(systemName: "sparkles")
                            .foregroundStyle(SomaTokens.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "nutrition.mealIdea.title", defaultValue: "What can I make?", comment: "Title of the entry point card into AI meal recommendations"))
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(SomaTokens.ink)
                        Text(String(localized: "nutrition.mealIdea.subtitle", defaultValue: "Tell Soma what's in your fridge -- get one full recipe, sized to what's left today.", comment: "Subtitle of the entry point card into AI meal recommendations"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SomaTokens.ink4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private static let proteinColor = Color(red: 0.90, green: 0.35, blue: 0.40)
    private static let carbsColor = Color(red: 0.95, green: 0.65, blue: 0.20)
    private static let fatColor = Color(red: 0.35, green: 0.55, blue: 0.90)

    private func macroBar(label: LocalizedStringKey, consumed: Int, target: Int, unit: String, fraction: Double, color: Color, isPrimary: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(isPrimary ? .subheadline.bold() : .caption.bold())
                Spacer()
                Text(String(localized: "nutrition.macroBar.value", defaultValue: "\(consumed) / \(target) \(unit)", comment: "Consumed vs target amount for a macro today, e.g. '30 / 120 g'"))
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

    /// Tapping the row (its own tap target, separate from the trash
    /// button) opens MealDetailView -- full macros, logged time, source,
    /// and the goal-fit rating. The score badge here is the same stored
    /// number MealDetailView shows, just a quick-glance version. Each row
    /// is its own flat glass surface rather than a full glassCard -- same
    /// row-vs-card distinction ProfileView's summaryRow/deviceRow use, so
    /// a long log doesn't stack heavy blurred cards on top of each other.
    private func logRow(_ entry: MealLogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                selectedEntry = entry
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    if let score = entry.score, let verdict = entry.verdict {
                        scoreBadge(score: score, color: verdict.color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.label?.isEmpty == false ? entry.label! : String(localized: "nutrition.loggedFoodFallback", defaultValue: "Logged food", comment: "Fallback title shown for a meal log entry that has no name"))
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(SomaTokens.ink)
                        Text(macroSummary(entry))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SomaTokens.ink4)
                        .padding(.top, 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await delete(entry) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glassCardFlat(cornerRadius: SomaTokens.rXL)
    }

    private func scoreBadge(score: Int, color: Color) -> some View {
        Text("\(score)")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
            .background(Circle().fill(color.opacity(0.15)))
    }

    private func macroSummary(_ entry: MealLogEntry) -> String {
        var parts = [
            String(localized: "nutrition.macroSummary.calories", defaultValue: "\(entry.calories) kcal", comment: "Calorie amount in a meal log row's macro summary"),
            String(localized: "nutrition.macroSummary.protein", defaultValue: "\(entry.proteinG)g protein", comment: "Protein amount in a meal log row's macro summary"),
        ]
        if let carbsG = entry.carbsG { parts.append(String(localized: "nutrition.macroSummary.carbs", defaultValue: "\(carbsG)g carbs", comment: "Carb amount in a meal log row's macro summary")) }
        if let fatG = entry.fatG { parts.append(String(localized: "nutrition.macroSummary.fat", defaultValue: "\(fatG)g fat", comment: "Fat amount in a meal log row's macro summary")) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Data loading

    private func load() async {
        isLoading = true
        errorMessage = nil
        target = try? await SupabaseClient.shared.fetchNutritionTargets()
        // No target yet doesn't necessarily mean "never set up goal
        // photos" -- analyze-body-photo can now also derive a target from
        // just the weight/goal-weight already collected at onboarding, no
        // photos required (real feedback: "a lot of users likely won't
        // want to upload their photos, and calories can already be
        // estimated roughly from the target weight and the current one").
        // One silent attempt, then re-check -- a user with neither weight
        // nor photos on file still lands on the real empty state below.
        if target == nil {
            try? await SupabaseClient.shared.analyzeBodyPhotos()
            target = try? await SupabaseClient.shared.fetchNutritionTargets()
        }
        // Always loaded, target or not -- logSection now renders
        // unconditionally, so an already-logged meal must actually be
        // fetched even for a user who never got a target computed.
        await loadEntries()
        isLoading = false
    }

    private func loadEntries() async {
        entries = (try? await SupabaseClient.shared.fetchMealLogs(date: Self.todayDateString())) ?? []
        autoRateUnratedEntries()
    }

    /// Fire-and-forget: rates any entry that doesn't have a score yet
    /// (a just-logged meal, or an older one from before this feature
    /// existed) so the badge appears without the user needing to tap in.
    /// ratingInFlight guards against re-firing for the same id across
    /// repeated loadEntries() calls while a rating is still in progress.
    private func autoRateUnratedEntries() {
        for entry in entries where entry.score == nil && !ratingInFlight.contains(entry.id) {
            ratingInFlight.insert(entry.id)
            Task {
                if let result = try? await MealRatingCoordinator.shared.rate(id: entry.id),
                   let index = entries.firstIndex(where: { $0.id == entry.id }) {
                    entries[index].score = result.score
                    entries[index].rationale = result.rationale
                }
                ratingInFlight.remove(entry.id)
            }
        }
    }

    private func delete(_ entry: MealLogEntry) async {
        errorMessage = nil
        do {
            try await SupabaseClient.shared.deleteMealLog(id: entry.id)
            entries.removeAll { $0.id == entry.id }
        } catch {
            errorMessage = String(localized: "nutrition.deleteError", defaultValue: "Couldn't remove that entry. Try again.", comment: "Error message shown when deleting a logged meal entry fails")
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
