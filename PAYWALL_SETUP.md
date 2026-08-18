# Paywall / Subscription Setup

Soma Premium: two plans, **Annual $119.99/yr** (3-day free trial) and
**Monthly $14.99/mo** (no trial), or a referral code that grants bonus free
days independent of either. Gates the recommendation **detail** view (step
target, workout suggestions, "why" explanation) — the Home card (today's
category + message) always stays free. Also shown as a **hard** paywall (no
skip) at the end of onboarding -- see §5 below.

Paywalls themselves are **Superwall dashboard paywalls**, not a native
in-app view -- see commit `14668d9` ("Integrate Superwall SDK for
remote-configurable paywalls"), which removed the old native `PaywallView`.
There are 4 placements registered in code, each via
`Superwall.shared.register(placement:handler:)` with
`SuperwallDiagnostics.handler(placement:)` as the handler (logs skip/error
reasons to both `os.Logger` and `AnalyticsManager` -- see that file's doc
comment for why both layers exist):

| Placement            | Call site                                    | Notes |
|-----------------------|----------------------------------------------|-------|
| `onboarding_paywall`   | `PostSetupFlowView.presentOnboardingPaywall()` | Hard-gated (no skip); see §5. |
| `view_premium`         | `ProfileView`, `HomeView`                     | "View SOMA Premium" entry points. |
| `detail_access`        | `HomeView`                                    | Locked recommendation-detail gate. |
| `paywall_exit_offer`   | `WinBackOfferManager`                         | Win-back offer after a decline -- see `docs/exit-offer-paywall-brief.md` for the dashboard paywall spec. |

## 1. Test the underlying purchase locally -- no App Store Connect needed

Superwall's dashboard paywalls still purchase real App Store products under
the hood via StoreKit 2 (`SomaPurchaseController` delegates to
`Superwall.shared.purchase`/`restorePurchases`). Xcode can simulate that
purchase flow locally using
[`Soma/Soma.storekit`](Soma/Soma.storekit), a StoreKit test configuration
already checked into this project with both products and the annual plan's
3-day free trial pre-configured.

**One-time step (Xcode UI, can't be scripted):**
1. Product menu (or the scheme selector) → **Edit Scheme...**
2. Select **Run** in the left sidebar → **Options** tab.
3. **StoreKit Configuration** dropdown → select `Soma.storekit`.
4. Close the scheme editor.

Build and run, then trigger any placement above (e.g. tap a recommendation
card with no active subscription, or run onboarding through to the end).
Superwall presents whichever paywall is configured for that placement on
the dashboard; a purchase against `Soma.storekit` completes without App
Store Connect or banking setup. Use **Debug → StoreKit → Manage
Transactions** in Xcode to inspect/delete simulated purchases while testing.

If a placement shows nothing instead of a paywall, that's very likely a
Superwall dashboard config issue (campaign not published, placement not
attached, or audience rules excluding the test user) rather than a code
bug -- `SuperwallDiagnostics` logs the exact `PaywallSkippedReason` to the
Xcode console (Debug) and to analytics (Release) for exactly this case.

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
7. **Superwall dashboard**: each placement in the table above needs a
   published campaign with a paywall attached, using these product IDs in
   its plan picker. A placement with no attached campaign resolves as
   `.placementNotFound` and silently completes the caller's `feature`
   closure -- see `SuperwallDiagnostics`'s doc comment.

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
step) -- both unlimited redemptions. Redemption itself lives in
`ReferralCodeSheet`, a standalone sheet (not a Superwall paywall template,
since a dashboard paywall can't host a custom text-entry field).

## 4. What's already wired up

- `SubscriptionManager` (StoreKit 2): reads `Transaction.currentEntitlements`
  across either product ID, syncs `subscription_tier` to Supabase, and
  mirrors the result into `Superwall.shared.subscriptionStatus` (see its
  own doc comment for why that mirroring is necessary once a custom
  `PurchaseController` is configured).
- `SomaPurchaseController`: the `PurchaseController` Superwall is configured
  with at launch (`AppDelegate`) -- delegates `purchase`/`restorePurchases`
  straight to `Superwall.shared`'s own StoreKit 2 handling; exists only so
  `SubscriptionManager` stays the sole reader of `currentEntitlements`.
- `SuperwallDiagnostics`: shared `PaywallPresentationHandler` factory every
  `register(placement:)` call site uses, so a skipped or failed
  presentation is never silent -- see its doc comment for the exact
  SuperwallKit behavior this works around.
- `AppState.referralBonusUntil`: fetched from `users.referral_bonus_until`
  on Home appear and after a successful redemption.
- `HomeView.hasDetailAccess`: `isSubscribed OR referralBonusUntil > now`
  -- gates whether tapping the card opens the recommendation detail or
  registers the `detail_access` placement.
- `WinBackOfferManager`: registers `paywall_exit_offer`, frequency-capped
  to once, after a decline on one of the other 3 placements -- see
  `docs/exit-offer-paywall-brief.md` for that paywall's dashboard spec.

## 5. Onboarding's hard paywall

Deliberately different from every other paywall presentation in the app:
no skip. A user finishing onboarding must either start the Annual trial,
subscribe Monthly, redeem a referral code (before reaching this step, via
the onboarding referral-code step), or (on a reinstall/new device) Restore
Purchases to reach Home at all. `PostSetupFlowView.presentOnboardingPaywall()`
skips registering the placement entirely if `appState.referralBonusUntil`
is already in the future (an active redeemed bonus). Otherwise it registers
`onboarding_paywall` and only calls `markOnboardingComplete()` from the
`feature` closure -- a purchase, a restore, or (if the dashboard paywall is
ever set to Non Gated) any dismissal. The dashboard paywall assigned to this
placement must be configured **non-dismissible** (no close button) for
that gating to hold -- see the comment at `PostSetupFlowView.swift` around
the `.paywall` case. This is intentional product behavior, not a bug --
confirm with product/legal before loosening it, the same way any other
paywall-gating change in this app gets flagged.
