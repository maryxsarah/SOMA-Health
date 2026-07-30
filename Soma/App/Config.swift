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
    /// The result is never shown to the user (no "AI analyzed your photos"
    /// screen) -- it's a silent input to workout-plan generation only.
    static let enableBodyPhotoVisionAnalysis = true

    private static func string(for key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}
