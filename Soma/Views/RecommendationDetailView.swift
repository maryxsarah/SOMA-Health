import SwiftUI
import SuperwallKit

/// Sheet shown when tapping the Home recommendation card. Everything here
/// is fixed, template-driven content (per-category step target/workouts,
/// per-reason explanation/tip, with real numbers substituted in) -- no
/// AI-generated freeform text, matching the rest of the app's approach.
struct RecommendationDetailView: View {
    let recommendation: DailyRecommendation

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var snapshots: [DailySnapshotRow] = []
    @State private var averageSteps: Double?
    @State private var todaySteps: Double?
    @State private var profile: UserProfile = .empty
    @State private var loggedTitlesToday: Set<String> = []
    /// Sum of caloriesBurned across today's logged workouts, when any are
    /// known -- feeds the same DayLoadState computation HomeView's
    /// readinessCard uses, so this sheet's pick card agrees with Home about
    /// whether today's already done (item 2 fix). Nil (not zero) when
    /// nothing's logged, or nothing logged has a resolved calorie number
    /// yet -- DayLoadState treats that the same as "logged, unknown load".
    @State private var todaysLoggedCalories: Int?
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
    @State private var isRegenerating = false
    @State private var aiPlanError: String?
    /// Set instead of `aiPlanError` specifically for a generation-limit
    /// hit -- 13a turns that one case into a calm amber nudge with an
    /// Upgrade link, distinct from the plain red text every other
    /// generation-failure case still gets.
    @State private var generationLimitMessage: String?
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

    // Active sport goal -- drives the "… · GOAL BLOCK" eyebrow over the
    // plan's first block. Nil (no eyebrow) when no active goal exists.
    @State private var activeSportGoal: UserGoal?
    @State private var sportGoalCatalog: SportCatalog?

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

    /// Same DayLoadState computation HomeView's readinessCard uses, kept in
    /// sync so this sheet never contradicts what Home already showed
    /// (item 2 fix).
    private var dayLoadState: DayLoadState {
        DayLoadState.resolve(
            hasLoggedWorkout: isCompletedToday,
            loggedKcal: todaysLoggedCalories,
            target: recommendation.category.dayLoadTargetKcal
        )
    }

    /// Same copy as HomeView.readinessHeadline, kept identical so the sheet
    /// never contradicts the card it was opened from.
    private var headerHeadline: String {
        switch dayLoadState {
        case .pending, .partiallyDone:
            return recommendation.category.displayTitle
        case .fulfilled:
            return String(localized: "home.readiness.fulfilled.headline", defaultValue: "Done for today", comment: "Home: readiness card headline once today's logged activity has met the day's target")
        case .overreached:
            return String(localized: "home.readiness.overreached.headline", defaultValue: "Plenty today", comment: "Home: readiness card headline once today's logged activity is well past the day's target")
        }
    }

    private var headerSubtitle: String {
        switch dayLoadState {
        case .pending:
            return recommendation.message
        case .partiallyDone:
            let logged = todaysLoggedCalories ?? 0
            let target = recommendation.category.dayLoadTargetKcal
            return String(localized: "home.readiness.partiallyDone.subtitle", defaultValue: "You've logged \(logged) of \(target) kcal today. A light session would finish it off.", comment: "Home: readiness card subtitle once some, but not enough, of today's activity target is logged; both numbers are kcal")
        case .fulfilled:
            if let calories = todaysLoggedCalories, calories > 0 {
                return String(localized: "home.readiness.fulfilled.subtitleWithCalories", defaultValue: "\(calories) kcal logged. Daily target met.", comment: "Home: readiness card subtitle once today's activity target is met, with a real calorie number")
            }
            return String(localized: "home.readiness.fulfilled.subtitle", defaultValue: "Today's activity is logged. Daily target met.", comment: "Home: readiness card subtitle once today's activity target is met, no calorie number available")
        case .overreached:
            return String(localized: "home.readiness.overreached.subtitle", defaultValue: "Today's already a lot. Tomorrow will be easier.", comment: "Home: readiness card subtitle once today's logged activity is well past the day's target")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Guide 04 header sheet: serif category, ONE line of
                // guidance, then a row pairing the "Why this?" disclosure
                // with the step tracker pill. The prose that used to fill
                // the top 40% of the screen now lives in the disclosure.
                VStack(alignment: .leading, spacing: 10) {
                    Text(headerHeadline)
                        .font(SomaType.screenTitle)
                    Text(headerSubtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(SomaTokens.ink2)
                        .lineLimit(3)
                    SomaDisclosure {
                        whyDisclosureBody
                    } triggerAccessory: {
                        stepTrackerPill
                    }
                }

                pickCard

                if !visibleSuggestions.isEmpty {
                    alternativesCard
                }

                CardView {
                    HStack(spacing: 9) {
                        sectionIcon("sparkles")
                        Text(String(localized: "recommendationDetail.aiWorkoutCard.title", defaultValue: "AI-generated workout", comment: "Title of the AI-generated-workout card"))
                            .font(.body.bold())
                    }
                    Text(String(localized: "recommendationDetail.aiWorkoutCard.subtitle", defaultValue: "Exact exercises, sets, weights, and how to do each one — built around the workout you picked above.", comment: "Subtitle explaining what the AI-generated-workout card provides"))
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
                        // 11d: "Try another" becomes "Regenerate", same icon
                        // same spot -- once a plan exists the choice is
                        // made, so pickCard's own reshuffle affordance hides
                        // (see `pickCard`) and this one takes over instead.
                        if !isCompletedToday {
                            HStack {
                                Text(String(localized: "recommendationDetail.yourWorkoutEyebrow", defaultValue: "YOUR WORKOUT", comment: "All-caps eyebrow label over the AI-generated plan once one exists"))
                                    .font(SomaType.eyebrow)
                                    .tracking(0.7)
                                    .foregroundStyle(SomaTokens.accent)
                                Spacer()
                                Button {
                                    Task { await loadAIPlan(forceRegenerate: true) }
                                } label: {
                                    HStack(spacing: 5) {
                                        if isRegenerating {
                                            ProgressView().controlSize(.mini)
                                        } else {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                                .font(.system(size: 12, weight: .semibold))
                                        }
                                        Text(String(localized: "recommendationDetail.regenerateButton", defaultValue: "Regenerate", comment: "Button that regenerates the AI workout plan for the current pick"))
                                            .font(.system(size: 12.5, weight: .semibold))
                                    }
                                    .foregroundStyle(SomaTokens.accent)
                                }
                                .buttonStyle(.plain)
                                .disabled(isRegenerating)
                            }
                            .padding(.top, 4)
                        }

                        // 13a: the conservative-weights note now lives
                        // inside AIWorkoutPlanView itself, merged into the
                        // same sentence/icon as the RPE explainer (used to
                        // be two separate footnotes on two screens).
                        AIWorkoutPlanView(plan: aiPlan, goalEyebrow: goalBlockEyebrow, isCompletedToday: isCompletedToday)

                        if isCompletedToday {
                            // 13c: the house gel-gold-on-amber-surface
                            // treatment -- a 30pt amber gel disc (not a flat
                            // system-yellow circle) on the amber nudge
                            // surface, deep-amber text -- this is the one
                            // badge on the whole screen that reads "you're
                            // done," so it gets a bit more visual weight
                            // than a caption.
                            HStack(spacing: 10) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        Color(red: 245 / 255, green: 205 / 255, blue: 120 / 255).opacity(0.95),
                                                        SomaTokens.warn.opacity(0.95)
                                                    ],
                                                    startPoint: .top, endPoint: .bottom
                                                )
                                            )
                                            .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                                            .overlay(
                                                Circle().strokeBorder(
                                                    LinearGradient(
                                                        stops: [
                                                            .init(color: .white.opacity(0.6), location: 0),
                                                            .init(color: .white.opacity(0), location: 0.5)
                                                        ],
                                                        startPoint: .top, endPoint: .bottom
                                                    ),
                                                    lineWidth: 1.5
                                                )
                                            )
                                            .shadow(color: SomaTokens.warn.opacity(0.3), radius: 4.5, x: 0, y: 4)
                                    )
                                Text(String(localized: "recommendationDetail.completedBadge", defaultValue: "Workout completed today", comment: "Badge shown once today's workout has been marked complete"))
                                    .font(.system(size: 13.5, weight: .bold))
                                    .foregroundStyle(Color(red: 0x9A / 255, green: 0x6A / 255, blue: 0x15 / 255))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(amberSurface(cornerRadius: 18))
                            .padding(.top, 10)

                            if isFetchingAddons {
                                HStack {
                                    ProgressView()
                                    Text(String(localized: "recommendationDetail.addonSuggestions.loading", defaultValue: "Thinking of ideas for next time…", comment: "Loading state while follow-up workout ideas are being fetched"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 6)
                            } else if !addonSuggestions.isEmpty {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(String(localized: "recommendationDetail.addonSuggestions.title", defaultValue: "Ideas for next time, based on your feedback", comment: "Header above the list of follow-up workout ideas"))
                                        .font(.caption.bold())
                                        .foregroundStyle(SomaTokens.ink3)
                                    ForEach(addonSuggestions, id: \.self) { suggestion in
                                        Text(String(localized: "recommendationDetail.addonSuggestions.bullet", defaultValue: "• \(suggestion)", comment: "One bulleted follow-up workout idea; placeholder is the server-provided suggestion text"))
                                            .font(.caption)
                                            .foregroundStyle(SomaTokens.inkParagraph)
                                    }
                                }
                                .padding(.top, 6)
                            }
                        } else {
                            if let generationLimitMessage {
                                generationLimitNudge(generationLimitMessage)
                            } else if let aiPlanError {
                                Text(aiPlanError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            if addedToPlan {
                                // 13a: a 20pt green gel disc + success-toned
                                // bold line, not a flat SF checkmark label.
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .heavy))
                                        .foregroundStyle(.white)
                                        .frame(width: 20, height: 20)
                                        .background(
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            Color(red: 94 / 255, green: 200 / 255, blue: 150 / 255).opacity(0.9),
                                                            SomaTokens.success.opacity(0.92)
                                                        ],
                                                        startPoint: .top, endPoint: .bottom
                                                    )
                                                )
                                                .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                                                .shadow(color: SomaTokens.success.opacity(0.28), radius: 3.5, x: 0, y: 3)
                                        )
                                    Text(String(localized: "recommendationDetail.addedToPlanBadge", defaultValue: "Added to today's plan", comment: "Badge confirming the AI plan was added to today's plan"))
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(SomaTokens.success)
                                }
                                .padding(.top, 4)
                            } else if let addToPlanError {
                                Text(addToPlanError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            // Committing (complete / add to plan) moved to
                            // the bottom bar -- one commitment area per
                            // screen (guide 00 §6), not buttons mid-card.
                            // No upper bound -- an upper-bounded lineLimit
                            // makes the field scroll its own text once full,
                            // which fights the outer ScrollView's drag when
                            // you touch down over the text itself.
                            TextField(
                                "",
                                text: $feedbackText,
                                prompt: Text(String(localized: "recommendationDetail.feedbackField.placeholder", defaultValue: "Feedback for next time (optional)", comment: "Placeholder for the optional post-workout feedback text field"))
                                    .foregroundStyle(SomaTokens.inkPlaceholder),
                                axis: .vertical
                            )
                            .lineLimit(2...)
                            .glassInput(cornerRadius: SomaTokens.rRow)
                                .padding(.top, 8)
                        }
                    } else if isLoadingAIPlan {
                        GenerationProgressView(estimatedSeconds: 8)
                            .padding(.top, 4)
                    } else {
                        if let generationLimitMessage {
                            generationLimitNudge(generationLimitMessage)
                        } else if let aiPlanError {
                            Text(aiPlanError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        // Generation itself fires from the bottom bar's
                        // "Start workout" -- only the optional note lives here.
                        // See the feedback field above -- no upper bound,
                        // same reason (avoids the internal-scroll-vs-outer-
                        // ScrollView drag conflict).
                        TextField(String(localized: "recommendationDetail.preGenNotes.placeholder", defaultValue: "Anything Soma should know for today's workout? (optional)", comment: "Placeholder for the optional pre-generation notes text field"), text: $preGenerationNotes, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...)
                            .padding(.top, 4)
                    }
                }

                if !openInjuryCheckins.isEmpty {
                    CardView {
                        Text(String(localized: "recommendationDetail.injuryCheckin.title", defaultValue: "Injury check-in", comment: "Title of the injury check-in card"))
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
                    HStack(alignment: .top, spacing: 12) {
                        sectionIcon("moon.fill")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "recommendationDetail.tomorrowCard.title", defaultValue: "Look out for tomorrow", comment: "Title of the tomorrow's-tip card"))
                                .font(.body.bold())
                            Text(personalizedTomorrowTip)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(20)
            // A fixed safety margin, not a value sized to clear bottomBar --
            // bottomBar reserves its OWN exact space via the safeAreaInset
            // below (and reserves none at all once isCompletedToday, when
            // it renders nothing), so double-padding for its height here
            // was pure guesswork that either wasted scroll distance or (once
            // completed) left content sitting right at the edge.
            .padding(.bottom, 24)
        }
        // 11a: this sheet had no visible dismiss affordance at all (swipe-
        // down only) -- a back chevron + "TODAY" eyebrow row, same glass-
        // circle recipe as the step pill/section icons. Pinned via
        // safeAreaInset(.top) rather than living inside the ScrollView's
        // own VStack -- as scroll content, it used to scroll away instead
        // of staying put like a real nav bar, which is what read as the
        // previous screen's own header showing through on top.
        .safeAreaInset(edge: .top) { topNavRow }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .somaSheetBackground()
        .task {
            await loadContext()
        }
    }

    // MARK: - Top nav row

    private var topNavRow: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SomaTokens.accent)
                    .frame(width: 40, height: 40)
                    .glassLens(cornerRadius: SomaTokens.rPill)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(String(localized: "recommendationDetail.topNav.eyebrow", defaultValue: "TODAY", comment: "All-caps eyebrow label in the top navigation row"))
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(SomaTokens.ink4)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background {
            LinearGradient(
                colors: [SomaTokens.surface.opacity(0.98), SomaTokens.surface.opacity(0.98), SomaTokens.surface.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .padding(.bottom, -20)
            .allowsHitTesting(false)
        }
    }

    /// Small glass-circle icon badge -- same recipe as `topNavRow`'s
    /// chevron, just 30pt, for the AI-workout/tomorrow-tip card headers.
    private func sectionIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(SomaTokens.accent)
            .frame(width: 30, height: 30)
            .glassLens(cornerRadius: SomaTokens.rPill)
    }

    /// 13a/13c's amber nudge surface -- soft warn-toned gradient with an
    /// inset amber hairline, never a flat system-orange fill.
    private func amberSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        SomaTokens.warnSoft,
                        Color(red: 240 / 255, green: 190 / 255, blue: 100 / 255).opacity(0.08)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(red: 240 / 255, green: 190 / 255, blue: 100 / 255).opacity(0.25), lineWidth: 1)
            )
    }

    /// 13a: replaces the old plain-red error text for a generation-limit
    /// hit with a calm amber nudge + a real "Upgrade" action -- the server
    /// message itself is shown verbatim (it already spells out the current
    /// tier's quota and reset timing), only the container changes. Icon
    /// disc is solid `warn`, body copy the design's muted amber-brown --
    /// system orange appears nowhere in this recipe.
    private func generationLimitNudge(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(SomaTokens.warn))
                .padding(.top, 1)
            Text(message)
                .font(.caption)
                .foregroundStyle(Color(red: 0x8A / 255, green: 0x75 / 255, blue: 0x50 / 255))
            Spacer(minLength: 8)
            Button {
                let handler = SuperwallDiagnostics.handler(placement: "view_premium")
                handler.onDismiss { _, result in
                    WinBackOfferManager.maybePresentAfterDecline(result: result)
                }
                Superwall.shared.register(placement: "view_premium", handler: handler)
            } label: {
                Text(String(localized: "recommendationDetail.generationLimit.upgrade", defaultValue: "Upgrade", comment: "Button in the amber generation-limit nudge card that opens the premium paywall"))
                    .font(.caption.bold())
                    .foregroundStyle(SomaTokens.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(amberSurface(cornerRadius: SomaTokens.rRow))
        .padding(.top, 4)
    }

    // MARK: - Why this? disclosure (was the "Why today" card)

    private var stepTargetText: String {
        let target = recommendation.category.stepTarget
        if let averageSteps {
            return String(localized: "recommendationDetail.stepTarget.withAverage", defaultValue: "Today's step target: \(target) — you've averaged ~\(Int(averageSteps.rounded()))/day over the last week.", comment: "Step-target sentence in the Why-this disclosure, shown when a recent average step count is available. First placeholder is the target range (e.g. '7,000–9,000 steps'), second is the rounded daily average.")
        }
        return String(localized: "recommendationDetail.stepTarget.noAverage", defaultValue: "Today's step target: \(target).", comment: "Step-target sentence in the Why-this disclosure, shown when no recent average step count is available. Placeholder is the target range (e.g. '7,000–9,000 steps').")
    }

    private var whyDisclosureBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Item 4 fix: the collapsed message line above is capped short
            // server-side and may have dropped the specific "why a cap
            // applied" clause -- messageDetail is the uncapped version of
            // that same sentence, so it still surfaces here rather than
            // disappearing. Nil for rows written before this column
            // existed, or when there was nothing more to add beyond the
            // (already short) message itself.
            if let messageDetail = recommendation.messageDetail, !messageDetail.isEmpty {
                Text(messageDetail)
            }
            Text(explanationText)
            Text(stepTargetText)
                .font(.system(size: 12.5))
            if let requested = recommendation.userRequestedCategory {
                        // Not styled as a warning (unlike the caps below) --
                        // this wasn't a safety downgrade, it's what the user
                        // themselves asked for.
                        Text(requested == .rest
                            ? String(localized: "recommendationDetail.requestedRest", defaultValue: "You asked for a rest day today.", comment: "Shown when the user explicitly requested a rest day")
                            : String(localized: "recommendationDetail.requestedActiveRecovery", defaultValue: "You asked for an active recovery day today.", comment: "Shown when the user explicitly requested an active recovery day"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if recommendation.sleepCapApplied {
                        Text(String(localized: "recommendationDetail.cap.sleep", defaultValue: "Note: today's intensity was capped because of short sleep, even though recovery looked strong.", comment: "Cap explanation shown in the Why-this disclosure when today's intensity was reduced due to short sleep"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if recommendation.hrvCapApplied {
                        Text(String(localized: "recommendationDetail.cap.hrv", defaultValue: "Note: today's intensity was capped because your HRV is noticeably below your usual baseline, even though recovery looked strong.", comment: "Cap explanation shown in the Why-this disclosure when today's intensity was reduced due to low HRV"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if recommendation.stressCapApplied {
                        Text(String(localized: "recommendationDetail.cap.stress", defaultValue: "Note: today's intensity was capped because of a high-stress day, even though recovery looked strong.", comment: "Cap explanation shown in the Why-this disclosure when today's intensity was reduced due to high stress"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if recommendation.injuryCapApplied {
                        Text(String(localized: "recommendationDetail.cap.injury", defaultValue: "Note: today's intensity was capped because of a noted injury, even though recovery looked strong.", comment: "Cap explanation shown in the Why-this disclosure when today's intensity was reduced due to a noted injury"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if recommendation.loadCapApplied {
                        Text(String(localized: "recommendationDetail.cap.load", defaultValue: "Note: today's intensity was capped because of a strenuous session very recently, even though recovery looked strong.", comment: "Cap explanation shown in the Why-this disclosure when today's intensity was reduced due to a recent strenuous session"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if recommendation.volumeCapApplied {
                        Text(String(localized: "recommendationDetail.cap.volume", defaultValue: "Note: today's intensity was capped because of a high training volume over the last week, even though recovery looked strong.", comment: "Cap explanation shown in the Why-this disclosure when today's intensity was reduced due to high recent training volume"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if recommendation.consecutiveDaysCapApplied, overrideCategory == nil {
                        Text(recommendation.category == .rest
                            ? String(localized: "recommendationDetail.cap.consecutiveDaysRest", defaultValue: "Note: you've trained several days in a row without a break, so today is a full rest day, even though recovery looked strong.", comment: "Cap explanation shown when several consecutive training days forced a full rest day")
                            : String(localized: "recommendationDetail.cap.consecutiveDaysActiveRecovery", defaultValue: "Note: you've trained 5+ days in a row, so today is active recovery -- light movement only, even though recovery looked strong.", comment: "Cap explanation shown when 5+ consecutive training days forced an active-recovery day"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                        if let preCapCategory = recommendation.preCapCategory, preCapCategory != recommendation.category {
                            Button(String(localized: "recommendationDetail.overrideCapButton", defaultValue: "Give me a standard workout anyway", comment: "Button offered when a consecutive-days cap forced a lighter day, letting the user override back to the pre-cap category")) {
                                overrideCategory = preCapCategory
                            }
                            .font(.caption.bold())
                            .padding(.top, 2)
                        }
                    }
                    if let overrideCategory, recommendation.consecutiveDaysCapApplied {
                        HStack(spacing: 4) {
                            Text(String(localized: "recommendationDetail.overrideActive.message", defaultValue: "Showing \(overrideCategory.displayTitle) workouts instead.", comment: "Shown after the user overrides a consecutive-days cap back to a standard workout. Placeholder is the workout category's display title (e.g. 'Moderate')."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(String(localized: "recommendationDetail.overrideActive.undoButton", defaultValue: "Undo", comment: "Button that reverts the standard-workout override back to the original capped recommendation")) { self.overrideCategory = nil }
                                .font(.caption.bold())
                        }
                    }
                    if recommendation.injuryProtocolCapApplied {
                        Text(String(localized: "recommendationDetail.cap.injuryProtocolSevere", defaultValue: "Note: today's intensity was capped to light because of an active severe-injury recovery protocol, even though recovery looked strong.", comment: "Cap explanation shown in the Why-this disclosure when today's intensity was capped to light due to an active severe-injury recovery protocol"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if recommendation.injuryProtocolModerateCapApplied {
                        Text(String(localized: "recommendationDetail.cap.injuryProtocolModerate", defaultValue: "Note: today's intensity was capped to moderate because of an active injury recovery protocol, even though recovery looked strong enough for push hard.", comment: "Cap explanation shown in the Why-this disclosure when today's intensity was capped to moderate due to an active injury recovery protocol"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if recommendation.injuryProtocolRestApplied {
                        Text(String(localized: "recommendationDetail.cap.injuryProtocolRest", defaultValue: "Note: today is a full rest day because of a severe injury you reported recently, or one that's been trending worse -- your safety comes before intensity here.", comment: "Cap explanation shown in the Why-this disclosure when today is a full rest day due to a severe injury recovery protocol"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if recommendation.moodCapApplied {
                        Text(String(localized: "recommendationDetail.cap.mood", defaultValue: "Note: today's intensity was eased based on how you said you're feeling, even though recovery looked strong.", comment: "Cap explanation shown in the Why-this disclosure when today's intensity was eased due to reported mood"))
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
    }

    private var explanationText: String {
        recommendation.reason.explanation(snapshots: snapshots)
    }

    // MARK: - Step tracker pill (guide 04: position, target, progress in 34pt)

    private var stepTrackerPill: some View {
        let target = effectiveCategory.stepTargetCount
        return Group {
            if let steps = todaySteps.map({ Int($0.rounded()) }) {
                let reached = steps >= target
                let overshoot = target > 0 ? Int((Double(steps - target) / Double(target) * 100).rounded()) : 0
                let progressText: String = {
                    if reached && overshoot >= 5 {
                        return String(localized: "recommendationDetail.steps.ahead", defaultValue: "\(steps.formatted()) / \(target.formatted()) · +\(overshoot)%", comment: "Step count vs today's target, shown once the user has exceeded the target by 5% or more. First two placeholders are the done/target step counts, third is the overshoot percentage.")
                    } else if reached {
                        return String(localized: "recommendationDetail.steps.goalHit", defaultValue: "\(steps.formatted()) / \(target.formatted()) · Goal hit", comment: "Step count vs today's target, shown once the target is reached. Placeholders are the done/target step counts.")
                    } else {
                        return String(localized: "recommendationDetail.steps.inProgress", defaultValue: "\(steps.formatted()) / \(target.formatted())", comment: "Step count vs today's target, still in progress. Placeholders are the done/target step counts.")
                    }
                }()
                HStack(spacing: 6) {
                    Image(systemName: reached ? "checkmark" : "figure.walk")
                        .font(.system(size: 11, weight: .bold))
                    Text(progressText)
                        .font(.system(size: 12, weight: .semibold))
                    Capsule()
                        .fill(reached ? SomaTokens.success.opacity(0.25) : SomaTokens.surface4)
                        .frame(width: 40, height: 4)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(reached ? SomaTokens.success : SomaTokens.accentDeep)
                                .frame(width: 40 * min(CGFloat(steps) / CGFloat(max(target, 1)), 1))
                        }
                }
                .foregroundStyle(reached ? SomaTokens.success : SomaTokens.accentDeep)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background {
                    if reached {
                        Capsule().fill(SomaTokens.successSoft)
                    } else {
                        Color.clear.glassLens()
                    }
                }
            } else if appState.connectedProviders.isEmpty {
                // No device at all -- say so instead of a silent target.
                // (Step counts come from Apple Health on-device; Oura/Whoop
                // don't sync steps into daily_snapshot yet.)
                HStack(spacing: 5) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(String(localized: "recommendationDetail.stepPill.noDevice", defaultValue: "Connect a device to track steps", comment: "Step-tracker pill, shown when no health/fitness device is connected"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(SomaTokens.ink3)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .glassLens()
            } else {
                // A device is connected but reported no steps (yet) --
                // state the target plainly rather than fabricating a count.
                Text(String(localized: "recommendationDetail.stepPill.targetOnly", defaultValue: "Target \(target.formatted()) steps", comment: "Step-tracker pill, shown when a device is connected but has reported no steps yet. Placeholder is the formatted step target count."))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SomaTokens.accentDeep)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .glassLens()
            }
        }
    }

    // MARK: - Soma's pick (guide 04: one recommendation, no checkboxes)

    /// The suggestion behind the current selection; nil for a seeded
    /// gym-photo title, which isn't in the fixed list.
    private var currentPickSuggestion: WorkoutSuggestion? {
        filteredWorkoutSuggestions.first { $0.title == selectedTitle }
    }

    /// ≤5 rows, everything that fits today -- including the current pick,
    /// shown with a selected state rather than removed. Tapping an option
    /// used to filter it out of this list once picked, which read as "my
    /// choice disappeared"; the pick stays visible and checked instead.
    private var visibleSuggestions: [WorkoutSuggestion] {
        Array(filteredWorkoutSuggestions.prefix(5))
    }

    private var pickCard: some View {
        CardView {
            HStack {
                Text(String(localized: "recommendationDetail.pickCard.eyebrow", defaultValue: "SOMA'S PICK", comment: "All-caps eyebrow label on the pick card"))
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(SomaTokens.accent)
                Spacer()
                // 11d: hides once a plan exists -- the choice is made, and
                // "Regenerate" (inside the AI-workout card below) takes over
                // as this screen's one reshuffle affordance.
                if !isCompletedToday, aiPlan == nil {
                    Button {
                        shuffleSeed += 1
                        selectTopSuggestion()
                    } label: {
                        Label(String(localized: "recommendationDetail.tryAnotherButton", defaultValue: "Try another", comment: "Button that reshuffles the pick card's suggested workout"), systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(SomaTokens.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(selectedTitle ?? String(localized: "recommendationDetail.loadingPick", defaultValue: "Loading today's pick…", comment: "Placeholder shown on the pick card while today's suggested workout is still loading"))
                .font(.system(size: 20, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(pickGearLine)
                .font(.system(size: 12.5))
                .foregroundStyle(SomaTokens.ink3)

            HStack(spacing: 8) {
                pickTile(label: LocalizedStringKey(String(localized: "recommendationDetail.pickTile.duration", defaultValue: "Duration", comment: "Label under the workout duration value on the pick card")), value: pickDurationText)
                pickTile(label: LocalizedStringKey(String(localized: "recommendationDetail.pickTile.effort", defaultValue: "Effort", comment: "Label under the workout effort/intensity value on the pick card")), value: effectiveCategory.displayTitle)
                pickTile(label: LocalizedStringKey(String(localized: "recommendationDetail.pickTile.exercises", defaultValue: "Exercises", comment: "Label under the exercise count value on the pick card")), value: pickExerciseCountText)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SomaTokens.success)
                    .padding(.top, 1)
                Text(pickStatusText)
                    .font(.caption)
                    .foregroundStyle(SomaTokens.ink3)
            }
        }
    }

    /// Extends the old binary isCompletedToday check with the graded
    /// DayLoadState -- "completed" alone didn't distinguish "closed
    /// today's quota" from "already went well past it" (item 2 fix).
    private var pickStatusText: String {
        guard isCompletedToday else {
            return aiPlan != nil
                ? String(localized: "recommendationDetail.pickStatus.planReady", defaultValue: "Exact sets, weights and how to do each one — ready below.", comment: "Pick-card status line once an AI plan has been generated")
                : String(localized: "recommendationDetail.pickStatus.planPending", defaultValue: "Exact sets, weights and how to do each one — built when you start.", comment: "Pick-card status line before an AI plan has been generated")
        }
        switch dayLoadState {
        case .overreached:
            return String(localized: "recommendationDetail.pickStatus.overreached", defaultValue: "Today's pick, completed — and then some.", comment: "Pick-card status line once today's workout is logged well past the day's target")
        default:
            return String(localized: "recommendationDetail.pickStatus.completed", defaultValue: "Today's pick, completed.", comment: "Pick-card status line once today's workout has been logged as complete")
        }
    }

    private var pickGearLine: String {
        if let suggestion = currentPickSuggestion {
            return suggestion.equipment.displayName
        }
        if aiPlan?.source == "gym_photo" {
            return String(localized: "recommendationDetail.gearLine.gymScan", defaultValue: "From your gym scan", comment: "Equipment/source line on the pick card, shown when the workout came from a scanned gym photo")
        }
        return String(localized: "recommendationDetail.gearLine.matched", defaultValue: "Matched to your equipment", comment: "Equipment/source line on the pick card, default case")
    }

    private var pickDurationText: String {
        if let actual = aiPlan?.actualDurationMinutes {
            return String(localized: "recommendationDetail.duration.minutes", defaultValue: "\(actual) min", comment: "Workout duration tile value, e.g. '45 min'")
        }
        guard let range = currentPickSuggestion?.targetDurationMinutes ?? selectedDurationRange else { return "—" }
        if range.lowerBound == range.upperBound {
            return String(localized: "recommendationDetail.duration.minutes", defaultValue: "\(range.lowerBound) min", comment: "Workout duration tile value, e.g. '45 min'")
        }
        return String(localized: "recommendationDetail.duration.range", defaultValue: "\(range.lowerBound)–\(range.upperBound) min", comment: "Workout duration range tile value, e.g. '30–40 min'")
    }

    private var pickExerciseCountText: String {
        guard let aiPlan else {
            return String(localized: "recommendationDetail.exercises.aiBuilt", defaultValue: "AI-built", comment: "Exercise-count tile value shown before a plan has been generated")
        }
        let count = aiPlan.warmUp.count + aiPlan.blocks.reduce(0) { $0 + $1.exercises.count } + aiPlan.coolDown.count
        return "\(count)"
    }

    private func pickTile(label: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(SomaTokens.ink4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .glassCardFlat(cornerRadius: SomaTokens.rTile)
    }

    // MARK: - Alternatives (guide 04: single-line rows, choosing opens it)

    private var alternativesCard: some View {
        CardView {
            HStack {
                Text(String(localized: "recommendationDetail.alternativesCard.title", defaultValue: "Workouts that fit today", comment: "Title of the card listing alternative workout suggestions for today"))
                    .font(.body.bold())
                Spacer()
                Text("\(visibleSuggestions.count)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink4)
            }
            ForEach(Array(visibleSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                if index > 0 {
                    Divider().overlay(SomaTokens.surface4)
                }
                let isSelected = suggestion.title == selectedTitle
                Button {
                    selectSuggestion(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .font(.system(size: 14, weight: .medium))
                                .multilineTextAlignment(.leading)
                                // Muted once selected -- this same title is
                                // already the pick card's own headline right
                                // above, at full emphasis; repeating that
                                // emphasis here would just be visual noise.
                                .foregroundStyle(isSelected ? SomaTokens.ink4 : SomaTokens.ink)
                            Text(String(localized: "recommendationDetail.alternativeRow.subtitle", defaultValue: "\(suggestion.bodyPart.displayName) · \(suggestion.equipment.displayName)", comment: "Subtitle under an alternative workout suggestion's title, joining its body part and equipment. Both placeholders are already-localized display names."))
                                .font(.system(size: 11.5))
                                .foregroundStyle(SomaTokens.ink4)
                        }
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .glassGel(.blue, cornerRadius: 11)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SomaTokens.ink4)
                        }
                    }
                    .padding(.vertical, 6)
                    // Must come after the padding above, not before -- a
                    // contentShape fixed on the pre-padding HStack leaves
                    // the row's own vertical padding as a dead tap zone
                    // (row visually spans it, but taps there don't land).
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Already the pick -- tapping again would be a no-op; only
                // non-selected rows are actionable, same as "no checkboxes."
                .disabled(isCompletedToday || isSelected)
            }
        }
    }

    private func selectSuggestion(_ suggestion: WorkoutSuggestion) {
        selectedTitle = suggestion.title
        selectedBodyPart = suggestion.bodyPart.rawValue
        selectedDurationRange = suggestion.targetDurationMinutes
        // A previously generated plan belongs to the old pick -- showing it
        // under the new title would let "Complete workout" log a mismatch.
        aiPlan = nil
        addedToPlan = false
        aiPlanError = nil
    }

    private func selectTopSuggestion() {
        guard let top = filteredWorkoutSuggestions.first else { return }
        selectSuggestion(top)
    }

    // MARK: - Bottom bar (guide 00 §6: one lg commitment per screen)

    @ViewBuilder
    private var bottomBar: some View {
        if !isCompletedToday {
            VStack(spacing: 9) {
                if aiPlan == nil {
                    SomaButton(title: LocalizedStringKey(String(localized: "recommendationDetail.startWorkoutButton", defaultValue: "Start workout", comment: "Primary bottom-bar CTA that generates the AI workout plan")), size: .lg, variant: .primary, isEnabled: selectedTitle != nil && !isLoadingAIPlan) {
                        Task { await loadAIPlan() }
                    }
                } else {
                    SomaButton(title: LocalizedStringKey(String(localized: "recommendationDetail.completeWorkoutButton", defaultValue: "Complete workout", comment: "Primary bottom-bar CTA that marks today's workout as done")), size: .lg, variant: .primary, isEnabled: !isMarkingComplete) {
                        Task { await markWorkoutComplete() }
                    }
                    if !addedToPlan {
                        SomaButton(title: LocalizedStringKey(String(localized: "recommendationDetail.addToPlanButton", defaultValue: "Add to today's plan", comment: "Secondary bottom-bar CTA that confirms the AI plan into today's plan")), size: .md, variant: .secondary, isEnabled: !isAddingToPlan) {
                            Task { await addToTodaysPlan() }
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 22)
            // Docks over a fade, not a hard white bar -- scrolled content
            // (the alternatives list, tomorrow's tip) reads through softly
            // instead of hard-clipping under an opaque strip.
            .background(
                LinearGradient(
                    colors: [SomaTokens.surface.opacity(0), SomaTokens.surface.opacity(0.85), SomaTokens.surface.opacity(0.98)],
                    startPoint: .top, endPoint: .bottom
                )
                .padding(.top, -34)
                .allowsHitTesting(false)
            )
        }
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
        if recommendation.injuryProtocolRestApplied {
            return String(localized: "recommendationDetail.tomorrowTip.injuryProtocolRest", defaultValue: "Today is a full rest day for your injury's sake. Tomorrow, only resume light activity if a check-in shows things are trending better -- pushing through too soon is what turns a short setback into a long one.", comment: "Tomorrow's-tip card, shown when today is a full rest day due to a severe injury recovery protocol")
        }
        if recommendation.volumeCapApplied {
            return String(localized: "recommendationDetail.tomorrowTip.volumeCap", defaultValue: "Today was capped for high training volume over the last week. Tomorrow, favor a lighter session or full rest -- accumulated fatigue, not just last night's sleep, is driving this one.", comment: "Tomorrow's-tip card, shown when today's intensity was capped for high training volume")
        }
        if recommendation.consecutiveDaysCapApplied {
            return String(localized: "recommendationDetail.tomorrowTip.consecutiveDays", defaultValue: "You've trained several days in a row. A genuine rest or active-recovery day tomorrow (short walk, light mobility) will do more for your next hard session than pushing through again.", comment: "Tomorrow's-tip card, shown when today's intensity was capped for consecutive training days")
        }
        if recommendation.injuryProtocolCapApplied || recommendation.injuryProtocolModerateCapApplied {
            return String(localized: "recommendationDetail.tomorrowTip.injuryProtocol", defaultValue: "You're in an active injury-recovery window. Keep tomorrow's intensity conservative even if recovery data looks good -- the check-ins are what actually clear you to progress, not a single good reading.", comment: "Tomorrow's-tip card, shown during an active injury-recovery protocol")
        }
        if recommendation.pregnancyCapApplied {
            return String(localized: "recommendationDetail.tomorrowTip.pregnancy", defaultValue: "General guidance for tomorrow: favor controlled, moderate sessions and listen to how your body responds -- your care provider's advice takes priority over this app's recommendation.", comment: "Tomorrow's-tip card, shown when today's intensity was capped for pregnancy")
        }
        if recommendation.moodCapApplied {
            return String(localized: "recommendationDetail.tomorrowTip.mood", defaultValue: "Today's session eased off based on how you said you were feeling. If tomorrow's check-in is better, intensity can pick back up -- this app tracks how you feel, not just how your wearable reads you.", comment: "Tomorrow's-tip card, shown when today's intensity was eased due to reported mood")
        }
        // Body-part imbalance: the same focus trained on most of the last
        // 4 logged days -- a real, evidence-based nudge toward variety
        // (recovery and balanced development both benefit from it),
        // not a fabricated observation.
        if let (dominant, count) = recentBodyPartCounts.max(by: { $0.value < $1.value }), count >= 3 {
            let bodyPart = dominant.displayName.lowercased()
            return String(localized: "recommendationDetail.tomorrowTip.bodyPartImbalance", defaultValue: "You've focused on \(bodyPart) \(count) of your last 4 logged sessions. Consider shifting focus tomorrow -- both recovery and balanced progress benefit from rotating which areas you load.", comment: "Tomorrow's-tip card, shown when one body part dominated recent sessions. First placeholder is the lowercased body-part name (from Models, not translated here), second is a session count.")
        }
        // Goal-aware: cardio-focused goal but no cardio-tagged session in
        // recent history (recentBodyPartCounts has no .cardio entry at all).
        if profile.goals.contains(.cardioEndurance), recentBodyPartCounts[.cardio] == nil {
            return String(localized: "recommendationDetail.tomorrowTip.cardioGoalGap", defaultValue: "Your goals include cardio endurance, but recent sessions haven't included one. If tomorrow's intensity allows, a cardio-focused session would round things out.", comment: "Tomorrow's-tip card, shown when the user has a cardio-endurance goal but no recent cardio sessions")
        }
        return recommendation.reason.tomorrowTip
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
    /// `forceRegenerate` is 11d's "Regenerate" -- same call, just telling
    /// the server to skip today's cached plan for this selection and build
    /// a fresh one. Shares this function (rather than a near-duplicate)
    /// since both are "get me a plan for the current selection", differing
    /// only in whether the cache is honored and which loading flag to flip.
    private func loadAIPlan(forceRegenerate: Bool = false) async {
        guard let selectedTitle, let selectedBodyPart else { return }

        if forceRegenerate { isRegenerating = true } else { isLoadingAIPlan = true }
        aiPlanError = nil
        generationLimitMessage = nil
        defer { if forceRegenerate { isRegenerating = false } else { isLoadingAIPlan = false } }
        let trimmedNotes = preGenerationNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        AnalyticsManager.shared.promptSubmitted()
        do {
            aiPlan = try await SupabaseClient.shared.fetchOrGenerateAIWorkoutPlan(
                date: recommendation.date,
                selectedTitle: selectedTitle,
                selectedBodyPart: selectedBodyPart,
                // currentPickSuggestion is nil for a gym-photo-generated
                // selection (see this function's own doc comment above) --
                // nil is the correct value to send there too, not a gap:
                // that flow is "whatever equipment the photo scan found",
                // not one of the fixed catalog's narrow EquipmentTag
                // categories, so the server's full-profile fallback is
                // exactly right for it, same as an older client.
                selectedEquipment: currentPickSuggestion?.equipment,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                targetDurationMinutes: selectedDurationRange,
                forceRegenerate: forceRegenerate
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
            // 13a: this specific case gets the amber nudge, not plain red
            // text -- see generationLimitNudge.
            generationLimitMessage = message
        } catch SupabaseError.serviceUnavailable {
            // Distinct from the generic case below -- an Anthropic-side
            // failure (rate limit, exhausted credits, bad key), not
            // something a retry can fix. See classifyGenerationError.
            aiPlanError = SupabaseError.serviceUnavailable.errorDescription
        } catch {
            aiPlanError = String(localized: "recommendationDetail.aiPlanError.generic", defaultValue: "Couldn't generate a plan right now. Try again in a moment.", comment: "Fallback error shown when AI workout plan generation fails for an unclassified reason")
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
            addToPlanError = String(localized: "recommendationDetail.addToPlanError", defaultValue: "Couldn't add to today's plan. Try again.", comment: "Error shown when confirming/adding the AI plan to today's plan fails")
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
                endedAt: planStartedAt != nil ? Date() : nil,
                reasonSnapshot: WorkoutReasonResolver.impactNote(source: "ai_plan", dayLoadState: dayLoadState)
            )
            loggedTitlesToday.insert(selectedTitle)
            // The evening reminder exists to nudge an UNlogged workout --
            // once one's actually done, cancel today's (only today's, the
            // identifier is day-stamped) pending request rather than
            // nagging someone who already finished.
            NotificationManager.shared.cancelEveningWorkoutReminder(for: recommendation.date)
            // Streak protection reminder for tomorrow + milestone
            // celebration if this log just crossed a tier -- best-effort,
            // fire-and-forget so a slow/failed fetch inside it never
            // blocks or fails the workout log that already succeeded above.
            Task { await NotificationManager.shared.handleWorkoutLogged(at: Date()) }
            if !trimmedFeedback.isEmpty {
                await fetchAddonSuggestions(feedback: trimmedFeedback, title: selectedTitle, bodyPart: selectedBodyPart)
            }
        } catch {
            aiPlanError = String(localized: "recommendationDetail.markCompleteError", defaultValue: "Couldn't log this workout. Try again.", comment: "Error shown when logging a completed workout fails")
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

    /// "VERTICAL JUMP · GOAL BLOCK" over the plan's first block -- gated on
    /// the PLAN's own goal_block marker, not just an active goal existing.
    private var goalBlockEyebrow: String? {
        guard Config.enableSportGoals, aiPlan?.goalBlock != nil,
              let activeSportGoal, activeSportGoal.status == .active else { return nil }
        let goalName = activeSportGoal.displayName(in: sportGoalCatalog).uppercased()
        return String(localized: "recommendationDetail.goalBlockEyebrow", defaultValue: "\(goalName) · GOAL BLOCK", comment: "Eyebrow label over the AI plan's first block when it's built around an active sport goal, e.g. 'VERTICAL JUMP · GOAL BLOCK'. Placeholder is the goal name, already uppercased.")
    }

    private func loadContext() async {
        async let snapshotFetch: [DailySnapshotRow]? = try? SupabaseClient.shared.fetchTodaysSnapshots(date: recommendation.date)
        async let stepsFetch: Double? = HealthKitManager.isAvailable ? await HealthKitManager.shared.fetchRecentAverageSteps() : nil
        async let todayStepsFetch: Double? = HealthKitManager.isAvailable ? await HealthKitManager.shared.fetchTodaysSteps() : nil
        async let profileFetch = fetchProfileSafely()
        async let todaysLogsFetch: [WorkoutLogEntry] = (try? await SupabaseClient.shared.fetchWorkoutLogs(date: recommendation.date)) ?? []
        async let recentLogsFetch: [WorkoutLogEntry] = (try? await SupabaseClient.shared.fetchWorkoutLogs(
            fromDate: Self.daysBefore(6, of: recommendation.date),
            toDate: Self.daysBefore(1, of: recommendation.date)
        )) ?? []
        async let injuryStatesFetch: [InjuryRecoveryState] = (try? await SupabaseClient.shared.fetchInjuryRecoveryStates()) ?? []
        async let injurySubstitutionsFetch: [String: String] = (try? await SupabaseClient.shared.fetchInjurySubstitutions()) ?? [:]
        // Joined into the concurrent batch -- these two were serial before.
        async let activeGoalFetch: UserGoal? = Config.enableSportGoals
            ? (try? await SupabaseClient.shared.fetchActiveGoal()) : nil
        async let catalogFetch: SportCatalog? = Config.enableSportGoals
            ? (try? await SupabaseClient.shared.fetchSportCatalog()) : nil

        activeSportGoal = await activeGoalFetch
        if activeSportGoal != nil {
            sportGoalCatalog = await catalogFetch
        }

        snapshots = await snapshotFetch ?? []
        averageSteps = await stepsFetch
        todaySteps = await todayStepsFetch
        profile = await profileFetch
        injuryStates = await injuryStatesFetch
        injurySubstitutions = await injurySubstitutionsFetch
        let todaysLogs = await todaysLogsFetch
        loggedTitlesToday = Set(todaysLogs.map(\.title))
        let todaysCalories = todaysLogs.compactMap(\.caloriesBurned)
        todaysLoggedCalories = todaysCalories.isEmpty ? nil : todaysCalories.reduce(0, +)
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
                // substitution record, the gym template's own bodyPart, or
                // the fixed suggestion list; full_body only as a last resort
                // (leaving it nil would silently no-op "Mark Workout Complete").
                selectedBodyPart = existing.plan.substitutedBodyPart
                    ?? existing.plan.templateBodyPart
                    ?? recommendation.category.workoutSuggestions.first(where: { $0.title == existing.selectedTitle })?.bodyPart.rawValue
                    ?? BodyPartFocus.fullBody.rawValue
                addedToPlan = existing.addedToPlan
            }
        }

        // Guide 04: exactly one recommendation, pre-selected -- the pick
        // card must never open empty waiting for a checkbox tap.
        if selectedTitle == nil {
            selectTopSuggestion()
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
            Text(String(localized: "recommendationDetail.injuryCheckin.question", defaultValue: "How's your \(tag?.displayName.lowercased() ?? state.injuryTag) feeling today?", comment: "Injury check-in question. Placeholder is the lowercased injury tag display name."))
                .font(.subheadline)
            HStack(spacing: 10) {
                ForEach([InjuryCheckinResponse.better, .same, .worse], id: \.self) { response in
                    SomaChip(title: LocalizedStringKey(Self.checkinResponseLabel(response))) {
                        Task { await submitCheckin(tag: state.injuryTag, response: response) }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    /// `response.rawValue.capitalized` alone would build a plain String at
    /// the call site (not a literal), which skips catalog lookup entirely --
    /// hence the explicit per-case localization here.
    private static func checkinResponseLabel(_ response: InjuryCheckinResponse) -> String {
        switch response {
        case .better: String(localized: "recommendationDetail.checkinResponse.better", defaultValue: "Better", comment: "Injury check-in response button: things feel better today")
        case .same: String(localized: "recommendationDetail.checkinResponse.same", defaultValue: "Same", comment: "Injury check-in response button: things feel the same today")
        case .worse: String(localized: "recommendationDetail.checkinResponse.worse", defaultValue: "Worse", comment: "Injury check-in response button: things feel worse today")
        }
    }

    private func submitCheckin(tag: String, response: InjuryCheckinResponse) async {
        guard let injuryTag = InjuryTag(rawValue: tag) else { return }
        do {
            let result = try await SupabaseClient.shared.recordInjuryCheckin(tag: injuryTag, response: response, date: recommendation.date)
            checkedInTagsToday.insert(tag)
            injuryCheckinMessage = result.escalate ? result.escalationMessage : nil
        } catch {
            injuryCheckinMessage = String(localized: "recommendationDetail.checkinError", defaultValue: "Couldn't record that check-in. Try again.", comment: "Error shown when submitting an injury check-in response fails")
        }
    }

    /// Mirrors pregnancyGuidance.ts's PREGNANCY_DISCLAIMER verbatim -- fixed
    /// UI copy, not sourced from the LLM response, so it always renders
    /// regardless of what the model actually returned.
    static let pregnancyDisclaimer = String(localized: "recommendationDetail.pregnancyDisclaimer", defaultValue: "This is general guidance only, not medical advice -- please follow your doctor's or midwife's recommendations, especially if you have any pregnancy complications.", comment: "Fixed safety disclaimer shown when the user's profile indicates pregnancy; mirrors pregnancyGuidance.ts's PREGNANCY_DISCLAIMER verbatim")

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
            messageDetail: nil,
            reason: .healthkitMedium,
            sleepCapApplied: false,
            injuryCapApplied: false,
            loadCapApplied: false,
            consecutiveDaysCapApplied: false,
            injuryProtocolCapApplied: false,
            injuryProtocolModerateCapApplied: false,
            pregnancyCapApplied: false,
            volumeCapApplied: false,
            hrvCapApplied: false,
            stressCapApplied: false,
            injuryProtocolRestApplied: false,
            moodCapApplied: false,
            preCapCategory: nil,
            dataConfidence: .low,
            userRequestedCategory: nil
        )
    )
    .environmentObject(AppState())
}
