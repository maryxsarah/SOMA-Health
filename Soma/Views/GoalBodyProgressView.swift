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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
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
                        if goalImage != nil || currentImage != nil {
                            addProgressPhotoRow
                        }
                        if !goalHistory.isEmpty || !currentHistory.isEmpty {
                            historySection(title: "Goal photo history", entries: goalHistory, kind: .goal)
                            historySection(title: "Your progress photos", entries: currentHistory, kind: .current)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
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

    private func emptyPhotoSlot(title: String, isUploading: Bool, selection: Binding<PhotosPickerItem?>) -> some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: selection, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemGray6))
                        .frame(height: 160)
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

    // MARK: - Photos (both set)

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                photoSlot(title: "Goal body", image: goalImage, isUploading: isUploadingGoal, selection: $goalPhotoItem)
                photoSlot(title: "Current body", image: currentImage, isUploading: isUploadingCurrent, selection: $currentPhotoItem)
            }
            if goalImage != nil && currentImage != nil {
                Button {
                    AnalyticsManager.shared.featureUsed(name: "body_photo_comparison")
                    showComparison = true
                } label: {
                    Label("Compare Goal vs. Current", systemImage: "arrow.left.and.right.square")
                        .font(.caption.bold())
                }
            }
        }
    }

    private func photoSlot(title: String, image: UIImage?, isUploading: Bool, selection: Binding<PhotosPickerItem?>) -> some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: selection, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemGray6))
                        .frame(height: 220)
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else if isUploading {
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

    // MARK: - Progress bar / tenure

    private func progressSection(_ progress: GoalJourneyProgress) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Day \(progress.daysElapsed + 1) of your journey")
                    .font(.subheadline.bold())
                ProgressView(value: progress.fraction)
                    .tint(SomaTokens.accent)
                Text(
                    progress.fraction >= 1.0
                        ? "Past your estimated ~\(progress.estimatedTotalDays / 30)-month timeline -- steady progress still counts."
                        : "Roughly \(progress.estimatedTotalDays / 30) months to your goal at your chosen pace."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Insights (AI photo comparison, shown directly per product decision)

    private var insightsSection: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Text("How Soma is getting you there")
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
                Text("Based on comparing your goal and current photos -- a secondary signal alongside your stated goals, not a replacement for them.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Add progress photo

    private var addProgressPhotoRow: some View {
        // Reuses the same slot binding as the "Current body" photo above --
        // tapping it replaces the pinned current photo AND keeps the old
        // one in history (see SupabaseClient.uploadBodyPhoto), which is
        // exactly "add a new progress photo" without a separate upload path.
        PhotosPicker(selection: $currentPhotoItem, matching: .images) {
            Label("Add a new progress photo", systemImage: "camera.fill")
                .font(.caption.bold())
        }
    }

    // MARK: - History

    private func historySection(title: String, entries: [BodyPhotoEntry], kind: SupabaseClient.BodyPhotoKind) -> some View {
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
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image = historyThumbnails[entry.storagePath] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.systemGray6)
                    }
                }
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isPinned ? SomaTokens.accent : .clear, lineWidth: 2)
                )
                if isPinned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(SomaTokens.accent)
                        .background(Circle().fill(.white))
                        .padding(4)
                }
            }
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
            errorMessage = "Couldn't process that photo. Try another one."
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
            errorMessage = "Couldn't upload that photo. Try again."
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
            errorMessage = "Couldn't switch to that photo. Try again."
        }
    }
}

#Preview {
    GoalBodyProgressView()
}
