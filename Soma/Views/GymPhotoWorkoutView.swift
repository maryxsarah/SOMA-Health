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
                                loadingContent(stages: [
                                    String(localized: "gymPhoto.analyzing.stage1", defaultValue: "Looking at your photo…", comment: "Loading stage while Soma examines the gym photo"),
                                    String(localized: "gymPhoto.analyzing.stage2", defaultValue: "Identifying equipment…", comment: "Loading stage while Soma identifies equipment in the photo"),
                                    String(localized: "gymPhoto.analyzing.stage3", defaultValue: "Checking what's usable…", comment: "Loading stage while Soma checks which equipment is usable"),
                                ])
                            case .confirmingEquipment:
                                confirmingEquipmentContent
                            case .generating:
                                loadingContent(stages: [
                                    String(localized: "gymPhoto.generating.stage1", defaultValue: "Matching a workout to your setup…", comment: "Loading stage while Soma builds a workout from the confirmed equipment"),
                                    String(localized: "gymPhoto.generating.stage2", defaultValue: "Selecting exercises…", comment: "Loading stage while Soma selects exercises"),
                                    String(localized: "gymPhoto.generating.stage3", defaultValue: "Writing your instructions…", comment: "Loading stage while Soma writes the workout instructions"),
                                ])
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
                    .somaSheetBackground()
                }
            }
            .navigationTitle(step == .result ? "" : String(localized: "gymPhoto.navigationTitle", defaultValue: "Scan your gym", comment: "Navigation title for the gym-photo scan flow"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(step == .result ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "gymPhoto.close", defaultValue: "Close", comment: "Button closing the gym-photo scan flow")) { dismiss() }
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
            Text(String(localized: "gymPhoto.pickPhoto.explainer", defaultValue: "Take or choose a photo of your gym or workout space, and Soma will build a workout around the equipment it sees.", comment: "Gym-photo scan: explainer shown before picking a photo"))
                .font(.body)
                .foregroundStyle(.secondary)

            photoDropZone

            HStack(spacing: 10) {
                SomaButton(title: "Take photo", size: .md, variant: .primary) {
                    Task { await startCamera() }
                }
                libraryPicker(fullWidth: true, title: "Choose photo", showIcon: false)
            }

            analysisPreview
        }
        .frame(maxWidth: .infinity)
    }

    /// Decorative preview of the drop target -- the actual tap targets are
    /// the buttons below it, this is just the "Then, while Soma looks"
    /// invitation the mockup leads with.
    private var photoDropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(SomaTokens.accent)
                .frame(width: 56, height: 56)
                .glassLens(cornerRadius: 28)

            Text(String(localized: "gymPhoto.dropZone.title", defaultValue: "Take or choose a photo", comment: "Gym-photo scan: decorative drop-zone label"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SomaTokens.ink2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .background(
            RoundedRectangle(cornerRadius: SomaTokens.rCard, style: .continuous)
                .fill(Color.white.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: SomaTokens.rCard, style: .continuous)
                        .strokeBorder(SomaTokens.accent.opacity(0.28), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                )
        )
    }

    /// A preview of `loadingContent`'s own stage copy for `.analyzing` --
    /// sets expectations before the tap, at ascending opacity to read as
    /// "this is coming up next", not as live progress.
    private var analysisPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "gymPhoto.analysisPreview.header", defaultValue: "THEN, WHILE SOMA LOOKS", comment: "Gym-photo scan: uppercase header previewing the analysis stage copy"))
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(SomaTokens.inkPlaceholder)

            analysisPreviewLine(String(localized: "gymPhoto.analysisPreview.step1", defaultValue: "Looking at your photo…", comment: "Gym-photo scan: analysis preview step 1"), opacity: 0.5)
            analysisPreviewLine(String(localized: "gymPhoto.analysisPreview.step2", defaultValue: "Identifying equipment…", comment: "Gym-photo scan: analysis preview step 2"), opacity: 0.75)
            analysisPreviewLine(String(localized: "gymPhoto.analysisPreview.step3", defaultValue: "Checking what's usable…", comment: "Gym-photo scan: analysis preview step 3"), opacity: 1)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func analysisPreviewLine(_ text: String, opacity: Double) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(SomaTokens.accent)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(SomaTokens.ink2)
        }
        .opacity(opacity)
    }

    /// The library-pick affordance, shared by the pick step and the
    /// camera-blocked explainer so copy/filter/icon changes happen once.
    private func libraryPicker(fullWidth: Bool, title: LocalizedStringKey = "Choose from library", showIcon: Bool = true) -> some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            Group {
                if showIcon {
                    Label(title, systemImage: "photo.on.rectangle")
                } else {
                    Text(title)
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(SomaTokens.accent)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 46)
            .padding(.horizontal, 18)
            .glassLens()
        }
        .buttonStyle(.plain)
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

                Text(cameraRestricted
                    ? String(localized: "gymPhoto.cameraBlocked.restrictedTitle", defaultValue: "Camera is restricted", comment: "Title shown when camera access is blocked by a device restriction")
                    : String(localized: "gymPhoto.cameraBlocked.offTitle", defaultValue: "Camera access is off", comment: "Title shown when camera access is simply denied"))
                    .font(.title3.bold())

                Text(cameraRestricted
                    ? String(localized: "gymPhoto.cameraBlocked.restrictedBody", defaultValue: "Something on this device is blocking the camera — usually Screen Time or a work/school profile. You can still scan your gym from a photo you already have.", comment: "Explainer shown when camera access is blocked by a device restriction")
                    : String(localized: "gymPhoto.cameraBlocked.offBody", defaultValue: "Soma needs camera access to see your gym equipment. You can turn it back on in Settings.", comment: "Explainer shown when camera access is simply denied"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(cameraRestricted
                    ? String(localized: "gymPhoto.cameraBlocked.restrictedHeading", defaultValue: "How to allow it", comment: "Heading above the numbered steps to allow camera access on a restricted device")
                    : String(localized: "gymPhoto.cameraBlocked.offHeading", defaultValue: "How to turn it on", comment: "Heading above the numbered steps to turn camera access back on"))
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
            .glassCardFlat(cornerRadius: 16)

            VStack(spacing: 10) {
                // Restricted devices have no Soma camera toggle to reach,
                // so sending them to the app's settings page would be a
                // dead end -- only the recoverable case gets the button.
                if !cameraRestricted {
                    SomaButton(title: "Open Settings", size: .lg, variant: .primary) {
                        SystemSettings.open()
                    }
                }

                libraryPicker(fullWidth: true)

                Button(String(localized: "gymPhoto.back", defaultValue: "Back", comment: "Button returning from the camera-blocked explainer to photo picking")) { step = .pickPhoto }
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cameraInstructionSteps: [String] {
        cameraRestricted
            ? [
                String(localized: "gymPhoto.cameraSteps.openSettings", defaultValue: "Open the Settings app", comment: "Step 1 of camera access instructions: open the Settings app"),
                String(localized: "gymPhoto.cameraSteps.restrictedScreenTime", defaultValue: "Go to Screen Time → Content & Privacy Restrictions", comment: "Step 2 of instructions for a restricted device: navigate to Screen Time restrictions"),
                String(localized: "gymPhoto.cameraSteps.restrictedAllowCamera", defaultValue: "Under Allowed Apps (or App Privacy), allow the Camera", comment: "Step 3 of instructions for a restricted device: allow Camera under Allowed Apps"),
            ]
            : [
                String(localized: "gymPhoto.cameraSteps.openSettings", defaultValue: "Open the Settings app", comment: "Step 1 of camera access instructions: open the Settings app"),
                String(localized: "gymPhoto.cameraSteps.scrollToSoma", defaultValue: "Scroll down and tap Soma", comment: "Step 2 of camera access instructions: find Soma in the Settings list"),
                String(localized: "gymPhoto.cameraSteps.turnOnCamera", defaultValue: "Turn on Camera", comment: "Step 3 of camera access instructions: enable the Camera toggle"),
            ]
    }

    private func loadingContent(stages: [String]) -> some View {
        GenerationProgressView(stages: stages, estimatedSeconds: 7)
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

            Text(lowConfidenceNotice
                ? String(localized: "gymPhoto.confirmEquipment.lowConfidence", defaultValue: "Soma wasn't sure what it saw -- add the equipment you have available.", comment: "Shown when gym-photo analysis had low confidence in what it detected")
                : String(localized: "gymPhoto.confirmEquipment.detected", defaultValue: "Here's what Soma detected. Add or remove anything before continuing.", comment: "Shown when gym-photo analysis detected equipment normally"))
                .font(.caption)
                .foregroundStyle(.secondary)

            FlowLayout {
                ForEach(equipment, id: \.self) { item in
                    equipmentChip(item)
                }
            }

            HStack(spacing: 8) {
                TextField(String(localized: "gymPhoto.addEquipment.placeholder", defaultValue: "Add equipment", comment: "Placeholder for the free-text add-equipment field"), text: $newEquipmentText)
                    .textFieldStyle(.roundedBorder)
                Button(String(localized: "gymPhoto.addEquipment.button", defaultValue: "Add", comment: "Button adding the typed equipment item")) {
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
                    Text(String(localized: "gymPhoto.result.header", defaultValue: "SOMA AI ANALYSIS", comment: "Gym-photo scan result: uppercase header above the generated plan"))
                        .font(.caption.bold())
                        .tracking(1)
                }
                .foregroundStyle(SomaTokens.accent)

                Text(resultPlan != nil
                    ? String(localized: "gymPhoto.result.withPlan", defaultValue: "Based on your setup and health, here's today's workout to reach your goal:", comment: "Gym-photo scan result: intro line when a workout plan was generated")
                    : String(localized: "gymPhoto.result.noPlan", defaultValue: "Let's check in first", comment: "Gym-photo scan result: intro line when no plan was generated yet (safety check-in needed)"))
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
                        Label(String(localized: "gymPhoto.result.addedToPlan", defaultValue: "Added to today's plan", comment: "Confirmation shown after the generated workout is added to today's plan"), systemImage: "checkmark.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    } else {
                        Button {
                            Task { await addToTodaysPlan() }
                        } label: {
                            Group {
                                if isAddingToPlan {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(String(localized: "gymPhoto.result.addToPlanButton", defaultValue: "Add to today's plan", comment: "Button adding the generated gym-photo workout to today's plan"))
                                }
                            }
                            .font(.system(size: 16.5, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .foregroundStyle(.white)
                        .glassGel(.blue)
                        .disabled(isAddingToPlan)
                        .padding(.top, 4)

                        // Kept available even after generating -- the
                        // workout stays on screen (resultPlan is never
                        // cleared by this tap), it's just a re-entry into
                        // the equipment step in case the plan isn't right.
                        SomaButton(title: "Adjust manually", size: .lg, variant: .secondary) {
                            step = .confirmingEquipment
                        }
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
        SomaChip(title: LocalizedStringKey(item), isSelected: true, showsRemoveIcon: true) {
            equipment.removeAll { $0 == item }
        }
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
            errorMessage = String(localized: "gymPhoto.error.photoProcessFailed", defaultValue: "Couldn't process that photo. Try another one.", comment: "Error shown when the selected/captured photo can't be compressed for upload")
            step = .pickPhoto
            return
        }
        do {
            let result = try await SupabaseClient.shared.analyzeGymPhoto(imageData: imageData)
            equipment = result.equipment
            lowConfidenceNotice = result.lowConfidence
            step = .confirmingEquipment
        } catch {
            errorMessage = String(localized: "gymPhoto.error.analyzeFailed", defaultValue: "Couldn't analyze that photo. Try again.", comment: "Error shown when the gym-photo equipment analysis request fails")
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
        } catch SupabaseError.serviceUnavailable {
            // Distinct from the generic case below -- the wording pass's
            // own OpenAI call failed (rate limit, exhausted credits, bad
            // key), not something a retry can fix. See
            // classifyGenerationError.
            errorMessage = SupabaseError.serviceUnavailable.errorDescription
            step = .confirmingEquipment
        } catch {
            errorMessage = String(localized: "gymPhoto.error.generateFailed", defaultValue: "Couldn't build a workout right now. Try again.", comment: "Error shown when generating a workout from confirmed equipment fails")
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
            addToPlanError = String(localized: "gymPhoto.error.addToPlanFailed", defaultValue: "Couldn't add to today's plan. Try again.", comment: "Error shown when confirming the AI-generated workout into today's plan fails")
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
