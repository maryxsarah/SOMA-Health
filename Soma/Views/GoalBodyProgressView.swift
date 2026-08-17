import PhotosUI
import SwiftUI

/// Standalone "where am I, and how do I get to my goal body" screen --
/// opened directly from Home/Profile, not tunneled through Profile's
/// settings machinery (guide-05's tab/summary-row/detail-sheet pattern
/// doesn't fit here; this is meant to feel like its own destination, not
/// one more settings row). Goal photo, current photo, a real elapsed-time
/// progress bar, what today's plan is actually doing in response, and
/// every progress photo ever uploaded, browsable.
///
/// Gated the same way the underlying feature already is (Config.
/// enableBodyPhotoUpload + adult confirmation) -- callers (HomeView,
/// ProfileView) check this before presenting; this view itself doesn't
/// re-check, matching how e.g. RecommendationDetailView doesn't re-check
/// the paywall gate its own caller already applied.
struct GoalBodyProgressView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var goalPhotoPath: String?
    @State private var currentPhotoPath: String?
    @State private var goalImage: UIImage?
    @State private var currentImage: UIImage?
    @State private var goalHistory: [BodyPhotoEntry] = []
    @State private var currentHistory: [BodyPhotoEntry] = []
    @State private var historyThumbnails: [String: UIImage] = [:]

    @State private var progress: GoalJourneyProgress?
    @State private var emphasisTags: [GoalTag] = []
    @State private var trainingEmphasis: TrainingEmphasis?

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isUploadingGoal = false
    @State private var isUploadingCurrent = false
    @State private var goalPhotoItem: PhotosPickerItem?
    @State private var currentPhotoItem: PhotosPickerItem?
    @State private var showComparison = false
    @State private var showAddPhotoPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isLoading {
                        SomaLoadingBar(messages: SomaLoadingBar.goalProgressMessages, barWidth: 240)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                    } else {
                        if goalImage == nil && currentImage == nil {
                            emptyStateSection
                        } else {
                            photosSection
                        }
                        if let progress {
                            progressSection(progress)
                        }
                        if trainingEmphasis != nil || !emphasisTags.isEmpty {
                            insightsSection
                        }
                        if !goalHistory.isEmpty {
                            historySection(title: "Goal photo history", entries: goalHistory, kind: .goal)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .somaBackground()
            .navigationTitle("Your Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 11b's serif-italic "Your progress" + glass "Done" chip,
                // via the standard toolbar (not a hand-drawn sheet header)
                // so Dynamic Type/VoiceOver/multitasking keep working.
                ToolbarItem(placement: .principal) {
                    Text("Your progress")
                        .font(.system(size: 28, weight: .bold, design: .serif).italic())
                        .foregroundStyle(SomaTokens.ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(SomaTokens.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .glassLens(cornerRadius: SomaTokens.rPill)
                }
            }
        }
        .task { await load() }
        .onChange(of: goalPhotoItem) { _, newItem in
            Task { await upload(kind: .goal, item: newItem) }
        }
        .onChange(of: currentPhotoItem) { _, newItem in
            Task { await upload(kind: .current, item: newItem) }
        }
        .sheet(isPresented: $showComparison) {
            if let goalImage, let currentImage {
                BodyPhotoComparisonView(goalImage: goalImage, currentImage: currentImage)
            }
        }
    }

    // MARK: - Empty state

    /// No photos at all yet -- this is the pitch, not a settings prompt:
    /// SOMA exists to close the gap between these two photos, so say that
    /// plainly rather than a generic "add a photo" line.
    private var emptyStateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("See exactly how you'll get there.")
                .font(Theme.display)
            Text("Add a photo of the body you're working toward and a photo of where you are today. Soma builds your plan around closing that gap, and shows you real progress along the way.")
                .font(.body)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                emptyPhotoSlot(title: "Goal body", isUploading: isUploadingGoal, selection: $goalPhotoItem)
                emptyPhotoSlot(title: "Current body", isUploading: isUploadingCurrent, selection: $currentPhotoItem)
            }
            // Constraint 8, same copy as the onboarding step: never a
            // "you will look exactly like this" promise.
            Text("This is a training direction, not a guarantee -- genetics differ, goal photos are sometimes edited or filtered, and real results take time.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func emptyPhotoSlot(title: LocalizedStringKey, isUploading: Bool, selection: Binding<PhotosPickerItem?>) -> some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: selection, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.clear)
                        .frame(height: 160)
                        .glassCard(cornerRadius: 16)
                    if isUploading {
                        ProgressView()
                    } else {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Photos (11b two-up compare)

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Item 3 fix: equal-width columns regardless of either slot's
            // intrinsic content -- Current uniquely renders an extra
            // on-photo date chip, so a plain HStack + maxWidth: .infinity
            // (which only splits LEFTOVER space, each child still claims
            // its own minimum content width first) let Current win the
            // width fight and pushed Goal past the screen edge. Same
            // flexible-GridItem recipe HomeView's widget grid already uses.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                compareSlot(kind: .current, title: LocalizedStringKey(String(localized: "goalProgress.photos.currentBody", defaultValue: "Current body", comment: "Caption under the 'Current' progress photo")), image: currentImage, isUploading: isUploadingCurrent, selection: $currentPhotoItem)
                compareSlot(kind: .goal, title: LocalizedStringKey(String(localized: "goalProgress.photos.goalBody", defaultValue: "Goal body", comment: "Caption under the 'Goal' progress photo")), image: goalImage, isUploading: isUploadingGoal, selection: $goalPhotoItem)
            }
            if !currentHistory.isEmpty {
                historyStrip
            }
            if goalImage != nil && currentImage != nil {
                Button {
                    AnalyticsManager.shared.featureUsed(name: "body_photo_comparison")
                    showComparison = true
                } label: {
                    Label(String(localized: "goalProgress.photos.compareButton", defaultValue: "Compare Goal vs. Current", comment: "Button that opens a side-by-side goal-vs-current photo comparison"), systemImage: "arrow.left.and.right.square")
                        .font(.caption.bold())
                }
            }
            CTAPillButton(title: LocalizedStringKey(String(localized: "goalProgress.photos.addNewButton", defaultValue: "Add a new progress photo", comment: "Button that opens the photo picker to add a new progress photo")), icon: Image(systemName: "camera.fill")) {
                showAddPhotoPicker = true
            }
        }
        .photosPicker(isPresented: $showAddPhotoPicker, selection: $currentPhotoItem, matching: .images)
    }

    /// One grid cell -- tinted-glass placeholder or the real photo, an
    /// on-photo "Current"/"Goal" chip (light glass vs. the accent gel), and
    /// (Current only) a dark date chip against the pinned photo's history
    /// entry. Tapping opens this slot's own picker directly, same as
    /// before -- re-uploading here already both replaces the pinned photo
    /// AND keeps the old one in history (see SupabaseClient.uploadBodyPhoto).
    private func compareSlot(kind: SupabaseClient.BodyPhotoKind, title: LocalizedStringKey, image: UIImage?, isUploading: Bool, selection: Binding<PhotosPickerItem?>) -> some View {
        let isGoal = kind == .goal
        return VStack(spacing: 8) {
            PhotosPicker(selection: selection, matching: .images) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isGoal
                                    ? [Color(red: 0.906, green: 0.886, blue: 0.965), Color(red: 0.784, green: 0.737, blue: 0.918)]
                                    : [Color(red: 0.863, green: 0.906, blue: 0.973), Color(red: 0.718, green: 0.800, blue: 0.925)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else if isUploading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Image(systemName: isGoal ? "target" : "camera.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(SomaTokens.accent.opacity(0.35))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    Group {
                        if isGoal {
                            Text("Goal")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .glassGel(.blue, cornerRadius: SomaTokens.rPill)
                        } else {
                            Text("Current")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(SomaTokens.ink)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                        }
                    }
                    .padding(10)

                    if !isGoal, let dateText = pinnedDate(kind: .current) {
                        Text(dateText)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                            .padding(10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Newest `currentHistory` entry pinned to the profile -- gives the
    /// on-photo date chip a real "when was this taken" rather than "today".
    private func pinnedDate(kind: SupabaseClient.BodyPhotoKind) -> String? {
        let path = kind == .goal ? goalPhotoPath : currentPhotoPath
        let entries = kind == .goal ? goalHistory : currentHistory
        return entries.first(where: { $0.storagePath == path })?.shortDate
    }

    // MARK: - History strip (current-body log, embedded in the compare card)

    private var historyStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "goalProgress.history.title", defaultValue: "HISTORY", comment: "All-caps section label above the current-body photo history strip"))
                .font(.system(size: 11, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(SomaTokens.inkPlaceholder)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(currentHistory) { entry in
                        historyThumbnail(entry, kind: .current)
                    }
                    addHistoryTile
                }
            }
            Text(String(localized: "goalProgress.history.caption", defaultValue: "Tap a photo to make it your current one.", comment: "Caption under the photo history strip explaining that tapping a past photo repins it as current"))
                .font(.system(size: 11.5))
                .foregroundStyle(SomaTokens.ink3)
        }
    }

    private var addHistoryTile: some View {
        Button { showAddPhotoPicker = true } label: {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(SomaTokens.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4]))
                .background(Color.white.opacity(0.5).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
                .frame(width: 64, height: 80)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SomaTokens.accent)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Progress bar / tenure

    private func progressSection(_ progress: GoalJourneyProgress) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "goalProgress.journey.dayCount", defaultValue: "Day \(progress.daysElapsed + 1) of your journey", comment: "Progress-screen headline showing how many days into the journey the user is"))
                    .font(.subheadline.bold())
                if progress.hasReliableEstimate {
                    ProgressView(value: progress.fraction)
                        .tint(SomaTokens.accent)
                }
                Text(estimateLine(progress))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A weight target barely different from today's can't honestly promise
    /// a timeline for a goal photo showing a much bigger change.
    private func estimateLine(_ progress: GoalJourneyProgress) -> String {
        guard progress.hasReliableEstimate else {
            return String(localized: "goal_progress.estimate.no_reliable_estimate", defaultValue: "Your target weight doesn't match your goal photo yet -- update it in Settings for a real estimate.", comment: "Shown when the user's target weight doesn't support a reliable goal timeline estimate")
        }
        // Rounded, not truncated -- 59 days is "2 months", not "1".
        let months = max(1, Int((Double(progress.estimatedTotalDays) / 30.0).rounded()))
        let monthsText = String(
            localized: "onboarding.monthsStandalone",
            defaultValue: "\(months) months",
            comment: "Bare month count used as a chart axis label and inline in a sentence, pluralized by count"
        )
        return progress.fraction >= 1.0
            ? String(localized: "goal_progress.estimate.past_timeline", defaultValue: "Past your estimated ~\(monthsText) timeline -- steady progress still counts.", comment: "Shown once the user has passed their estimated goal timeline; the placeholder is a month count like '3 months'")
            : String(localized: "goal_progress.estimate.remaining_timeline", defaultValue: "Roughly \(monthsText) to your goal at your chosen pace.", comment: "Shown with the estimated remaining time to reach the goal; the placeholder is a month count like '3 months'")
    }

    // MARK: - Insights (AI photo comparison, shown directly per product decision)

    private var insightsSection: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "goalProgress.insights.title", defaultValue: "How Soma is getting you there", comment: "Title of the card explaining how the plan targets the user's goal photo comparison"))
                    .font(.subheadline.bold())
                if let trainingEmphasis {
                    Text(trainingEmphasis.planDirectionSentence)
                        .font(.body)
                }
                if !emphasisTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(emphasisTags) { tag in
                                Label(tag.displayName, systemImage: tag.systemImageName)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(SomaTokens.accentSoft))
                                    .foregroundStyle(SomaTokens.accent)
                            }
                        }
                    }
                }
                Text(String(localized: "goalProgress.insights.disclaimer", defaultValue: "Based on comparing your goal and current photos -- a secondary signal alongside your stated goals, not a replacement for them.", comment: "Disclaimer under the goal-progress insights card"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - History

    private func historySection(title: LocalizedStringKey, entries: [BodyPhotoEntry], kind: SupabaseClient.BodyPhotoKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(entries) { entry in
                        historyThumbnail(entry, kind: kind)
                    }
                }
            }
        }
    }

    private func historyThumbnail(_ entry: BodyPhotoEntry, kind: SupabaseClient.BodyPhotoKind) -> some View {
        let isPinned = entry.storagePath == (kind == .goal ? goalPhotoPath : currentPhotoPath)
        return Button {
            guard !isPinned else { return }
            Task { await pin(entry, kind: kind) }
        } label: {
            ZStack(alignment: .bottom) {
                Group {
                    if let image = historyThumbnails[entry.storagePath] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.clear.glassCardFlat(cornerRadius: 16)
                    }
                }
                .frame(width: 64, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                if let shortDate = entry.shortDate {
                    Text(shortDate)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(isPinned ? SomaTokens.accent : SomaTokens.ink3)
                        .padding(.bottom, 5)
                }
            }
            .frame(width: 64, height: 80)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isPinned ? SomaTokens.accent.opacity(0.45) : .clear, lineWidth: 1.5)
            )
            .opacity(isPinned ? 1 : 0.85)
        }
        .buttonStyle(.plain)
        .task { await loadThumbnailIfNeeded(entry) }
    }

    // MARK: - Data loading

    private func load() async {
        guard let userId = SupabaseClient.shared.currentUserID,
              let profile = try? await SupabaseClient.shared.fetchProfile(id: userId) else {
            isLoading = false
            return
        }

        goalPhotoPath = profile.goalBodyPhotoPath
        currentPhotoPath = profile.currentBodyPhotoPath
        emphasisTags = profile.bodyPhotoEmphasisTags ?? []
        trainingEmphasis = profile.trainingEmphasis
        progress = GoalJourneyProgress.compute(
            createdAt: profile.createdAt,
            weightKg: profile.weightKg,
            desiredWeightKg: profile.desiredWeightKg,
            goalPace: profile.goalPace
        )

        async let goalImageFetch: UIImage? = {
            guard let path = profile.goalBodyPhotoPath else { return nil }
            return await SupabaseClient.shared.loadBodyPhotoImage(path: path)
        }()
        async let currentImageFetch: UIImage? = {
            guard let path = profile.currentBodyPhotoPath else { return nil }
            return await SupabaseClient.shared.loadBodyPhotoImage(path: path)
        }()
        async let goalHistoryFetch = (try? await SupabaseClient.shared.fetchBodyPhotos(kind: .goal)) ?? []
        async let currentHistoryFetch = (try? await SupabaseClient.shared.fetchBodyPhotos(kind: .current)) ?? []

        goalImage = await goalImageFetch
        currentImage = await currentImageFetch
        goalHistory = await goalHistoryFetch
        currentHistory = await currentHistoryFetch
        isLoading = false
    }

    private func loadThumbnailIfNeeded(_ entry: BodyPhotoEntry) async {
        guard historyThumbnails[entry.storagePath] == nil else { return }
        guard let image = await SupabaseClient.shared.loadBodyPhotoImage(path: entry.storagePath) else { return }
        historyThumbnails[entry.storagePath] = image
    }

    private func upload(kind: SupabaseClient.BodyPhotoKind, item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        guard let compressed = ImageCompression.jpeg(image) else {
            errorMessage = String(localized: "goal_progress.error.process_photo", defaultValue: "Couldn't process that photo. Try another one.", comment: "Error shown when a selected photo fails to compress/process")
            return
        }

        if kind == .goal { isUploadingGoal = true } else { isUploadingCurrent = true }
        errorMessage = nil
        defer {
            if kind == .goal { isUploadingGoal = false } else { isUploadingCurrent = false }
        }

        do {
            try await SupabaseClient.shared.uploadBodyPhoto(kind: kind, imageData: compressed)
            if kind == .goal {
                goalImage = image
                goalPhotoPath = nil // re-resolved below via a fresh fetch
            } else {
                currentImage = image
                currentPhotoPath = nil
            }
            // Refresh paths + history so the newly-pinned photo shows as
            // pinned in the history strip immediately, not just after a
            // full screen relaunch.
            if let userId = SupabaseClient.shared.currentUserID,
               let profile = try? await SupabaseClient.shared.fetchProfile(id: userId) {
                goalPhotoPath = profile.goalBodyPhotoPath
                currentPhotoPath = profile.currentBodyPhotoPath
            }
            if kind == .goal {
                goalHistory = (try? await SupabaseClient.shared.fetchBodyPhotos(kind: .goal)) ?? []
            } else {
                currentHistory = (try? await SupabaseClient.shared.fetchBodyPhotos(kind: .current)) ?? []
            }
            // Silent, fire-and-forget re-analysis -- see this function's
            // own header comment on SupabaseClient for why there's no
            // loading state here. Re-fetch afterward so a fresh insight
            // shows without the user having to reopen this screen.
            if goalImage != nil, currentImage != nil {
                Task {
                    try? await SupabaseClient.shared.analyzeBodyPhotos()
                    if let userId = SupabaseClient.shared.currentUserID,
                       let profile = try? await SupabaseClient.shared.fetchProfile(id: userId) {
                        emphasisTags = profile.bodyPhotoEmphasisTags ?? []
                        trainingEmphasis = profile.trainingEmphasis
                    }
                }
            }
        } catch {
            errorMessage = String(localized: "goal_progress.error.upload_photo", defaultValue: "Couldn't upload that photo. Try again.", comment: "Error shown when uploading a photo to the server fails")
        }
    }

    private func pin(_ entry: BodyPhotoEntry, kind: SupabaseClient.BodyPhotoKind) async {
        errorMessage = nil
        do {
            try await SupabaseClient.shared.pinBodyPhoto(kind: kind, path: entry.storagePath)
            let image = await SupabaseClient.shared.loadBodyPhotoImage(path: entry.storagePath)
            if kind == .goal {
                goalPhotoPath = entry.storagePath
                goalImage = image
            } else {
                currentPhotoPath = entry.storagePath
                currentImage = image
            }
        } catch {
            errorMessage = String(localized: "goal_progress.error.switch_photo", defaultValue: "Couldn't switch to that photo. Try again.", comment: "Error shown when pinning/switching to a history photo fails")
        }
    }
}

#Preview {
    GoalBodyProgressView()
}
