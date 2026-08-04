import SwiftUI

/// The shared S1/S2 list block (README "Block anatomy"): standalone white
/// card, 46×46 icon plate, title + optional badge, note line, chevron.
private struct GoalListBlock: View {
    var icon: String
    var plateColor: Color = SomaTokens.accentSoft
    var iconColor: Color = SomaTokens.accent
    var title: String
    var badge: GoalKindBadge?
    var note: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(plateColor)
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(iconColor)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(SomaTokens.ink)
                        badge
                    }
                    Text(note)
                        .font(.system(size: 12.5))
                        .foregroundStyle(SomaTokens.ink3)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink5)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SomaTokens.rCard, style: .continuous)
                    .fill(SomaTokens.surface)
                    .shadow(color: SomaTokens.ink.opacity(0.06), radius: 2, y: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// S1 -- the sport list. One identical block per sport; adding a sport is
/// a config change, never a new screen.
struct SportListView: View {
    let catalog: SportCatalog
    let onSelectSport: (Sport) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NEW GOAL · ONE AT A TIME")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(SomaTokens.ink4)
                    Text("What do you train for?")
                        .font(Theme.display)
                }

                ForEach(catalog.sports) { sport in
                    GoalListBlock(
                        icon: sport.iconSystemName,
                        title: sport.name,
                        note: sportNote(sport)
                    ) {
                        onSelectSport(sport)
                    }
                }

                Text("Every sport has measurable goals — plus your own coach's task, tracked the same honest way.")
                    .font(.system(size: 12))
                    .foregroundStyle(SomaTokens.ink4)
                    .padding(.top, 4)
            }
            .padding(20)
        }
    }

    private func sportNote(_ sport: Sport) -> String {
        let goals = catalog.goals(for: sport)
        let count = goals.count
        let names = goals.map { $0.name.lowercased() }.joined(separator: ", ")
        guard count > 0 else { return "Your own coach's task" }
        return "\(count) \(count == 1 ? "goal" : "goals") · \(names)"
    }
}

/// S2 -- goals of ONE chosen sport, same block anatomy, plus the single
/// "Your own" coach's-task block under its own eyebrow. Generic: any sport
/// renders from the catalog, no per-sport screens.
struct GoalPickerView: View {
    let sport: Sport
    let catalog: SportCatalog
    let onSelectPreset: (SportGoal) -> Void
    let onSelectCustom: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(sport.name.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(SomaTokens.ink4)
                    Text("Pick a goal")
                        .font(Theme.display)
                    Text("One goal at a time — measured honestly, matched to your readiness every day.")
                        .font(.system(size: 14))
                        .foregroundStyle(SomaTokens.ink2)
                }

                VStack(spacing: 12) {
                    ForEach(catalog.goals(for: sport)) { goal in
                        GoalListBlock(
                            icon: sport.iconSystemName,
                            title: goal.name,
                            badge: GoalKindBadge(kind: goal.kind),
                            note: goal.promiseLine
                        ) {
                            onSelectPreset(goal)
                        }
                    }
                }

                // Padel's known sport risk -- one caption, this screen only.
                if sport.name.lowercased().contains("padel") {
                    Text("Certified eye protection is recommended for all padel play.")
                        .font(.system(size: 12))
                        .foregroundStyle(SomaTokens.ink3)
                }

                Text("YOUR OWN")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(SomaTokens.ink4)
                    .padding(.top, 4)

                GoalListBlock(
                    icon: "list.clipboard",
                    plateColor: SomaTokens.heartSoft,
                    iconColor: SomaTokens.heart,
                    title: "Your own — coach's task",
                    badge: .custom,
                    note: "Attach your coach's assignment — Soma schedules and tracks it"
                ) {
                    onSelectCustom()
                }

                Text("Got a task from your coach? Add it here — do the work in Soma and show them your progress: sessions and measurements export as one card.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(SomaTokens.ink3)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.surface3))
            }
            .padding(20)
        }
    }
}
