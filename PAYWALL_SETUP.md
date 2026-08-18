# Paywall / Subscription Setup

Soma Pro: two plans, **Annual $119.99/yr** (3-day free trial) and
**Monthly $14.99/mo** (no trial), or a referral code that grants bonus free
days independent of either. Gates the recommendation **detail**
view (step target, workout suggestions, "why" explanation) — the Home
card (today's category + message) always stays free. Also shown as a
**hard** paywall (no skip) at the end of onboarding -- see §5 below.

Pro (Annual only) also raises the daily AI-workout-generation limit --
see `generationLimits.ts` for the current numbers (free/monthly/annual),
one shared bucket across the workout-suggestion and gym-photo-scan
features.

## 1. Test it right now -- no App Store Connect needed

Xcode can simulate the entire purchase flow locally using
[`Soma/Soma.storekit`](Soma/Soma.storekit), a StoreKit test configuration
already checked into this project with both products and the annual
plan's 3-day free trial pre-configured. This only applies to the **Soma**
scheme's Debug **Run** action (see `project.yml`'s
`storeKitConfiguration` under `schemes.Soma.run`) -- Release
archives/TestFlight builds always talk to the real App Store, StoreKit
test config or not.

**One-time step (Xcode UI, can't be scripted):**
1. Product menu (or the scheme selector) → **Edit Scheme...**
2. Select **Run** in the left sidebar → **Options** tab.
3. **StoreKit Configuration** dropdown → select `Soma.storekit` (this is
   normally already set via `project.yml`, but `xcodegen generate` does
   not reliably preserve it across regeneration -- reselect it if
   purchases start failing locally with "products not found").
4. Close the scheme editor.

Now build and run. Tapping a recommendation card with no active
subscription/referral bonus opens the dashboard-configured Superwall
paywall (see §4) for the `detail_access` placement. Use **Debug →
StoreKit → Manage Transactions** in Xcode to inspect/delete simulated
purchases while testing.

## 2. Go live: App Store Connect (manual -- your legal/bank identity)

Nothing in step 1 needs this, but a real purchase from a real user does.

1. **App Store Connect → Agreements, Tax, and Banking** -- accept the
   Paid Apps agreement, submit tax forms, add a bank account for
   payouts. Apple can take 24-48h to process this.
2. **Your app → Monetization → Subscriptions** → **Create a Subscription
   Group** (e.g. "Soma Pro") -- both plans below go in the *same*
   group, as tiers of one subscription.
3. Inside that group, **create the annual subscription**:
   - Reference name: `Soma Pro Annual`
   - **Product ID: `com.skollnitzer.soma.premium.annual`** -- must match
     exactly, it's hardcoded in `SubscriptionManager.annualProductID`
     (the product ID string itself predates the Pro rename and is not
     worth churning -- Apple product IDs are effectively permanent once
     live).
   - Duration: 1 year, Price: $119.99
   - **Subscription Prices** → add an **Introductory Offer** → Free →
     Duration: 3 days → applies once per subscriber.
4. **Create the monthly subscription** in the same group:
   - Reference name: `Soma Pro Monthly`
   - **Product ID: `com.skollnitzer.soma.premium.monthly`** -- matches
     `SubscriptionManager.monthlyProductID` (same product-ID-naming note
     as above).
   - Duration: 1 month, Price: $14.99, no introductory offer as a
     *default* offer -- see §4a for the invite-only Offer Code path.
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
Two codes are already seeded: `SOMA14` and `SOMAFIRST` -- both currently
grant **14 bonus days** and both have unlimited redemptions.
(`SOMAFIRST` originally granted 21 days; reduced to 14 in a later
migration, see `20260727010000_reduce_somafirst_bonus_days.sql`.)

## 3a. App Store Offer Codes (separate from referral codes)

Additive to, not a replacement for, the custom referral system above:
Apple **Offer Codes** on the Monthly product let an invited user redeem
one month free through Apple's own StoreKit UI
(`AppStore.presentOfferCodeRedeemSheet`, wired to Profile's "Redeem App
Store code" row and the paywall's "Have a code?" link). Set these up in
**App Store Connect → your Monthly subscription → Offer Codes**: Free
mode, 1 month, customer eligibility "new and expired subscribers",
configured to *replace* rather than stack with any introductory offer.
Offer codes can't be edited after creation -- only deactivated and
recreated. A redeemed offer code is detected as a trial via
`transaction.offer?.paymentMode == .freeTrial` in `SubscriptionManager`
(not `offerType == .introductory`, which only catches Apple's
per-product intro offer, not a redeemed code).

## 4. What's already wired up

Superwall (not a bespoke `PaywallView`) owns the actual paywall UI,
purchase button, plan copy, and "Restore Purchases" -- configured
entirely in the Superwall dashboard as templated pages, not in this
repo. What Swift code still owns:

- `SubscriptionManager` (StoreKit 2): the single reader of
  `Transaction.currentEntitlements`/`Transaction.updates`, tracking
  `isSubscribed`/`tier`/`isInTrial`/`expirationDate` across either
  product ID, syncing `tier` to Supabase's `subscription_tier` (used
  server-side for AI-generation quota), and mirroring the result into
  `Superwall.shared.subscriptionStatus` via `SomaPurchaseController`
  (Soma's custom `PurchaseController`, so Superwall never tracks
  subscription status on its own).
- `AppState.referralBonusUntil`: fetched from `users.referral_bonus_until`
  on Home appear and after a successful redemption -- checked in Swift
  (`requestDetailAccess` in `HomeView`), since Superwall's own dashboard
  has no visibility into this custom bonus system.
- `HomeView.requestDetailAccess(then:)`: if a referral bonus is active,
  runs the action directly; otherwise defers entirely to Superwall's
  `detail_access` placement (`Superwall.shared.register(placement:
  "detail_access", handler:, feature:)`) -- whether today's audience even
  shows a paywall, and what it looks like, is the dashboard's call, not
  this repo's.
- The onboarding flow (`PostSetupFlowView`) registers the
  `onboarding_paywall` placement once, right before Home. This
  presentation is the hard, non-dismissible one (see §5) --
  `markOnboardingComplete()` only fires after a real purchase succeeds,
  a referral bonus is already active, or Restore Purchases recovers an
  existing subscription.
- Every `Superwall.shared.register(...)` call site in the app should pass
  a `handler:` built from `SuperwallDiagnostics.handler(placement:)` --
  without it, a misconfigured placement (no campaign attached on the
  dashboard) or a presentation error both fail *silently*, and Superwall
  itself calls the `feature` closure anyway in both the `.skipped` case
  and the non-gated decline branch, so a broken paywall is
  indistinguishable from "already subscribed" without this logging.

### Known failure modes (all hit this repo for real -- check these first)

A paywall that "just doesn't open," with no crash and no visible error,
almost always traces to one of these:

1. **Empty/wrong `SUPERWALL_API_KEY`.** `Superwall.configure(apiKey:)`
   with an empty or invalid key fails to load, and every `register()`
   call presents nothing (`SWKPresentationError` code 104, "Trying to
   present paywall without the Superwall config" -- visible via Console.app
   filtered on the device/process, even without an Xcode debugger
   attached, since `SuperwallDiagnostics` logs through `os.Logger`).
   **This shipped for real on 2026-08-18**: the CI-driven TestFlight
   workflow never had `SUPERWALL_API_KEY` in its injected secrets from
   when it was first set up until that date -- every CI-built TestFlight
   release up to then had no working paywall at all. The workflow now
   fails outright if `SUPERWALL_API_KEY`/`POSTHOG_API_KEY` come through
   empty (see `.github/workflows/testflight.yml`), but a *wrong* (not
   empty) secret value passes that check silently -- confirm the actual
   value matches the dashboard's Public API Key, e.g. via
   `scripts/gh-set-secrets.sh` (gitignored, holds the known-correct
   value) or `gh secret list` (existence only, GitHub never lets you read
   a secret's value back).
2. **A campaign's audience is paused on the dashboard.** `register()`
   silently skips and the feature closure runs as if nothing were wrong.
   Devices that launched during the pause hold a cached config until the
   next cold start (reinstall forces a refresh).
3. **An active referral bonus.** `requestDetailAccess`/the onboarding
   flow skip registering Superwall entirely while
   `appState.referralBonusUntil` is in the future -- a tester who redeemed
   `SOMA14`/`SOMAFIRST` won't see a paywall for two weeks. Check
   `users.referral_bonus_until` for the test account before assuming
   Superwall itself is broken.
4. **A stale `subscriptionStatus`.** Superwall persists
   `subscriptionStatus` across launches; it's only refreshed by
   `SubscriptionManager.refreshEntitlement()`'s
   `mirrorSubscriptionStatusToSuperwall()`, called lazily from `init()`.
   If `Transaction.currentEntitlements` is slow (sandbox account, poor
   network), a placement registered before that resolves can see a
   stale/`.unknown` status. `PostSetupFlowView` explicitly awaits a fresh
   `refreshEntitlement()` before registering; other call sites currently
   don't.
5. **Missing/incomplete App Store Connect subscription setup** --
   Agreements/Tax/Banking not accepted, subscription status "Missing
   Metadata," or within the ~72h propagation window after a subscription
   first goes live. Not fixable from this repo.
6. **TestFlight/sandbox quirks** -- a fresh reinstall resets local app
   state (the tester is anonymous again), and sandbox subscriptions
   renew on an accelerated cycle (roughly one renewal per real day, capped
   at 6 renewals before auto-renew stops) -- subscription behavior in
   TestFlight is not a faithful stand-in for production.

## 5. Onboarding's hard paywall

Deliberately different from every other paywall presentation in the app:
no skip. A user finishing onboarding must either start the Annual trial,
subscribe Monthly, redeem a referral code, or (on a reinstall/new device)
Restore Purchases to reach Home at all. This is intentional product
behavior, not a bug -- confirm with product/legal before loosening it, the
same way any other paywall-gating change in this app gets flagged.
