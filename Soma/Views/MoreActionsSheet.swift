import SwiftUI

/// "All actions" (4h) -- every quick action, not just the dock's pinned +
/// configurable slots. Tapping a tile dismisses this sheet and hands the
/// tapped action back to the caller, which fires it from the dock sheet's
/// own `onDismiss` -- the same chain-sheets-via-onDismiss pattern used
/// elsewhere in this app (see `GymPhotoWorkoutView`'s seeded-detail flow)
/// so two sheets never fight to present at once.
struct MoreActionsSheet: View {
    let actions: [DashboardDockAction]
    let onSelect: (DashboardDockAction) -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(actions) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            VStack(spacing: 7) {
                                icon(for: item)
                                    .foregroundStyle(SomaTokens.accent)
                                Text(item.label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(SomaTokens.inkRowTitle)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .glassLens(cornerRadius: SomaTokens.rCard)
                        }
                        .buttonStyle(.plain)
                        .modifier(OptionalAccessibilityIdentifier(id: item.accessibilityIdentifier))
                    }
                }
                .padding(20)
            }
            .somaSheetBackground()
            .navigationTitle("All actions")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func icon(for item: DashboardDockAction) -> some View {
        if let asset = item.assetImage {
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 21, height: 21)
        } else if let symbol = item.systemImage {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .medium))
        }
    }
}
