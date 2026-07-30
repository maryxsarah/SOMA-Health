import AVFoundation
import XCTest
@testable import Soma

/// Covers the gate that replaced a black camera screen with an
/// explainer. `UIImagePickerController` presents a dead, black
/// viewfinder when camera access is denied instead of refusing, so the
/// decision has to be made from the authorization status before the
/// sheet is ever shown.
final class CameraAccessTests: XCTestCase {

    func testAuthorizedPresentsTheCamera() {
        XCTAssertEqual(CameraAccess.action(for: .authorized, cameraAvailable: true), .present)
    }

    func testNotDeterminedAsksFirst() {
        XCTAssertEqual(CameraAccess.action(for: .notDetermined, cameraAvailable: true), .request)
    }

    /// The regression: this used to fall through to the picker.
    func testDeniedExplainsInsteadOfPresenting() {
        XCTAssertEqual(CameraAccess.action(for: .denied, cameraAvailable: true), .explainDenied)
    }

    func testRestrictedGetsItsOwnExplanation() {
        XCTAssertEqual(CameraAccess.action(for: .restricted, cameraAvailable: true), .explainRestricted)
    }

    /// The second regression: Screen Time / MDM restrictions also make
    /// `isSourceTypeAvailable(.camera)` false, so a hardware guard placed
    /// before the status check shadowed `.restricted` and this explainer
    /// was unreachable on real devices.
    func testRestrictedWinsOverUnavailableHardware() {
        XCTAssertEqual(CameraAccess.action(for: .restricted, cameraAvailable: false), .explainRestricted)
    }

    /// Simulator and camera-less iPads: the picker substitutes the photo
    /// library, so gating on permission there would break a flow that
    /// works. (`.restricted` is excluded -- that means a policy is
    /// blocking the camera, not that the hardware is absent.)
    func testNoCameraHardwareStillPresents() {
        for status in [AVAuthorizationStatus.denied, .notDetermined, .authorized] {
            XCTAssertEqual(
                CameraAccess.action(for: status, cameraAvailable: false),
                .present,
                "status \(status.rawValue) should present when there is no camera"
            )
        }
    }
}
