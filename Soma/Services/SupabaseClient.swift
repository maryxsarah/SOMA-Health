import Foundation

/// Thin URLSession wrapper over Supabase's Auth REST API, PostgREST, and
/// Edge Functions. V1's needs are narrow enough (one Auth grant, a couple
/// of table reads/upserts, two function invocations) that pulling in the
/// full supabase-swift SDK would add more surface than it saves.
final class SupabaseClient {
    static let shared = SupabaseClient()

    private let keychain = KeychainStore()
    // Every request funnels through this one session; SomaUITests swap it
    // for a fixture-serving stub (nil outside `--ui-test-fixtures` runs).
    private let urlSession = UITestSupport.stubbedSession ?? URLSession.shared

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

    // MARK: - Sign in with Google

    /// Exchanges the PKCE authorization code from GoogleOAuthManager for a
    /// Supabase session -- same grant Supabase's own client SDKs use for
    /// native OAuth, no client_secret needed since PKCE's code_verifier is
    /// itself the exchange credential.
    @discardableResult
    func signInWithGoogle(code: String, codeVerifier: String) async throws -> String {
        var request = URLRequest(
            url: URL(string: "\(Config.supabaseURL.absoluteString)/auth/v1/token?grant_type=pkce")!
        )
        request.httpMethod = "POST"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "auth_code": code,
            "code_verifier": codeVerifier,
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
        try await upsertUser(id: auth.user.id, contactEmail: auth.user.email)
        return auth.user.id
    }

    // MARK: - Email/password

    /// Supabase's default project setting requires email confirmation
    /// before a session is usable -- the signup response then has no
    /// access_token yet. Returns `true` if a session was established
    /// immediately, `false` if the caller should show a
    /// "check your email to confirm" message instead.
    @discardableResult
    func signUpWithEmail(email: String, password: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "\(Config.supabaseURL.absoluteString)/auth/v1/signup")!)
        request.httpMethod = "POST"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)

        guard let auth = try? JSONDecoder().decode(AuthResponse.self, from: data) else {
            return false
        }
        keychain.save(StoredSession(
            userID: auth.user.id,
            accessToken: auth.access_token,
            refreshToken: auth.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(auth.expires_in))
        ))
        try await upsertUser(id: auth.user.id, contactEmail: auth.user.email ?? email)
        return true
    }

    @discardableResult
    func signInWithEmail(email: String, password: String) async throws -> String {
        var request = URLRequest(
            url: URL(string: "\(Config.supabaseURL.absoluteString)/auth/v1/token?grant_type=password")!
        )
        request.httpMethod = "POST"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)

        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        keychain.save(StoredSession(
            userID: auth.user.id,
            accessToken: auth.access_token,
            refreshToken: auth.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(auth.expires_in))
        ))
        try await upsertUser(id: auth.user.id, contactEmail: auth.user.email ?? email)
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
        contactEmail: String? = nil,
        marketingOptIn: Bool? = nil,
        legalAck: Bool = false
    ) async throws {
        var body: [String: Any] = ["id": id]
        if let wakeTimePref { body["wake_time_pref"] = wakeTimePref }
        if let onboardingComplete { body["onboarding_complete"] = onboardingComplete }
        if let contactEmail { body["contact_email"] = contactEmail }
        if let marketingOptIn { body["marketing_opt_in"] = marketingOptIn }
        // Every sign-in method below can only be reached after the user has
        // checked OnboardingView's acknowledgment box, so recording this here
        // -- rather than trusting a client-passed timestamp -- ties the
        // record to an actual completed, gated auth flow.
        if legalAck {
            body["legal_ack_at"] = Date().ISO8601Format()
            body["legal_ack_version"] = LegalContent.currentVersion
        }

        var request = try await authorizedRequest(path: "rest/v1/users", method: "POST")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    /// One-time batch write at the end of the onboarding survey. Only
    /// answers actually given get written -- any left `nil` are omitted
    /// (fresh user row, so nothing to accidentally clobber).
    func saveOnboardingSurvey(id: String, answers: OnboardingSurveyAnswers) async throws {
        var body: [String: Any] = ["id": id]
        if let sex = answers.sex { body["sex"] = sex.rawValue }
        if let frequency = answers.workoutFrequency { body["workouts_per_week"] = frequency.rawValue }
        if let dob = answers.dateOfBirth {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = .current
            body["date_of_birth"] = formatter.string(from: dob)
        }
        if let source = answers.referralSource { body["referral_source"] = source.rawValue }
        if let weight = answers.weightKg { body["weight_kg"] = weight }
        if let height = answers.heightCm { body["height_cm"] = height }
        if let trainer = answers.worksWithTrainer { body["works_with_trainer"] = trainer }
        if !answers.goal.isEmpty { body["goals"] = answers.goal.map(\.rawValue) }
        if let desired = answers.desiredWeightKg { body["desired_weight_kg"] = desired }
        if let pace = answers.goalPace { body["goal_pace"] = pace.rawValue }
        if let journeyStage = answers.journeyStage { body["journey_stage"] = journeyStage.rawValue }
        if !answers.blockers.isEmpty { body["blockers"] = answers.blockers.map(\.rawValue) }
        if let blockersNotes = answers.blockersNotes, !blockersNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["blockers_notes"] = blockersNotes
        }
        if let diet = answers.dietType { body["diet_type"] = diet.rawValue }
        if !answers.accomplishmentGoals.isEmpty { body["accomplishment_goals"] = answers.accomplishmentGoals.map(\.rawValue) }
        body["marketing_opt_in"] = answers.marketingOptIn

        var request = try await authorizedRequest(path: "rest/v1/users", method: "POST")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    /// Plain read via RLS -- used by ProfileView on appear.
    func fetchProfile(id: String) async throws -> UserProfile {
        // injury_severity must stay in this list: UserProfile decodes it
        // non-optionally, and PostgREST returns only selected columns --
        // omitting it made every profile fetch throw keyNotFound, which
        // `try?` call sites turned into an empty profile (and a subsequent
        // Save would then wipe the user's real data).
        let path = "rest/v1/users?id=eq.\(id)&select=contact_email,goals,other_goal_notes,equipment,other_equipment_notes,injury_tags,injury_severity,injury_type,injury_pain_level,injury_notes,experience_level,pregnancy,pregnancy_week,weekly_session_target,goal_body_photo_path,current_body_photo_path,weight_kg,desired_weight_kg,country,city,height_cm,journey_stage,blockers_notes,date_of_birth&limit=1"
        var request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        let rows = try JSONDecoder().decode([UserProfile].self, from: data)
        return rows.first ?? .empty
    }

    // injury_tags/injury_severity are deliberately NOT written here -- they
    // go through reportInjury below instead, which diffs server-side
    // against the current row to detect new/escalated injuries and start
    // the corresponding recovery protocol. Writing them via this plain RLS
    // path too would just be redundant (reportInjury already persists the
    // same values) and risks the two calls racing on the same columns.
    func updateProfile(id: String, profile: UserProfile) async throws {
        var body: [String: Any] = [
            "id": id,
            "goals": profile.goals.map(\.rawValue),
            "equipment": profile.equipment.map(\.rawValue),
        ]
        // JSONSerialization can't encode `nil` -- use NSNull so Postgres
        // actually clears these columns rather than leaving them untouched.
        body["contact_email"] = profile.contactEmail ?? NSNull()
        body["other_goal_notes"] = profile.otherGoalNotes ?? NSNull()
        body["other_equipment_notes"] = profile.otherEquipmentNotes ?? NSNull()
        body["injury_notes"] = profile.injuryNotes ?? NSNull()
        body["experience_level"] = profile.experienceLevel?.rawValue ?? NSNull()
        body["pregnancy"] = profile.pregnancy ?? NSNull()
        body["pregnancy_week"] = profile.pregnancy == true ? (profile.pregnancyWeek ?? NSNull()) : NSNull()
        body["weekly_session_target"] = profile.weeklySessionTarget ?? NSNull()
        body["country"] = profile.country ?? NSNull()
        body["city"] = profile.city ?? NSNull()
        body["height_cm"] = profile.heightCm ?? NSNull()
        body["journey_stage"] = profile.journeyStage?.rawValue ?? NSNull()
        body["blockers_notes"] = profile.blockersNotes ?? NSNull()

        var request = try await authorizedRequest(path: "rest/v1/users", method: "POST")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    /// Calls the report-injury Edge Function -- the sole writer of
    /// injury_tags/injury_severity. Diffs server-side against the current
    /// row to detect new/escalated injuries and start (or clear) the
    /// corresponding injury_recovery_state protocol.
    func reportInjury(
        tags: [InjuryTag],
        severity: [InjuryTag: InjurySeverity],
        type: [InjuryTag: InjuryType] = [:],
        painLevel: [InjuryTag: Int] = [:]
    ) async throws {
        var request = try await authorizedRequest(path: "functions/v1/report-injury", method: "POST")
        let severityBody = Dictionary(uniqueKeysWithValues: severity.map { ($0.rawValue, $1.rawValue) })
        let typeBody = Dictionary(uniqueKeysWithValues: type.map { ($0.rawValue, $1.rawValue) })
        let painLevelBody = Dictionary(uniqueKeysWithValues: painLevel.map { ($0.rawValue, $1) })
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "injuryTags": tags.map(\.rawValue),
            "injurySeverity": severityBody,
            "injuryType": typeBody,
            "injuryPainLevel": painLevelBody,
        ])
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    /// Every body-part redirect currently active for the caller's noted
    /// injuries -- e.g. `["lower_body": "upper_body"]` for a knee injury --
    /// so RecommendationDetailView can steer its suggestion list away from
    /// a conflicting body part before the user even picks one. Empty
    /// result means nothing is currently redirected.
    func fetchInjurySubstitutions() async throws -> [String: String] {
        let request = try await authorizedRequest(path: "functions/v1/resolve-injury-substitutions", method: "POST")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        struct Response: Decodable { let substitutions: [String: String] }
        return try JSONDecoder().decode(Response.self, from: data).substitutions
    }

    /// Plain read via RLS -- active/recovering rows drive the daily
    /// check-in card on RecommendationDetailView.
    func fetchInjuryRecoveryStates() async throws -> [InjuryRecoveryState] {
        let path = "rest/v1/injury_recovery_state?status=in.(active,recovering)&select=injury_tag,severity,status,consecutive_good_days,consecutive_bad_days,last_checkin_date"
        var request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        return try JSONDecoder().decode([InjuryRecoveryState].self, from: data)
    }

    /// Calls the record-injury-checkin Edge Function for one tag. `date`
    /// is the client's local calendar date (the recommendation date the
    /// check-in card was shown for) -- the server used to stamp its own
    /// UTC date, which disagreed with the local date for hours every day
    /// and let the same real day be checked in twice.
    func recordInjuryCheckin(tag: InjuryTag, response: InjuryCheckinResponse, date: String, painLevel: Int? = nil) async throws -> InjuryCheckinResult {
        var request = try await authorizedRequest(path: "functions/v1/record-injury-checkin", method: "POST")
        var body: [String: Any] = [
            "injuryTag": tag.rawValue,
            "response": response.rawValue,
            "date": date,
        ]
        if let painLevel { body["painLevel"] = painLevel }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, httpResponse) = try await urlSession.data(for: request)
        try Self.assertSuccess(httpResponse, data: data)
        return try JSONDecoder().decode(InjuryCheckinResult.self, from: data)
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

    // MARK: - Body photos (feature-flagged, see Config.enableBodyPhotoUpload)

    enum BodyPhotoKind: String {
        case goal = "goal-body"
        case current = "current-body"
    }

    /// Unique, UUID-suffixed path per upload -- previously a fixed
    /// "{userId}/{kind}.jpg" path that silently overwrote the prior photo
    /// via x-upsert, with no history. Now every upload both lands at its
    /// own path AND inserts a body_photo history row, while the
    /// goal_body_photo_path/current_body_photo_path columns keep being
    /// updated to point at the newest upload -- so existing read sites
    /// (ProfileView's single "latest photo" slot) keep working unmodified,
    /// and body_photo becomes the real history source for the comparison
    /// slider/history grid. Uses Storage's binary-body endpoint directly
    /// rather than `authorizedRequest` (which hardcodes
    /// Content-Type: application/json).
    func uploadBodyPhoto(kind: BodyPhotoKind, imageData: Data) async throws {
        guard let userId = currentUserID else { throw SupabaseError.notSignedIn }
        let path = "\(userId)/\(kind.rawValue)-\(UUID().uuidString).jpg"
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "\(Config.supabaseURL.absoluteString)/storage/v1/object/body-photos/\(path)")!)
        request.httpMethod = "POST"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)

        let column = kind == .goal ? "goal_body_photo_path" : "current_body_photo_path"
        var upsertRequest = try await authorizedRequest(path: "rest/v1/users", method: "POST")
        upsertRequest.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        upsertRequest.httpBody = try JSONSerialization.data(withJSONObject: ["id": userId, column: path])
        let (d2, r2) = try await urlSession.data(for: upsertRequest)
        try Self.assertSuccess(r2, data: d2)

        var historyRequest = try await authorizedRequest(path: "rest/v1/body_photo", method: "POST")
        historyRequest.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        historyRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "user_id": userId, "kind": kind == .goal ? "goal" : "current", "storage_path": path,
        ])
        let (d3, r3) = try await urlSession.data(for: historyRequest)
        try Self.assertSuccess(r3, data: d3)
    }

    /// Full upload history for one kind, newest first -- feeds the Profile
    /// photo-history grid and the comparison slider's photo picker.
    func fetchBodyPhotos(kind: BodyPhotoKind) async throws -> [BodyPhotoEntry] {
        let dbKind = kind == .goal ? "goal" : "current"
        let path = "rest/v1/body_photo?kind=eq.\(dbKind)&select=id,kind,storage_path,taken_at&order=taken_at.desc"
        let request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        return try JSONDecoder().decode([BodyPhotoEntry].self, from: data)
    }

    /// Fires the silent AI comparison of the user's stored goal/current
    /// photos (see analyze-body-photo). Fire-and-forget by every caller --
    /// this function itself still throws normally so `try?` callers can
    /// choose to ignore failures, but there's no result to act on either
    /// way (the analysis result is never shown to the user).
    func analyzeBodyPhotos() async throws {
        var request = try await authorizedRequest(path: "functions/v1/analyze-body-photo", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: [String: Any]())
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    /// The bucket is private, so viewing a stored photo needs a short-lived
    /// signed URL rather than a plain public one.
    func signedBodyPhotoURL(path: String, expiresInSeconds: Int = 3600) async throws -> URL {
        var request = try await authorizedRequest(path: "storage/v1/object/sign/body-photos/\(path)", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["expiresIn": expiresInSeconds])
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        struct Response: Decodable { let signedURL: String }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let url = URL(string: "\(Config.supabaseURL.absoluteString)/storage/v1\(decoded.signedURL)") else {
            throw SupabaseError.requestFailed(status: 0, message: "Invalid signed URL in response")
        }
        return url
    }

    /// Deletes the currently pinned photo for `kind` -- `path` is the
    /// caller's already-loaded goalBodyPhotoPath/currentBodyPhotoPath,
    /// needed now that upload paths are unique rather than fixed per kind.
    /// Removes the Storage object, its body_photo history row, and clears
    /// the pointer column.
    func deleteBodyPhoto(kind: BodyPhotoKind, path: String) async throws {
        guard let userId = currentUserID else { throw SupabaseError.notSignedIn }
        // Built manually: authorizedRequest declares Content-Type json with
        // no body, which storage-api rejects outright (400) on DELETE.
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "\(Config.supabaseURL.absoluteString)/storage/v1/object/body-photos/\(path)")!)
        request.httpMethod = "DELETE"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)

        let dbKind = kind == .goal ? "goal" : "current"
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let deleteRowRequest = try await authorizedRequest(
            path: "rest/v1/body_photo?user_id=eq.\(userId)&kind=eq.\(dbKind)&storage_path=eq.\(encodedPath)",
            method: "DELETE"
        )
        let (dRow, rRow) = try await urlSession.data(for: deleteRowRequest)
        try Self.assertSuccess(rRow, data: dRow)

        let column = kind == .goal ? "goal_body_photo_path" : "current_body_photo_path"
        var clearRequest = try await authorizedRequest(path: "rest/v1/users", method: "POST")
        clearRequest.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        // Emphasis tags were derived from the deleted photo -- a plan must
        // never keep steering toward a photo the user removed.
        clearRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "id": userId, column: NSNull(), "body_photo_emphasis_tags": NSNull(),
        ])
        let (d2, r2) = try await urlSession.data(for: clearRequest)
        try Self.assertSuccess(r2, data: d2)
    }

    /// Re-points the "latest" pointer column at an older history entry --
    /// used after deleting the pinned photo to promote the previous upload
    /// instead of leaving the slot empty while history still exists.
    func pinBodyPhoto(kind: BodyPhotoKind, path: String) async throws {
        guard let userId = currentUserID else { throw SupabaseError.notSignedIn }
        let column = kind == .goal ? "goal_body_photo_path" : "current_body_photo_path"
        var request = try await authorizedRequest(path: "rest/v1/users", method: "POST")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": userId, column: path])
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    // MARK: - daily_recommendation

    /// Plain read via RLS -- used by HomeView on appear so opening the app
    /// doesn't invoke the mutating generate-recommendation function every time.
    func fetchTodaysRecommendation(date: String) async throws -> DailyRecommendation? {
        let path = "rest/v1/daily_recommendation?date=eq.\(date)&select=date,category,message,reason,data_confidence,sleep_cap_applied,injury_cap_applied,load_cap_applied,consecutive_days_cap_applied,injury_protocol_cap_applied,injury_protocol_moderate_cap_applied,pregnancy_cap_applied,volume_cap_applied,pre_cap_category&limit=1"
        var request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        let rows = try JSONDecoder().decode([DailyRecommendation].self, from: data)
        return rows.first
    }

    /// Plain read via RLS -- feeds Home's calendar strip (green/yellow/
    /// orange/red per day, based on that day's category).
    func fetchRecentRecommendations(days: Int = 7) async throws -> [DailyRecommendation] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current

        let end = Date()
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        let startStr = formatter.string(from: start)
        let endStr = formatter.string(from: end)

        let path = "rest/v1/daily_recommendation?date=gte.\(startStr)&date=lte.\(endStr)&select=date,category,message,reason,data_confidence,sleep_cap_applied,injury_cap_applied,load_cap_applied,consecutive_days_cap_applied,injury_protocol_cap_applied,injury_protocol_moderate_cap_applied,pregnancy_cap_applied,volume_cap_applied,pre_cap_category&order=date.asc"
        var request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        return try JSONDecoder().decode([DailyRecommendation].self, from: data)
    }

    // MARK: - daily_snapshot

    /// Plain read via RLS -- used by RecommendationDetailView to pull the
    /// real metric value for RecommendationReason's explanation templates.
    func fetchTodaysSnapshots(date: String) async throws -> [DailySnapshotRow] {
        let path = "rest/v1/daily_snapshot?date=eq.\(date)&select=source,recovery_score,readiness_score,hrv_ms,sleep_hours,resting_hr,strain_score,stress_score,sleep_light_hours,sleep_deep_hours,sleep_rem_hours,sleep_awake_hours"
        var request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        return try JSONDecoder().decode([DailySnapshotRow].self, from: data)
    }

    /// Feeds HealthDashboardView's trend section -- same columns as
    /// fetchTodaysSnapshots plus `date`, over a range instead of one day.
    func fetchSnapshots(fromDate: String, toDate: String) async throws -> [DailySnapshotRow] {
        let path = "rest/v1/daily_snapshot?date=gte.\(fromDate)&date=lte.\(toDate)&select=date,source,recovery_score,readiness_score,hrv_ms,sleep_hours,resting_hr,strain_score,stress_score,sleep_light_hours,sleep_deep_hours,sleep_rem_hours,sleep_awake_hours&order=date.asc"
        var request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        return try JSONDecoder().decode([DailySnapshotRow].self, from: data)
    }

    // MARK: - workout_log

    /// Marks a suggestion as done for the day -- client-writable directly
    /// via RLS (`workout_log_insert_own`), same pattern as the `users`
    /// profile writes; no Edge Function needed for user-entered content.
    /// `feedback` is optional free-text the user can leave when marking a
    /// workout done (e.g. "I like a 5-10min incline treadmill warm-up") --
    /// generate-workout-plan folds recent feedback into future plans for a
    /// similar workout.
    func logWorkout(
        date: String,
        title: String,
        bodyPart: String,
        category: String,
        feedback: String? = nil,
        feelRating: WorkoutFeelRating? = nil,
        planSnapshot: AIWorkoutPlan? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil
    ) async throws {
        guard let userId = currentUserID else { throw SupabaseError.notSignedIn }
        var body: [String: Any] = [
            "user_id": userId,
            "date": date,
            "title": title,
            "body_part": bodyPart,
            "category": category,
        ]
        if let feedback, !feedback.isEmpty {
            body["feedback"] = feedback
        }
        if let feelRating {
            body["feel_rating"] = feelRating.rawValue
        }
        // Real workout start/end, distinct from completed_at (the log
        // action's own timestamp) -- needed to match wearable HR data to
        // the exact session window later. Nil when the caller has no
        // reliable start time to offer (e.g. a workout logged without ever
        // opening the AI plan first).
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let startedAt { body["started_at"] = isoFormatter.string(from: startedAt) }
        if let endedAt { body["ended_at"] = isoFormatter.string(from: endedAt) }
        // Snapshots the actual plan shown at log time -- ai_workout_plan is
        // keyed by (user_id, date) and gets overwritten on regeneration, so
        // it's not a reliable source for "what did they actually do" later.
        if let planSnapshot,
           let encoded = try? JSONEncoder().encode(planSnapshot),
           let obj = try? JSONSerialization.jsonObject(with: encoded) {
            body["plan_snapshot"] = obj
        }
        var request = try await authorizedRequest(path: "rest/v1/workout_log", method: "POST")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    /// Plain read via RLS -- used both by RecommendationDetailView (to show
    /// which of today's/yesterday's suggestions are already logged) and
    /// DayDetailView (calendar day drill-down).
    func fetchWorkoutLogs(date: String) async throws -> [WorkoutLogEntry] {
        let path = "rest/v1/workout_log?date=eq.\(date)&select=id,date,title,body_part,category,completed_at,feedback,plan_snapshot,started_at,ended_at,feel_rating&order=completed_at.asc"
        var request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        return try JSONDecoder().decode([WorkoutLogEntry].self, from: data)
    }

    /// Same shape as the single-date read above, over a range -- feeds
    /// TrainingHistoryView's 30-day list and RecommendationDetailView's
    /// 7-day body-part balancing.
    func fetchWorkoutLogs(fromDate: String, toDate: String) async throws -> [WorkoutLogEntry] {
        let path = "rest/v1/workout_log?date=gte.\(fromDate)&date=lte.\(toDate)&select=id,date,title,body_part,category,completed_at,feedback,plan_snapshot,started_at,ended_at,feel_rating&order=date.desc"
        var request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        return try JSONDecoder().decode([WorkoutLogEntry].self, from: data)
    }

    /// "Edit this log" on CompletedWorkoutView -- updates the feel rating
    /// (and optionally the free-text feedback) on an already-logged
    /// workout, by its own row id. RLS restricts this to the row's owner,
    /// same as every other workout_log write.
    func updateWorkoutLog(id: String, feelRating: WorkoutFeelRating?, feedback: String?) async throws {
        var body: [String: Any] = ["feel_rating": feelRating?.rawValue ?? NSNull()]
        if let feedback {
            body["feedback"] = feedback.isEmpty ? NSNull() : feedback
        }
        var request = try await authorizedRequest(path: "rest/v1/workout_log?id=eq.\(id)", method: "PATCH")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    /// Turns freeform post-workout feedback into 3 concrete add-on
    /// suggestions for future similar workouts (e.g. a specific warm-up
    /// variation) -- a small, uncached Claude Haiku call since feedback is
    /// occasional and low-cost, not a once-a-day-capped generation like
    /// the AI workout plan.
    func fetchWorkoutAddonSuggestions(feedback: String, workoutTitle: String, bodyPart: String) async throws -> [String] {
        var request = try await authorizedRequest(path: "functions/v1/suggest-workout-addons", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "feedback": feedback,
            "workoutTitle": workoutTitle,
            "bodyPart": bodyPart,
        ])

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)

        struct Response: Decodable { let suggestions: [String] }
        return try JSONDecoder().decode(Response.self, from: data).suggestions
    }

    /// Plain read via RLS -- feeds Home's calendar strip crown badge (any
    /// day with at least one logged workout gets a crown). Distinct dates
    /// only; the strip doesn't care how many workouts were logged in a day.
    func fetchRecentWorkoutLogDates(days: Int = 7) async throws -> Set<String> {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current

        let end = Date()
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        let path = "rest/v1/workout_log?date=gte.\(formatter.string(from: start))&date=lte.\(formatter.string(from: end))&select=date"
        var request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)

        struct Row: Decodable { let date: String }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        return Set(rows.map(\.date))
    }

    /// Real dates the user scanned their gym setup (a gym_photo generation
    /// actually happened, per ai_generation_log) -- feeds Home's "Scan
    /// today's setup" streak, distinct from workout completion.
    func fetchGymPhotoScanDates(days: Int = 30) async throws -> Set<String> {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current

        let end = Date()
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        let path = "rest/v1/ai_generation_log?date=gte.\(formatter.string(from: start))&date=lte.\(formatter.string(from: end))&source=eq.gym_photo&select=date"
        let request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)

        struct Row: Decodable { let date: String }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        return Set(rows.map(\.date))
    }

    /// Total AI generations logged for `date` across ALL sources -- mirrors
    /// the server's tiered quota check (generationLimits.ts counts every row).
    func fetchTodaysGenerationCount(date: String) async throws -> Int {
        let path = "rest/v1/ai_generation_log?date=eq.\(date)&select=id"
        let request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)

        struct Row: Decodable { let id: String }
        return try JSONDecoder().decode([Row].self, from: data).count
    }

    /// Looks up one exercise_library row for the "what does this look like"
    /// detail view. Prefers exact id (generate-gym-workout's hand-verified
    /// library_id); falls back to exact name (generate-workout-plan's
    /// `name` is schema-constrained to a real library name, see
    /// _shared/exerciseLibraryMatch.ts). Returns nil rather than guessing
    /// when neither is available or nothing matches -- an honest "no media"
    /// state, not a fuzzy best-effort match.
    func fetchExerciseLibraryEntry(libraryId: String?, name: String) async throws -> ExerciseLibraryEntry? {
        let cacheKey = Self.exerciseLibraryCacheKey(libraryId: libraryId, name: name)
        if let cached = await ExerciseLibraryCache.shared.cached(for: cacheKey) {
            return cached
        }

        let path: String
        if let libraryId, !libraryId.isEmpty {
            let encodedId = libraryId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? libraryId
            path = "rest/v1/exercise_library?id=eq.\(encodedId)&select=*&limit=1"
        } else {
            let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
            path = "rest/v1/exercise_library?name=eq.\(encodedName)&select=*&limit=1"
        }
        let request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        let rows = try JSONDecoder().decode([ExerciseLibraryEntry].self, from: data)
        if let entry = rows.first {
            await ExerciseLibraryCache.shared.store(entry, for: cacheKey)
        }
        return rows.first
    }

    /// Today's actual recorded workout sessions from connected wearables
    /// (Oura/Whoop) -- distinct from workout_log (what the user told Soma
    /// they did). HealthKit's own workouts are read separately, on-device,
    /// via HealthKitManager -- the caller merges both into one timeline.
    /// `startTime`/`endTime`, if given, narrow the wearable query to a
    /// specific logged workout's exact span (DayDetailView's wearable-HR-
    /// matched-to-workout feature) instead of the whole day.
    func fetchProviderWorkoutTimeline(date: String, startTime: Date? = nil, endTime: Date? = nil) async throws -> [WorkoutTimelineEntry] {
        var request = try await authorizedRequest(path: "functions/v1/fetch-workout-timeline", method: "POST")
        var body: [String: Any] = ["date": date]
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let startTime { body["startTime"] = isoFormatter.string(from: startTime) }
        if let endTime { body["endTime"] = isoFormatter.string(from: endTime) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)

        struct DTO: Decodable {
            let source: String
            let title: String
            let start_time: String
            let duration_minutes: Int
            let calories: Int?
            let average_heart_rate: Int?
            let max_heart_rate: Int?
        }
        struct Response: Decodable { let entries: [DTO] }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()

        return decoded.entries.compactMap { dto in
            guard let start = formatter.date(from: dto.start_time) ?? plainFormatter.date(from: dto.start_time) else {
                return nil
            }
            return WorkoutTimelineEntry(
                source: dto.source,
                title: dto.title,
                startTime: start,
                durationMinutes: dto.duration_minutes,
                calories: dto.calories,
                averageHeartRate: dto.average_heart_rate,
                maxHeartRate: dto.max_heart_rate
            )
        }
    }

    /// Uploads HealthKit's on-device workouts so they persist server-side --
    /// previously HomeView only ever held these in-memory (see
    /// loadTimeline()), so they vanished on every app relaunch and never
    /// showed up in the backend at all.
    ///
    /// Throws like every other call here; it is the *caller* that treats
    /// this as best-effort (HomeView wraps it in `try?`), because a failed
    /// sync has no user-visible impact -- the timeline is still built
    /// locally either way. Kept throwing rather than swallowing internally
    /// so a future caller that does care can handle the error.
    func syncHealthKitWorkouts(_ entries: [WorkoutTimelineEntry]) async throws {
        guard let userId = currentUserID, !entries.isEmpty else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let rows: [[String: Any]] = entries.map { entry in
            var row: [String: Any] = [
                "user_id": userId,
                "source": entry.source,
                "start_time": formatter.string(from: entry.startTime),
                "title": entry.title,
                "duration_minutes": entry.durationMinutes,
            ]
            // NSNull rather than omitting the key: PostgREST requires every
            // object in a bulk insert to have identical keys and answers 400
            // PGRST102 otherwise. A day mixing a run (has calories) with a
            // yoga session (has none) therefore synced NOTHING -- and since
            // the call site uses `try?`, silently.
            row["calories"] = entry.calories ?? NSNull()
            return row
        }

        // on_conflict names the real constraint. Without it PostgREST targets
        // the primary key, which never conflicts (no id is sent), so the
        // second sync of the day hit unique (user_id, source, start_time),
        // returned 409, and -- because a multi-row INSERT aborts as a unit --
        // dropped every row in the batch including workouts not yet stored.
        var request = try await authorizedRequest(
            path: "rest/v1/healthkit_workout_sync?on_conflict=user_id,source,start_time",
            method: "POST"
        )
        request.setValue("resolution=ignore-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: rows)

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    /// Reads back what previous syncs stored, so a workout recorded on one
    /// device shows up on another.
    ///
    /// Without this the table was write-only: rows were uploaded on every
    /// Home appear and never read by anything, while the privacy policy told
    /// the user their history "persists across devices". Collecting health
    /// data that nothing consumes is the wrong side of data minimisation as
    /// well as an unmet promise.
    func fetchSyncedHealthKitWorkouts(date: String) async throws -> [WorkoutTimelineEntry] {
        let path = "rest/v1/healthkit_workout_sync?select=source,title,start_time,duration_minutes,calories&start_time=gte.\(date)T00:00:00&start_time=lt.\(date)T23:59:59.999&order=start_time.asc"
        var request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)

        struct Row: Decodable {
            let source: String
            let title: String
            let start_time: String
            let duration_minutes: Int
            let calories: Int?
        }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()

        return try JSONDecoder().decode([Row].self, from: data).compactMap { row in
            guard let start = withFractional.date(from: row.start_time) ?? plain.date(from: row.start_time) else {
                return nil
            }
            return WorkoutTimelineEntry(
                source: row.source,
                title: row.title,
                startTime: start,
                durationMinutes: row.duration_minutes,
                calories: row.calories
            )
        }
    }

    // MARK: - Edge Functions

    /// Cached server-side (one Claude call per user per day) -- safe to
    /// call every time the user opens the AI plan section, not just once.
    /// `selectedTitle`/`selectedBodyPart` are the workout the user checked
    /// in RecommendationDetailView -- the plan is built around that pick,
    /// not a generic "some workout for today's category" choice.
    /// `notes` is optional freeform text the user typed right after
    /// checking a workout (e.g. "sore shoulder today") -- folded into the
    /// generation prompt for this call only, not persisted.
    func fetchOrGenerateAIWorkoutPlan(date: String, selectedTitle: String, selectedBodyPart: String, notes: String? = nil, targetDurationMinutes: ClosedRange<Int>? = nil) async throws -> AIWorkoutPlan {
        var request = try await authorizedRequest(path: "functions/v1/generate-workout-plan", method: "POST", timeout: 180)
        var body: [String: Any] = [
            "date": date,
            "selection": ["title": selectedTitle, "bodyPart": selectedBodyPart],
        ]
        if let notes { body["notes"] = notes }
        if let targetDurationMinutes {
            body["targetDurationRange"] = ["min": targetDurationMinutes.lowerBound, "max": targetDurationMinutes.upperBound]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)

        // The guardrail answers 200 with a flag rather than an error status,
        // since being withheld is a normal outcome, not a failure. Checked
        // before decoding the plan: that decode would throw on this shape and
        // surface as "couldn't generate a plan", hiding the real reason.
        struct SafetyResponse: Decodable { let safety_flag: Bool; let message: String? }
        if let safety = try? JSONDecoder().decode(SafetyResponse.self, from: data), safety.safety_flag {
            throw SupabaseError.safetyBlocked(
                message: safety.message ?? "Please check with a healthcare professional before starting a new workout."
            )
        }
        struct LockedResponse: Decodable { let locked: Bool; let message: String? }
        if let locked = try? JSONDecoder().decode(LockedResponse.self, from: data), locked.locked {
            throw SupabaseError.workoutLocked(message: locked.message ?? "Today's workout is already logged.")
        }
        struct LimitResponse: Decodable { let generation_limit_reached: Bool; let message: String? }
        if let limit = try? JSONDecoder().decode(LimitResponse.self, from: data), limit.generation_limit_reached {
            throw SupabaseError.generationLimitReached(message: limit.message ?? "You've used today's AI workout generations.")
        }
        return try JSONDecoder().decode(AIWorkoutPlan.self, from: data)
    }

    /// Step 1 of the gym-photo-workout flow -- sends a client-compressed
    /// gym photo for equipment recognition. `imageData` should already be
    /// resized/compressed (~1024px longest edge, JPEG quality ~0.6) by the
    /// caller before this is invoked.
    func analyzeGymPhoto(imageData: Data) async throws -> GymPhotoEquipmentResult {
        var request = try await authorizedRequest(path: "functions/v1/analyze-gym-photo", method: "POST", timeout: 120)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "imageBase64": imageData.base64EncodedString(),
        ])

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        return try JSONDecoder().decode(GymPhotoEquipmentResult.self, from: data)
    }

    /// Steps 3+4 of the gym-photo-workout flow, combined -- deterministic
    /// template selection (server-side, gated by the safety guardrail)
    /// plus Luna's wording pass. `date` is used server-side to look up
    /// today's already-computed category and readiness data; that
    /// safety-relevant decision is never trusted from the client.
    func generateGymWorkout(date: String, confirmedEquipment: [String]) async throws -> GymWorkoutOutcome {
        var request = try await authorizedRequest(path: "functions/v1/generate-gym-workout", method: "POST", timeout: 180)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "date": date,
            "confirmedEquipment": confirmedEquipment,
        ])

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)

        struct SafetyResponse: Decodable { let safety_flag: Bool; let message: String? }
        if let safety = try? JSONDecoder().decode(SafetyResponse.self, from: data), safety.safety_flag {
            return .safetyBlocked(message: safety.message ?? "Please check with a healthcare professional before starting a new workout.")
        }
        struct LockedResponse: Decodable { let locked: Bool; let message: String? }
        if let locked = try? JSONDecoder().decode(LockedResponse.self, from: data), locked.locked {
            throw SupabaseError.workoutLocked(message: locked.message ?? "Today's workout is already logged.")
        }
        struct LimitResponse: Decodable { let generation_limit_reached: Bool; let message: String? }
        if let limit = try? JSONDecoder().decode(LimitResponse.self, from: data), limit.generation_limit_reached {
            return .generationLimitReached(message: limit.message ?? "You've used today's AI workout generations.")
        }
        struct TitleDTO: Decodable { let title: String; let bodyPart: String }
        let titleInfo = try JSONDecoder().decode(TitleDTO.self, from: data)
        let plan = try JSONDecoder().decode(AIWorkoutPlan.self, from: data)
        return .plan(plan, title: titleInfo.title, bodyPart: titleInfo.bodyPart)
    }

    /// Today's persisted AI plan, if any exists yet -- survives app
    /// relaunch, unlike the in-memory plan a view session holds. Feeds
    /// Home's persistent "AI-generated workout" card and the
    /// generate-button disable-once-confirmed gate.
    func fetchTodaysAIPlan(date: String) async throws -> TodaysAIPlan? {
        let path = "rest/v1/ai_workout_plan?date=eq.\(date)&select=category,plan,selected_title,added_to_plan,source&limit=1"
        var request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        let rows = try JSONDecoder().decode([TodaysAIPlan].self, from: data)
        return rows.first
    }

    /// "Add to today's plan" -- server-side because ai_workout_plan has no
    /// client-facing write RLS policy (see confirm-ai-plan's own comment).
    func confirmAIPlan(date: String) async throws {
        var request = try await authorizedRequest(path: "functions/v1/confirm-ai-plan", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["date": date])
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    /// Fire-and-forget from SubscriptionManager.refreshEntitlement -- lets
    /// server-side generation-limit checks read a recent (client-reported,
    /// not cryptographically verified) subscription tier. See
    /// generationLimits.ts's own comment on this trust model.
    func updateSubscriptionTier(_ tier: String) async throws {
        guard let userId = currentUserID else { return }
        var request = try await authorizedRequest(path: "rest/v1/users", method: "POST")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": userId, "subscription_tier": tier])
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    func invokeGenerateRecommendation(date: String, healthkit: HealthKitSnapshot?) async throws -> DailyRecommendation {
        var body: [String: Any] = ["date": date]
        if let healthkit {
            var hk: [String: Any] = [:]
            if let v = healthkit.sleepHours { hk["sleepHours"] = v }
            if let v = healthkit.hrvMs { hk["hrvMs"] = v }
            if let v = healthkit.restingHr { hk["restingHr"] = v }
            if let v = healthkit.sleepLightHours { hk["sleepLightHours"] = v }
            if let v = healthkit.sleepDeepHours { hk["sleepDeepHours"] = v }
            if let v = healthkit.sleepRemHours { hk["sleepRemHours"] = v }
            if let v = healthkit.sleepAwakeHours { hk["sleepAwakeHours"] = v }
            body["healthkit"] = hk
        }

        var request = try await authorizedRequest(path: "functions/v1/generate-recommendation", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        return try JSONDecoder().decode(DailyRecommendation.self, from: data)
    }

    /// Sets or clears the user's own "request a rest/active-recovery day"
    /// override for `date` -- distinct from generate-recommendation's
    /// health-data-driven caps, this wins outright over all of them
    /// server-side. `category: nil` clears an existing request. Throws
    /// (rather than silently no-op-ing) if no recommendation exists yet
    /// for that date -- callers should ensure today's recommendation has
    /// already loaded before offering this affordance.
    func setRecommendationOverride(date: String, category: RecommendationCategory?) async throws {
        // `category?.rawValue ?? NSNull()` reaches the server as JSON
        // `null` when clearing -- a plain Swift `nil` inside `[String: Any]`
        // would instead be silently dropped by JSONSerialization.
        let body: [String: Any] = ["date": date, "category": category?.rawValue ?? NSNull()]
        var request = try await authorizedRequest(path: "functions/v1/set-recommendation-override", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    struct ConnectionStatus: Decodable {
        struct Provider: Decodable {
            let connected: Bool
            let needsReconnect: Bool
        }
        let whoop: Provider
        let oura: Provider
    }

    /// Server-verified Whoop/Oura connection health -- distinct from
    /// AppState.connectedProviders, which is a local cache set once at
    /// connect time and never re-verified. A refresh-token failure
    /// server-side (revoked access, expired refresh token) has no other
    /// way to reach the client; see fetch-connection-status.
    func fetchConnectionStatus() async throws -> ConnectionStatus {
        let request = try await authorizedRequest(path: "functions/v1/fetch-connection-status", method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        return try JSONDecoder().decode(ConnectionStatus.self, from: data)
    }

    /// Backfills the last N days right after a wearable is connected, so
    /// the calendar strip and HRV baseline aren't stuck waiting day-by-day
    /// for history to accumulate -- reuses generate-recommendation itself
    /// (it already accepts any `date`, not just "today"), since Whoop/Oura
    /// both expose historical recovery/readiness/sleep/workout data via
    /// the same endpoints. Best-effort and silent: a failed day just stays
    /// a gray dot, same as before the device was connected. Sequential
    /// (not parallel) to stay well under Whoop/Oura per-user rate limits.
    func backfillRecentHistory(days: Int = 14) async {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current

        for offset in 1...days {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            _ = try? await invokeGenerateRecommendation(date: formatter.string(from: date), healthkit: nil)
        }
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

    // MARK: - Beta opt-in (self-service beta_optins table, RLS own-row)

    /// Whether the caller has opted into beta features -- own-row select.
    func fetchBetaOptIn() async throws -> Bool {
        let path = "rest/v1/beta_optins?select=user_id&limit=1"
        let request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        struct Row: Decodable { let user_id: String }
        return !(try JSONDecoder().decode([Row].self, from: data)).isEmpty
    }

    /// Inserts (opt in) or deletes (opt out) the caller's own row -- direct
    /// RLS write, same trust model as logWorkout.
    func setBetaOptIn(_ enabled: Bool) async throws {
        guard let userId = currentUserID else { throw SupabaseError.notSignedIn }
        if enabled {
            var request = try await authorizedRequest(path: "rest/v1/beta_optins", method: "POST")
            // ignore-duplicates: re-enabling after a missed response must
            // not 409 on the already-present pk row.
            request.setValue("resolution=ignore-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["user_id": userId])
            let (data, response) = try await urlSession.data(for: request)
            try Self.assertSuccess(response, data: data)
        } else {
            var request = try await authorizedRequest(path: "rest/v1/beta_optins?user_id=eq.\(userId)", method: "DELETE")
            request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            let (data, response) = try await urlSession.data(for: request)
            try Self.assertSuccess(response, data: data)
        }
    }

    // MARK: - user_feedback

    /// Direct insert via RLS (`user_feedback_insert_own`) -- user-entered
    /// content, same pattern as `logWorkout`. The device/app context comes
    /// in as parameters (captured by the feedback UI at submit time) so
    /// this stays a dumb transport.
    func submitFeedback(
        type: String,
        message: String,
        appVersion: String,
        build: String,
        osVersion: String,
        deviceModel: String
    ) async throws {
        guard let userId = currentUserID else { throw SupabaseError.notSignedIn }
        var request = try await authorizedRequest(path: "rest/v1/user_feedback", method: "POST")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "user_id": userId,
            "type": type,
            "message": message,
            "app_version": appVersion,
            "build": build,
            "os_version": osVersion,
            "device_model": deviceModel,
        ])

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    // MARK: - Sport goals (feature-flagged, see Config.enableSportGoals)

    /// RLS-gated catalog read -- `sports` visibility is filtered server-side
    /// by status, so an empty result means the feature is off for this user.
    func fetchSportCatalog() async throws -> SportCatalog {
        let sportsRequest = try await authorizedRequest(path: "rest/v1/sports?select=*&order=name.asc", method: "GET")
        let (sportsData, sportsResponse) = try await urlSession.data(for: sportsRequest)
        try Self.assertSuccess(sportsResponse, data: sportsData)
        let sports = try JSONDecoder().decode([Sport].self, from: sportsData)
        guard !sports.isEmpty else { return SportCatalog() }

        let goalsRequest = try await authorizedRequest(path: "rest/v1/sport_goals?select=*&order=name.asc", method: "GET")
        let (goalsData, goalsResponse) = try await urlSession.data(for: goalsRequest)
        try Self.assertSuccess(goalsResponse, data: goalsData)
        // Goals are re-filtered to visible sports so a sport flipped dark
        // can never leak its goals through a laxer sport_goals policy.
        let visibleSportIds = Set(sports.map(\.id))
        let goals = try JSONDecoder().decode([SportGoal].self, from: goalsData)
            .filter { visibleSportIds.contains($0.sportId) }
        return SportCatalog(sports: sports, goals: goals)
    }

    /// Calls the create-goal edge function -- it validates, runs the safety
    /// keyword pass, and either creates the goal or returns conflicts for
    /// the explicit-acknowledgment flow.
    func createGoal(_ goalRequest: CreateGoalRequest) async throws -> CreateGoalOutcome {
        var body: [String: Any] = [
            "kind": goalRequest.kind.rawValue,
            "targetKind": goalRequest.targetKind.rawValue,
            "acknowledgeConflicts": goalRequest.acknowledgeConflicts,
        ]
        if let v = goalRequest.goalId { body["goalId"] = v }
        if let v = goalRequest.baselineValue { body["baselineValue"] = v }
        if let v = goalRequest.baselineStage { body["baselineStage"] = v }
        if let v = goalRequest.targetText { body["targetText"] = v }
        if let v = goalRequest.givenText { body["givenText"] = v }
        if let v = goalRequest.workoutText { body["workoutText"] = v }
        if let v = goalRequest.coachName { body["coachName"] = v }
        if let v = goalRequest.durationWeeks { body["durationWeeks"] = v }
        if let v = goalRequest.customMetricName { body["customMetricName"] = v }
        if let v = goalRequest.customMetricUnit { body["customMetricUnit"] = v }
        if let v = goalRequest.assignmentPhotoPath { body["assignmentPhotoPath"] = v }
        if let v = goalRequest.frequencyPerWeek { body["frequencyPerWeek"] = v }
        if let v = goalRequest.scheduleRule { body["scheduleRule"] = v.rawValue }
        if let v = goalRequest.scheduleDays { body["scheduleDays"] = v }
        if let v = goalRequest.courtDays { body["courtDays"] = v }

        var request = try await authorizedRequest(path: "functions/v1/create-goal", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)

        // Conflicts come back as 200 + {conflicts} -- a normal outcome that
        // needs the user's acknowledgment, not an error.
        struct ConflictsResponse: Decodable { let conflicts: [GoalSafetyConflict] }
        if let decoded = try? JSONDecoder().decode(ConflictsResponse.self, from: data), !decoded.conflicts.isEmpty {
            return .conflicts(decoded.conflicts)
        }
        // create-goal answers { created: true, goal: <row> } -- use that row
        // directly instead of re-fetching the active goal afterwards.
        struct CreatedResponse: Decodable { let goal: UserGoal }
        return .created(try JSONDecoder().decode(CreatedResponse.self, from: data).goal)
    }

    /// Plain read via RLS -- the one `status='active'` row, if any.
    func fetchActiveGoal() async throws -> UserGoal? {
        let path = "rest/v1/user_goal?status=eq.active&select=*&limit=1"
        let request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        return try JSONDecoder().decode([UserGoal].self, from: data).first
    }

    /// Everything that isn't active, newest first -- completed rows ARE the
    /// achievements log; paused rows are resumable.
    func fetchGoalHistory() async throws -> [UserGoal] {
        let path = "rest/v1/user_goal?status=neq.active&select=*&order=created_at.desc"
        let request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        return try JSONDecoder().decode([UserGoal].self, from: data)
    }

    /// User-owned lifecycle transitions (pause/resume/abandon/complete) --
    /// direct RLS PATCH, same trust level as workout_log edits.
    func updateGoalStatus(id: String, status: UserGoalStatus, pauseReason: GoalPauseReason? = nil, resultValue: Double? = nil) async throws {
        var body: [String: Any] = ["status": status.rawValue]
        body["pause_reason"] = pauseReason?.rawValue ?? NSNull()
        if status == .completed {
            body["completed_at"] = Date().ISO8601Format()
            if let resultValue { body["result_value"] = resultValue }
        }
        var request = try await authorizedRequest(path: "rest/v1/user_goal?id=eq.\(id)", method: "PATCH")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    /// Chart history for one goal, oldest first.
    func fetchGoalMeasurements(userGoalId: String) async throws -> [GoalMeasurement] {
        let path = "rest/v1/goal_measurement_log?user_goal_id=eq.\(userGoalId)&select=*&order=measured_at.asc"
        let request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        return try JSONDecoder().decode([GoalMeasurement].self, from: data)
    }

    /// Direct RLS insert -- user-entered measurement, `logWorkout` pattern.
    func insertMeasurement(userGoalId: String, kind: GoalMeasurementKind, value: Double) async throws {
        guard let userId = currentUserID else { throw SupabaseError.notSignedIn }
        var request = try await authorizedRequest(path: "rest/v1/goal_measurement_log", method: "POST")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "user_id": userId,
            "user_goal_id": userGoalId,
            "kind": kind.rawValue,
            "value": value,
            "measured_at": Date().ISO8601Format(),
        ])
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    /// Coach-assignment photo into its private bucket (body-photos
    /// archetype: user-scoped path, binary body). Returns the storage path.
    func uploadAssignmentPhoto(imageData: Data) async throws -> String {
        guard let userId = currentUserID else { throw SupabaseError.notSignedIn }
        let path = "\(userId)/assignment-\(UUID().uuidString).jpg"
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "\(Config.supabaseURL.absoluteString)/storage/v1/object/coach-assignments/\(path)")!)
        request.httpMethod = "POST"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        return path
    }

    // MARK: - Request helpers

    /// `timeout` above the 60s URLSession default is for LLM-generation
    /// endpoints only: a fresh generation (cold start + schema compilation
    /// + up to two sequential model calls) can legitimately outlive 60s,
    /// and cutting it off client-side while the server finishes and caches
    /// is exactly the "fails first, works on retry" bug.
    private func authorizedRequest(path: String, method: String, timeout: TimeInterval? = nil) async throws -> URLRequest {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "\(Config.supabaseURL.absoluteString)/\(path)")!)
        request.httpMethod = method
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let timeout { request.timeoutInterval = timeout }
        return request
    }

    private static func assertSuccess(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            // Generation functions (generate-workout-plan, generate-gym-
            // workout) answer this way specifically when their own
            // Anthropic/OpenAI call failed -- see
            // _shared/anthropicErrors.ts. Surfaced as its own case so
            // callers can show an honest "not your fault, retrying won't
            // help" message instead of a generic request-failed one.
            struct ServiceUnavailableResponse: Decodable { let service_unavailable: Bool }
            if let flagged = try? JSONDecoder().decode(ServiceUnavailableResponse.self, from: data), flagged.service_unavailable {
                throw SupabaseError.serviceUnavailable
            }
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
        /// Present for Google/email sign-in (unlike Apple, which never
        /// includes it here -- that flow captures email from the
        /// ASAuthorizationAppleIDCredential directly instead).
        let email: String?
    }
}

enum SupabaseError: LocalizedError {
    case notSignedIn
    case requestFailed(status: Int, message: String)
    /// The server's safety guardrail withheld generation. Its message is
    /// authored server-side and shown verbatim -- never reworded here, and
    /// never made specific about which condition triggered it.
    case safetyBlocked(message: String)
    /// Today's workout is already logged -- the server refused to generate
    /// or replace the plan rather than silently overwriting what's shown
    /// for an already-completed day.
    case workoutLocked(message: String)
    /// Today's AI-generation cap (1/day free & monthly, 3/day annual) is
    /// used up -- distinct from workoutLocked, which is about an already-
    /// completed day, not a quota.
    case generationLimitReached(message: String)
    /// The generation function's own LLM call failed (Anthropic/OpenAI
    /// unavailable, rate-limited, or the account is out of credits) --
    /// distinct from every case above, which are normal/expected server
    /// decisions. Retrying immediately won't help; this needs the team to
    /// go check the provider account. See _shared/anthropicErrors.ts.
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in."
        case .safetyBlocked(let message):
            return message
        case .workoutLocked(let message):
            return message
        case .generationLimitReached(let message):
            return message
        case .serviceUnavailable:
            return "Soma's AI service is temporarily unavailable. We've been notified -- please try again later."
        case .requestFailed(let status, let message):
            return "Request failed (\(status)): \(message)"
        }
    }
}
