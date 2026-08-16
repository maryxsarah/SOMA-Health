import SwiftUI

/// Screen 3 -- Notification Enablement.
struct NotificationEnablementView: View {
    @EnvironmentObject private var appState: AppState

    @State private var wakeTime: Date =
        Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var notificationsEnabled = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Text(String(localized: "notificationEnablement.headline", defaultValue: "Never wonder what to do today.", comment: "Notification enablement screen: headline"))
                .font(Theme.display)
                .multilineTextAlignment(.center)
                .padding(.top, 56)
                .padding(.horizontal, 24)

            CardView {
                Text(notificationsEnabled
                    ? String(localized: "notificationEnablement.enabledTitle", defaultValue: "Notifications enabled", comment: "Notification enablement screen: card title once notifications are enabled")
                    : String(localized: "notificationEnablement.disabledTitle", defaultValue: "Enable notifications", comment: "Notification enablement screen: card title before notifications are enabled"))
                    .font(.body.bold())
                Text(String(localized: "notificationEnablement.body", defaultValue: "Soma sends your morning training recommendation, plus a few light check-ins through the day -- a movement nudge, an evening reminder if today's workout is still open, and a quick progress update.", comment: "Notification enablement screen: explanation of what notifications will be sent"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                PillButton(
                    title: LocalizedStringKey(String(localized: "notificationEnablement.cta.enable", defaultValue: "Enable Notifications", comment: "Notification enablement screen: CTA button to request notification permission")),
                    style: notificationsEnabled ? .connected : .primary
                ) {
                    Task {
                        do {
                            try await NotificationManager.shared.requestAuthorization()
                            notificationsEnabled = true
                            AnalyticsManager.shared.notificationsEnabled()
                            // Same-day coverage: the wake-time-triggered
                            // refresh (BackgroundTaskManager) won't run
                            // again until tomorrow morning, so without
                            // this a user enabling notifications mid-day
                            // would see none of today's engagement
                            // notifications. Best-effort/fire-and-forget --
                            // scheduleToday already skips any time that's
                            // already passed today.
                            Task { await NotificationManager.shared.scheduleTodaysEngagementNotifications() }
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            CardView {
                Text(String(localized: "notificationEnablement.wakeTimeQuestion", defaultValue: "What time do you usually wake up?", comment: "Notification enablement screen: prompt above the wake-time picker"))
                    .font(.body.bold())
                DatePicker(String(localized: "notificationEnablement.wakeTimeLabel", defaultValue: "Wake time", comment: "Notification enablement screen: accessibility label for the wake-time picker (visually hidden)"), selection: $wakeTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            PillButton(title: LocalizedStringKey(String(localized: "notificationEnablement.cta.finish", defaultValue: "Finish Setup", comment: "Notification enablement screen: CTA button completing onboarding setup")), isEnabled: !isSaving) {
                finishSetup()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .somaBackground()
    }

    private func finishSetup() {
        isSaving = true
        errorMessage = nil

        Task {
            defer { isSaving = false }
            do {
                guard let userID = SupabaseClient.shared.currentUserID else {
                    throw SupabaseError.notSignedIn
                }
                try await SupabaseClient.shared.upsertUser(
                    id: userID,
                    wakeTimePref: Self.timeString(from: wakeTime)
                )
                // Arms Trigger B (the BGAppRefreshTask fallback) around
                // this wake time; Trigger A (HealthKit observer) is
                // already armed in AppDelegate if Apple Health was connected.
                BackgroundTaskManager.shared.rememberWakeTime(wakeTime)
                BackgroundTaskManager.shared.scheduleNextRefresh(wakeTime: wakeTime)
                // onboarding_complete is only set true at the end of the
                // post-setup sequence (referral code -> loading -> plan
                // summary -> consent -> paywall), not here.
                appState.advanceToPostSetup()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}

#Preview {
    NotificationEnablementView()
        .environmentObject(AppState())
}
