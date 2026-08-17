import AuthenticationServices
import StoreKit
import SwiftUI

/// In-app account deletion (App Review Guideline 5.1.1(v)) -- pushed from
/// Account settings. Explains exactly what gets erased, warns that an
/// Apple-billed subscription keeps billing until cancelled with Apple
/// (with a direct manage-subscriptions sheet), re-authenticates Sign in
/// with Apple users to obtain the authorization code Apple's mandated
/// token revocation needs (TN3194), then calls the delete-account edge
/// function and cleans up every local trace.
struct DeleteAccountView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    /// Auth identity providers ("apple"/"google"/"email") -- decides
    /// whether the Apple re-auth step applies.
    @State private var providers: [String] = []
    @State private var appleAuthorizationCode: String?
    /// The SIWA re-auth prompt failed or was cancelled -- surfaces a
    /// retry plus an explicit "delete anyway" (revocation is Apple's
    /// mandate, but it must never stand between the user and erasure).
    @State private var appleReauthFailed = false
    @State private var showConfirmation = false
    @State private var isDeleting = false
    @State private var showDeletedConfirmation = false
    @State private var showManageSubscriptions = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                whatGetsErasedCard

                if subscriptionManager.isSubscribed {
                    subscriptionWarningCard
                }

                deleteButton

                if appleReauthFailed {
                    deleteAnywayButton
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(SomaTokens.danger)
                        .padding(.horizontal, 4)
                }
            }
            .padding(20)
        }
        .somaBackground()
        .navigationTitle(String(localized: "deleteAccount.title", defaultValue: "Delete account", comment: "Navigation title of the account deletion page"))
        .navigationBarTitleDisplayMode(.inline)
        .task { providers = (try? await SupabaseClient.shared.fetchAuthProviders()) ?? [] }
        .confirmationDialog(
            String(localized: "deleteAccount.confirm.title", defaultValue: "Delete your account permanently?", comment: "Title of the final account-deletion confirmation dialog"),
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "deleteAccount.confirm.delete", defaultValue: "Delete account", comment: "Destructive confirmation button that actually deletes the account"), role: .destructive) {
                Task { await performDeletion() }
            }
            Button(String(localized: "deleteAccount.confirm.cancel", defaultValue: "Cancel", comment: "Cancel button in the account-deletion confirmation dialog"), role: .cancel) {}
        } message: {
            Text(String(localized: "deleteAccount.confirm.message", defaultValue: "This can't be undone. All your data will be erased.", comment: "Message in the final account-deletion confirmation dialog"))
        }
        .alert(
            String(localized: "deleteAccount.done.title", defaultValue: "Your account has been deleted", comment: "Title of the alert confirming the account was deleted"),
            isPresented: $showDeletedConfirmation
        ) {
            Button(String(localized: "deleteAccount.done.ok", defaultValue: "OK", comment: "OK button on the deletion-complete alert")) {
                appState.signOut()
            }
        } message: {
            Text(String(localized: "deleteAccount.done.message", defaultValue: "Your data has been erased. Removal from encrypted backups completes within 30 days.", comment: "Message on the deletion-complete alert, disclosing the backup retention window"))
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
    }

    // MARK: - Cards

    private var whatGetsErasedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "deleteAccount.erased.eyebrow", defaultValue: "What gets erased", comment: "Eyebrow above the list of data account deletion removes"))
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(SomaTokens.ink4)
            erasedRow("person.crop.circle", String(localized: "deleteAccount.erased.profile", defaultValue: "Your profile, goals, and settings", comment: "Deleted-data list: profile and settings"))
            erasedRow("chart.bar", String(localized: "deleteAccount.erased.history", defaultValue: "Workout, nutrition, sleep, and mood history", comment: "Deleted-data list: activity history"))
            erasedRow("photo.on.rectangle.angled", String(localized: "deleteAccount.erased.photos", defaultValue: "Progress photos", comment: "Deleted-data list: uploaded photos"))
            erasedRow("sparkles", String(localized: "deleteAccount.erased.affirmations", defaultValue: "Saved affirmations and AI generations", comment: "Deleted-data list: affirmations and AI content"))
            Text(String(localized: "deleteAccount.erased.footnote", defaultValue: "Deletion is permanent and can't be undone. It completes immediately; removal from encrypted backups finishes within 30 days.", comment: "Footnote under the deleted-data list explaining permanence and the backup window"))
                .font(.system(size: 11.5))
                .foregroundStyle(SomaTokens.ink3)
                .padding(.top, 2)
        }
        .padding(.init(top: 14, leading: 16, bottom: 14, trailing: 16))
        .glassCardFlat(cornerRadius: SomaTokens.rRow)
    }

    private func erasedRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(SomaTokens.ink4)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(SomaTokens.inkRowTitle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Apple can't let us cancel a subscription on the user's behalf --
    /// deleting the account does NOT stop billing, so this is a required
    /// disclosure (Apple's own account-deletion guidance) with a direct
    /// path to the native management sheet.
    private var subscriptionWarningCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SomaTokens.warn)
                Text(String(localized: "deleteAccount.subscription.title", defaultValue: "You have an active subscription", comment: "Title of the active-subscription warning on the deletion page"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SomaTokens.ink)
            }
            Text(String(localized: "deleteAccount.subscription.body", defaultValue: "Deleting your account does not cancel it — billing continues through Apple until you cancel it yourself.", comment: "Body of the active-subscription warning explaining Apple billing continues"))
                .font(.system(size: 12.5))
                .foregroundStyle(SomaTokens.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showManageSubscriptions = true
            } label: {
                Text(String(localized: "deleteAccount.subscription.manage", defaultValue: "Manage subscription", comment: "Button opening Apple's native manage-subscriptions sheet"))
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(SomaTokens.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.55))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                            .overlay(Capsule().stroke(SomaTokens.hairline, lineWidth: 1).padding(-0.5))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.init(top: 14, leading: 16, bottom: 14, trailing: 16))
        .background(SomaTokens.warnSoft, in: RoundedRectangle(cornerRadius: SomaTokens.rRow, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SomaTokens.rRow, style: .continuous).strokeBorder(SomaTokens.warnLine, lineWidth: 1))
    }

    // MARK: - Actions

    private var deleteButton: some View {
        Button {
            Task { await startDeletion() }
        } label: {
            Group {
                if isDeleting {
                    ProgressView()
                } else {
                    Text(String(localized: "deleteAccount.deleteButton", defaultValue: "Delete my account", comment: "Primary destructive button starting account deletion"))
                        .font(.system(size: 15.5, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassGel(.red)
        }
        .buttonStyle(.plain)
        .disabled(isDeleting)
        .padding(.top, 6)
        .accessibilityHint(Text(String(localized: "deleteAccount.deleteButtonHint", defaultValue: "Permanently erases your account after confirmation", comment: "VoiceOver hint on the delete-account button")))
    }

    /// Only after a failed/cancelled SIWA re-auth: Apple's token
    /// revocation is their mandate, but it must never block the user's
    /// right to erasure -- so the escape hatch exists, explicitly labeled.
    private var deleteAnywayButton: some View {
        Button {
            showConfirmation = true
        } label: {
            Text(String(localized: "deleteAccount.deleteAnyway", defaultValue: "Delete without Apple sign-in", comment: "Secondary destructive button deleting the account without SIWA re-authentication after it failed"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SomaTokens.danger)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isDeleting)
    }

    private func startDeletion() async {
        errorMessage = nil
        // Apple-mandated (TN3194): revoking SIWA tokens needs a FRESH
        // authorization code (~5 min lifetime), so the prompt runs right
        // before confirmation and doubles as re-authentication.
        if providers.contains("apple"), appleAuthorizationCode == nil {
            do {
                appleAuthorizationCode = try await AppleReauthCoordinator.requestAuthorizationCode()
                appleReauthFailed = false
            } catch {
                appleReauthFailed = true
                errorMessage = String(localized: "deleteAccount.appleReauthFailed", defaultValue: "Couldn't confirm your Apple ID. Try again, or delete without it.", comment: "Error shown when the Sign in with Apple re-authentication before deletion fails")
                return
            }
        }
        showConfirmation = true
    }

    private func performDeletion() async {
        isDeleting = true
        defer { isDeleting = false }
        errorMessage = nil
        // Last attributable event -- identifiers reset right after.
        AnalyticsManager.shared.accountDeleted()
        do {
            try await SupabaseClient.shared.deleteAccount(appleAuthorizationCode: appleAuthorizationCode)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        AnalyticsManager.shared.resetAfterAccountDeletion()
        // Day-stamped reminders for an account that no longer exists.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        showDeletedConfirmation = true
    }
}

/// One-shot Sign in with Apple prompt that returns only the authorization
/// code (no scopes requested) -- the input Apple's /auth/token +
/// /auth/revoke pair needs. Deliberately separate from SessionManager's
/// sign-IN flow, which exchanges the credential for a Supabase session;
/// here the account is about to stop existing.
private final class AppleReauthCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<String, Error>?
    /// Keeps the coordinator alive for the duration of the prompt --
    /// ASAuthorizationController holds its delegate weakly.
    private static var active: AppleReauthCoordinator?

    static func requestAuthorizationCode() async throws -> String {
        let coordinator = AppleReauthCoordinator()
        active = coordinator
        defer { active = nil }
        return try await withCheckedThrowingContinuation { continuation in
            coordinator.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = coordinator
            controller.presentationContextProvider = coordinator
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let codeData = credential.authorizationCode,
            let code = String(data: codeData, encoding: .utf8)
        else {
            continuation?.resume(throwing: URLError(.userAuthenticationRequired))
            continuation = nil
            return
        }
        continuation?.resume(returning: code)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}

#Preview {
    NavigationStack {
        DeleteAccountView()
            .environmentObject(AppState())
    }
}
