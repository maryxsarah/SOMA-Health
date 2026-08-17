import SwiftUI

/// "Your widgets" (3c) -- glass bottom sheet toggling which optional cards
/// show on the dashboard. Log workout isn't listed: it's the dock's
/// pinned-first action, not a toggleable widget.
struct EditWidgetsSheet: View {
    @Binding var waterEnabled: Bool
    @Binding var sleepEnabled: Bool
    @Binding var streakEnabled: Bool
    @Binding var dailyTasksEnabled: Bool
    @Binding var moodEnabled: Bool
    @Binding var nutritionEnabled: Bool
    @Binding var sportGoalEnabled: Bool
    @Binding var photoProgressEnabled: Bool
    @Binding var affirmationEnabled: Bool

    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let id: String
        let systemImage: String
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
        let binding: Binding<Bool>
    }

    private var rows: [Row] {
        [
            Row(id: "water", systemImage: "drop.fill", title: LocalizedStringKey(String(localized: "editWidgets.row.water.title", defaultValue: "Water tracker", comment: "Edit widgets sheet: title for the water tracker widget row")), subtitle: LocalizedStringKey(String(localized: "editWidgets.row.water.subtitle", defaultValue: "Goal 8 glasses · tap to change", comment: "Edit widgets sheet: subtitle for the water tracker widget row")), binding: $waterEnabled),
            Row(id: "sleep", systemImage: "moon.fill", title: LocalizedStringKey(String(localized: "editWidgets.row.sleep.title", defaultValue: "Sleep summary", comment: "Edit widgets sheet: title for the sleep summary widget row")), subtitle: LocalizedStringKey(String(localized: "editWidgets.row.sleep.subtitle", defaultValue: "Last night, on home", comment: "Edit widgets sheet: subtitle for the sleep summary widget row")), binding: $sleepEnabled),
            Row(id: "streak", systemImage: "flame.fill", title: LocalizedStringKey(String(localized: "editWidgets.row.streak.title", defaultValue: "Workout streak", comment: "Edit widgets sheet: title for the workout streak widget row")), subtitle: LocalizedStringKey(String(localized: "editWidgets.row.streak.subtitle", defaultValue: "Consecutive days trained", comment: "Edit widgets sheet: subtitle for the workout streak widget row")), binding: $streakEnabled),
            Row(id: "tasks", systemImage: "checklist", title: LocalizedStringKey(String(localized: "editWidgets.row.tasks.title", defaultValue: "Daily tasks", comment: "Edit widgets sheet: title for the daily tasks widget row")), subtitle: LocalizedStringKey(String(localized: "editWidgets.row.tasks.subtitle", defaultValue: "Checklist with today's to-dos", comment: "Edit widgets sheet: subtitle for the daily tasks widget row")), binding: $dailyTasksEnabled),
            Row(id: "mood", systemImage: "face.smiling", title: LocalizedStringKey(String(localized: "editWidgets.row.mood.title", defaultValue: "Mood check-in", comment: "Edit widgets sheet: title for the mood check-in widget row")), subtitle: LocalizedStringKey(String(localized: "editWidgets.row.mood.subtitle", defaultValue: "How you're feeling today", comment: "Edit widgets sheet: subtitle for the mood check-in widget row")), binding: $moodEnabled),
            Row(id: "nutrition", systemImage: "fork.knife", title: LocalizedStringKey(String(localized: "editWidgets.row.nutrition.title", defaultValue: "Nutrition today", comment: "Edit widgets sheet: title for the nutrition widget row")), subtitle: LocalizedStringKey(String(localized: "editWidgets.row.nutrition.subtitle", defaultValue: "Calories and macros vs today's target", comment: "Edit widgets sheet: subtitle for the nutrition widget row")), binding: $nutritionEnabled),
            Row(id: "goal", systemImage: "target", title: LocalizedStringKey(String(localized: "editWidgets.row.goal.title", defaultValue: "Sport goal", comment: "Edit widgets sheet: title for the sport goal widget row")), subtitle: LocalizedStringKey(String(localized: "editWidgets.row.goal.subtitle", defaultValue: "Your active goal's progress", comment: "Edit widgets sheet: subtitle for the sport goal widget row")), binding: $sportGoalEnabled),
            Row(id: "photos", systemImage: "photo.on.rectangle.angled", title: LocalizedStringKey(String(localized: "editWidgets.row.photos.title", defaultValue: "Photo progress", comment: "Edit widgets sheet: title for the photo progress widget row")), subtitle: LocalizedStringKey(String(localized: "editWidgets.row.photos.subtitle", defaultValue: "Goal photo comparison", comment: "Edit widgets sheet: subtitle for the photo progress widget row")), binding: $photoProgressEnabled),
            Row(id: "affirmation", systemImage: "sparkles", title: LocalizedStringKey(String(localized: "editWidgets.row.affirmation.title", defaultValue: "Affirmation", comment: "Edit widgets sheet: title for the affirmation widget row")), subtitle: LocalizedStringKey(String(localized: "editWidgets.row.affirmation.subtitle", defaultValue: "A kind line, new each morning", comment: "Edit widgets sheet: subtitle for the affirmation widget row")), binding: $affirmationEnabled)
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "editWidgets.intro", defaultValue: "Toggle what shows on home. Log workout is always there.", comment: "Edit widgets sheet: intro copy above the list of toggleable widgets"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(SomaTokens.ink3)

                    VStack(spacing: 8) {
                        ForEach(rows) { row in
                            HStack(spacing: 12) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(SomaTokens.ink5)
                                Image(systemName: row.systemImage)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(row.binding.wrappedValue ? SomaTokens.accent : SomaTokens.ink4)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(row.binding.wrappedValue ? SomaTokens.ink : SomaTokens.ink4)
                                    Text(row.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(SomaTokens.ink5)
                                }
                                Spacer()
                                Toggle(isOn: row.binding) { EmptyView() }
                                    .labelsHidden()
                                    .tint(SomaTokens.accent)
                            }
                            .padding(13)
                            .glassCardFlat(cornerRadius: SomaTokens.rRow)
                        }
                    }

                    Text(String(localized: "editWidgets.footer", defaultValue: "Changes apply instantly.", comment: "Edit widgets sheet: footer note under the widget list"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(SomaTokens.ink5)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(20)
            }
            .somaSheetBackground()
            .navigationTitle(String(localized: "editWidgets.navigationTitle", defaultValue: "Your widgets", comment: "Edit widgets sheet: navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "editWidgets.done", defaultValue: "Done", comment: "Edit widgets sheet: done button in the toolbar")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
