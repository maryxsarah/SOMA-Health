import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

private enum GymPhotoStep {
    case pickPhoto, cameraBlocked, analyzing, confirmingEquipment, generating, result
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
    @Environment(\.scenePhase) private var scenePhase

    @State private var step: GymPhotoStep = .pickPhoto
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    /// Which explanation `cameraBlockedContent` renders. Restricted
    /// devices get different instructions than a plain denial, because
    /// Settings > Soma has no camera toggle for them to flip.
    @State private var cameraRestricted = false
    @State private var selectedImage: UIImage?
    @State private var equipment: [String] = []
    @State private var newEquipmentText = ""
    @State private var lowConfidenceNotice = false
    @State private var errorMessage: String?
    @State private var resultPlan: AIWorkoutPlan?
    @State private var safetyMessage: String?
    @State private var isAddingToPlan = false
    @State private var addedToPlan = false
    @State private var addToPlanError: String?

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
                            case .cameraBlocked:
                                cameraBlockedContent
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
        // Granting access in Settings suspends the app; on the way back
        // the explainer is stale, so drop the user at the picker with a
        // working "Take a photo" button instead of instructions they've
        // already followed.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, step == .cameraBlocked else { return }
            if CameraAccess.currentAction() == .present {
                step = .pickPhoto
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
                Task { await startCamera() }
            } label: {
                Label("Take a photo", systemImage: "camera.fill")
            }
            .buttonStyle(.borderedProminent)

            libraryPicker(fullWidth: false)
        }
        .frame(maxWidth: .infinity)
    }

    /// The library-pick affordance, shared by the pick step and the
    /// camera-blocked explainer so copy/filter/icon changes happen once.
    private func libraryPicker(fullWidth: Bool) -> some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            Label("Choose from library", systemImage: "photo.on.rectangle")
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(.bordered)
    }

    /// Shown instead of the camera when access isn't granted. Without
    /// this the picker still opened and just sat there black -- nothing
    /// on screen said permission was the problem or where to change it.
    private var cameraBlockedContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "camera.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.pillFill)

                Text(cameraRestricted ? "Camera is restricted" : "Camera access is off")
                    .font(.title3.bold())

                Text(cameraRestricted
                    ? "Something on this device is blocking the camera — usually Screen Time or a work/school profile. You can still scan your gym from a photo you already have."
                    : "Soma needs camera access to see your gym equipment. You can turn it back on in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(cameraRestricted ? "How to allow it" : "How to turn it on")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                ForEach(Array(cameraInstructionSteps.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.pillFill)
                        Text(line)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.systemGray6)))

            VStack(spacing: 10) {
                // Restricted devices have no Soma camera toggle to reach,
                // so sending them to the app's settings page would be a
                // dead end -- only the recoverable case gets the button.
                if !cameraRestricted {
                    Button {
                        SystemSettings.open()
                    } label: {
                        Text("Open Settings")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                libraryPicker(fullWidth: true)

                Button("Back") { step = .pickPhoto }
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cameraInstructionSteps: [String] {
        cameraRestricted
            ? ["Open the Settings app", "Go to Screen Time → Content & Privacy Restrictions", "Under Allowed Apps (or App Privacy), allow the Camera"]
            : ["Open the Settings app", "Scroll down and tap Soma", "Turn on Camera"]
    }

    private func loadingContent(text: String) -> some View {
        GenerationProgressView(message: text, estimatedSeconds: 7)
            .padding(.horizontal, 32)
            .padding(.top, 60)
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

                if let addToPlanError {
                    Text(addToPlanError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if resultPlan != nil {
                    if addedToPlan {
                        Label("Added to today's plan", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    } else {
                        Button {
                            Task { await addToTodaysPlan() }
                        } label: {
                            if isAddingToPlan {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Add to today's plan")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isAddingToPlan)
                        .padding(.top, 4)

                        // Kept available even after generating -- the
                        // workout stays on screen (resultPlan is never
                        // cleared by this tap), it's just a re-entry into
                        // the equipment step in case the plan isn't right.
                        Button {
                            step = .confirmingEquipment
                        } label: {
                            Text("Adjust manually")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
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

    /// Gate in front of every camera presentation. Denied access used to
    /// reach `UIImagePickerController` anyway, which shows a black
    /// viewfinder rather than refusing -- so the check has to happen
    /// here, before the sheet.
    private func startCamera() async {
        switch CameraAccess.currentAction() {
        case .present:
            showingCamera = true
        case .request:
            // First run: the system prompt only ever appears once, so a
            // "no" here lands on the explainer instead of a dead sheet.
            if await AVCaptureDevice.requestAccess(for: .video) {
                showingCamera = true
            } else {
                cameraRestricted = false
                step = .cameraBlocked
            }
        case .explainDenied:
            cameraRestricted = false
            step = .cameraBlocked
        case .explainRestricted:
            cameraRestricted = true
            step = .cameraBlocked
        }
    }

    private func analyze(image: UIImage) async {
        step = .analyzing
        errorMessage = nil
        guard let imageData = ImageCompression.jpeg(image) else {
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
            case .generationLimitReached(let message):
                safetyMessage = message
                resultPlan = nil
            }
            step = .result
        } catch {
            errorMessage = "Couldn't build a workout right now. Try again."
            step = .confirmingEquipment
        }
    }

    private func addToTodaysPlan() async {
        isAddingToPlan = true
        addToPlanError = nil
        defer { isAddingToPlan = false }
        do {
            try await SupabaseClient.shared.confirmAIPlan(date: date)
            addedToPlan = true
        } catch {
            addToPlanError = "Couldn't add to today's plan. Try again."
        }
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
        // Guard, not an assumption: assigning an unavailable source type
        // throws NSInvalidArgumentException and takes the app down. The
        // camera is unavailable under Screen Time restrictions, MDM policy,
        // and in the Simulator -- one tap was enough to crash.
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera)
            ? .camera
            : .photoLibrary
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
