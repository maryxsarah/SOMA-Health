import UserNotifications

/// Local notifications only -- no APNs, per spec.
final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let sentDateDefaultsKey = "com.soma.app.lastNotificationSentDate"

    func requestAuthorization() async throws {
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Fires immediately (nil trigger) with the day's fixed category/message.
    func scheduleImmediateNotification(category: RecommendationCategory, message: String) async {
        let content = UNMutableNotificationContent()
        content.title = category.displayTitle
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "daily-recommendation-\(todayKey())",
            content: content,
            trigger: nil
        )

        await withCheckedContinuation { continuation in
            center.add(request) { _ in continuation.resume() }
        }
    }

    /// Schedules a one-time reminder to upgrade, fired when a referral
    /// code's free-access bonus period ends (e.g. "somafirst" grants 3
    /// weeks with no payment method required, then this nudges them to
    /// subscribe). Re-redeeming another code reschedules this same
    /// notification rather than stacking multiple reminders, since the
    /// identifier is fixed.
    func scheduleUpgradeReminder(at date: Date) async {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your free access is ending"
        content.body = "Subscribe to Soma Premium to keep getting your full daily plan -- workouts, step targets, and more."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "referral-upgrade-reminder",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )

        await withCheckedContinuation { continuation in
            center.add(request) { _ in continuation.resume() }
        }
    }

    // MARK: - "Already sent today" flag
    //
    // Shared by both the HealthKit-observer trigger and the
    // BGAppRefreshTask fallback so a day never gets double-notified.

    func hasSentToday() -> Bool {
        UserDefaults.standard.string(forKey: sentDateDefaultsKey) == todayKey()
    }

    func markSentToday() {
        UserDefaults.standard.set(todayKey(), forKey: sentDateDefaultsKey)
    }

    private func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
