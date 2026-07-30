import AVFoundation
import UIKit

/// Decides what the gym-photo flow should do before it presents the
/// camera.
///
/// `UIImagePickerController` does not check camera permission for us:
/// with `.camera` as the source type and access denied it presents
/// happily and renders a black preview with a shutter button that can
/// never take anything. `isSourceTypeAvailable(.camera)` doesn't catch
/// it either -- that reports hardware, not authorization, so it's `true`
/// on a denied device. The status has to be read explicitly first.
///
/// Pure and separate from the view so the black-screen case is testable
/// without a camera or a permission prompt.
enum CameraAccess {
    enum Action: Equatable {
        /// Safe to show the picker.
        case present
        /// First run -- ask the system, then re-decide on the answer.
        case request
        /// User said no; Settings can undo it.
        case explainDenied
        /// Screen Time or an MDM policy said no; Settings > Soma has no
        /// toggle to flip, so the copy has to point elsewhere.
        case explainRestricted
    }

    static func action(for status: AVAuthorizationStatus, cameraAvailable: Bool) -> Action {
        // Status is consulted before the hardware check: Screen Time /
        // MDM camera restrictions make `isSourceTypeAvailable(.camera)`
        // return false *too*, so a hardware guard placed first shadowed
        // `.restricted` entirely and the restricted explainer -- the very
        // case it was written for -- was unreachable on real devices.
        if status == .restricted { return .explainRestricted }

        // No camera hardware (Simulator, some iPads): fall through to the
        // picker, which substitutes the photo library. Permission is moot
        // there, and blocking it would break the Simulator flow.
        guard cameraAvailable else { return .present }

        switch status {
        case .authorized:
            return .present
        case .notDetermined:
            return .request
        case .restricted:
            return .explainRestricted // unreachable; handled above
        case .denied:
            return .explainDenied
        @unknown default:
            // A future status we can't reason about is treated as "not
            // usable" rather than presented -- an explanation is
            // recoverable, a black viewfinder isn't.
            return .explainDenied
        }
    }

    /// Live device state, split out so `action(for:cameraAvailable:)`
    /// stays free of globals.
    @MainActor
    static func currentAction() -> Action {
        action(
            for: AVCaptureDevice.authorizationStatus(for: .video),
            cameraAvailable: UIImagePickerController.isSourceTypeAvailable(.camera)
        )
    }
}
