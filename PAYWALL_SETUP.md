# Paywall / Subscription Setup

Soma Premium: $4.99/month, 14-day free trial, or a referral code that
grants bonus free days independent of the trial. Gates only the
recommendation **detail** view (step target, workout suggestions, "why"
explanation) — the Home card (today's category + message) always stays
free.

## 1. Test it right now -- no App Store Connect needed

Xcode can simulate the entire purchase flow locally using
[`Soma/Soma.storekit`](Soma/Soma.storekit), a StoreKit test configuration
already checked into this project with the $4.99/mo product and its
14-day free trial pre-configured.

**One-time step (Xcode UI, can't be scripted):**
1. Product menu (or the scheme selector) → **Edit Scheme...**
2. Select **Run** in the left sidebar → **Options** tab.
3. **StoreKit Configuration** dropdown → select `Soma.storekit`.
4. Close the scheme editor.

Now build and run. Tapping a recommendation card with no active
subscription shows the paywall; "Start Free Trial" triggers a real
(simulated) StoreKit purchase sheet, no App Store Connect account or
banking setup required. Use **Debug → StoreKit → Manage Transactions**
in Xcode to inspect/delete simulated purchases while testing.

## 2. Go live: App Store Connect (manual -- your legal/bank identity)

Nothing in step 1 needs this, but a real purchase from a real user does.

1. **App Store Connect → Agreements, Tax, and Banking** -- accept the
   Paid Apps agreement, submit tax forms, add a bank account for
   payouts. Apple can take 24-48h to process this.
2. **Your app → Monetization → Subscriptions** → **Create a Subscription
   Group** (e.g. "Soma Premium").
3. Inside that group, **create a subscription**:
   - Reference name: `Soma Premium Monthly`
   - **Product ID: `com.skollnitzer.soma.premium.monthly`** -- must match
     exactly, it's hardcoded in `SubscriptionManager.productID`.
   - Duration: 1 month
   - Price: $4.99 (Tier 5, or type the price directly)
   - **Subscription Prices** → add an **Introductory Offer** → Free →
     Duration: 2 weeks → applies once per subscriber.
   - Add localization (display name, description) for at least English.
4. Submit the subscription for review along with your next app version
   (subscriptions are reviewed together with a build, not standalone).

No entitlement or capability needs adding in Xcode for this -- StoreKit
purchase APIs don't require a special entitlements-file key the way
HealthKit does.

## 3. Referral codes

`referral_codes` has no client-facing access (same pattern as
`wearable_tokens`) -- add new codes via the Supabase Dashboard's **SQL
Editor** or **Table Editor**:
```sql
insert into referral_codes (code, bonus_days, max_redemptions)
values ('YOURCODE', 14, 100);  -- null max_redemptions = unlimited
```
One test code, `SOMA14` (14 bonus days, unlimited redemptions), is
already seeded via migration `20260722000001_seed_referral_code.sql`.

## 4. What's already wired up

- `SubscriptionManager` (StoreKit 2): loads the product, handles
  purchase/restore, tracks `isSubscribed` from `Transaction.currentEntitlements`.
- `PaywallView`: price, "Start Free Trial", "Restore Purchases" (required
  by App Review for any subscription app), and a referral code field.
- `AppState.referralBonusUntil`: fetched from `users.referral_bonus_until`
  on Home appear and after a successful redemption.
- `HomeView.hasDetailAccess`: `isSubscribed OR referralBonusUntil > now`
  -- gates whether tapping the card opens `RecommendationDetailView` or
  `PaywallView`.
