import AuthenticationServices
import CryptoKit
import SuperwallKit
import UIKit

/// Drives Sign in with Apple (Screen 1's "Get Started" button) using a
/// custom pill button rather than Apple's mandated SignInWithAppleButton
/// view, per the spec's visual style.
@MainActor
final class SessionManager: NSObject, ObservableObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    @Published var isSigningIn = false
    @Published var errorMessage: String?

    /// Set when the failure looks like "no Apple ID on this device", which is
    /// the one case the user can actually resolve themselves. Drives an
    /// "Open Settings" affordance.
    ///
    /// That button can only open Settings at THIS APP's page --
    /// `openSettingsURLString` is the only public entry point, and the
    /// private `prefs:root=APPLE_ACCOUNT` scheme that would land directly on
    /// the Apple ID screen is grounds for App Store rejection. One step up
    /// from the app's page is the Settings root, where "Sign in to your
    /// iPhone" sits at the very top.
    @Published var needsAppleIDSetup = false

    private var currentNonce: String?
    private var continuation: CheckedContinuation<Void, Error>?

    /// True only when a session was actually established.
    ///
    /// Callers must branch on this return value, NOT on `errorMessage == nil`.
    /// Cancelling is a silent non-error, so "no message" and "signed in" are
    /// no longer the same thing -- treating them as equivalent would let a
    /// user who tapped Cancel straight into the app.
    @discardableResult
    func signInWithApple() async -> Bool {
        isSigningIn = true
        errorMessage = nil
        needsAppleIDSetup = false
        defer { isSigningIn = false }

        do {
            try await performSignIn()
            AnalyticsManager.shared.loginCompleted()
            identifyWithSuperwall()
            return true
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            if let authError = error as? ASAuthorizationError {
                needsAppleIDSetup = authError.code == .unknown || authError.code == .notHandled
            }
            return false
        }
    }

    /// Turns an authorization failure into something a person can act on.
    ///
    /// This used to be `error.localizedDescription`, which for
    /// ASAuthorizationError renders as "The operation couldn't be completed.
    /// (com.apple.AuthenticationServices.AuthorizationError error 1000.)" --
    /// text that tells the user nothing and, worse, appeared even when they
    /// had simply tapped Cancel. Cancelling is not a failure and now shows
    /// nothing at all.
    ///
    /// The technical detail still goes to the console, since that is where it
    /// is useful and where it cannot mislead anyone.
    private static func userFacingMessage(for error: Error) -> String? {
        guard let authError = error as? ASAuthorizationError else {
            return error.localizedDescription
        }

        print("[SignInWithApple] \(authError.code.rawValue): \(authError.localizedDescription)")

        switch authError.code {
        case .canceled:
            return nil
        case .notHandled, .unknown:
            // Overwhelmingly this means no Apple ID is signed in on the
            // device, so name that rather than making the user guess.
            return String(localized: "signIn.apple.error.noAppleID", defaultValue: "Couldn't sign in with Apple. Check that you're signed in to an Apple ID in Settings, then try again.", comment: "Sign in with Apple error shown when no Apple ID appears to be signed in on the device")
        case .invalidResponse, .failed:
            return String(localized: "signIn.apple.error.failed", defaultValue: "Apple couldn't complete the sign-in. Please try again in a moment.", comment: "Sign in with Apple error shown when Apple's own sign-in flow failed or returned an invalid response")
        default:
            return String(localized: "signIn.apple.error.generic", defaultValue: "Couldn't sign in with Apple. Please try again.", comment: "Sign in with Apple error shown for any other authorization failure")
        }
    }

    // MARK: - Sign in with Google

    /// Same success-semantics as signInWithApple: branch on the return
    /// value, not on `errorMessage == nil` (cancelling the browser sheet is
    /// a silent non-error).
    @discardableResult
    func signInWithGoogle() async -> Bool {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            try await GoogleOAuthManager.shared.signIn()
            AnalyticsManager.shared.loginCompleted()
            identifyWithSuperwall()
            return true
        } catch {
            errorMessage = Self.userFacingMessage(forGoogleOrEmail: error)
            return false
        }
    }

    // MARK: - Email/password

    /// Returns `true` if a session was established, `false` if the caller
    /// should show a "check your email to confirm" message (Supabase's
    /// default project setting requires email confirmation before a
    /// signup session is usable).
    @discardableResult
    func signUpWithEmail(email: String, password: String) async -> Bool? {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let sessionEstablished = try await SupabaseClient.shared.signUpWithEmail(email: email, password: password)
            AnalyticsManager.shared.signupCompleted()
            identifyWithSuperwall()
            return sessionEstablished
        } catch {
            errorMessage = Self.userFacingMessage(forGoogleOrEmail: error)
            return nil
        }
    }

    @discardableResult
    func signInWithEmail(email: String, password: String) async -> Bool {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            try await SupabaseClient.shared.signInWithEmail(email: email, password: password)
            AnalyticsManager.shared.loginCompleted()
            identifyWithSuperwall()
            return true
        } catch {
            errorMessage = Self.userFacingMessage(forGoogleOrEmail: error)
            return false
        }
    }

    /// Translates a raw SupabaseError (which carries the provider's raw
    /// JSON error body) into text a person can act on -- never shown raw,
    /// same principle as userFacingMessage(for:) above for Apple.
    private static func userFacingMessage(forGoogleOrEmail error: Error) -> String? {
        if case ASWebAuthenticationSessionError.canceledLogin = error {
            return nil
        }
        guard case SupabaseError.requestFailed(_, let message) = error else {
            return String(localized: "signIn.generic.error.somethingWrong", defaultValue: "Something went wrong. Please try again.", comment: "Generic sign-in/sign-up error shown when the underlying error isn't a recognized Supabase request failure")
        }
        print("[Auth] \(message)")
        if message.contains("already registered") || message.contains("already exists") {
            return String(localized: "signIn.generic.error.accountExists", defaultValue: "An account with that email already exists -- try logging in instead.", comment: "Sign-up error shown when the email is already registered")
        }
        if message.contains("Invalid login credentials") {
            return String(localized: "signIn.generic.error.invalidCredentials", defaultValue: "That email or password isn't right. Try again.", comment: "Sign-in error shown when the email/password combination is wrong")
        }
        if message.contains("Password") {
            return String(localized: "signIn.generic.error.passwordRequirements", defaultValue: "That password doesn't meet the requirements -- try a longer one.", comment: "Sign-up error shown when the password fails Supabase's own validation")
        }
        return String(localized: "signIn.generic.error.fallback", defaultValue: "Couldn't complete that. Please try again.", comment: "Fallback sign-in/sign-up error for any other recognized Supabase request failure")
    }

    /// Aliases the anonymous on-device Superwall ID to Soma's real user id
    /// (a UUID, satisfying StoreKit's appAccountToken requirement -- see
    /// Superwall's identify(userId:) docs) so paywall assignment and
    /// purchase attribution carry across reinstalls/devices. A returning
    /// signed-in user is identified separately, at launch, in
    /// AppDelegate -- this covers the moment of interactive sign-in itself.
    private func identifyWithSuperwall() {
        guard let userId = SupabaseClient.shared.currentUserID else { return }
        Superwall.shared.identify(userId: userId)
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
