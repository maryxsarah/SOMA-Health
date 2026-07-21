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

    var errorDescription: String? {
        switch self {
        case .missingCode: "No authorization code was returned."
        case .stateMismatch: "OAuth state mismatch -- possible interception, aborting."
        }
    }
}
