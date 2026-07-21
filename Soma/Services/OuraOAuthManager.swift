import AuthenticationServices
import UIKit

/// Oura API v2 OAuth2 auth-code flow via ASWebAuthenticationSession. Same
/// pattern as WhoopOAuthManager -- the app never sees a client_secret;
/// token exchange happens server-side in store-wearable-token.
@MainActor
final class OuraOAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OuraOAuthManager()

    private static let authorizeURL = "https://cloud.ouraring.com/oauth/authorize"
    // "daily" scope covers the daily_readiness endpoint used by
    // generate-recommendation. Verify against the current Oura developer
    // portal at setup time if this changes.
    private static let scopes = "daily"

    private var activeSession: ASWebAuthenticationSession?

    func connect() async throws {
        let verifier = OAuthPKCE.generateCodeVerifier()
        let challenge = OAuthPKCE.codeChallenge(for: verifier)
        let state = OAuthPKCE.randomState()

        var components = URLComponents(string: Self.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Config.ouraClientID),
            URLQueryItem(name: "redirect_uri", value: Config.ouraRedirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        let code = try await presentSession(url: components.url!, expectedState: state)
        try await SupabaseClient.shared.exchangeAndStoreWearableToken(
            provider: "oura",
            code: code,
            codeVerifier: verifier,
            redirectURI: Config.ouraRedirectURI
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
                guard
                    let callbackURL,
                    let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                    let code = components.queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    continuation.resume(throwing: OAuthError.missingCode)
                    return
                }
                let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value
                guard returnedState == expectedState else {
                    continuation.resume(throwing: OAuthError.stateMismatch)
                    return
                }
                continuation.resume(returning: code)
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
