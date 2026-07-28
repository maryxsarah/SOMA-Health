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
        contactEmail: String? = nil,
        marketingOptIn: Bool? = nil
    ) async throws {
        var body: [String: Any] = ["id": id]
        if let wakeTimePref { body["wake_time_pref"] = wakeTimePref }
        if let onboardingComplete { body["onboarding_complete"] = onboardingComplete }
        if let contactEmail { body["contact_email"] = contactEmail }
        if let marketingOptIn { body["marketing_opt_in"] = marketingOptIn }

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
        if let trainer = answers.worksWithTrainer { body["works_with_trainer"] = trainer }
        if let goal = answers.goal { body["goals"] = [goal.rawValue] }
        if let desired = answers.desiredWeightKg { body["desired_weight_kg"] = desired }
        if let pace = answers.goalPace { body["goal_pace"] = pace.rawValue }
        if !answers.blockers.isEmpty { body["blockers"] = answers.blockers.map(\.rawValue) }
        if let diet = answers.dietType { body["diet_type"] = diet.rawValue }
        if let accomplishment = answers.accomplishmentGoal { body["accomplishment_goal"] = accomplishment.rawValue }
        body["marketing_opt_in"] = answers.marketingOptIn

        var request = try await authorizedRequest(path: "rest/v1/users", method: "POST")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
    }

    /// Plain read via RLS -- used by ProfileView on appear.
    func fetchProfile(id: String) async throws -> UserProfile {
        let path = "rest/v1/users?id=eq.\(id)&select=contact_email,goals,other_goal_notes,equipment,other_equipment_notes,injury_tags,injury_notes,experience_level,pregnancy&limit=1"
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
        body["experience_level"] = profile.experienceLevel?.rawValue ?? NSNull()
        body["pregnancy"] = profile.pregnancy ?? NSNull()

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
        let path = "rest/v1/daily_recommendation?date=eq.\(date)&select=date,category,message,reason,data_confidence,sleep_cap_applied,injury_cap_applied,load_cap_applied&limit=1"
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

        let path = "rest/v1/daily_recommendation?date=gte.\(startStr)&date=lte.\(endStr)&select=date,category,message,reason,data_confidence,sleep_cap_applied,injury_cap_applied,load_cap_applied&order=date.asc"
        var request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        return try JSONDecoder().decode([DailyRecommendation].self, from: data)
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

    // MARK: - workout_log

    /// Marks a suggestion as done for the day -- client-writable directly
    /// via RLS (`workout_log_insert_own`), same pattern as the `users`
    /// profile writes; no Edge Function needed for user-entered content.
    /// `feedback` is optional free-text the user can leave when marking a
    /// workout done (e.g. "I like a 5-10min incline treadmill warm-up") --
    /// generate-workout-plan folds recent feedback into future plans for a
    /// similar workout.
    func logWorkout(date: String, title: String, bodyPart: String, category: String, feedback: String? = nil) async throws {
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
        let path = "rest/v1/workout_log?date=eq.\(date)&select=id,date,title,body_part,category,completed_at,feedback&order=completed_at.asc"
        var request = try await authorizedRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)
        return try JSONDecoder().decode([WorkoutLogEntry].self, from: data)
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

    /// Today's actual recorded workout sessions from connected wearables
    /// (Oura/Whoop) -- distinct from workout_log (what the user told Soma
    /// they did). HealthKit's own workouts are read separately, on-device,
    /// via HealthKitManager -- the caller merges both into one timeline.
    func fetchProviderWorkoutTimeline(date: String) async throws -> [WorkoutTimelineEntry] {
        var request = try await authorizedRequest(path: "functions/v1/fetch-workout-timeline", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["date": date])

        let (data, response) = try await urlSession.data(for: request)
        try Self.assertSuccess(response, data: data)

        struct DTO: Decodable {
            let source: String
            let title: String
            let start_time: String
            let duration_minutes: Int
            let calories: Int?
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
                calories: dto.calories
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
    func fetchOrGenerateAIWorkoutPlan(date: String, selectedTitle: String, selectedBodyPart: String) async throws -> AIWorkoutPlan {
        var request = try await authorizedRequest(path: "functions/v1/generate-workout-plan", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "date": date,
            "selection": ["title": selectedTitle, "bodyPart": selectedBodyPart],
        ])

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
        return try JSONDecoder().decode(AIWorkoutPlan.self, from: data)
    }

    /// Step 1 of the gym-photo-workout flow -- sends a client-compressed
    /// gym photo for equipment recognition. `imageData` should already be
    /// resized/compressed (~1024px longest edge, JPEG quality ~0.6) by the
    /// caller before this is invoked.
    func analyzeGymPhoto(imageData: Data) async throws -> GymPhotoEquipmentResult {
        var request = try await authorizedRequest(path: "functions/v1/analyze-gym-photo", method: "POST")
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
        var request = try await authorizedRequest(path: "functions/v1/generate-gym-workout", method: "POST")
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
        return .plan(try JSONDecoder().decode(AIWorkoutPlan.self, from: data))
    }

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
    /// The server's safety guardrail withheld generation. Its message is
    /// authored server-side and shown verbatim -- never reworded here, and
    /// never made specific about which condition triggered it.
    case safetyBlocked(message: String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in."
        case .safetyBlocked(let message):
            return message
        case .requestFailed(let status, let message):
            return "Request failed (\(status)): \(message)"
        }
    }
}
