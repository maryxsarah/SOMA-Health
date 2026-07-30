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

    private static func string(for key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}
