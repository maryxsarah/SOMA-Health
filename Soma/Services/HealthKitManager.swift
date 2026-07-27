import HealthKit

/// Wraps the exact read-only HealthKit access the spec calls for: sleep,
/// HRV, resting/instant heart rate, steps, active energy, exercise time.
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

    /// Best-effort snapshot of today's metrics for the optional `healthkit`
    /// payload sent to generate-recommendation.
    func fetchTodaysMetrics() async -> HealthKitSnapshot {
        async let sleep = fetchSleepHours()
        async let hrv = fetchLatestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let restingHR = fetchLatestQuantity(
            .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        return await HealthKitSnapshot(sleepHours: sleep, hrvMs: hrv, restingHr: restingHR)
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
                        calories: workout.totalEnergyBurned.map { Int($0.doubleValue(for: .kilocalorie())) }
                    )
                } ?? []
                continuation.resume(returning: entries)
            }
            store.execute(query)
        }
    }

    private static func displayName(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "Running"
        case .walking: "Walking"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength Training"
        case .yoga: "Yoga"
        case .highIntensityIntervalTraining: "HIIT"
        case .coreTraining: "Core Training"
        case .flexibility: "Flexibility"
        case .hiking: "Hiking"
        case .rowing: "Rowing"
        case .elliptical: "Elliptical"
        default: "Workout"
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
                let totalSeconds = asleepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: totalSeconds > 0 ? totalSeconds / 3600 : nil)
            }
            store.execute(query)
        }
    }

    private func fetchLatestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }
}

enum HealthKitError: LocalizedError {
    case notAvailable
    var errorDescription: String? { "HealthKit is not available on this device." }
}
