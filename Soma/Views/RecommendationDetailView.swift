import SwiftUI

/// Sheet shown when tapping the Home recommendation card. Everything here
/// is fixed, template-driven content (per-category step target/workouts,
/// per-reason explanation/tip, with real numbers substituted in) -- no
/// AI-generated freeform text, matching the rest of the app's approach.
struct RecommendationDetailView: View {
    let recommendation: DailyRecommendation

    @State private var snapshots: [DailySnapshotRow] = []
    @State private var averageSteps: Double?
    @State private var profile: UserProfile = .empty
    @State private var loggedTitlesToday: Set<String> = []
    @State private var recentBodyPartCounts: [BodyPartFocus: Int] = [:]
    @State private var shuffleSeed: UInt64 = 0
    @State private var selectedTitle: String?
    @State private var selectedBodyPart: String?
    @State private var selectedDurationRange: ClosedRange<Int>?
    @State private var preGenerationNotes = ""
    @State private var aiPlan: AIWorkoutPlan?
    /// Set the moment a plan is first shown -- the most honest available
    /// approximation of "when the workout started" without a dedicated
    /// start-workout timer. Feeds workout_log.started_at, which lets
    /// DayDetailView match wearable heart-rate data to the exact session
    /// window later, instead of the whole day.
    @State private var planStartedAt: Date?
    @State private var isLoadingAIPlan = false
    @State private var aiPlanError: String?
    /// True once "Add to today's plan" has been confirmed for `aiPlan` --
    /// distinct from `isCompletedToday` (a separate, later, explicit action).
    @State private var addedToPlan = false
    @State private var isAddingToPlan = false
    @State private var addToPlanError: String?

    @State private var isMarkingComplete = false
    @State private var feedbackText = ""
    @State private var addonSuggestions: [String] = []
    @State private var isFetchingAddons = false

    /// Set only via the "give me a standard workout anyway" / active-
    /// recovery-type override affordance, shown when a cap has been
    /// applied. See `effectiveCategory`.
    @State private var overrideCategory: RecommendationCategory?

    @State private var injuryStates: [InjuryRecoveryState] = []
    // Body-part redirects currently active for the user's injuries (e.g.
    // "lower_body": "upper_body" for a knee injury) -- steers the
    // suggestion list away from a conflicting body part before the user
    // even picks one. generate-workout-plan runs the same resolution
    // server-side as a defense-in-depth fallback if this list is stale.
    @State private var injurySubstitutions: [String: String] = [:]
    // Tags checked in during THIS view session -- hides the row immediately
    // without waiting on a re-fetch of injuryStates.
    @State private var checkedInTagsToday: Set<String> = []
    @State private var injuryCheckinMessage: String?

    /// Lets HomeView hand off an already-generated gym-photo plan so it
    /// shows up here immediately -- the "Take a Picture of Your Gym" entry
    /// point now lives on Home (not here), so this is the only way a
    /// gym-photo result reaches this view.
    init(recommendation: DailyRecommendation, seededPlan: AIWorkoutPlan? = nil, seededTitle: String? = nil, seededBodyPart: String? = nil) {
        self.recommendation = recommendation
        _aiPlan = State(initialValue: seededPlan)
        _selectedTitle = State(initialValue: seededTitle)
        _selectedBodyPart = State(initialValue: seededBodyPart)
    }

    /// True once the user has explicitly logged today's workout as done
    /// (via "Mark Workout Complete") -- generating/viewing an AI plan does
    /// NOT complete it, only tapping that button does. Only one workout is
    /// tracked per day, matching the single daily category/recommendation
    /// model, so once true the day's pick is locked in.
    private var isCompletedToday: Bool { !loggedTitlesToday.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.category.displayTitle)
                        .font(Theme.display)
                    Text(recommendation.message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                CardView {
                    Text("Today's step target")
                        .font(.body.bold())
                    Text(recommendation.category.stepTarget)
                        .font(.title2.bold())
                        .foregroundStyle(Theme.pillFill)
                    if let averageSteps {
                        Text("You've averaged ~\(Int(averageSteps)) steps/day over the last week.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                CardView {
                    HStack {
                        Text("Workouts that fit today")
                            .font(.body.bold())
                        Spacer()
                        Button {
                            shuffleSeed += 1
                        } label: {
                            Label("Try another", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption.bold())
                        }
                    }
                    Text(isCompletedToday ? "Today's pick, completed." : "Check the one you want to do today, then tap Generate AI Workout.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(filteredWorkoutSuggestions) { suggestion in
                        workoutRow(suggestion)
                    }
                }

                CardView {
                    Text("AI-generated workout")
                        .font(.body.bold())
                    Text("Exact exercises, sets, weights, and how to do each one -- built around the workout you picked above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Fixed, non-LLM-generated -- never rely on the model to
                    // include this in its own output. Shown whenever the
                    // user's profile has pregnancy set, regardless of what
                    // plan is displayed below.
                    if profile.pregnancy == true {
                        Text(Self.pregnancyDisclaimer)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.top, 2)
                    }

                    if let aiPlan {
                        AIWorkoutPlanView(plan: aiPlan)

                        if isCompletedToday {
                            Label("Workout completed today", systemImage: "crown.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.yellow)
                                .padding(.top, 10)

                            if isFetchingAddons {
                                HStack {
                                    ProgressView()
                                    Text("Thinking of ideas for next time…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 6)
                            } else if !addonSuggestions.isEmpty {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Ideas for next time, based on your feedback")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    ForEach(addonSuggestions, id: \.self) { suggestion in
                                        Text("• \(suggestion)")
                                            .font(.caption)
                                    }
                                }
                                .padding(.top, 6)
                            }
                        } else {
                            if let aiPlanError {
                                Text(aiPlanError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            if addedToPlan {
                                Label("Added to today's plan", systemImage: "checkmark.circle.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                                    .padding(.top, 4)
                            } else {
                                if let addToPlanError {
                                    Text(addToPlanError)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                PillButton(title: "Add to today's plan", isEnabled: !isAddingToPlan) {
                                    Task { await addToTodaysPlan() }
                                }
                                .padding(.top, 4)
                            }

                            TextField("Feedback for next time (optional)", text: $feedbackText, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                                .padding(.top, 8)
                            PillButton(title: "Mark Workout Complete", isEnabled: !isMarkingComplete) {
                                Task { await markWorkoutComplete() }
                            }
                            .padding(.top, 8)
                        }
                    } else if isLoadingAIPlan {
                        GenerationProgressView(message: "Building your plan…", estimatedSeconds: 8)
                            .padding(.top, 4)
                    } else {
                        if let aiPlanError {
                            Text(aiPlanError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if selectedTitle == nil {
                            Text("Check a workout above first.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        } else {
                            TextField("Anything Soma should know for today's workout? (optional)", text: $preGenerationNotes, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                                .padding(.top, 4)
                        }
                        PillButton(title: "Generate AI Workout", isEnabled: selectedTitle != nil && !isLoadingAIPlan) {
                            Task { await loadAIPlan() }
                        }
                        .padding(.top, 4)
                    }
                }

                CardView {
                    Text("Why today")
                        .font(.body.bold())
                    Text(explanationText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if recommendation.sleepCapApplied {
                        Text("Note: today's intensity was capped because of short sleep, even though recovery looked strong.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if recommendation.injuryCapApplied {
                        Text("Note: today's intensity was capped because of a noted injury, even though recovery looked strong.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if recommendation.loadCapApplied {
                        Text("Note: today's intensity was capped because of a strenuous session very recently, even though recovery looked strong.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if recommendation.volumeCapApplied {
                        Text("Note: today's intensity was capped because of a high training volume over the last week, even though recovery looked strong.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if recommendation.consecutiveDaysCapApplied, overrideCategory == nil {
                        Text(recommendation.category == .rest
                            ? "Note: you've trained several days in a row without a break, so today is a full rest day, even though recovery looked strong."
                            : "Note: you've trained 5+ days in a row, so today is active recovery -- light movement only, even though recovery looked strong.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        if let preCapCategory = recommendation.preCapCategory, preCapCategory != recommendation.category {
                            Button("Give me a standard workout anyway") {
                                overrideCategory = preCapCategory
                            }
                            .font(.caption.bold())
                            .padding(.top, 2)
                        }
                    }
                    if let overrideCategory, recommendation.consecutiveDaysCapApplied {
                        HStack(spacing: 4) {
                            Text("Showing \(overrideCategory.displayTitle) workouts instead.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Undo") { self.overrideCategory = nil }
                                .font(.caption.bold())
                        }
                    }
                    if recommendation.injuryProtocolCapApplied {
                        Text("Note: today's intensity was capped to light because of an active severe-injury recovery protocol, even though recovery looked strong.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if recommendation.injuryProtocolModerateCapApplied {
                        Text("Note: today's intensity was capped to moderate because of an active injury recovery protocol, even though recovery looked strong enough for push hard.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    // Says out loud when the read is thin. Without this a run
                    // of identical days is indistinguishable from the app
                    // being broken -- which is exactly how testers read it.
                    if let caveat = recommendation.dataConfidence?.caveat {
                        Text(caveat)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !openInjuryCheckins.isEmpty {
                    CardView {
                        Text("Injury check-in")
                            .font(.body.bold())
                        ForEach(openInjuryCheckins) { state in
                            injuryCheckinRow(state)
                        }
                        if let injuryCheckinMessage {
                            Text(injuryCheckinMessage)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.top, 4)
                        }
                    }
                }

                CardView {
                    Text("Look out for tomorrow")
                        .font(.body.bold())
                    Text(personalizedTomorrowTip)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .somaBackground()
        .task {
            await loadContext()
        }
    }

    private var explanationText: String {
        switch recommendation.reason {
        case .whoopHigh, .whoopMedium, .whoopLow:
            let value = snapshots.first(where: { $0.source == "whoop" })?.recoveryScore
            return String(format: recommendation.reason.explanationTemplate, formattedNumber(value))
        case .ouraHigh, .ouraMediumHigh, .ouraMedium, .ouraLow:
            let value = snapshots.first(where: { $0.source == "oura" })?.readinessScore
            return String(format: recommendation.reason.explanationTemplate, formattedNumber(value))
        case .healthkitHigh, .healthkitMedium, .healthkitLow, .insufficientData, .unknown:
            return recommendation.reason.explanationTemplate
        }
    }

    private func formattedNumber(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(Int(value.rounded()))
    }

    /// Deterministic, never LLM-generated -- same standing rule this
    /// codebase applies to every other safety/guidance-adjacent string.
    /// Layers real, currently-known context (which cap fired today, recent
    /// body-part frequency, stated goals) on top of the base band-based
    /// tip, checked in priority order -- so two days with the same
    /// recommendation category genuinely differ in what they tell the
    /// user, instead of repeating identical copy. Falls through to the
    /// original per-reason tip only when none of the richer signals apply.
    private var personalizedTomorrowTip: String {
        if recommendation.volumeCapApplied {
            return "Today was capped for high training volume over the last week. Tomorrow, favor a lighter session or full rest -- accumulated fatigue, not just last night's sleep, is driving this one."
        }
        if recommendation.consecutiveDaysCapApplied {
            return "You've trained several days in a row. A genuine rest or active-recovery day tomorrow (short walk, light mobility) will do more for your next hard session than pushing through again."
        }
        if recommendation.injuryProtocolCapApplied || recommendation.injuryProtocolModerateCapApplied {
            return "You're in an active injury-recovery window. Keep tomorrow's intensity conservative even if recovery data looks good -- the check-ins are what actually clear you to progress, not a single good reading."
        }
        if recommendation.pregnancyCapApplied {
            return "General guidance for tomorrow: favor controlled, moderate sessions and listen to how your body responds -- your care provider's advice takes priority over this app's recommendation."
        }
        // Body-part imbalance: the same focus trained on most of the last
        // 4 logged days -- a real, evidence-based nudge toward variety
        // (recovery and balanced development both benefit from it),
        // not a fabricated observation.
        if let (dominant, count) = recentBodyPartCounts.max(by: { $0.value < $1.value }), count >= 3 {
            return "You've focused on \(dominant.displayName.lowercased()) \(count) of your last 4 logged sessions. Consider shifting focus tomorrow -- both recovery and balanced progress benefit from rotating which areas you load."
        }
        // Goal-aware: cardio-focused goal but no cardio-tagged session in
        // recent history (recentBodyPartCounts has no .cardio entry at all).
        if profile.goals.contains(.cardioEndurance), recentBodyPartCounts[.cardio] == nil {
            return "Your goals include cardio endurance, but recent sessions haven't included one. If tomorrow's intensity allows, a cardio-focused session would round things out."
        }
        return recommendation.reason.tomorrowTip
    }

    /// A single-select checkbox per suggestion -- checking one is what
    /// "Generate AI Workout" builds its plan around. Locked once a workout
    /// has been logged for the day (see `isCompletedToday`), so the choice
    /// can't be swapped out from under an already-generated plan.
    private func workoutRow(_ suggestion: WorkoutSuggestion) -> some View {
        let isSelected = selectedTitle == suggestion.title
        return Button {
            selectedTitle = suggestion.title
            selectedBodyPart = suggestion.bodyPart.rawValue
            selectedDurationRange = suggestion.targetDurationMinutes
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Theme.pillFill : .secondary)
                    .font(.body)
                VStack(alignment: .leading, spacing: 2) {
                    if suggestion.id == filteredWorkoutSuggestions.first?.id {
                        Text("SOMA TOP RECOMMENDATION")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.pillFill))
                    }
                    Text(suggestion.title)
                        .font(.subheadline)
                    Text(suggestion.bodyPart.displayName)
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.pillFill)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(isCompletedToday)
        .opacity(isCompletedToday && !isSelected ? 0.4 : 1)
        .padding(.vertical, 4)
    }

    /// Filters the fixed candidate list down to what the user's saved
    /// equipment/injuries actually support, prioritizes matches for their
    /// saved goals, then deprioritizes (not removes) whichever body parts
    /// have been trained most in the last 7 days -- avoids stacking the
    /// same muscle group repeatedly across the week, not just avoiding an
    /// exact repeat of yesterday. "Try another" reshuffles within what's
    /// left via a seeded shuffle, so repeated taps give a different order
    /// deterministically rather than a fresh random flicker each render.
    /// Never returns an empty list -- falls back to the unfiltered set if
    /// filtering would otherwise leave nothing to show. The first item in
    /// this ranked order is shown as "SOMA Top Recommendation" in
    /// `workoutRow`.
    /// The category actually in effect for suggestion/logging purposes --
    /// the server's recommendation unless the user has tapped the override
    /// affordance below, in which case their choice wins. Session-local
    /// only: never written back as the server's own record of what was
    /// actually recommended, so the day's real history stays honest.
    private var effectiveCategory: RecommendationCategory {
        overrideCategory ?? recommendation.category
    }

    private var filteredWorkoutSuggestions: [WorkoutSuggestion] {
        let all = effectiveCategory.workoutSuggestions
        let hasInjury = !profile.injuryTags.isEmpty

        var candidates = profile.equipment.isEmpty
            ? all
            : all.filter { $0.equipment == .bodyweightOnly || profile.equipment.contains($0.equipment) }

        if hasInjury {
            candidates = candidates.filter { !$0.highImpact }
        }
        // Genuine substitution, not just exclusion: don't even offer a
        // suggestion whose body part conflicts with a moderate/severe
        // injury -- generation would silently redirect it anyway, so
        // showing it here would mismatch the title the user picked
        // against what actually gets built.
        if !injurySubstitutions.isEmpty {
            let redirected = candidates.filter { injurySubstitutions[$0.bodyPart.rawValue] == nil }
            if !redirected.isEmpty {
                candidates = redirected
            }
        }
        if candidates.isEmpty {
            candidates = all
        }

        if shuffleSeed > 0 {
            var rng = SeededGenerator(seed: shuffleSeed)
            candidates.shuffle(using: &rng)
        }

        let goalSet = Set(profile.goals)
        // Stable sort: matching-goal suggestions float to the top, then
        // whichever body part has been trained less recently/frequently
        // this week floats above one trained more (repeat, not remove --
        // still selectable if the user actually wants to repeat a lift).
        return candidates.sorted { lhs, rhs in
            let lhsGoalMatch = !lhs.goals.isDisjoint(with: goalSet)
            let rhsGoalMatch = !rhs.goals.isDisjoint(with: goalSet)
            if lhsGoalMatch != rhsGoalMatch { return lhsGoalMatch && !rhsGoalMatch }

            let lhsCount = recentBodyPartCounts[lhs.bodyPart] ?? 0
            let rhsCount = recentBodyPartCounts[rhs.bodyPart] ?? 0
            return lhsCount < rhsCount
        }
    }

    /// Generates (or fetches the cached) AI plan around whatever's checked
    /// above. This only builds/shows the plan -- it does NOT mark the
    /// workout done. Completion is a separate explicit step
    /// (`markWorkoutComplete`), so the user can review the plan before
    /// committing to having done it.
    ///
    /// Reads `selectedTitle`/`selectedBodyPart` directly rather than
    /// looking the title up in `recommendation.category.workoutSuggestions`
    /// -- a gym-photo-generated workout's title/bodyPart aren't in that
    /// fixed list, so a lookup would silently fail for it.
    private func loadAIPlan() async {
        guard let selectedTitle, let selectedBodyPart else { return }

        isLoadingAIPlan = true
        aiPlanError = nil
        defer { isLoadingAIPlan = false }
        let trimmedNotes = preGenerationNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        AnalyticsManager.shared.promptSubmitted()
        do {
            aiPlan = try await SupabaseClient.shared.fetchOrGenerateAIWorkoutPlan(
                date: recommendation.date,
                selectedTitle: selectedTitle,
                selectedBodyPart: selectedBodyPart,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                targetDurationMinutes: selectedDurationRange
            )
            AnalyticsManager.shared.aiResponseReceived()
            if planStartedAt == nil { planStartedAt = Date() }
            // A freshly generated plan always starts unconfirmed, matching
            // the server resetting added_to_plan on every real generation.
            // (loadContext's restore path is what sets this true again for
            // an already-confirmed plan on reopen -- this line only runs
            // right after this view itself triggered a generation.)
            addedToPlan = false
        } catch SupabaseError.safetyBlocked(let message) {
            // Shown verbatim. A generic "try again in a moment" would be a
            // lie -- retrying cannot help, and the user would keep tapping.
            aiPlanError = message
        } catch SupabaseError.workoutLocked(let message) {
            aiPlanError = message
        } catch SupabaseError.generationLimitReached(let message) {
            aiPlanError = message
        } catch SupabaseError.serviceUnavailable {
            // Distinct from the generic case below -- an Anthropic-side
            // failure (rate limit, exhausted credits, bad key), not
            // something a retry can fix. See classifyGenerationError.
            aiPlanError = SupabaseError.serviceUnavailable.errorDescription
        } catch {
            aiPlanError = "Couldn't generate a plan right now. Try again in a moment."
        }
    }

    private func addToTodaysPlan() async {
        isAddingToPlan = true
        addToPlanError = nil
        defer { isAddingToPlan = false }
        do {
            try await SupabaseClient.shared.confirmAIPlan(date: recommendation.date)
            addedToPlan = true
        } catch {
            addToPlanError = "Couldn't add to today's plan. Try again."
        }
    }

    /// The explicit "I finished this" step -- creates the workout_log row
    /// that Home's calendar strip renders as a crown for the day.
    private func markWorkoutComplete() async {
        guard let selectedTitle, let selectedBodyPart else { return }

        isMarkingComplete = true
        aiPlanError = nil
        defer { isMarkingComplete = false }
        let trimmedFeedback = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await SupabaseClient.shared.logWorkout(
                date: recommendation.date,
                title: selectedTitle,
                bodyPart: selectedBodyPart,
                // The category actually done (which may be the user's
                // override), not the server's original capped
                // recommendation -- keeps future load-tracking honest.
                category: effectiveCategory.rawValue,
                feedback: trimmedFeedback.isEmpty ? nil : trimmedFeedback,
                planSnapshot: aiPlan,
                startedAt: planStartedAt,
                endedAt: planStartedAt != nil ? Date() : nil
            )
            loggedTitlesToday.insert(selectedTitle)
            if !trimmedFeedback.isEmpty {
                await fetchAddonSuggestions(feedback: trimmedFeedback, title: selectedTitle, bodyPart: selectedBodyPart)
            }
        } catch {
            aiPlanError = "Couldn't log this workout. Try again."
        }
    }

    /// Best-effort -- if this fails, the workout is still logged fine, the
    /// user just doesn't see follow-up ideas this time.
    private func fetchAddonSuggestions(feedback: String, title: String, bodyPart: String) async {
        isFetchingAddons = true
        defer { isFetchingAddons = false }
        let bodyPartDisplay = BodyPartFocus(rawValue: bodyPart)?.displayName ?? bodyPart
        addonSuggestions = (try? await SupabaseClient.shared.fetchWorkoutAddonSuggestions(
            feedback: feedback,
            workoutTitle: title,
            bodyPart: bodyPartDisplay
        )) ?? []
    }

    private func loadContext() async {
        async let snapshotFetch: [DailySnapshotRow]? = try? SupabaseClient.shared.fetchTodaysSnapshots(date: recommendation.date)
        async let stepsFetch: Double? = HealthKitManager.isAvailable ? await HealthKitManager.shared.fetchRecentAverageSteps() : nil
        async let profileFetch = fetchProfileSafely()
        async let todaysLogsFetch: [WorkoutLogEntry] = (try? await SupabaseClient.shared.fetchWorkoutLogs(date: recommendation.date)) ?? []
        async let recentLogsFetch: [WorkoutLogEntry] = (try? await SupabaseClient.shared.fetchWorkoutLogs(
            fromDate: Self.daysBefore(6, of: recommendation.date),
            toDate: Self.daysBefore(1, of: recommendation.date)
        )) ?? []
        async let injuryStatesFetch: [InjuryRecoveryState] = (try? await SupabaseClient.shared.fetchInjuryRecoveryStates()) ?? []
        async let injurySubstitutionsFetch: [String: String] = (try? await SupabaseClient.shared.fetchInjurySubstitutions()) ?? [:]

        snapshots = await snapshotFetch ?? []
        averageSteps = await stepsFetch
        profile = await profileFetch
        injuryStates = await injuryStatesFetch
        injurySubstitutions = await injurySubstitutionsFetch
        let todaysLogs = await todaysLogsFetch
        loggedTitlesToday = Set(todaysLogs.map(\.title))
        recentBodyPartCounts = await recentLogsFetch.compactMap { BodyPartFocus(rawValue: $0.bodyPart) }
            .reduce(into: [:]) { counts, bodyPart in counts[bodyPart, default: 0] += 1 }

        // Already logged today (e.g. reopening the sheet) -- restore the
        // choice and pull the cached plan rather than leaving the picker
        // blank as if nothing had been done yet.
        if selectedTitle == nil, let alreadyLogged = todaysLogs.first {
            selectedTitle = alreadyLogged.title
            selectedBodyPart = alreadyLogged.bodyPart
            await loadAIPlan()
        } else if aiPlan == nil, selectedTitle == nil {
            // Not completed, but a plan may already exist for today (e.g.
            // generated and/or added to plan, then the sheet was closed and
            // reopened -- from Home's persistent AI-generated-workout card,
            // most commonly). Restore it instead of showing a blank
            // generator, same reasoning as the completed-log branch above.
            if let existing = try? await SupabaseClient.shared.fetchTodaysAIPlan(date: recommendation.date) {
                aiPlan = existing.plan
                selectedTitle = existing.selectedTitle
                // bodyPart isn't a persisted column -- recover it from a
                // substitution record if one exists, else from matching the
                // title against the fixed suggestion list (works for the
                // normal flow; a gym-photo title won't match, so fall back
                // to full_body rather than leaving this nil, which would
                // silently no-op "Mark Workout Complete").
                selectedBodyPart = existing.plan.substitutedBodyPart
                    ?? recommendation.category.workoutSuggestions.first(where: { $0.title == existing.selectedTitle })?.bodyPart.rawValue
                    ?? BodyPartFocus.fullBody.rawValue
                addedToPlan = existing.addedToPlan
            }
        }
    }

    /// Active/recovering injury protocols that haven't been checked in on
    /// today yet -- shown once per tag per day.
    private var openInjuryCheckins: [InjuryRecoveryState] {
        injuryStates.filter {
            !$0.hasCheckedInToday(recommendation.date) && !checkedInTagsToday.contains($0.injuryTag)
        }
    }

    private func injuryCheckinRow(_ state: InjuryRecoveryState) -> some View {
        let tag = InjuryTag(rawValue: state.injuryTag)
        return VStack(alignment: .leading, spacing: 6) {
            Text("How's your \(tag?.displayName.lowercased() ?? state.injuryTag) feeling today?")
                .font(.subheadline)
            HStack(spacing: 10) {
                ForEach([InjuryCheckinResponse.better, .same, .worse], id: \.self) { response in
                    Button(response.rawValue.capitalized) {
                        Task { await submitCheckin(tag: state.injuryTag, response: response) }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.bold())
                }
            }
        }
        .padding(.top, 4)
    }

    private func submitCheckin(tag: String, response: InjuryCheckinResponse) async {
        guard let injuryTag = InjuryTag(rawValue: tag) else { return }
        do {
            let result = try await SupabaseClient.shared.recordInjuryCheckin(tag: injuryTag, response: response, date: recommendation.date)
            checkedInTagsToday.insert(tag)
            injuryCheckinMessage = result.escalate ? result.escalationMessage : nil
        } catch {
            injuryCheckinMessage = "Couldn't record that check-in. Try again."
        }
    }

    /// Mirrors pregnancyGuidance.ts's PREGNANCY_DISCLAIMER verbatim -- fixed
    /// UI copy, not sourced from the LLM response, so it always renders
    /// regardless of what the model actually returned.
    static let pregnancyDisclaimer = "This is general guidance only, not medical advice -- please follow your doctor's or midwife's recommendations, especially if you have any pregnancy complications."

    private func fetchProfileSafely() async -> UserProfile {
        guard let userId = SupabaseClient.shared.currentUserID else { return .empty }
        return (try? await SupabaseClient.shared.fetchProfile(id: userId)) ?? .empty
    }

    private static func daysBefore(_ days: Int, of dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        guard let date = formatter.date(from: dateString),
              let earlier = Calendar.current.date(byAdding: .day, value: -days, to: date) else {
            return dateString
        }
        return formatter.string(from: earlier)
    }
}

/// Tiny deterministic RNG so "Try another" gives a stable, different order
/// per tap instead of reshuffling on every SwiftUI re-render.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

#Preview {
    RecommendationDetailView(
        recommendation: DailyRecommendation(
            date: "2026-07-21",
            category: .light,
            message: "Take it easier today — a short walk, mobility work, or light yoga (20-30 min) is ideal.",
            reason: .healthkitMedium,
            sleepCapApplied: false,
            injuryCapApplied: false,
            loadCapApplied: false,
            consecutiveDaysCapApplied: false,
            injuryProtocolCapApplied: false,
            injuryProtocolModerateCapApplied: false,
            pregnancyCapApplied: false,
            volumeCapApplied: false,
            preCapCategory: nil,
            dataConfidence: .low
        )
    )
}
