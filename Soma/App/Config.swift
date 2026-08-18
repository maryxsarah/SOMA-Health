import Foundation

/// Reads environment-specific values injected into Info.plist via xcconfig
/// ($(VAR) substitution). See Config/Config.sample.xcconfig and SETUP.md.
enum Config {
    static var supabaseURL: URL {
        URL(string: "https://\(string(for: "SUPABASE_HOST"))")!
    }

    static var supabaseAnonKey: String {
        string(for: "SUPABASE_ANON_KEY")
    }

    static var whoopClientID: String {
        string(for: "WHOOP_CLIENT_ID")
    }

    static var ouraClientID: String {
        string(for: "OURA_CLIENT_ID")
    }

    static var posthogAPIKey: String {
        string(for: "POSTHOG_API_KEY")
    }

    static var posthogHost: URL {
        URL(string: "https://\(string(for: "POSTHOG_HOST"))")!
    }

    static var superwallAPIKey: String {
        string(for: "SUPERWALL_API_KEY")
    }

    /// Fixed by convention (matches CFBundleURLTypes in Info.plist), not
    /// per-environment config -- these never need to change per deployment.
    static let oauthURLScheme = "soma"
    static let whoopRedirectURI = "soma://oauth-callback/whoop"
    static let ouraRedirectURI = "soma://oauth-callback/oura"
    /// Sign-in (not a data connection like Whoop/Oura) via Supabase's own
    /// /authorize endpoint acting as the OAuth intermediary to Google --
    /// this exact URL must also be added to the Supabase Dashboard's
    /// Auth -> URL Configuration -> Redirect URLs allow-list.
    static let googleRedirectURI = "soma://oauth-callback/google"

    /// Where the branded signup-confirmation email's "Commit now to your
    /// goal" button lands -- a universal link (not the `soma://` custom
    /// scheme above), so a device without the app installed falls through
    /// to Safari instead of the link silently doing nothing. Requires:
    /// 1) the Associated Domains entitlement (Soma.entitlements),
    /// 2) an apple-app-site-association file hosted at this domain (see
    ///    deep-linking/README.md), and
    /// 3) this exact URL added to Supabase Dashboard's Auth -> URL
    ///    Configuration -> Redirect URLs allow-list, same as
    ///    googleRedirectURI above. See SomaApp's onOpenURL for the
    ///    handler and supabase/email-templates/confirm-signup.html for
    ///    the template that links here via {{ .ConfirmationURL }}.
    ///
    /// www, not bare -- soma4health.com 308-redirects to
    /// www.soma4health.com site-wide, and Apple's swcd does not follow
    /// redirects when fetching apple-app-site-association, so the bare
    /// domain would never actually verify. Confirmed 2026-08-10.
    static let emailConfirmationRedirectURL = "https://www.soma4health.com/auth/confirm"

    static let backgroundTaskIdentifier = "com.soma.app.refresh"

    /// Goal/current body photo upload, history, and comparison slider.
    /// Live -- the Privacy Policy discloses this (see LegalContent.swift's
    /// "Photographs you choose to add of your current body and goal body"
    /// bullet).
    static let enableBodyPhotoUpload = true

    /// AI vision analysis comparing the user's goal/current body photos --
    /// deliberately independent of `enableBodyPhotoUpload` above, so that
    /// feature was never held hostage to this materially riskier addition.
    ///
    /// Live as of 2026-07-31. What shipped, matching the five prerequisites
    /// this flag used to gate:
    ///   1. `analyze-body-photo` Edge Function (its own function, not
    ///      folded into analyze-gym-photo -- body photos are a different,
    ///      more sensitive, already-stored data category).
    ///   2. Server-side enforcement via `ENABLE_BODY_PHOTO_VISION_ANALYSIS`
    ///      (a Supabase secret/env var the function checks itself) --
    ///      this client-side flag is never trusted alone.
    ///   3. Structured, categorical output only -- mapped to the existing
    ///      `GoalTag` set (`_shared/goalTags.ts`), no numeric or
    ///      clinical-sounding score anywhere in the schema.
    ///   4. Privacy Policy discloses both the photo storage itself and the
    ///      OpenAI vendor use specifically for this comparison (two new
    ///      bullets, `LegalContent.currentVersion` bumped).
    ///   5. Legal sign-off on the biometric-data-law question was the
    ///      product owner's own call to accept, not blocked on external
    ///      review -- see the epic's plan notes.
    ///
    /// UPDATE (2026-08-05): originally "never shown to the user (no 'AI
    /// analyzed your photos' screen)" -- reversed by a second product-owner
    /// decision so the Progress screen (GoalBodyProgressView) can show the
    /// result directly, e.g. "Your plan is shaped toward: leaner & toned."
    /// Uses the same plain-language GoalTag/TrainingEmphasis copy already
    /// shown as goal options elsewhere in the app, not a clinical score --
    /// but this IS new user-facing exposure of prerequisite #3's output,
    /// so a Privacy Policy language check is worth doing even though no
    /// new data collection or vendor was added.
    static let enableBodyPhotoVisionAnalysis = true

    /// Sport goal programs -- compile-time safety net only. Live to every
    /// user as of 2026-08-16 (`sports.status = 'live'`, no opt-in); this
    /// flag stays as the emergency kill switch (SGP-A7).
    static let enableSportGoals = true

    /// Opt-in cycle-phase tracking (Phase 5: see
    /// docs/coaching-personalization-plan.md) -- gates whether ProfileView's
    /// "Cycle tracking" row/editor even appears. Dark-launchable kill
    /// switch, same reasoning as enableBodyPhotoVisionAnalysis/
    /// enableSportGoals above, for data this sensitive. No server-side
    /// gate needed alongside it: unlike analyze-body-photo, nothing in
    /// this feature calls a vendor API there's a key/cost to protect --
    /// generate-workout-plan's own deriveCyclePhase already fails closed to
    /// "no guidance" for anyone with no last_period_start_date on file,
    /// which is exactly what disabling this flag client-side achieves.
    static let enableCyclePhaseTracking = true

    private static func string(for key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}
