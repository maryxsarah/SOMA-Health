import AuthenticationServices
import CryptoKit
import UIKit

/// Drives Sign in with Apple (Screen 1's "Get Started" button) using a
/// custom pill button rather than Apple's mandated SignInWithAppleButton
/// view, per the spec's visual style.
@MainActor
final class SessionManager: NSObject, ObservableObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    @Published var isSigningIn = false
    @Published var errorMessage: String?

    private var currentNonce: String?
    private var continuation: CheckedContinuation<Void, Error>?

    func signInWithApple() async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            try await performSignIn()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performSignIn() async throws {
        let nonce = Self.randomNonceString()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = []
        request.nonce = Self.sha256(nonce)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                continuation?.resume(throwing: OAuthError.missingCode)
                continuation = nil
                return
            }

            do {
                // credential.email is only ever non-nil on the user's
                // first authorization for this app -- Apple never re-shares
                // it on subsequent sign-ins.
                try await SupabaseClient.shared.signInWithApple(
                    idToken: idToken,
                    rawNonce: nonce,
                    email: credential.email
                )
                continuation?.resume()
            } catch {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }

    // MARK: - Nonce helpers (standard Sign in with Apple + Supabase pattern:
    // Apple gets sha256(nonce), Supabase's id_token grant gets the raw nonce
    // and verifies it against the hash embedded in Apple's identity token.)

    private static func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(status == errSecSuccess, "Unable to generate secure nonce")

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
