import SwiftUI

extension View {
    /// Dismisses the keyboard when the user taps anywhere outside an
    /// active text field. Combine with `.scrollDismissesKeyboard(.interactively)`
    /// on a containing ScrollView so scrolling also dismisses it.
    func dismissKeyboardOnTap() -> some View {
        onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }
}
