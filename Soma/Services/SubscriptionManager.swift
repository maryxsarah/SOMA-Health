import StoreKit

/// Wraps StoreKit 2 for Soma Premium's two auto-renewable subscription
/// options: monthly ($14.99/mo, no trial) and annual ($119.99/yr, with a
/// 3-day free trial as its introductory offer). This is the source of
/// truth for "does this device have an active subscription" -- separate
/// from and additive to the referral-code bonus tracked server-side in
/// `users.referral_bonus_until` (see AppState).
@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    static let monthlyProductID = "com.skollnitzer.soma.premium.monthly"
    static let annualProductID = "com.skollnitzer.soma.premium.annual"

    @Published private(set) var monthlyProduct: Product?
    @Published private(set) var annualProduct: Product?
    @Published private(set) var isSubscribed = false
    @Published var errorMessage: String?
    @Published var isPurchasing = false
    /// Drives the paywall's loading state so it can hold off on prices
    /// instead of rendering hardcoded ones as if they were real.
    @Published private(set) var isLoadingProducts = false

    /// At least one plan is missing from StoreKit. Deliberately not
    /// "both are nil": a partial response (e.g. only monthly returned
    /// while the annual product awaits App Store approval) leaves the
    /// paywall's default plan unbuyable, so it needs the same error/retry
    /// treatment as a total failure -- gating recovery on "both missing"
    /// made a partial load a silent dead end.
    var productsIncomplete: Bool {
        monthlyProduct == nil || annualProduct == nil
    }

    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = Task { [weak self] in
            await self?.listenForTransactionUpdates()
        }
        Task { [weak self] in
            await self?.loadProducts()
            await self?.refreshEntitlement()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let products = try await Product.products(for: [Self.monthlyProductID, Self.annualProductID])
            monthlyProduct = products.first { $0.id == Self.monthlyProductID }
            annualProduct = products.first { $0.id == Self.annualProductID }
            errorMessage = productsIncomplete ? Self.productsUnavailableMessage : nil
        } catch {
            errorMessage = "Couldn't load subscription options. Check your connection and try again."
        }
    }

    /// The old copy here spelled out an Xcode scheme fix ("Edit Scheme ->
    /// Run -> Options -> StoreKit Configuration") -- development
    /// instructions that a TestFlight user has no way to act on, in red,
    /// on the paywall. The hint is still useful while developing, so it
    /// stays behind `#if DEBUG`; release builds get copy written for the
    /// person actually reading it.
    static var productsUnavailableMessage: String {
        #if DEBUG
        return "Subscription options aren't available right now. (Debug: check Edit Scheme -> Run -> Options -> StoreKit Configuration is set to Soma.storekit.)"
        #else
        return "Subscription options aren't available right now. Please try again in a moment."
        #endif
    }

    func purchase(_ product: Product) async {
        if productsIncomplete {
            // Retry once on-demand -- covers the case where the initial
            // load in init() hadn't finished yet when the user tapped in.
            await loadProducts()
        }

        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    isSubscribed = true
                    AnalyticsManager.shared.subscriptionStarted(plan: transaction.productID)
                } else {
                    errorMessage = "Purchase couldn't be verified."
                }
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Purchase is awaiting approval (e.g. Ask to Buy)."
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    /// Required by App Store guidelines for any app selling subscriptions
    /// -- lets a user recover access on a new device/reinstall.
    func restorePurchases() async {
        errorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !isSubscribed {
                errorMessage = "No active subscription found for this Apple ID."
            }
        } catch {
            errorMessage = "Couldn't restore purchases: \(error.localizedDescription)"
        }
    }

    func refreshEntitlement() async {
        // StoreKit has no direct "user cancelled" push -- this is the one
        // observable signal available: isSubscribed flipping true -> false
        // across a refresh (expired, revoked/refunded, or no longer in
        // currentEntitlements at all). Doesn't change the entitlement logic
        // below, just observes its before/after result.
        let wasSubscribed = isSubscribed
        defer {
            if wasSubscribed, !isSubscribed {
                AnalyticsManager.shared.subscriptionCancelled()
            }
        }

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.monthlyProductID || transaction.productID == Self.annualProductID
            else { continue }
            isSubscribed = transaction.revocationDate == nil
            let tier = isSubscribed ? (transaction.productID == Self.annualProductID ? "annual" : "monthly") : "free"
            updateSubscriptionTierRemote(tier)
            return
        }
        isSubscribed = false
        updateSubscriptionTierRemote("free")
    }

    /// Fire-and-forget, best-effort -- see SupabaseClient.updateSubscriptionTier's
    /// own comment on why a client-reported tier is an acceptable trust
    /// model here (a cost-control soft limit, not a security boundary).
    private func updateSubscriptionTierRemote(_ tier: String) {
        Task { try? await SupabaseClient.shared.updateSubscriptionTier(tier) }
    }

    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await transaction.finish()
            await refreshEntitlement()
        }
    }
}
