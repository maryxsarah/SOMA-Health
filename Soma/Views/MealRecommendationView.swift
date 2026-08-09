import SwiftUI
import UIKit

/// "What can I make?" -- NutritionView's entry point for turning what's
/// actually in the fridge/pantry (typed or dictated) into one complete AI
/// recipe suggestion (generate-meal-recommendation), scoped to the user's
/// real kitchen equipment and how much of today's target is left. Two
/// states in one sheet: the input form, then the result -- "Try different
/// ingredients" goes back to the form rather than opening a second sheet,
/// same single-flow shape as LogMealView.
struct MealRecommendationView: View {
    /// Today's remaining macros, computed by NutritionView from the same
    /// target/entries it already has loaded -- passed in rather than
    /// re-fetched here, so there's exactly one source of truth for "what's
    /// left today" and this view never risks disagreeing with it.
    let remaining: NutritionDayProgress?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var speechRecognizer = SpeechRecognizer()

    @State private var ingredientsText = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var recommendation: MealRecommendation?

    @State private var householdEquipmentIsEmpty = false
    @State private var showKitchenSetup = false

    @State private var showCookMode = false
    @State private var isLogging = false
    @State private var didLog = false

    private var canGenerate: Bool {
        !ingredientsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isGenerating && !speechRecognizer.isListening
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let recommendation {
                        resultSection(recommendation)
                    } else {
                        inputSection
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(SomaTokens.danger)
                    }
                }
                .padding(20)
                .padding(.bottom, 90)
            }
            .somaBackground()
            .navigationTitle("What can I make?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(recommendation == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let recommendation {
                    bottomBar(recommendation)
                }
            }
        }
        .task { await loadEquipmentState() }
        .sheet(isPresented: $showKitchenSetup, onDismiss: {
            Task { await loadEquipmentState() }
        }) {
            ProfileView()
        }
        .fullScreenCover(isPresented: $showCookMode) {
            if let recommendation {
                CookModeView(mealName: recommendation.name, steps: recommendation.steps)
            }
        }
        .onChange(of: speechRecognizer.transcript) { _, newValue in
            ingredientsText = newValue
        }
        .onChange(of: speechRecognizer.errorMessage) { _, newValue in
            if let newValue { errorMessage = newValue }
        }
        .onChange(of: speechRecognizer.isListening) { wasListening, isListening in
            // Same "dictate = one action, not two" auto-generate wiring
            // LogMealView uses for its own mic button.
            guard wasListening, !isListening, speechRecognizer.errorMessage == nil,
                  !ingredientsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            Task { await generate() }
        }
        .onDisappear { speechRecognizer.stop() }
    }

    // MARK: - Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tell Soma what you have.")
                .font(Theme.display)
            Text("Type it, dictate it, or just list what's in the fridge and pantry -- Soma builds one full recipe from it, sized to what's left of today's target.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if householdEquipmentIsEmpty {
                equipmentHint
            }

            CardView {
                HStack(alignment: .top, spacing: 8) {
                    TextField("e.g. \"chicken breast, spinach, rice, half an onion\"", text: $ingredientsText, axis: .vertical)
                        .lineLimit(1...4)
                    dictateButton
                }
                if speechRecognizer.isListening {
                    Label("Listening -- tap the mic when you're done, or just stop talking.", systemImage: "waveform")
                        .font(.caption2)
                        .foregroundStyle(SomaTokens.accent)
                }
            }

            if isGenerating {
                SomaLoadingBar(messages: Self.thinkingMessages.shuffled(), barWidth: 220)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                SomaButton(title: "Get a meal idea", size: .lg, variant: .primary, isEnabled: canGenerate) {
                    Task { await generate() }
                }
            }
        }
    }

    private var equipmentHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(SomaTokens.warn)
            VStack(alignment: .leading, spacing: 4) {
                Text("We don't know your kitchen yet")
                    .font(.system(size: 13, weight: .semibold))
                Text("Recipes will assume a stove, oven, and microwave until you set up your full kitchen equipment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Set up now") { showKitchenSetup = true }
                    .font(.caption.bold())
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.warnSoft))
        .overlay(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).stroke(SomaTokens.warnLine, lineWidth: 1))
    }

    private var dictateButton: some View {
        Button {
            if speechRecognizer.isListening { speechRecognizer.stop() } else { speechRecognizer.start() }
        } label: {
            Image(systemName: speechRecognizer.isListening ? "mic.fill" : "mic")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(speechRecognizer.isListening ? .white : SomaTokens.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(speechRecognizer.isListening ? SomaTokens.danger : SomaTokens.accentSoft))
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
    }

    private static let thinkingMessages = [
        "Checking what's actually in season...",
        "Matching this to today's remaining macros...",
        "Making sure every step fits your kitchen...",
        "Working out realistic portions...",
    ]

    // MARK: - Result

    private func resultSection(_ rec: MealRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(rec.name)
                    .font(Theme.display)
                HStack(spacing: 10) {
                    Label("\(rec.totalTimeMinutes) min", systemImage: "clock")
                    Label("\(rec.calories) kcal", systemImage: "flame")
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            }

            SomaDisclosure(closedLabel: "Why this meal?", openLabel: "Hide") {
                Text(rec.whyThisMeal)
            }

            if let remaining {
                macroFitCard(rec, remaining: remaining)
            }

            ingredientsCard(rec)
            stepsCard(rec)

            if !rec.equipmentUsed.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.caption2)
                    Text("Uses: \(rec.equipmentUsed.joined(separator: ", "))")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func macroFitCard(_ rec: MealRecommendation, remaining: NutritionDayProgress) -> some View {
        CardView {
            Text("How this fits what's left today")
                .font(.subheadline.bold())
            macroFitRow(label: "Calories", value: rec.calories, of: remaining.caloriesRemaining, unit: "kcal", color: SomaTokens.accent)
            macroFitRow(label: "Protein", value: rec.proteinG, of: remaining.proteinRemainingG, unit: "g", color: Self.proteinColor)
            macroFitRow(label: "Carbs", value: rec.carbsG, of: remaining.carbsRemainingG, unit: "g", color: Self.carbsColor)
            macroFitRow(label: "Fat", value: rec.fatG, of: remaining.fatRemainingG, unit: "g", color: Self.fatColor)
        }
    }

    private static let proteinColor = Color(red: 0.90, green: 0.35, blue: 0.40)
    private static let carbsColor = Color(red: 0.95, green: 0.65, blue: 0.20)
    private static let fatColor = Color(red: 0.35, green: 0.55, blue: 0.90)

    /// `value` (this recipe) plotted against `of` (what's left today) --
    /// the fill can run past 100% (this meal alone can exceed what's left,
    /// same "the real numbers tell the honest story" rule NutritionView's
    /// own macroBar follows, never silently clamped to look flattering).
    private func macroFitRow(label: String, value: Int, of remaining: Int, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.caption.bold())
                Spacer()
                Text("\(value) / \(remaining) \(unit) left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SomaTokens.surface3)
                    Capsule()
                        .fill(color)
                        .frame(width: remaining > 0 ? min(geo.size.width, geo.size.width * CGFloat(value) / CGFloat(remaining)) : geo.size.width)
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
        }
    }

    private func ingredientsCard(_ rec: MealRecommendation) -> some View {
        CardView {
            Text("Ingredients")
                .font(.subheadline.bold())
            ForEach(rec.ingredients) { ingredient in
                HStack {
                    Text(ingredient.name)
                        .font(.system(size: 14))
                    Spacer()
                    Text(ingredient.quantity)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stepsCard(_ rec: MealRecommendation) -> some View {
        CardView {
            Text("How to make it")
                .font(.subheadline.bold())
            ForEach(Array(rec.steps.prefix(2).enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(SomaTokens.accent)
                    Text(step)
                        .font(.system(size: 13.5))
                        .foregroundStyle(SomaTokens.ink2)
                }
            }
            if rec.steps.count > 2 {
                Text("+ \(rec.steps.count - 2) more step\(rec.steps.count - 2 == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            SomaButton(title: "Start cooking", size: .md, variant: .secondary) {
                showCookMode = true
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private func bottomBar(_ rec: MealRecommendation) -> some View {
        VStack(spacing: 8) {
            if didLog {
                Label("Logged -- nice.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(SomaTokens.success)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .transition(.scale.combined(with: .opacity))
            } else {
                HStack(spacing: 10) {
                    SomaButton(title: "Try different ingredients", size: .lg, variant: .secondary) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            recommendation = nil
                            ingredientsText = ""
                        }
                    }
                    SomaButton(title: isLogging ? "Logging..." : "Log this meal", size: .lg, variant: .primary, isEnabled: !isLogging) {
                        Task { await logThisMeal(rec) }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private func generate() async {
        errorMessage = nil
        isGenerating = true
        defer { isGenerating = false }
        do {
            let result = try await SupabaseClient.shared.generateMealRecommendation(ingredients: ingredientsText)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                recommendation = result
            }
        } catch {
            errorMessage = "Couldn't come up with something from that -- try describing it differently, or try again in a moment."
        }
    }

    private func logThisMeal(_ rec: MealRecommendation) async {
        isLogging = true
        errorMessage = nil
        defer { isLogging = false }
        do {
            try await SupabaseClient.shared.logMeal(
                date: NutritionView.todayDateString(),
                label: rec.name,
                calories: rec.calories,
                proteinG: rec.proteinG,
                carbsG: rec.carbsG,
                fatG: rec.fatG,
                source: "recipe_ai"
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                didLog = true
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } catch {
            errorMessage = "Couldn't save that entry. Try again."
        }
    }

    private func loadEquipmentState() async {
        guard let userId = SupabaseClient.shared.currentUserID else { return }
        let profile = try? await SupabaseClient.shared.fetchProfile(id: userId)
        householdEquipmentIsEmpty = profile?.householdEquipment.isEmpty ?? true
    }
}

#Preview {
    MealRecommendationView(remaining: nil)
}
