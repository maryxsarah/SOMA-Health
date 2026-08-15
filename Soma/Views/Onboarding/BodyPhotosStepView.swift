import PhotosUI
import SwiftUI

/// Optional goal-body/current-body photo upload -- only reachable while
/// Config.enableBodyPhotoUpload is true. Both slots are skippable; neither
/// blocks onboarding. Uploads happen immediately on picking a photo (not
/// deferred to a batch save like the main survey), since this is a real
/// network action with its own loading/failure state.
struct BodyPhotosStepView: View {
    let onContinue: () -> Void

    @State private var goalPhotoItem: PhotosPickerItem?
    @State private var currentPhotoItem: PhotosPickerItem?
    @State private var goalPhoto: UIImage?
    @State private var currentPhoto: UIImage?
    @State private var isUploadingGoal = false
    @State private var isUploadingCurrent = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Show us your goal")
                    .font(Theme.display)
                Text("Optional -- add a goal-body reference photo and a current photo to help point your plan and nutrition in the right direction. You can skip this and add it later from your profile.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                // Constraint 8: never a "you will look exactly like this"
                // promise -- genetics, photo editing/filters, and realistic
                // timelines acknowledged up front, not just implied.
                Text("This is a training direction, not a guarantee -- genetics differ, goal photos are sometimes edited or filtered, and real results take time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            HStack(spacing: 16) {
                photoSlot(kind: .goal, title: "Goal body", image: goalPhoto, isUploading: isUploadingGoal, selection: $goalPhotoItem)
                photoSlot(kind: .current, title: "Current body", image: currentPhoto, isUploading: isUploadingCurrent, selection: $currentPhotoItem)
            }
            .padding(.horizontal, 24)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            PillButton(title: goalPhoto == nil && currentPhoto == nil ? "Skip" : "Continue", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .padding(.top, 40)
        .somaBackground()
        .onChange(of: goalPhotoItem) { _, newItem in
            Task { await upload(kind: .goal, item: newItem) }
        }
        .onChange(of: currentPhotoItem) { _, newItem in
            Task { await upload(kind: .current, item: newItem) }
        }
    }

    /// Same tinted-glass/badge treatment as `GoalBodyProgressView`'s
    /// compare grid (11b) -- minus the History strip, since there's
    /// nothing to show a history of yet at this point in onboarding.
    private func photoSlot(kind: SupabaseClient.BodyPhotoKind, title: String, image: UIImage?, isUploading: Bool, selection: Binding<PhotosPickerItem?>) -> some View {
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

    private func upload(kind: SupabaseClient.BodyPhotoKind, item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        guard let compressed = ImageCompression.jpeg(image) else {
            errorMessage = String(localized: "photoUpload.error.processingFailed", defaultValue: "Couldn't process that photo. Try another one.", comment: "Error shown when a selected body photo fails local compression/processing before upload.")
            return
        }

        if kind == .goal { isUploadingGoal = true } else { isUploadingCurrent = true }
        errorMessage = nil
        defer {
            if kind == .goal { isUploadingGoal = false } else { isUploadingCurrent = false }
        }

        do {
            try await SupabaseClient.shared.uploadBodyPhoto(kind: kind, imageData: compressed)
            if kind == .goal { goalPhoto = image } else { currentPhoto = image }
            // Silent, fire-and-forget -- see ProfileView's matching hook for
            // why this has no loading state or surfaced error.
            if goalPhoto != nil, currentPhoto != nil {
                Task { try? await SupabaseClient.shared.analyzeBodyPhotos() }
            }
        } catch {
            errorMessage = String(localized: "photoUpload.error.uploadFailed", defaultValue: "Couldn't upload that photo. Try again.", comment: "Error shown when the body photo upload request to the backend fails.")
        }
    }
}

#Preview {
    BodyPhotosStepView(onContinue: {})
}
