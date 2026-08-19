# Universal links: signup-confirmation and password-reset deep links

The app owns two universal links today, both under the same
`www.soma4health.com` Associated Domain and the same mechanism: the
"Commit now to your goal" button in
`supabase/email-templates/confirm-signup.html` lands on
`https://www.soma4health.com/auth/confirm`, and the "Reset password" button
in `supabase/email-templates/reset-password.html` lands on
`https://www.soma4health.com/auth/reset-password`. Either path opens
directly in the app (instead of Safari) if the app is installed, and falls
through to Safari normally if it isn't — the honest "no dead custom-scheme
link" behavior a `soma://` link can't give you (tapping a custom-scheme
link with the app absent just does nothing, silently).

**www, not bare `soma4health.com`** — confirmed 2026-08-10 that the bare
domain 308-redirects to `www` site-wide (normal canonicalization), and
Apple's `swcd` does NOT follow redirects when fetching the AASA file below.
Every value in this repo (entitlement, Config, onOpenURL check, Supabase
redirect allow-list) has been pointed at `www` accordingly. If this ever
changes site-side (e.g. canonicalizing the other way, to bare), all of
those need to move together.

## What's already done (in this repo)

- `Soma/Resources/Soma.entitlements` — `com.apple.developer.associated-domains`
  = `applinks:www.soma4health.com` (domain-level, covers both paths below --
  no entitlement change needed when a new path is added under the same
  domain).
- `Soma/App/Config.swift` — `emailConfirmationRedirectURL` and
  `passwordResetRedirectURL`.
- `Soma/App/SomaApp.swift` — `onOpenURL` recognizes both host+path
  combinations. `/auth/confirm` routes to `handleEmailConfirmation`, which
  establishes the session from the redirect's token fragment and advances
  the same way Sign in with Apple/Google does (`appState.markSignedIn()` →
  the survey step). `/auth/reset-password` routes to
  `handlePasswordRecovery`, which establishes a recovery session and
  presents `SetNewPasswordView` as a root `.fullScreenCover` — it does NOT
  touch `appState.screen`, since (unlike confirm-signup) this link can be
  tapped by a user who's already mid-session elsewhere in the app.
- `Soma/Services/SupabaseClient.swift` — `signUpWithEmail` passes
  `redirect_to=https://www.soma4health.com/auth/confirm`, and
  `completeEmailConfirmation(fragment:)` does the actual token/session
  work. `requestPasswordReset(email:)` passes
  `redirect_to=https://www.soma4health.com/auth/reset-password`, and
  `completePasswordRecovery(fragment:)` is its counterpart.
- This file (`apple-app-site-association`, no extension) — the exact bytes
  to host, `paths` now listing both `/auth/confirm` and
  `/auth/reset-password`.

## What only you can do (hosting + dashboard)

1. **Host this exact file** at `https://www.soma4health.com/.well-known/apple-app-site-association` --
   **done for `/auth/confirm`** (2026-08-10, via
   `public/.well-known/apple-app-site-association` in the
   `SOMA-Landing-Page-2026` repo, deployed on Vercel). **Still needed:**
   re-deploy that same file with `/auth/reset-password` added to `paths`
   (copy this repo's updated copy over) so the new path validates too.
   Confirmed live for the original path:
   `curl -sI https://www.soma4health.com/.well-known/apple-app-site-association`
   returns `200`, `content-type: application/octet-stream` (fine -- Apple
   accepts this, doesn't require `application/json`) -- re-run this check
   after redeploying to confirm the body now matches this file's contents
   exactly, including the new path.
   - Only hosted at `www` -- the bare domain still 308-redirects there,
     which is fine, since the entitlement/Config/onOpenURL all target
     `www` now too. Don't "fix" the bare-domain redirect to serve the file
     directly unless you also move every other reference back to bare.

2. **Add the same URL to Supabase's redirect allow-list**: Dashboard →
   Authentication → URL Configuration → Redirect URLs → add
   `https://www.soma4health.com/auth/confirm` -- **done** (2026-08-10).
   **Still needed:** also add
   `https://www.soma4health.com/auth/reset-password` to the same allow-list,
   and paste `supabase/email-templates/reset-password.html` into
   Authentication → Email Templates → **Reset Password** (see that
   directory's own README).

3. **Verify the association**, any time you want to double check it's still live:
   ```
   curl -s https://www.soma4health.com/.well-known/apple-app-site-association | python3 -m json.tool
   ```
   should print back exactly this file's contents (both paths). You can
   also check Apple's own validator:
   https://search.developer.apple.com/appsearch-validation-tool/

4. **A fresh install/reinstall is needed** to see it take effect on a test
   device -- iOS fetches and caches `apple-app-site-association` at install
   time (and periodically after), not on every launch. Any build installed
   before the file went live (or before the entitlement pointed at `www`)
   needs to be deleted and reinstalled, not just relaunched. This applies
   again once the `/auth/reset-password` path is added to the hosted file.

## Testing without a real email

You don't need a live SMTP provider to test the deep link mechanics
themselves. Open this on the test device (Notes app, Messages to yourself,
anywhere tappable — NOT Safari's address bar, which never triggers
universal-link handoff):

```
https://www.soma4health.com/auth/confirm#access_token=x&refresh_token=x&expires_in=3600&token_type=bearer&type=signup
```

Tapping it should open Soma directly. It won't complete sign-in (`x` isn't
a real Supabase JWT, so `completeEmailConfirmation` will fail to decode it
and `sessionManager.errorMessage` will show) — this only proves iOS is
routing the link to the app instead of Safari, which is the part that
depends on your hosting, not on Supabase. The full round trip (real
token → real session → landing on the survey step) needs an actual signup.

Same idea for the reset-password path, once `/auth/reset-password` is on
the hosted apple-app-site-association file:

```
https://www.soma4health.com/auth/reset-password#access_token=x&refresh_token=x&expires_in=3600&token_type=bearer&type=recovery
```

Tapping it should open Soma directly and, once the link mechanics work,
should present Set New Password (`completePasswordRecovery` will still
fail to decode the fake `x` token here too — same caveat as above). The
full round trip needs an actual password-reset request.
