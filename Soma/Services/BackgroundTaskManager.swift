import BackgroundTasks
import Foundation

/// Trigger B: a BGAppRefreshTask scheduled around the user's
/// wake_time_pref, covering every user (not just those with a paired
/// Watch) and any day Trigger A (the HealthKit observer) doesn't fire.
///
/// iOS background execution timing is best-effort only -- earliestBeginDate
/// is a lower bound, not a promise. The system decides the actual fire
/// time based on usage patterns, battery, etc. This is expected and
/// acceptable for V1.
final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    private let identifier = Config.backgroundTaskIdentifier
    private let wakeTimeDefaultsKey = "com.soma.app.wakeTime"

    /// Must run synchronously during app launch (before
    /// applicationDidFinishLaunching returns) -- BGTaskScheduler requires
    /// registration before the app finishes launching, so this lives in
    /// AppDelegate, not a SwiftUI `.task`.
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handleRefresh(task: refreshTask)
        }
    }

    func rememberWakeTime(_ wakeTime: Date) {
        UserDefaults.standard.set(wakeTime, forKey: wakeTimeDefaultsKey)
    }

    /// Submits a one-shot request targeting the next occurrence of the
    /// given wake time (today if still upcoming, else tomorrow).
    func scheduleNextRefresh(wakeTime: Date) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Self.nextOccurrence(of: wakeTime)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleRefresh(task: BGAppRefreshTask) {
        // Re-schedule tomorrow's request FIRST: BGAppRefreshTaskRequest is
        // one-shot, so skipping this would silently kill the fallback
        // after its first run.
        let wakeTime = UserDefaults.standard.object(forKey: wakeTimeDefaultsKey) as? Date ?? Self.defaultWakeTime()
        scheduleNextRefresh(wakeTime: wakeTime)

        let work = Task {
            await performCheckAndNotify()
        }
        task.expirationHandler = {
            work.cancel()
        }
        Task {
            await work.value
            task.setTaskCompleted(success: true)
        }
    }

    private func performCheckAndNotify() async {
        guard !Task.isCancelled else { return }
        guard !NotificationManager.shared.hasSentToday() else { return }
        guard SupabaseClient.shared.isSignedIn else { return }

        let snapshot = HealthKitManager.isAvailable
            ? await HealthKitManager.shared.fetchTodaysMetrics()
            : nil
        guard !Task.isCancelled else { return }

        do {
            let recommendation = try await SupabaseClient.shared.invokeGenerateRecommendation(
                date: Self.todayDateString(),
                healthkit: snapshot
            )
            await NotificationManager.shared.scheduleImmediateNotification(
                category: recommendation.category,
                message: recommendation.message
            )
            NotificationManager.shared.markSentToday()
        } catch {
            // Best-effort: tomorrow's fallback (or a manual "Check now" tap
            // on Home) will retry. Nothing to surface to the user here --
            // there's no UI attached to a background task.
        }
    }

    private static func nextOccurrence(of wakeTime: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: wakeTime)
        let next = calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime)
        return next ?? Date().addingTimeInterval(24 * 3600)
    }

    private static func defaultWakeTime() -> Date {
        Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private static func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
