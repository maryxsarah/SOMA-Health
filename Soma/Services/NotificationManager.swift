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
