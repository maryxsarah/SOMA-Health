import PhotosUI
import SwiftUI
import UIKit

private enum GymPhotoStep {
    case pickPhoto, analyzing, confirmingEquipment, generating, result
}

/// Entry point: RecommendationDetailView's "Or scan your gym →" button.
/// Flow: pick/take a photo -> Luna (with a Terra retry on low confidence)
/// detects equipment -> user confirms/edits the list -> a deterministic
/// template (never LLM-chosen) is selected server-side and worded by Luna.
/// `date` is the only thing passed in -- category/profile/readiness are
/// all re-derived server-side, since template selection is a
/// safety-relevant decision that shouldn't trust client-supplied state.
///
/// `onGenerated` fires as soon as a plan comes back (not only when the
/// sheet closes) so RecommendationDetailView's AI-generated-workout card
/// is already showing it the moment the user dismisses this sheet --
/// there's no separate "gym photo result" display, it's the same card the
/// normal picker flow populates.
struct GymPhotoWorkoutView: View {
    let date: String
    var onGenerated: (AIWorkoutPlan, String, String) -> Void = { _, _, _ in }

    @Environment(\.dismiss) private var dismiss

    @State private var step: GymPhotoStep = .pickPhoto
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var selectedImage: UIImage?
    @State private var equipment: [String] = []
    @State private var newEquipmentText = ""
    @State private var lowConfidenceNotice = false
    @State private var errorMessage: String?
    @State private var resultPlan: AIWorkoutPlan?
    @State private var safetyMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if step == .result {
                    resultOverlayContent
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            switch step {
                            case .pickPhoto:
                                pickPhotoContent
                            case .analyzing:
                                loadingContent(text: "Looking at your photo…")
                            case .confirmingEquipment:
                                confirmingEquipmentContent
                            case .generating:
                                loadingContent(text: "Building your workout…")
                            case .result:
                                EmptyView()
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
                }
            }
            .navigationTitle(step == .result ? "" : "Scan your gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(step == .result ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker { image in
                selectedImage = image
                Task { await analyze(image: image) }
            }
        }
        .onChange(of: photoItem) { _, newItem in
            Task {
                guard let newItem, let data = try? await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)
                else { return }
                selectedImage = image
                await analyze(image: image)
            }
        }
    }

    private var pickPhotoContent: some View {
        VStack(spacing: 16) {
            Text("Take or choose a photo of your gym or workout space, and Soma will build a workout around the equipment it sees.")
                .font(.body)
                .foregroundStyle(.secondary)

            Button {
                showingCamera = true
            } label: {
                Label("Take a photo", systemImage: "camera.fill")
            }
            .buttonStyle(.borderedProminent)

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose from library", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadingContent(text: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 12) {
                ProgressView()
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 40)
    }

    private var confirmingEquipmentContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Text(lowConfidenceNotice ? "Soma wasn't sure what it saw -- add the equipment you have available." : "Here's what Soma detected. Add or remove anything before continuing.")
                .font(.caption)
                .foregroundStyle(.secondary)

            FlowLayout {
                ForEach(equipment, id: \.self) { item in
                    equipmentChip(item)
                }
            }

            HStack(spacing: 8) {
                TextField("Add equipment", text: $newEquipmentText)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    addEquipment()
                }
                .disabled(newEquipmentText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            PillButton(title: "Build my workout", isEnabled: !equipment.isEmpty) {
                Task { await generateWorkout() }
            }
        }
    }

    /// The "wow moment" result screen -- the captured gym photo fills the
    /// background, with a rounded, frosted card floating up over its
    /// bottom portion (same visual language as an AR-style analysis
    /// overlay) holding the actual workout. A safety-guardrail block gets
    /// the same treatment but with the fixed message instead of a plan.
    private var resultOverlayContent: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Group {
                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.systemGray5)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()

                // Darkens the lower portion of the photo so the card's
                // top edge reads clearly even where it hasn't fully
                // covered the image yet.
                LinearGradient(
                    colors: [.clear, .black.opacity(0.35)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                resultCard
                    .frame(height: geo.size.height * 0.62)
            }
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.bold())
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.black.opacity(0.35)))
                    }
                    .padding(.trailing, 16)
                }
                .padding(.top, 8)
            }
        }
    }

    private var resultCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("SOMA AI ANALYSIS")
                        .font(.caption.bold())
                        .tracking(1)
                }
                .foregroundStyle(Theme.pillFill)

                Text(resultPlan != nil
                    ? "Based on your setup and health, here's today's workout to reach your goal:"
                    : "Let's check in first")
                    .font(.body.bold())

                if let resultPlan {
                    AIWorkoutPlanView(plan: resultPlan)
                } else if let safetyMessage {
                    Text(safetyMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if resultPlan != nil {
                    Button {
                        step = .confirmingEquipment
                    } label: {
                        Text("Adjust manually")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .padding(.bottom, 24)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func equipmentChip(_ item: String) -> some View {
        HStack(spacing: 4) {
            Text(item)
                .font(.subheadline.weight(.medium))
            Button {
                equipment.removeAll { $0 == item }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(.systemGray6)))
    }

    private func addEquipment() {
        let trimmed = newEquipmentText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !equipment.contains(trimmed) else { return }
        equipment.append(trimmed)
        newEquipmentText = ""
    }

    private func analyze(image: UIImage) async {
        step = .analyzing
        errorMessage = nil
        guard let imageData = Self.compressedJPEG(image) else {
            errorMessage = "Couldn't process that photo. Try another one."
            step = .pickPhoto
            return
        }
        do {
            let result = try await SupabaseClient.shared.analyzeGymPhoto(imageData: imageData)
            equipment = result.equipment
            lowConfidenceNotice = result.lowConfidence
            step = .confirmingEquipment
        } catch {
            errorMessage = "Couldn't analyze that photo. Try again."
            step = .pickPhoto
        }
    }

    private func generateWorkout() async {
        step = .generating
        errorMessage = nil
        do {
            let outcome = try await SupabaseClient.shared.generateGymWorkout(date: date, confirmedEquipment: equipment)
            switch outcome {
            case .plan(let plan, let title, let bodyPart):
                resultPlan = plan
                safetyMessage = nil
                onGenerated(plan, title, bodyPart)
            case .safetyBlocked(let message):
                safetyMessage = message
                resultPlan = nil
            }
            step = .result
        } catch {
            errorMessage = "Couldn't build a workout right now. Try again."
            step = .confirmingEquipment
        }
    }

    /// Resizes to ~1024px longest edge and compresses to keep the request
    /// well under Edge Function body-size limits.
    private static func compressedJPEG(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1024
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.6)
    }
}

/// Thin UIImagePickerController wrapper -- this codebase has no prior
/// camera/photo-picker pattern (only PhotosPicker is a standard SwiftUI
/// API and needs no wrapper), so this is the standard bridge for camera
/// capture.
private struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

#Preview {
    GymPhotoWorkoutView(date: "2026-07-27")
}
