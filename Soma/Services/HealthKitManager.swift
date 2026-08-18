import HealthKit

/// Wraps the exact read-only HealthKit access the spec calls for: sleep,
/// HRV, resting/instant heart rate, steps, active energy, basal energy,
/// exercise time.
final class HealthKitManager {
    static let shared = HealthKitManager()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let store = HKHealthStore()
    private var observerQuery: HKObserverQuery?

    private let readTypes: Set<HKObjectType> = [
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
        HKObjectType.workoutType(),
    ]

    /// Requests read access for all 7 types in one sheet.
    ///
    /// IMPORTANT: HealthKit deliberately never reports back which
    /// individual types were granted vs. denied (a privacy protection).
    /// A successful return here means "the permission sheet was completed,"
    /// not "the user granted every type." Screen 2 treats that completion
    /// as "Connected" per the spec -- this is expected HealthKit behavior,
    /// not a bug to fix later.
    func requestAuthorization() async throws {
        guard Self.isAvailable else { throw HealthKitError.notAvailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Whether this install has already completed the read-authorization
    /// sheet for `readTypes` -- the only signal HealthKit exposes for read
    /// access (see requestAuthorization's own doc comment: it never
    /// reports per-type grant/denial). `.unnecessary` means "already
    /// asked," which this app already treats as "Connected" the moment
    /// requestAuthorization's sheet completes -- same definition, just
    /// checked without re-prompting.
    ///
    /// This is an OS-level, install-scoped grant -- entirely untouched by
    /// SOMA sign-out/sign-in, unlike Whoop/Oura's server-stored tokens. So
    /// unlike AppState.refreshConnectedProviders' Whoop/Oura fetch, a
    /// `false` here after a prior `true` is never treated as "must have
    /// been revoked, ignore it" -- it just means never authorized yet.
    func isAuthorized() async -> Bool {
        #if DEBUG
        // The demo-recording harness needs Connect Device's gate to clear
        // without a real HealthKit consent sheet -- the simulator's own
        // authorization-status API is unreliable for read-only types
        // regardless of whether the sheet was ever answered. Never
        // compiled into Release; every other DEBUG build still hits the
        // real check below.
        if UITestSupport.isOnboardingDemo || UITestSupport.isOnboardingDemoResume { return true }
        #endif
        guard Self.isAvailable else { return false }
        guard let status = try? await store.statusForAuthorizationRequest(toShare: [], read: readTypes) else {
            return false
        }
        return status == .unnecessary
    }

    /// Snapshot of today's metrics for the optional `healthkit` payload sent
    /// to generate-recommendation.
    ///
    /// Every metric here is bounded to the last 24 hours and returns nil when
    /// nothing was recorded in that window. That "nil rather than stale" rule
    /// is the whole point: this used to read the most recent sample of ALL
    /// TIME (HKSampleQuery with predicate: nil, limit: 1), so a user whose
    /// watch had not logged HRV in a week submitted last week's number as
    /// today's, every single day. The server then averaged those repeated
    /// values into the baseline it compared them against, so the ratio came
    /// out at exactly 1.0 forever and the user was pinned to "Moderate".
    /// A missing metric is honest and the band logic handles it; a stale one
    /// is a silent lie that also corrupts the baseline.
    ///
    /// Values are medians, not single samples. Apple Watch records SDNN
    /// irregularly (roughly every 2-4h awake, ~1 min per 15 min overnight,
    /// skipping on motion) and individual readings are famously noisy -- a
    /// median over the window resists outliers without needing an outlier
    /// model.
    func fetchTodaysMetrics() async -> HealthKitSnapshot {
        async let sleep = fetchSleepHours()
        async let hrv = fetchMedianQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let restingHR = fetchMedianQuantity(
            .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let basalEnergy = fetchCumulativeQuantity(.basalEnergyBurned, unit: .kilocalorie())
        async let stages = fetchSleepStageBreakdown()
        let stageBreakdown = await stages
        return await HealthKitSnapshot(
            sleepHours: sleep,
            hrvMs: hrv,
            restingHr: restingHR,
            sleepLightHours: stageBreakdown.light,
            sleepDeepHours: stageBreakdown.deep,
            sleepRemHours: stageBreakdown.rem,
            sleepAwakeHours: stageBreakdown.awake,
            basalEnergyKcal: basalEnergy
        )
    }

    /// Trailing daily average step count -- used only for display context
    /// on RecommendationDetailView's step-count target ("you've been
    /// averaging ~X/day recently"), not fed into the decision engine.
    func fetchRecentAverageSteps(days: Int = 7) async -> Double? {
        guard Self.isAvailable, let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            return nil
        }
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                guard let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let total = sum.doubleValue(for: .count())
                continuation.resume(returning: total / Double(days))
            }
            store.execute(query)
        }
    }

    /// Steps taken so far today -- feeds RecommendationDetailView's step
    /// tracker pill (position vs today's target), never the decision engine.
    func fetchTodaysSteps() async -> Double? {
        guard Self.isAvailable, let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            return nil
        }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                guard let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sum.doubleValue(for: .count()))
            }
            store.execute(query)
        }
    }

    /// Per-day step totals over a range -- feeds the history calendar's
    /// "perfect day" crown, which needs to know whether the step goal was
    /// hit on a *past* day, not just today. Keyed by "yyyy-MM-dd".
    func fetchDailySteps(from start: Date, to end: Date) async -> [String: Double] {
        guard Self.isAvailable, let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            return [:]
        }
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                guard let results else {
                    continuation.resume(returning: [:])
                    return
                }
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = .current
                var byDate: [String: Double] = [:]
                results.enumerateStatistics(from: anchor, to: end) { stats, _ in
                    guard let sum = stats.sumQuantity() else { return }
                    byDate[formatter.string(from: stats.startDate)] = sum.doubleValue(for: .count())
                }
                continuation.resume(returning: byDate)
            }
            store.execute(query)
        }
    }

    /// Today's workout sessions actually recorded in Apple Health -- feeds
    /// Home's workout timeline alongside the server-fetched Oura/Whoop
    /// sessions (HealthKit can only be read on-device, never from a
    /// server, so this half of the timeline has to come from here).
    func fetchTodaysWorkouts() async -> [WorkoutTimelineEntry] {
        guard Self.isAvailable else { return [] }
        let workoutType = HKObjectType.workoutType()
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let entries = (samples as? [HKWorkout])?.map { workout in
                    WorkoutTimelineEntry(
                        source: "apple_health",
                        title: Self.displayName(for: workout.workoutActivityType),
                        startTime: workout.startDate,
                        durationMinutes: Int(workout.duration / 60),
                        calories: workout.totalEnergyBurned.map { Int($0.doubleValue(for: .kilocalorie())) },
                        activityType: Self.activityTypeKey(for: workout.workoutActivityType)
                    )
                } ?? []
                continuation.resume(returning: entries)
            }
            store.execute(query)
        }
    }

    /// Stable machine key for WorkoutTimelineEntry.activityType -- kept
    /// separate from displayName() below since that one is user-facing
    /// copy and free to change wording without breaking the "is this a
    /// walk" check that depends on this key.
    private static func activityTypeKey(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .walking: "walking"
        case .running: "running"
        case .cycling: "cycling"
        case .swimming: "swimming"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "strength_training"
        case .yoga: "yoga"
        case .highIntensityIntervalTraining: "hiit"
        case .coreTraining: "core_training"
        case .flexibility: "flexibility"
        case .hiking: "hiking"
        case .rowing: "rowing"
        case .elliptical: "elliptical"
        default: "other"
        }
    }

    private static func displayName(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:
            String(localized: "healthKit.workoutType.running", defaultValue: "Running", comment: "Workout type label shown in the home workout timeline")
        case .walking:
            String(localized: "healthKit.workoutType.walking", defaultValue: "Walking", comment: "Workout type label shown in the home workout timeline")
        case .cycling:
            String(localized: "healthKit.workoutType.cycling", defaultValue: "Cycling", comment: "Workout type label shown in the home workout timeline")
        case .swimming:
            String(localized: "healthKit.workoutType.swimming", defaultValue: "Swimming", comment: "Workout type label shown in the home workout timeline")
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            String(localized: "healthKit.workoutType.strengthTraining", defaultValue: "Strength Training", comment: "Workout type label shown in the home workout timeline")
        case .yoga:
            String(localized: "healthKit.workoutType.yoga", defaultValue: "Yoga", comment: "Workout type label shown in the home workout timeline")
        case .highIntensityIntervalTraining:
            String(localized: "healthKit.workoutType.hiit", defaultValue: "HIIT", comment: "Workout type label shown in the home workout timeline (High Intensity Interval Training)")
        case .coreTraining:
            String(localized: "healthKit.workoutType.coreTraining", defaultValue: "Core Training", comment: "Workout type label shown in the home workout timeline")
        case .flexibility:
            String(localized: "healthKit.workoutType.flexibility", defaultValue: "Flexibility", comment: "Workout type label shown in the home workout timeline")
        case .hiking:
            String(localized: "healthKit.workoutType.hiking", defaultValue: "Hiking", comment: "Workout type label shown in the home workout timeline")
        case .rowing:
            String(localized: "healthKit.workoutType.rowing", defaultValue: "Rowing", comment: "Workout type label shown in the home workout timeline")
        case .elliptical:
            String(localized: "healthKit.workoutType.elliptical", defaultValue: "Elliptical", comment: "Workout type label shown in the home workout timeline")
        default:
            String(localized: "healthKit.workoutType.fallback", defaultValue: "Workout", comment: "Generic fallback workout type label shown in the home workout timeline")
        }
    }

    // MARK: - Background delivery (Trigger A: wake-based)

    /// Registers the observer + background delivery described in the spec.
    /// `onUpdate` fires whenever a new sleep sample is written (e.g. the
    /// Watch detects sleep has ended); the caller is responsible for
    /// generating + delivering the notification and marking "sent today".
    func startObserving(onUpdate: @escaping () -> Void) {
        guard Self.isAvailable else { return }
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

        let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { _, completionHandler, error in
            defer { completionHandler() }
            guard error == nil else { return }
            onUpdate()
        }
        observerQuery = query
        store.execute(query)

        store.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { _, _ in
            // Best-effort; iOS decides actual wake timing. Failures here
            // just mean Trigger B (BGAppRefreshTask) is the only path for
            // this user, which is already an acceptable fallback per spec.
        }
    }

    // MARK: - Private fetch helpers

    private func fetchSleepHours() async -> Double? {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let now = Date()
        let windowStart = Calendar.current.startOfDay(for: now).addingTimeInterval(-12 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                ]
                let asleepSamples = (samples as? [HKCategorySample])?.filter {
                    asleepValues.contains($0.value)
                } ?? []
                // Union of the intervals, not the sum of their durations --
                // overlapping samples from different sources would otherwise
                // be counted twice. See mergedDuration().
                let totalSeconds = Self.mergedDuration(
                    asleepSamples.map { (start: $0.startDate, end: $0.endDate) }
                )
                continuation.resume(returning: totalSeconds > 0 ? totalSeconds / 3600 : nil)
            }
            store.execute(query)
        }
    }

    /// Same window/query as fetchSleepHours() above, but grouped by stage
    /// instead of merged into one total -- the per-stage split HealthKit
    /// already classifies samples into (asleepCore/asleepDeep/asleepREM,
    /// plus .awake) was previously computed and immediately discarded.
    /// mergedDuration() still runs PER BUCKET (not just once overall) to
    /// avoid double-counting overlapping samples from different sources
    /// within the same stage, same reasoning as fetchSleepHours().
    private func fetchSleepStageBreakdown() async -> (light: Double?, deep: Double?, rem: Double?, awake: Double?) {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let now = Date()
        let windowStart = Calendar.current.startOfDay(for: now).addingTimeInterval(-12 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let categorySamples = (samples as? [HKCategorySample]) ?? []
                func hours(for values: Set<Int>) -> Double? {
                    let matching = categorySamples.filter { values.contains($0.value) }
                    let seconds = Self.mergedDuration(matching.map { (start: $0.startDate, end: $0.endDate) })
                    return seconds > 0 ? seconds / 3600 : nil
                }
                // asleepUnspecified (a source that reports sleep without a
                // stage breakdown) has no matching Oura/Whoop concept and no
                // clear stage to fold it into -- left out of every bucket
                // rather than guessed, so the four stages here can undercount
                // fetchSleepHours()'s total for a mixed-source night. That's
                // an honest gap, not a bug.
                let light = hours(for: [HKCategoryValueSleepAnalysis.asleepCore.rawValue])
                let deep = hours(for: [HKCategoryValueSleepAnalysis.asleepDeep.rawValue])
                let rem = hours(for: [HKCategoryValueSleepAnalysis.asleepREM.rawValue])
                let awake = hours(for: [HKCategoryValueSleepAnalysis.awake.rawValue])
                continuation.resume(returning: (light: light, deep: deep, rem: rem, awake: awake))
            }
            store.execute(query)
        }
    }

    /// Median of every sample recorded in the trailing `hours` window, or nil
    /// if there were none. See fetchTodaysMetrics() for why this must never
    /// fall back to an older sample.
    private func fetchMedianQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        hours: Double = 24
    ) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let now = Date()
        let predicate = HKQuery.predicateForSamples(
            withStart: now.addingTimeInterval(-hours * 3600),
            end: now,
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let values = (samples as? [HKQuantitySample])?
                    .map { $0.quantity.doubleValue(for: unit) } ?? []
                continuation.resume(returning: Self.median(values))
            }
            store.execute(query)
        }
    }

    /// Trailing-window SUM of a cumulative quantity type (e.g.
    /// basalEnergyBurned, which HealthKit reports as many small
    /// per-interval samples throughout the day, not one point reading like
    /// restingHeartRate/HRV) -- nil if nothing was recorded in the window.
    /// Same "nil rather than stale" rule as fetchMedianQuantity: this is
    /// never allowed to fall back to an older window's total.
    ///
    /// basalEnergyBurned specifically: summing a full trailing 24h already
    /// yields kcal/day directly (it's a rate accumulated over the day, not
    /// a snapshot to average) -- this is what nutritionTargets.ts treats as
    /// a "measured BMR" override for the day's calorie target. Apple's own
    /// estimate, itself algorithmic (derived from the user's weight/age/sex
    /// plus their actual activity), not a lab-measured BMR -- but it is
    /// this specific user's real recent data rather than a population
    /// formula, and it's the only device-level resting-energy signal this
    /// app has access to (see nutritionTargets.ts's own comment on this).
    private func fetchCumulativeQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        hours: Double = 24
    ) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let now = Date()
        let predicate = HKQuery.predicateForSamples(
            withStart: now.addingTimeInterval(-hours * 3600),
            end: now,
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                guard let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sum.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Average and max heart rate over an EXACT window -- e.g. a logged
    /// workout's start/end timestamps, not the whole day. Everything else
    /// in this file only ever computes a day-level median (see
    /// fetchMedianQuantity above); this is the one query scoped to an
    /// arbitrary caller-supplied interval, for DayDetailView's wearable-
    /// HR-matched-to-workout feature. Returns nil if nothing was recorded
    /// in that exact window (a workout logged with no Watch worn, or a
    /// window HealthKit simply has no samples for) -- never a
    /// zero/placeholder value.
    func fetchHeartRateSummary(start: Date, end: Date) async -> (average: Double, max: Double)? {
        guard Self.isAvailable, let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let unit = HKUnit.count().unitDivided(by: .minute())

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let values = (samples as? [HKQuantitySample])?
                    .map { $0.quantity.doubleValue(for: unit) } ?? []
                guard !values.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let average = values.reduce(0, +) / Double(values.count)
                continuation.resume(returning: (average: average, max: values.max() ?? average))
            }
            store.execute(query)
        }
    }

    /// Active energy burned over an EXACT window -- same "arbitrary
    /// caller-supplied interval" shape as fetchHeartRateSummary above (a
    /// logged workout's start/end), not the trailing-24h rate
    /// fetchCumulativeQuantity's basalEnergyBurned use computes. Feeds
    /// CompletedWorkoutView's calorie hero stat as the real, measured
    /// number when one exists; the estimate in WorkoutCalorieEstimator is
    /// only ever a fallback for when this returns nil. Returns nil (never
    /// a placeholder) if nothing was recorded in that exact window.
    func fetchActiveEnergy(start: Date, end: Date) async -> Int? {
        guard Self.isAvailable, let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                guard let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Int(sum.doubleValue(for: .kilocalorie()).rounded()))
            }
            store.execute(query)
        }
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }

    /// Total length covered by these intervals, counting any overlap once.
    ///
    /// HealthKit does not deduplicate across sources: an Apple Watch, a
    /// third-party sleep app, and an iPhone can each write samples covering
    /// the same minutes, and a sample query returns all of them. Summing
    /// durations naively therefore inflates total sleep, sometimes to
    /// physically impossible numbers.
    static func mergedDuration(_ intervals: [(start: Date, end: Date)]) -> TimeInterval {
        let sorted = intervals.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return 0 }

        var total: TimeInterval = 0
        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                current.end = max(current.end, interval.end)
            } else {
                total += current.end.timeIntervalSince(current.start)
                current = interval
            }
        }
        return total + current.end.timeIntervalSince(current.start)
    }
}

enum HealthKitError: LocalizedError {
    case notAvailable
    var errorDescription: String? {
        String(localized: "healthKit.error.notAvailable", defaultValue: "HealthKit is not available on this device.", comment: "Error shown when the device doesn't support HealthKit")
    }
}
