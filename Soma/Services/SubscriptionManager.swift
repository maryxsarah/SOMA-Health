import StoreKit

/// Wraps StoreKit 2 for the single $4.99/mo auto-renewable subscription
/// (with Apple's built-in 14-day free trial as its introductory offer).
/// This is the source of truth for "does this device have an active
/// subscription" -- separate from and additive to the referral-code bonus
/// tracked server-side in `users.referral_bonus_until` (see AppState).
@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    static let productID = "com.skollnitzer.soma.premium.monthly"

    @Published private(set) var product: Product?
    @Published private(set) var isSubscribed = false
    @Published var errorMessage: String?
    @Published var isPurchasing = false

    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = Task { [weak self] in
            await self?.listenForTransactionUpdates()
        }
        Task { [weak self] in
            await self?.loadProduct()
            await self?.refreshEntitlement()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            errorMessage = "Couldn't load subscription info. Check your connection."
        }
    }

    func purchase() async {
        guard let product else {
            errorMessage = "Subscription isn't available right now."
            return
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
            guard case .verified(let transaction) = result, transaction.productID == Self.productID else {
                continue
            }
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
