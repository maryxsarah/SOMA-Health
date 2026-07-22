import StoreKit

/// Wraps StoreKit 2 for Soma Premium's two auto-renewable subscription
/// options: monthly ($4.99/mo, no trial) and annual ($39.99/yr, with a
/// 7-day free trial as its introductory offer). This is the source of
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
        do {
            let products = try await Product.products(for: [Self.monthlyProductID, Self.annualProductID])
            monthlyProduct = products.first { $0.id == Self.monthlyProductID }
            annualProduct = products.first { $0.id == Self.annualProductID }
            if monthlyProduct == nil, annualProduct == nil {
                // Most common cause during development: the Xcode scheme
                // isn't pointed at Soma.storekit (Edit Scheme -> Run ->
                // Options -> StoreKit Configuration), so this is asking the
                // real App Store for products that don't exist there yet.
                errorMessage = "Subscription products not found. If you're testing in Xcode, check Edit Scheme -> Run -> Options -> StoreKit Configuration is set to Soma.storekit."
            }
        } catch {
            errorMessage = "Couldn't load subscription info. Check your connection."
        }
    }

    func purchase(_ product: Product) async {
        if monthlyProduct == nil, annualProduct == nil {
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
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.monthlyProductID || transaction.productID == Self.annualProductID
            else { continue }
            isSubscribed = transaction.revocationDate == nil
            return
        }
        isSubscribed = false
    }

    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await transaction.finish()
            await refreshEntitlement()
        }
    }
}
