import SwiftUI
import UIKit

/// Shake-to-report plumbing. SwiftUI has no shake API, so the standard
/// bridge is a `UIWindow.motionEnded` override rebroadcast through
/// NotificationCenter -- every window in the app inherits it, no
/// subclassing or per-scene wiring needed.
extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

/// `.onShake { ... }` -- reads as a first-class gesture at the call site.
struct ShakeListener: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            action()
        }
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        modifier(ShakeListener(action: action))
    }
}
