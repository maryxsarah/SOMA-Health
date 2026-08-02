# Soma V1 — Setup

Everything code-side is written. This document is the remaining manual
path from "empty checkout" to "running on a device": installing tools,
creating the Supabase project, registering OAuth apps, and wiring
capabilities in Xcode. None of this can be automated from a machine
without a full Xcode install and your own accounts/credentials.

## 0. Prerequisites

- **Apple Developer Program membership** (paid, $99/yr) — required for
  Sign in with Apple, HealthKit background delivery, and running on a
  real device. Free accounts cannot provision these capabilities.
- **Full Xcode** (not just Command Line Tools) from the Mac App Store.
- **A real iPhone**, ideally with a paired Apple Watch — HealthKit
  background delivery and real sleep/HRV data don't work meaningfully in
  Simulator (see [Known limitations](#known-limitations)).
- Homebrew tools:
  ```
  brew install supabase
  ```
  (`deno` is already installed on this machine and was used to type-check
  the Edge Functions during the build.)

## 1. Generate the Xcode project

**Use the pinned XcodeGen 2.42.0 binary at `.xcodegen-2.42.0/bin/xcodegen`,
not a `brew install xcodegen`.** Current XcodeGen (2.46+) writes a project
file format (`objectVersion 77`, targeting Xcode 16.3+) that Xcode 15.4
cannot open, and *hand-patching* that version number after the fact (which
was tried here first) corrupts the file in a different way -- the rest of
the file still has newer-format attributes, and Xcode crashes with an
uncaught `NSInvalidArgumentException` in `PBXProject
_formatForMissingPreferredProjectFormatAttribute` when it hits the
mismatch. 2.42.0 natively writes a fully self-consistent `objectVersion 54`
project, which is what avoids both problems.

```
cd "SOMA V1"
.xcodegen-2.42.0/bin/xcodegen generate
open Soma.xcodeproj
```

If you later update to a newer Xcode (16.3+, needs macOS 14.5+) and want
to move to current XcodeGen, delete `.xcodegen-2.42.0/` and go back to
`brew install xcodegen` -- there's no other reason to stay pinned to the
older version.

### 0.5. Point xcode-select at the full Xcode (not just Command Line Tools)

If `xcodebuild -version` errors with "requires Xcode, but active
developer directory is a command line tools instance", run:
```
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```
This only affects command-line tool invocations (`xcodebuild`, `swift`,
etc.) -- the Xcode GUI app works regardless.

In Xcode, select the `Soma` target → **Signing & Capabilities**:
1. Set your **Team** and enable **Automatically manage signing**.
2. Click **+ Capability** and add: **HealthKit** (also check **Background
   Delivery** in its settings), **Background Modes** (check **Background
   fetch** and **Background processing**), and **Sign in with Apple**.
   This syncs your App ID on the Developer portal — `Soma.entitlements`
   and `Info.plist` already have the corresponding keys checked in.

## 2. Supabase project

```
supabase login
supabase projects create soma        # or use an existing project
supabase link --project-ref <your-project-ref>
supabase db push                     # runs supabase/migrations/*.sql
```

Deploy the two Edge Functions:
```
supabase functions deploy generate-recommendation
supabase functions deploy store-wearable-token
```

Set the secrets they need (Whoop/Oura client IDs+secrets — see steps 3–4
below for where these come from):
```
supabase secrets set \
  WHOOP_CLIENT_ID=... WHOOP_CLIENT_SECRET=... \
  OURA_CLIENT_ID=... OURA_CLIENT_SECRET=...
```
(`SUPABASE_URL` / `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` are
injected automatically — no manual step.)

Grab your project's URL host and anon key (Project Settings → API) for
step 5.

## 3. Whoop developer app

1. Register an app at the Whoop developer portal.
2. Redirect URI: `soma://oauth-callback/whoop`
3. Copy the Client ID/Secret into `supabase secrets set` above.
4. **Verify the API paths in `supabase/functions/generate-recommendation/index.ts`
   and `Soma/Services/WhoopOAuthManager.swift` against the current Whoop
   docs before relying on them** — Whoop has changed API version prefixes
   before, and the exact `/recovery` path used here (`/developer/v1/recovery`)
   should be confirmed against your app's dashboard.

## 4. Oura developer app

1. Register an app at the Oura developer portal (cloud.ouraring.com).
2. Redirect URI: `soma://oauth-callback/oura`
3. Copy the Client ID/Secret into `supabase secrets set` above.
4. Confirm the `daily` scope still covers `/v2/usercollection/daily_readiness`
   at setup time.

## 5. Sign in with Apple (Supabase Auth side)

The app only uses **native** Sign in with Apple (`ASAuthorizationAppleIDProvider`
→ Supabase's `id_token` grant) -- there is no web or Android flow in V1.
For that path, Supabase does **not** need a Services ID, a `.p8` key, or a
signed client secret JWT. (An earlier draft of this doc said otherwise --
that was wrong. A Services ID is only needed if you later add web/Android
Sign in with Apple.)

1. Supabase Dashboard → **Authentication → Sign In / Providers → Apple**.
2. Toggle it **Enabled**.
3. **Client IDs** field: enter your app's bundle ID (`com.skollnitzer.soma`,
   or whatever you changed `PRODUCT_BUNDLE_IDENTIFIER` to in `project.yml`).
4. Save.

`supabase/config.toml`'s `[auth.external.apple]` block (with
`env(APPLE_CLIENT_ID)`/`env(APPLE_CLIENT_SECRET)`) is only relevant if you
manage auth config declaratively via the CLI instead of the Dashboard --
for a normal hosted project, the Dashboard steps above are the actual
source of truth and are all you need.

## 6. Fill in the iOS config

```
cp Config/Config.sample.xcconfig Config/Config-Debug.xcconfig
cp Config/Config.sample.xcconfig Config/Config-Release.xcconfig
```
Edit both with your real `SUPABASE_HOST` (bare host, no `https://` —
xcconfig treats `//` as a comment, see the file's own comment),
`SUPABASE_ANON_KEY`, `WHOOP_CLIENT_ID`, `OURA_CLIENT_ID`, `POSTHOG_API_KEY`
(step 6c below), `POSTHOG_HOST` (bare host, same `//` reason).

**Analytics only reports from Release builds** (TestFlight / App Store).
Local Debug runs from Xcode initialize neither Firebase nor PostHog and
send no events (`#if !DEBUG` in `AppDelegate` + `AnalyticsManager`) -- so
dev sessions never pollute the dashboards. To verify analytics locally
(e.g. Firebase DebugView), run the Release configuration: Edit Scheme →
Run → Info → Build Configuration → Release.

## 6b. Google Analytics for Firebase (GA4)

1. Place your downloaded `GoogleService-Info.plist` at
   `Soma/Resources/GoogleService-Info.plist` (same folder as `Info.plist`
   and `Soma.entitlements`). The existing `sources: - path: Soma` glob in
   `project.yml` picks up any file placed under `Soma/` automatically as a
   bundle resource -- no `project.yml` change needed for the file itself,
   just re-run `xcodegen generate` (or reopen the project) so Xcode's
   project index picks up the new file reference.
2. `xcodegen generate` also resolves the `Firebase` Swift Package
   dependency (`FirebaseAnalytics` + `FirebaseCore`, declared in
   `project.yml`'s `packages:` block) the first time you open/build the
   project -- this downloads the Firebase SDK, which can take a few
   minutes on a fresh checkout.
3. `FirebaseApp.configure()` runs once, at the very top of
   `AppDelegate.application(_:didFinishLaunchingWithOptions:)` -- before
   that line runs, the plist from step 1 must already be in place or the
   app crashes on launch with a "could not locate configuration file"
   error.
4. To verify events are reaching Firebase (DebugView), run the app with
   this launch argument (Xcode → Edit Scheme → Run → Arguments →
   Arguments Passed On Launch):
   ```
   -FIRAnalyticsDebugEnabled
   ```
   Then in the Firebase console: **Analytics → DebugView** and select
   your device. Events typically appear within a few seconds to a minute.

## 6c. PostHog

1. Grab your **Project API Key** from the PostHog dashboard (**Project
   Settings → Project API Key**) and set `POSTHOG_API_KEY` in both
   `Config-Debug.xcconfig`/`Config-Release.xcconfig` (step 6 above).
2. `POSTHOG_HOST` is pre-filled to `us.i.posthog.com` (US Cloud ingestion
   host). If your project is on **EU Cloud**, change it to
   `eu.i.posthog.com`; if self-hosted, use your instance's host instead.
   This is the *ingestion* host, not the dashboard URL (`app.posthog.com`/
   `eu.posthog.com`) -- they're different hostnames.
3. `xcodegen generate` resolves the `PostHog` Swift Package dependency the
   same way as Firebase's, above.
4. `PostHogSDK.shared.setup(...)` runs right after `FirebaseApp.configure()`
   in `AppDelegate`, reading the two config values from step 1-2 via
   `Config.swift`.
5. To verify events, PostHog dashboard → **Activity** (or your project's
   live events view) — events typically appear within a few seconds.
   PostHog doesn't have a separate "debug mode" flag like Firebase; if an
   event doesn't show up, first confirm `POSTHOG_API_KEY`/`POSTHOG_HOST`
   are real (not the placeholder values) and that the device has network
   access.

Both backends are driven from the same call: every method on
`Soma/Services/AnalyticsManager.swift` (`AnalyticsManager.shared.<method>()`)
fans out to Firebase Analytics **and** PostHog in one place. Never call
`Analytics.logEvent` or `PostHogSDK.shared.capture` directly elsewhere --
event names/parameter keys are defined exactly once, in `AnalyticsManager`.

## 7. Build and run

Build to a real device (Simulator can't exercise HealthKit sensor data or
background delivery meaningfully). On first launch:
1. Onboarding → **Get Started** → Sign in with Apple.
2. Connect Device → connect at least one provider → **Continue**.
3. Notification Enablement → allow notifications, set wake time →
   **Finish Setup**.
4. Home → tap **Check now** to manually invoke `generate-recommendation`
   and confirm a category + message renders.

## 8. Testing the morning triggers

- **Trigger A (wake-based)**: with a paired Watch, log a sleep session
  in the Health app (or let the Watch do it naturally) and confirm the
  observer fires and a notification arrives.
- **Trigger B (fallback)**: in Xcode, pause at a breakpoint after
  `BackgroundTaskManager.shared.register()` runs, then in the debugger
  console:
  ```
  e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.soma.app.refresh"]
  ```
  This forces the registered handler to run immediately without waiting
  for a real background window.

## 8b. Running the test suites

Two suites, split by where the logic lives. Both are fast and neither needs
network access, a device, or Supabase credentials.

**Swift — app-side pure logic** (`Tests/`):

```
xcodegen generate    # only if project.yml changed
xcodebuild test -project Soma.xcodeproj -scheme Soma \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Covers HealthKit metric aggregation (median sampling, sleep interval union)
and `DailyRecommendation` decoding, including rows written before
`data_confidence` existed. Anything that needs a live `HKHealthStore` is out
of scope -- HealthKit cannot be meaningfully faked in a unit test.

**Deno — Edge Function decision logic**:

```
deno test supabase/functions/
```

Covers the two deterministic decisions that most affect what a user sees:
`assessHealthKit` (which training band the day gets from Apple Health
signals) and `selectTemplate` (which gym-photo workout is chosen), plus
invariants over the template library itself.

### Conventions

Tests named `REGRESSION:` or `testX...` referencing a past failure exist
because that exact bug shipped. Read the comment before changing the
assertion -- several of them encode behaviour that looked wrong to a
previous reader and was not.

Tests named `INVARIANT:` guard properties the data must keep, not behaviour
of a single function. If one fails, the fix is usually in the data (a
template, the equipment vocabulary), not in the test.

## 9. TestFlight & App Store submission

### 9.1 App Store Connect setup (one-time)

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) →
   **Apps** → **+** → **New App**.
2. Platform: iOS. Name: "Soma" (or another name if taken -- app names
   must be unique on the Store). Primary language, bundle ID: pick
   `com.skollnitzer.soma` from the dropdown (it appears because it's
   already registered from Xcode's automatic signing), SKU: anything
   unique to you (e.g. `soma-v1`).
3. **App Information** tab: set the **Privacy Policy URL** to your
   hosted legal page (confirm it loads in a private/incognito browser
   window with no login prompt first -- Apple's reviewers need to open
   it with no account). Category: Health & Fitness.
4. **App Privacy** tab: fill out Apple's data-collection questionnaire.
   Based on what Soma actually collects: Health & Fitness data (linked to
   the user, used for App Functionality only, not for tracking), and an
   Identifier (the Apple user ID from Sign in with Apple, used for App
   Functionality). Answer "No" to using data for tracking/advertising --
   this matches the Privacy Policy's actual claims, so keep them
   consistent.
5. **Pricing and Availability**: set your price tier (or free) and
   territories.

### 9.2 Archive and upload a build

In Xcode, with a real device or "Any iOS Device" selected as the run
destination (archiving requires a device destination, not Simulator):
1. Set your version/build number: target **General** tab, or
   `project.yml`'s `settings.base` (`MARKETING_VERSION` /
   `CURRENT_PROJECT_VERSION`) if you want it tracked in source control.
2. **Product → Archive**. Once it finishes, the Organizer window opens
   automatically.
3. Select the archive → **Distribute App** → **App Store Connect** →
   **Upload**. Keep the default signing options (automatic signing,
   already configured). This uploads the build; it does not submit it
   for review yet.
4. Processing takes anywhere from a few minutes to ~1 hour. You'll get
   an email, and the build will appear under App Store Connect → your
   app → **TestFlight** tab once ready.

### 9.3 TestFlight

- **Internal testing**: add up to 100 testers who are Users with Access
  on your App Store Connect team (App Store Connect → Users and Access).
  No review required -- available within minutes of the build
  processing.
- **External testing**: add testers by email (up to 10,000) or a public
  link. External builds require **Beta App Review** the first time (a
  lighter version of full App Review, usually ~24-48h). You'll need to
  fill in "What to Test" notes.
- Testers install via the **TestFlight** app (from the App Store),
  redeem the invite or link, and install Soma through it.

### 9.4 Submitting for full App Store review

Once you're ready to go live (not just TestFlight):
1. App Store Connect → your app → **+ Version** (e.g. 1.0).
2. Fill in: screenshots (required sizes depend on which device families
   you support -- at minimum 6.7" and 6.5" iPhone screenshots), promotional
   text, description, keywords, support URL, marketing URL (optional).
3. **Age Rating** questionnaire -- answer honestly; a health/fitness app
   with no objectionable content is typically rated 4+.
4. Select the build you uploaded in 9.2 under **Build**.
5. **Submit for Review**. Typical review time is 24-48h, sometimes
   longer. Apple will reject the build if:
   - The Privacy Policy URL doesn't load, or doesn't match what's
     declared in the App Privacy questionnaire.
   - HealthKit usage isn't clearly explained (the `NSHealthShareUsageDescription`
     string already in `Info.plist` covers this, but reviewers do check
     it reads clearly).
   - Sign in with Apple isn't offered as an equally prominent option
     when other third-party logins exist -- not an issue here since Apple
     is the only account sign-in method.

## Decisions worth knowing about

- **Supabase Cron is intentionally not used.** Local notifications (no
  APNs in V1) can only be delivered from the device itself, so a
  server-side cron job has no way to actually notify the user — it could
  only pre-compute a `daily_recommendation` row ahead of time. The
  on-device `BGAppRefreshTask` fallback already calls
  `generate-recommendation` for every user regardless of which
  provider(s) they connected, so cron would add backend surface for
  marginal benefit. If you want faster "Check now" responses later, a
  nightly cron restricted to Whoop/Oura users would be the place to add
  it — not required for V1 correctness.
- **OAuth token exchange happens server-side**, not on-device, even
  though the app never displays raw tokens. Whoop/Oura's authorization
  code grant requires a `client_secret`, which must never ship inside an
  iOS binary.

## Known limitations

- Simulator has no real HealthKit sensor data and does not deliver
  background HealthKit updates — Trigger A needs a real device with a
  paired Watch to test meaningfully.
- `BGAppRefreshTask` timing is best-effort; iOS decides the actual fire
  time based on usage patterns and battery. This is expected, not a bug.
- HealthKit's authorization API never reports back which individual read
  types were granted vs. denied. "Connected" on Screen 2 means "the
  permission sheet was completed," not "every type was granted."
