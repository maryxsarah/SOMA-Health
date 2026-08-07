# Paywall / Subscription Setup

Soma Premium: two plans, **Annual $119.99/yr** (3-day free trial) and
**Monthly $14.99/mo** (no trial), or a referral code that grants bonus free
days independent of either. Gates the recommendation **detail**
view (step target, workout suggestions, "why" explanation) — the Home
card (today's category + message) always stays free. Also shown as a
**hard** paywall (no skip) at the end of onboarding -- see §5 below.

Premium (Annual only) also raises the daily AI-workout-generation limit
from 1/day (free and Monthly) to 3/day -- see `generationLimits.ts`.

## 1. Test it right now -- no App Store Connect needed

Xcode can simulate the entire purchase flow locally using
[`Soma/Soma.storekit`](Soma/Soma.storekit), a StoreKit test configuration
already checked into this project with both products and the annual
plan's 3-day free trial pre-configured.

**One-time step (Xcode UI, can't be scripted):**
1. Product menu (or the scheme selector) → **Edit Scheme...**
2. Select **Run** in the left sidebar → **Options** tab.
3. **StoreKit Configuration** dropdown → select `Soma.storekit`.
4. Close the scheme editor.

Now build and run. Tapping a recommendation card with no active
subscription shows the paywall; the annual plan is selected by default
and shows "Start Free Trial", switching to monthly shows "Continue" (no
trial). No App Store Connect account or banking setup required for this.
Use **Debug → StoreKit → Manage Transactions** in Xcode to inspect/delete
simulated purchases while testing.

## 2. Go live: App Store Connect (manual -- your legal/bank identity)

Nothing in step 1 needs this, but a real purchase from a real user does.

1. **App Store Connect → Agreements, Tax, and Banking** -- accept the
   Paid Apps agreement, submit tax forms, add a bank account for
   payouts. Apple can take 24-48h to process this.
2. **Your app → Monetization → Subscriptions** → **Create a Subscription
   Group** (e.g. "Soma Premium") -- both plans below go in the *same*
   group, as tiers of one subscription.
3. Inside that group, **create the annual subscription**:
   - Reference name: `Soma Premium Annual`
   - **Product ID: `com.skollnitzer.soma.premium.annual`** -- must match
     exactly, it's hardcoded in `SubscriptionManager.annualProductID`.
   - Duration: 1 year, Price: $119.99
   - **Subscription Prices** → add an **Introductory Offer** → Free →
     Duration: 3 days → applies once per subscriber.
4. **Create the monthly subscription** in the same group:
   - Reference name: `Soma Premium Monthly`
   - **Product ID: `com.skollnitzer.soma.premium.monthly`** -- matches
     `SubscriptionManager.monthlyProductID`.
   - Duration: 1 month, Price: $14.99, **no** introductory offer.
5. Set the annual plan's rank/priority above the monthly plan in the
   group (so App Store surfaces it as the default/"upgrade" tier).
6. Add localization (display name, description) for at least English on
   both, then submit both subscriptions for review along with your next
   app version (subscriptions are reviewed together with a build, not
   standalone).

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
Two codes are already seeded: `SOMA14` (14 bonus days) and `SOMAFIRST`
(21 days / 3 weeks, entered on the dedicated onboarding referral-code
step) -- both unlimited redemptions.

## 4. What's already wired up

- `SubscriptionManager` (StoreKit 2): loads both products, handles
  purchase/restore for whichever is selected, tracks `isSubscribed` from
  `Transaction.currentEntitlements` across either product ID.
- `PaywallView`: annual/monthly selectable plan cards, dynamic price/fine
  print, "Restore Purchases" (required by App Review for any subscription
  app), and a referral code field. Also accepts an `onFinished` closure so
  it can run as a plain onboarding step, not only as a `.sheet`.
- `AppState.referralBonusUntil`: fetched from `users.referral_bonus_until`
  on Home appear and after a successful redemption.
- `HomeView.hasDetailAccess`: `isSubscribed OR referralBonusUntil > now`
  -- gates whether tapping the card opens `RecommendationDetailView` or
  `PaywallView`.
- The onboarding flow (`PostSetupFlowView`) shows the same `PaywallView`
  once, right before Home, after two soft reassurance screens ("try free"
  / "trial reminder"). This one presentation passes `allowsDismissal:
  false` -- there is no "Not now" here, and `markOnboardingComplete()`
  only fires after a real purchase succeeds (or a referral code is
  redeemed, or Restore Purchases recovers an existing one). Every other
  `PaywallView` presentation in the app (Home's locked-detail sheet,
  Profile's) keeps the default `allowsDismissal: true`.

## 5. Onboarding's hard paywall

Deliberately different from every other paywall presentation in the app:
no skip. A user finishing onboarding must either start the Annual trial,
subscribe Monthly, redeem a referral code, or (on a reinstall/new device)
Restore Purchases to reach Home at all. This is intentional product
behavior, not a bug -- confirm with product/legal before loosening it, the
same way any other paywall-gating change in this app gets flagged.
