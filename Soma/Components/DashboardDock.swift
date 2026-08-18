import SwiftUI

/// One action in the floating quick-action dock or the "More" sheet.
struct DashboardDockAction: Identifiable {
    enum Style { case lens, gel }

    let id: String
    /// Asset-catalog template image (`soma.dock.*`) -- the mockup's own
    /// thin 1.7pt outline icons, no filled SF Symbol matches them.
    var assetImage: String? = nil
    /// SF Symbol fallback, only for actions with no drawn icon yet.
    var systemImage: String? = nil
    var style: Style = .lens
    let label: LocalizedStringKey
    let accessibilityLabel: String
    /// Stable XCUITest hook, only set where a test already depends on one
    /// (e.g. "profile-button" -- Profile used to be a persistent top-row
    /// gear icon; it now only lives in the More sheet, but the existing
    /// UI tests still look it up by this exact identifier).
    var accessibilityIdentifier: String? = nil
    let action: () -> Void
}

/// The floating glass dock -- a fixed row of icon buttons pinned to the
/// bottom of the dashboard (per `soma-glass-tokens.css`: "quick actions
/// live in the floating glass dock"). Each icon is its own raised glass
/// lens (or, for the primary slot, a filled gel) inside an outer frosted
/// capsule.
struct DashboardDockView: View {
    let actions: [DashboardDockAction]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(actions) { item in
                Button(action: item.action) {
                    iconView(item)
                        .foregroundStyle(item.style == .gel ? Color.white : SomaTokens.accent)
                        .frame(width: 50, height: 50)
                        .background { buttonSurface(item.style) }
                }
                .buttonStyle(SomaNavPillButtonStyle())
                .accessibilityLabel(item.accessibilityLabel)
                .modifier(OptionalAccessibilityIdentifier(id: item.accessibilityIdentifier))
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .glassDock()
    }

    @ViewBuilder
    private func iconView(_ item: DashboardDockAction) -> some View {
        if let asset = item.assetImage {
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
        } else if let symbol = item.systemImage {
            // Outline variant + regular weight -- closest SF Symbol
            // approximation of the mockup's 1.7pt stroke look, for actions
            // that don't have a drawn icon (yet).
            Image(systemName: symbol).font(.system(size: 19, weight: .regular))
        }
    }

    @ViewBuilder
    private func buttonSurface(_ style: DashboardDockAction.Style) -> some View {
        if style == .gel {
            Circle().fill(Color.clear).glassGel(.blue, cornerRadius: 25)
        } else {
            Circle().fill(Color.clear).glassLens(cornerRadius: 25)
        }
    }
}

/// `.accessibilityIdentifier` has no optional-string overload -- this
/// no-ops when `id` is nil instead of stamping every dock/More-sheet
/// button with an empty identifier. Internal (not private): reused by
/// `MoreActionsSheet`.
struct OptionalAccessibilityIdentifier: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
    }
}
