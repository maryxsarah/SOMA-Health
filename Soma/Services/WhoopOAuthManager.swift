import AuthenticationServices
import UIKit

/// Whoop OAuth2 auth-code flow via ASWebAuthenticationSession. The app
/// only ever sees the authorization `code` -- token exchange (which needs
/// a client_secret) happens server-side in store-wearable-token.
@MainActor
final class WhoopOAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WhoopOAuthManager()

    // NOTE: verify this path against the current Whoop developer dashboard
    // at setup time -- Whoop has changed API generation prefixes before.
    private static let authorizeURL = "https://api.prod.whoop.com/oauth/oauth2/auth"
    // recovery -> band; cycles -> day strain (recent training load cap);
    // sleep -> real sleep hours for the sleep safety cap; workout -> recent
    // high-strain session detection (also feeds the load cap).
    private static let scopes = "read:recovery read:cycles read:sleep read:workout offline"

    private var activeSession: ASWebAuthenticationSession?

    func connect() async throws {
        let verifier = OAuthPKCE.generateCodeVerifier()
        let challenge = OAuthPKCE.codeChallenge(for: verifier)
        let state = OAuthPKCE.randomState()

        var components = URLComponents(string: Self.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Config.whoopClientID),
            URLQueryItem(name: "redirect_uri", value: Config.whoopRedirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        let code = try await presentSession(url: components.url!, expectedState: state)
        try await SupabaseClient.shared.exchangeAndStoreWearableToken(
            provider: "whoop",
            code: code,
            codeVerifier: verifier,
            redirectURI: Config.whoopRedirectURI
        )
    }

    private func presentSession(url: URL, expectedState: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: Config.oauthURLScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: OAuthError.missingCode)
                    return
                }
                do {
                    let code = try OAuthPKCE.extractCode(from: callbackURL, expectedState: expectedState)
                    continuation.resume(returning: code)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            activeSession = session
            session.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
