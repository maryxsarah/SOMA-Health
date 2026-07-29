import AuthenticationServices
import UIKit

/// Sign in with Google via Supabase's own /authorize endpoint acting as
/// the OAuth intermediary -- NOT the Google Sign-In SDK. This is a sign-in
/// method (parallel to Sign in with Apple), not a data connection like
/// Whoop/Oura, but reuses the exact same ASWebAuthenticationSession + PKCE
/// pattern already proven there (see WhoopOAuthManager), so this app adds
/// zero new third-party dependencies for it.
///
/// Unlike Whoop (where PKCE support is unconfirmed and `state` is the real
/// CSRF defense), Supabase's own auth server enforces PKCE properly: the
/// code exchange fails without the matching code_verifier, which is
/// already sufficient protection against interception -- no separate
/// `state` round-trip is needed here.
@MainActor
final class GoogleOAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleOAuthManager()

    private var activeSession: ASWebAuthenticationSession?

    /// Returns the new Supabase user ID on success.
    @discardableResult
    func signIn() async throws -> String {
        let verifier = OAuthPKCE.generateCodeVerifier()
        let challenge = OAuthPKCE.codeChallenge(for: verifier)

        var components = URLComponents(string: "\(Config.supabaseURL.absoluteString)/auth/v1/authorize")!
        components.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: Config.googleRedirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]

        let code = try await presentSession(url: components.url!)
        return try await SupabaseClient.shared.signInWithGoogle(code: code, codeVerifier: verifier)
    }

    private func presentSession(url: URL) async throws -> String {
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
