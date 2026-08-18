import SwiftUI

/// "Custom training — pick sport type" (5b). Lists the sports from the
/// real Sport Goals catalog (`SportCatalog.sports`, already loaded by
/// `HomeView` for the goal flow) -- no invented sport list, no
/// invented "sessions" counts, since those aren't backed by real data yet.
struct CustomTrainingPickerSheet: View {
    let sports: [Sport]
    let selectedSportId: String?
    let onSelect: (Sport) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(String(localized: "customTrainingPicker.subtitle", defaultValue: "Pick a sport type — Soma still scales volume and intensity to today's readiness.", comment: "Custom training picker: subtitle explaining the sport type picker"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(SomaTokens.ink3)

                    if sports.isEmpty {
                        Text(String(localized: "customTrainingPicker.empty", defaultValue: "No sport types yet — add one from Sport Goals first.", comment: "Custom training picker: empty state shown when there are no sport types yet"))
                            .font(.system(size: 13))
                            .foregroundStyle(SomaTokens.ink4)
                            .padding(.top, 8)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(sports) { sport in
                                sportTile(sport, isSelected: sport.id == selectedSportId)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .somaSheetBackground()
            .navigationTitle(String(localized: "customTrainingPicker.navigationTitle", defaultValue: "Custom training", comment: "Custom training picker: navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "customTrainingPicker.close", defaultValue: "Close", comment: "Custom training picker: close button in the toolbar")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func sportTile(_ sport: Sport, isSelected: Bool) -> some View {
        Button {
            onSelect(sport)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: sport.iconSystemName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? .white : SomaTokens.accent)
                Text(sport.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isSelected ? .white : SomaTokens.inkRowTitle)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    Color.clear.glassGel(.blue)
                } else {
                    Color.clear.glassLens()
                }
            }
        }
        .buttonStyle(.plain)
    }
}
