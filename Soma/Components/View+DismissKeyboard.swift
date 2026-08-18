import SwiftUI

extension View {
    /// Dismisses the keyboard when the user taps anywhere outside an
    /// active text field. Combine with `.scrollDismissesKeyboard(.interactively)`
    /// on a containing ScrollView so scrolling also dismisses it.
    ///
    /// Uses `.simultaneousGesture`, not `.onTapGesture` -- a plain
    /// `onTapGesture` is exclusive and can win the gesture race against a
    /// child TextField/Button's own tap, swallowing the touch instead of
    /// passing it through (blocked-looking fields/buttons on screens where
    /// this wraps the whole content, e.g. EmailAuthView).
    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
        )
    }
}
