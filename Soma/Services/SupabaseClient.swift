import Foundation

/// Thin URLSession wrapper over Supabase's Auth REST API, PostgREST, and
/// Edge Functions. V1's needs are narrow enough (one Auth grant, a couple
/// of table reads/upserts, two function invocations) that pulling in the
/// full supabase-swift SDK would add more surface than it saves.
final class SupabaseClient {
    static let shared = SupabaseClient()

    private let keychain = KeychainStore()
    private let urlSession = URLSession.shared

    private init() {}

    // MARK: - Session state

    var isSignedIn: Bool { keychain.load() != nil }
    var currentUserID: String? { keychain.load()?.userID }

    func signOut() {
        keychain.clear()
    }

    // MARK: - Sign in with Apple

    /// Exchanges the Apple identity token for a Supabase session, then
    /// ensures a corresponding `users` row exists (required before any
    /// other table can reference it via foreign key).
    @discardableResult
    func signInWithApple(idToken: String, rawNonce: String, email: String? = nil) async throws -> String {
        var request = URLRequest(
            url: URL(string: "\(Config.supabaseURL.absoluteString)/auth/v1/token?grant_type=id_token")!
        )
        request.httpMethod = "POST"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "provider": "apple",
            "id_token": idToken,
            "nonce": rawNonce,
        ])

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)

        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        let session = StoredSession(
            userID: auth.user.id,
            accessToken: auth.access_token,
            refreshToken: auth.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(auth.expires_in))
        )
        keychain.save(session)

        // Apple only shares the real email on the user's very first
        // authorization for this app -- capture it here since it's never
        // offered again on subsequent sign-ins.
        try await upsertUser(id: auth.user.id, contactEmail: email)
        return auth.user.id
    }

    private func refreshSession() async throws {
        guard let current = keychain.load() else {
            throw SupabaseError.notSignedIn
        }

        var request = URLRequest(
            url: URL(string: "\(Config.supabaseURL.absoluteString)/auth/v1/token?grant_type=refresh_token")!
        )
        request.httpMethod = "POST"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "refresh_token": current.refreshToken,
        ])

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)

        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        keychain.save(StoredSession(
            userID: auth.user.id,
            accessToken: auth.access_token,
            refreshToken: auth.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(auth.expires_in))
        ))
    }

    private func validAccessToken() async throws -> String {
        guard var session = keychain.load() else { throw SupabaseError.notSignedIn }
        if session.expiresAt < Date().addingTimeInterval(60) {
            try await refreshSession()
            guard let refreshed = keychain.load() else { throw SupabaseError.notSignedIn }
            session = refreshed
        }
        return session.accessToken
    }

    // MARK: - users table

    /// Partial update -- only columns explicitly passed get written, so
    /// this is always safe to call without risking clobbering fields
    /// (like profile goals/equipment/injuries) set elsewhere.
    func upsertUser(
        id: String,
        wakeTimePref: String? = nil,
        onboardingComplete: Bool? = nil,
        contactEmail: String? = nil
    ) async throws {
        var body: [String: Any] = ["id": id]
        if let wakeTimePref { body["wake_time_pref"] = wakeTimePref }
        if let onboardingComplete { body["onboarding_complete"] = onboardingComplete }
        if let contactEmail { body["contact_email"] = contactEmail }

        var request = try await authorizedRequest(path: "rest/v1/users", method: "POST")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    /// Plain read via RLS -- used by ProfileView on appear.
    func fetchProfile(id: String) async throws -> UserProfile {
        let path = "rest/v1/users?id=eq.\(id)&select=contact_email,goals,other_goal_notes,equipment,other_equipment_notes,injury_tags,injury_notes&limit=1"
        var request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        let rows = try JSONDecoder().decode([UserProfile].self, from: data)
        return rows.first ?? .empty
    }

    func updateProfile(id: String, profile: UserProfile) async throws {
        var body: [String: Any] = [
            "id": id,
            "goals": profile.goals.map(\.rawValue),
            "equipment": profile.equipment.map(\.rawValue),
            "injury_tags": profile.injuryTags.map(\.rawValue),
        ]
        // JSONSerialization can't encode `nil` -- use NSNull so Postgres
        // actually clears these columns rather than leaving them untouched.
        body["contact_email"] = profile.contactEmail ?? NSNull()
        body["other_goal_notes"] = profile.otherGoalNotes ?? NSNull()
        body["other_equipment_notes"] = profile.otherEquipmentNotes ?? NSNull()
        body["injury_notes"] = profile.injuryNotes ?? NSNull()

        var request = try await authorizedRequest(path: "rest/v1/users", method: "POST")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    /// Plain read via RLS -- used to check whether a referral bonus is
    /// currently active (paywall gating in AppState).
    func fetchReferralBonusUntil(id: String) async throws -> Date? {
        let path = "rest/v1/users?id=eq.\(id)&select=referral_bonus_until&limit=1"
        var request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)

        struct Row: Decodable {
            let referral_bonus_until: String?
        }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        guard let iso = rows.first?.referral_bonus_until else { return nil }
        return Self.parsePostgRESTDate(iso)
    }

    /// Calls the redeem-referral-code Edge Function; returns the new
    /// referral_bonus_until on success.
    func redeemReferralCode(_ code: String) async throws -> Date {
        var request = try await authorizedRequest(path: "functions/v1/redeem-referral-code", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code])

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)

        struct Response: Decodable {
            let referral_bonus_until: String
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let date = Self.parsePostgRESTDate(decoded.referral_bonus_until) else {
            throw SupabaseError.requestFailed(status: 0, message: "Invalid date in response")
        }
        return date
    }

    private static func parsePostgRESTDate(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    // MARK: - daily_recommendation

    /// Plain read via RLS -- used by HomeView on appear so opening the app
    /// doesn't invoke the mutating generate-recommendation function every time.
    func fetchTodaysRecommendation(date: String) async throws -> DailyRecommendation? {
        let path = "rest/v1/daily_recommendation?date=eq.\(date)&select=date,category,message,reason,sleep_cap_applied,injury_cap_applied&limit=1"
        var request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        let rows = try JSONDecoder().decode([DailyRecommendation].self, from: data)
        return rows.first
    }

    // MARK: - daily_snapshot

    /// Plain read via RLS -- used by RecommendationDetailView to pull the
    /// real metric value for RecommendationReason's explanation templates.
    func fetchTodaysSnapshots(date: String) async throws -> [DailySnapshotRow] {
        let path = "rest/v1/daily_snapshot?date=eq.\(date)&select=source,recovery_score,readiness_score,hrv_ms,sleep_hours,resting_hr"
        var request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        return try JSONDecoder().decode([DailySnapshotRow].self, from: data)
    }

    // MARK: - Edge Functions

    func invokeGenerateRecommendation(date: String, healthkit: HealthKitSnapshot?) async throws -> DailyRecommendation {
        var body: [String: Any] = ["date": date]
        if let healthkit {
            var hk: [String: Any] = [:]
            if let v = healthkit.sleepHours { hk["sleepHours"] = v }
            if let v = healthkit.hrvMs { hk["hrvMs"] = v }
            if let v = healthkit.restingHr { hk["restingHr"] = v }
            body["healthkit"] = hk
        }

        var request = try await authorizedRequest(path: "functions/v1/generate-recommendation", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        return try JSONDecoder().decode(DailyRecommendation.self, from: data)
    }

    func exchangeAndStoreWearableToken(
        provider: String,
        code: String,
        codeVerifier: String?,
        redirectURI: String
    ) async throws {
        var body: [String: Any] = [
            "provider": provider,
            "code": code,
            "redirectUri": redirectURI,
        ]
        if let codeVerifier { body["codeVerifier"] = codeVerifier }

        var request = try await authorizedRequest(path: "functions/v1/store-wearable-token", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    // MARK: - Request helpers

    private func authorizedRequest(path: String, method: String) async throws -> URLRequest {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "\(Config.supabaseURL.absoluteString)/\(path)")!)
        request.httpMethod = method
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private static func assertSuccess(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "unknown error"
            throw SupabaseError.requestFailed(status: http.statusCode, message: message)
        }
    }
}

private struct AuthResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int
    let user: AuthUser

    struct AuthUser: Decodable {
        let id: String
    }
}

enum SupabaseError: LocalizedError {
    case notSignedIn
    case requestFailed(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in."
        case .requestFailed(let status, let message):
            return "Request failed (\(status)): \(message)"
        }
    }
}
