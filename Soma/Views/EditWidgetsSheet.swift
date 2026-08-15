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
    @Binding var sportGoalEnabled: Bool
    @Binding var photoProgressEnabled: Bool

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
            Row(id: "water", systemImage: "drop.fill", title: "Water tracker", subtitle: "Goal 8 glasses · tap to change", binding: $waterEnabled),
            Row(id: "sleep", systemImage: "moon.fill", title: "Sleep summary", subtitle: "Last night, on home", binding: $sleepEnabled),
            Row(id: "streak", systemImage: "flame.fill", title: "Workout streak", subtitle: "Consecutive days trained", binding: $streakEnabled),
            Row(id: "tasks", systemImage: "checklist", title: "Daily tasks", subtitle: "Checklist with today's to-dos", binding: $dailyTasksEnabled),
            Row(id: "mood", systemImage: "face.smiling", title: "Mood check-in", subtitle: "How you're feeling today", binding: $moodEnabled),
            Row(id: "goal", systemImage: "target", title: "Sport goal", subtitle: "Your active goal's progress", binding: $sportGoalEnabled),
            Row(id: "photos", systemImage: "photo.on.rectangle.angled", title: "Photo progress", subtitle: "Goal photo comparison", binding: $photoProgressEnabled)
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Toggle what shows on home. Log workout is always there.")
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

                    Text("Changes apply instantly.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(SomaTokens.ink5)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(20)
            }
            .somaSheetBackground()
            .navigationTitle("Your widgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
