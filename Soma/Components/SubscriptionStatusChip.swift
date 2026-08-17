import SwiftUI

/// The gold subscription plaque from the dashboard status row (design
/// 15a's governing spec; demonstrated on 5a/3a/3e): ONE chip, three
/// states -- solid gold "PRO" for a paid subscription, solid gold
/// "N DAYS" counting down a referral/promo bonus, glass-gold
/// "TRIAL · N DAYS" during the free trial. Plain free users see nothing,
/// never a locked icon -- resolve() returns nil and the caller renders
/// no chip at all.
enum SubscriptionChipState: Equatable {
    case paid
    case trial(daysLeft: Int?)
    case promoBonus(daysLeft: Int)

    /// The one place the status-row state is decided, so Home and any
    /// future surface agree: paid wins (PRO), a running trial beats the
    /// bonus countdown, bonus shows only while actually in the future.
    static func resolve(isSubscribed: Bool, isInTrial: Bool, expirationDate: Date?, referralBonusUntil: Date?) -> SubscriptionChipState? {
        if isSubscribed && !isInTrial { return .paid }
        if isInTrial { return .trial(daysLeft: daysLeft(until: expirationDate)) }
        if let bonusDays = daysLeft(until: referralBonusUntil), bonusDays > 0 { return .promoBonus(daysLeft: bonusDays) }
        return nil
    }

    private static func daysLeft(until date: Date?) -> Int? {
        guard let date, date > Date() else { return nil }
        // Ceiling, not floor -- "expires in 2 days 23 h" must read
        // "3 DAYS": the countdown states how long access still works.
        return max(Int(ceil(date.timeIntervalSinceNow / 86400)), 1)
    }
}

struct SubscriptionStatusChip: View {
    let state: SubscriptionChipState
    var action: () -> Void = {}

    /// The design's gold pair (#F5CD78 -> #C98A1E); the deep stop is
    /// SomaTokens.warn exactly.
    private static let goldLight = Color(red: 0xF5 / 255, green: 0xCD / 255, blue: 0x78 / 255)

    private var isGlass: Bool {
        if case .trial = state { return true }
        return false
    }

    private var label: String {
        switch state {
        case .paid:
            String(localized: "subscriptionChip.pro", defaultValue: "PRO", comment: "Status-row chip label for a paid subscription")
        case .trial(let daysLeft):
            if let daysLeft {
                String(localized: "subscriptionChip.trialDays", defaultValue: "TRIAL · \(daysLeft) DAYS", comment: "Status-row chip label during a free trial, with days remaining")
            } else {
                String(localized: "subscriptionChip.trial", defaultValue: "TRIAL", comment: "Status-row chip label during a free trial when the days remaining are unknown")
            }
        case .promoBonus(let daysLeft):
            String(localized: "subscriptionChip.bonusDays", defaultValue: "\(daysLeft) DAYS", comment: "Status-row chip label counting down a referral/promo free-access bonus")
        }
    }

    private var accessibilityText: String {
        switch state {
        case .paid:
            String(localized: "subscriptionChip.pro.accessibility", defaultValue: "Soma Premium active. Opens subscription management.", comment: "VoiceOver label for the PRO chip")
        case .trial:
            String(localized: "subscriptionChip.trial.accessibility", defaultValue: "Free trial running. Opens the subscribe screen.", comment: "VoiceOver label for the trial chip")
        case .promoBonus(let daysLeft):
            String(localized: "subscriptionChip.bonus.accessibility", defaultValue: "\(daysLeft) days of free access left. Opens the subscribe screen.", comment: "VoiceOver label for the promo-bonus chip")
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "crown")
                    .font(.system(size: 9, weight: .bold))
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .lineLimit(1)
            }
            .foregroundStyle(isGlass ? SomaTokens.warn : .white)
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background {
                if isGlass {
                    // Glass-gold: white glass body, inner white ring,
                    // outer gold hairline -- the trial reads as "almost
                    // gold", per the mockup.
                    Capsule()
                        .fill(Color.white.opacity(0.55))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                        .overlay(Capsule().stroke(SomaTokens.warn.opacity(0.45), lineWidth: 1).padding(-0.5))
                        .shadow(color: SomaTokens.warn.opacity(0.18), radius: 2.5, x: 0, y: 2)
                } else {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Self.goldLight.opacity(0.95), SomaTokens.warn.opacity(0.95)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 1))
                        .shadow(color: SomaTokens.warn.opacity(0.28), radius: 2.5, x: 0, y: 2)
                }
            }
            // The 20pt visual height is the design's; the tap target
            // still needs to clear ~44pt.
            .contentShape(Rectangle().inset(by: -12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityText))
    }
}

#Preview {
    VStack(spacing: 14) {
        SubscriptionStatusChip(state: .paid)
        SubscriptionStatusChip(state: .promoBonus(daysLeft: 5))
        SubscriptionStatusChip(state: .trial(daysLeft: 3))
    }
    .padding()
    .somaBackground()
}
