import Foundation
import CryptoKit

/// PKCE helpers shared by the Whoop and Oura auth-code flows. Whoop's docs
/// don't confirm PKCE support and Oura's confidential-client flow doesn't
/// strictly require it either, but sending code_challenge/code_verifier is
/// harmless if the provider ignores it, and free defense-in-depth if not.
enum OAuthPKCE {
    static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URLEncode(Data(bytes))
    }

    static func codeChallenge(for verifier: String) -> String {
        let hashed = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(hashed))
    }

    static func randomState() -> String {
        generateCodeVerifier()
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum OAuthError: LocalizedError {
    case missingCode
    case stateMismatch
    /// The provider's callback carried an explicit `error` (and often
    /// `error_description`) param instead of `code` -- e.g. the user denied
    /// consent, or the app's registered redirect_uri doesn't match what
    /// Whoop/Oura have on file. Surfaced verbatim rather than collapsed
    /// into the generic .missingCode message below, which used to hide
    /// exactly the information needed to diagnose a failed connect.
    case providerError(String)

    var errorDescription: String? {
        switch self {
        case .missingCode:
            String(localized: "oauth.error.missingCode", defaultValue: "No authorization code was returned.", comment: "Error shown when an OAuth connect flow (Whoop/Oura) doesn't return an authorization code")
        case .stateMismatch:
            String(localized: "oauth.error.stateMismatch", defaultValue: "OAuth state mismatch -- possible interception, aborting.", comment: "Error shown when an OAuth connect flow (Whoop/Oura) returns a state parameter that doesn't match what was sent")
        case .providerError(let message): message
        }
    }
}

extension OAuthPKCE {
    /// Parses a provider's OAuth callback URL. Three outcomes: a real
    /// `code` (success), an explicit `error`/`error_description` the
    /// provider chose to return (thrown as .providerError so the real
    /// reason reaches the UI instead of a generic "no code" message), or
    /// truly nothing usable (.missingCode -- e.g. a malformed callback).
    static func extractCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw OAuthError.missingCode
        }
        if let providerError = components.queryItems?.first(where: { $0.name == "error" })?.value {
            let description = components.queryItems?.first(where: { $0.name == "error_description" })?.value
            throw OAuthError.providerError(description.map { "\(providerError): \($0)" } ?? providerError)
        }
        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.missingCode
        }
        let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value
        guard returnedState == expectedState else {
            throw OAuthError.stateMismatch
        }
        return code
    }
}
