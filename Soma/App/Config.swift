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

    static let backgroundTaskIdentifier = "com.soma.app.refresh"

    private static func string(for key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}
