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
                Text("Optional -- add a goal-body reference photo and a current photo to help personalize your plan. You can skip this and add it later from your profile.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            HStack(spacing: 16) {
                photoSlot(title: "Goal body", image: goalPhoto, isUploading: isUploadingGoal, selection: $goalPhotoItem)
                photoSlot(title: "Current body", image: currentPhoto, isUploading: isUploadingCurrent, selection: $currentPhotoItem)
            }
            .padding(.horizontal, 24)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            PillButton(title: "Continue", action: onContinue)
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

    private func photoSlot(title: String, image: UIImage?, isUploading: Bool, selection: Binding<PhotosPickerItem?>) -> some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: selection, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemGray6))
                        .frame(height: 160)
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 160)
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
            if kind == .goal { goalPhoto = image } else { currentPhoto = image }
            // Silent, fire-and-forget -- see ProfileView's matching hook for
            // why this has no loading state or surfaced error.
            if goalPhoto != nil, currentPhoto != nil {
                Task { try? await SupabaseClient.shared.analyzeBodyPhotos() }
            }
        } catch {
            errorMessage = "Couldn't upload that photo. Try again."
        }
    }
}

#Preview {
    BodyPhotosStepView(onContinue: {})
}
