import SwiftUI
import UIKit

/// In-app bug report / feedback form. Reachable two ways: the Feedback
/// card in Profile, and shaking the device anywhere after sign-in (the
/// gesture every feedback SDK and TestFlight itself trains users on).
///
/// The user types only the message. Everything triage would otherwise
/// have to ask -- app version, build, OS, hardware, who sent it -- is
/// captured automatically and shown to the user before sending, not
/// collected silently. Reports land in the `user_feedback` table; read
/// them in the Supabase dashboard, newest first.
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    /// Raw values are the `user_feedback.type` CHECK constraint values.
    private enum FeedbackType: String, CaseIterable {
        case bug, idea, other

        var label: String {
            switch self {
            case .bug: "Bug"
            case .idea: "Idea"
            case .other: "Other"
            }
        }
    }

    @State private var type: FeedbackType = .bug
    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var sent = false

    /// Mirrors the `user_feedback.message` CHECK constraint. Without the
    /// client-side cap, a longer paste failed the insert server-side and
    /// the catch block blamed the connection -- unretryable, report lost.
    private static let maxMessageLength = 4000

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if sent {
                        sentContent
                    } else {
                        formContent
                    }
                }
                .padding(20)
            }
            .somaBackground()
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Found a bug or have an idea? It goes straight to the team.")
                .font(.body)
                .foregroundStyle(.secondary)

            Picker("Type", selection: $type) {
                ForEach(FeedbackType.allCases, id: \.self) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)

            TextField(
                type == .bug
                    ? "What happened, and what did you expect instead?"
                    : "What's on your mind?",
                text: $message,
                axis: .vertical
            )
            .lineLimit(5...10)
            .textFieldStyle(.roundedBorder)
            .onChange(of: message) { _, newValue in
                if newValue.count > Self.maxMessageLength {
                    message = String(newValue.prefix(Self.maxMessageLength))
                }
            }

            // Silent until it matters -- a counter on an empty form is
            // noise, but hitting the cap with no explanation looks broken.
            if message.count >= Self.maxMessageLength - 500 {
                Text("\(message.count)/\(Self.maxMessageLength)")
                    .font(.caption2)
                    .foregroundStyle(message.count >= Self.maxMessageLength ? .red : .secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            PillButton(
                title: isSending ? "Sending…" : "Send",
                isEnabled: !isSending && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                Task { await send() }
            }

            // Disclosed, not buried: the user sees exactly what rides along
            // with their words before they hit Send.
            Text("Sent with your report: Soma \(Self.appVersion) (\(Self.build)), iOS \(Self.osVersion), \(Self.deviceModel), and your account ID.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var sentContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.pillFill)
            Text("Thank you!")
                .font(.title3.bold())
            Text("Your \(type == .bug ? "report" : "feedback") is in. It helps more than you'd think.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            PillButton(title: "Done") { dismiss() }
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await SupabaseClient.shared.submitFeedback(
                type: type.rawValue,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                appVersion: Self.appVersion,
                build: Self.build,
                osVersion: Self.osVersion,
                deviceModel: Self.deviceModel
            )
            sent = true
        } catch {
            errorMessage = "Couldn't send right now. Check your connection and try again."
        }
    }

    // MARK: - Auto-captured context

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    private static var osVersion: String {
        UIDevice.current.systemVersion
    }

    /// Hardware identifier ("iPhone17,3"), not the marketing name --
    /// `UIDevice.model` only says "iPhone", which is useless for triage.
    private static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}

/// Presents FeedbackView from the top-most presented view controller.
/// A SwiftUI `.sheet` at the WindowGroup root cannot present while any
/// descendant sheet is up (paywall, gym-photo flow...) -- UIKit logs
/// "Attempt to present ... which is already presenting" and the shake
/// silently does nothing exactly on the modal screens where bugs get
/// reported. Walking to the top of the presentation stack works over
/// anything, so every entry point (shake, Profile button) routes here.
@MainActor
enum FeedbackPresenter {
    /// Marker subclass so an already-presented feedback sheet can be
    /// recognized and not presented twice on repeated shakes.
    final class HostingController: UIHostingController<AnyView> {}

    static func present() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.keyWindow?.rootViewController
        else { return }

        var top = root
        while let presented = top.presentedViewController { top = presented }
        guard !(top is HostingController) else { return }

        // The root's .preferredColorScheme(.light) doesn't reach a
        // UIKit-presented controller, so the fixed light aesthetic is
        // re-applied here.
        let host = HostingController(rootView: AnyView(FeedbackView().preferredColorScheme(.light)))
        top.present(host, animated: true)
    }
}

#Preview {
    FeedbackView()
}
