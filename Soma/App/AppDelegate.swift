import FirebaseCore
import PostHog
import SuperwallKit
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Analytics runs ONLY in Release builds (TestFlight/App Store) --
        // local Debug runs must not pollute GA4/PostHog with dev data.
        // Within Release, both SDKs are still guarded on their config
        // being present (gitignored plist / xcconfig key), so a keyless
        // checkout launches fine instead of crashing at configure.
        #if !DEBUG
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
        if !Config.posthogAPIKey.isEmpty {
            let postHogConfig = PostHogConfig(apiKey: Config.posthogAPIKey, host: Config.posthogHost.absoluteString)
            PostHogSDK.shared.setup(postHogConfig)
        }
        #endif

        AnalyticsManager.shared.appOpened()

        // Custom PurchaseController: Soma's own SubscriptionManager stays
        // the single reader of Transaction.currentEntitlements (needed for
        // the Supabase subscription_tier sync generation limits depend on)
        // and pushes the result into Superwall.shared.subscriptionStatus --
        // see SubscriptionManager.refreshEntitlement(). Deliberately NOT
        // gated on the key being present: `Superwall.shared` asserts in
        // Debug when unconfigured, so skipping configure would crash every
        // keyless dev build at the first register() call. An empty key just
        // logs errors and lets register() fall through to its feature block.
        Superwall.configure(apiKey: Config.superwallAPIKey, purchaseController: SomaPurchaseController.shared)
        Superwall.shared.delegate = SuperwallEventForwarder.shared
        // A returning signed-in user (persisted session from the keychain,
        // not a fresh interactive sign-in) still needs to be identified on
        // every cold launch -- the interactive sign-in call sites
        // (SessionManager) only fire once, at the moment of login/signup.
        if let userId = SupabaseClient.shared.currentUserID {
            Superwall.shared.identify(userId: userId)
        }

        // BGTaskScheduler registration must happen synchronously here,
        // before this method returns -- it cannot live in a SwiftUI .task.
        BackgroundTaskManager.shared.register()
        UNUserNotificationCenter.current().delegate = self

        // Re-arm Trigger A (HealthKit observer) on every launch if the
        // user previously connected Apple Health and is still signed in.
        if HealthKitManager.isAvailable, SupabaseClient.shared.isSignedIn {
            HealthKitManager.shared.startObserving {
                Task {
                    await Self.handleWakeTrigger()
                }
            }
        }

        return true
    }

    /// Trigger A: the HealthKit observer fired (e.g. the Watch marked
    /// sleep as ended). Generates today's recommendation and fires the
    /// local notification immediately, then marks "sent today" so
    /// Trigger B (the BGAppRefreshTask fallback) doesn't double-send.
    private static func handleWakeTrigger() async {
        guard !NotificationManager.shared.hasSentToday() else { return }
        guard SupabaseClient.shared.isSignedIn else { return }

        let snapshot = await HealthKitManager.shared.fetchTodaysMetrics()
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
            // Trigger B (BGAppRefreshTask fallback) will retry later today.
        }
    }

    private static func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
