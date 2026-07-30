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

    static let backgroundTaskIdentifier = "com.soma.app.refresh"

    /// Gated pending legal review of body-photo storage/consent copy.
    /// Flipping this to true is the entire "ship it" step -- no other code
    /// changes needed; onboarding and Profile show zero trace of the
    /// feature while it's false.
    static let enableBodyPhotoUpload = false

    /// Separate flag for AI vision analysis of goal/current body photos --
    /// deliberately independent of `enableBodyPhotoUpload` above, so the
    /// already-working upload/history/comparison feature is never held
    /// hostage to this materially riskier addition.
    ///
    /// UNBUILT. No vision-analysis code exists yet -- this flag is a
    /// placeholder documenting what flipping it would require, not
    /// something safe to flip on its own:
    ///   1. A new `analyze-body-photo` Edge Function (would reuse
    ///      _shared/openai.ts's existing Responses-API pattern from
    ///      analyze-gym-photo, but MUST be its own function -- body photos
    ///      are a different, more sensitive data category than gym-
    ///      equipment photos, with their own consent/retention/vendor-
    ///      disclosure requirements).
    ///   2. Server-side enforcement of this flag (an env var the function
    ///      checks itself) -- never trust a client-side check alone for a
    ///      feature this sensitive.
    ///   3. Structured (categorical, non-clinical) output only -- map to
    ///      the existing GoalTag set rather than inventing new categories
    ///      or numeric/clinical-sounding scores.
    ///   4. Explicit disclosure of the vision-model vendor in the Privacy
    ///      Policy (LegalContent.swift + docs/privacy.html), and a bumped
    ///      LegalContent.currentVersion so existing users re-acknowledge.
    ///   5. Legal sign-off specifically on the biometric-data-law question
    ///      (e.g. BIPA-style statutes) BEFORE this ships -- a separate,
    ///      narrower review than the general privacy/liability pass that
    ///      already covers plain photo storage.
    /// Do not flip this to true without all five in place.
    static let enableBodyPhotoVisionAnalysis = false

    private static func string(for key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}
