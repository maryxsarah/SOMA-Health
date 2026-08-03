import SwiftUI

/// A1 -- one grouped list replaces sport picker + goal picker: slim sport
/// section headers, preset goal rows, and a per-sport "Your own" row.
struct GoalPickerView: View {
    let catalog: SportCatalog
    let onSelectPreset: (SportGoal) -> Void
    let onSelectCustom: (Sport) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pick a goal")
                        .font(Theme.display)
                    Text("One goal at a time — measured honestly, matched to your readiness every day.")
                        .font(.system(size: 14))
                        .foregroundStyle(SomaTokens.ink2)
                }

                ForEach(catalog.sports) { sport in
                    sportSection(sport)
                }
            }
            .padding(20)
        }
    }

    private func sportSection(_ sport: Sport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: sport.iconSystemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink3)
                Text(sport.name.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(SomaTokens.ink3)
            }
            .padding(.top, 4)

            // One caption line for padel only -- eye injuries are the
            // sport's known risk; certified protection cuts it sharply.
            if sport.name.lowercased().contains("padel") {
                Text("Certified eye protection is recommended for all padel play.")
                    .font(.system(size: 12))
                    .foregroundStyle(SomaTokens.ink3)
            }

            VStack(spacing: 8) {
                ForEach(catalog.goals(for: sport)) { goal in
                    goalRow(goal)
                }
                customRow(sport)
            }
        }
    }

    private func goalRow(_ goal: SportGoal) -> some View {
        Button {
            onSelectPreset(goal)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(SomaTokens.ink)
                    Text(goal.promiseLine)
                        .font(.system(size: 12))
                        .foregroundStyle(SomaTokens.ink3)
                        .lineLimit(1)
                }
                Spacer()
                GoalKindBadge(kind: goal.kind)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink5)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.surface))
        }
        .buttonStyle(.plain)
    }

    private func customRow(_ sport: Sport) -> some View {
        Button {
            onSelectCustom(sport)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SomaTokens.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your own — coach's task")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(SomaTokens.ink)
                    Text("Attach your coach's assignment — Soma schedules and tracks it")
                        .font(.system(size: 12))
                        .foregroundStyle(SomaTokens.ink3)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink5)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous)
                    .fill(SomaTokens.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous)
                            .strokeBorder(SomaTokens.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
