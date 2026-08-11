# Email templates

Supabase Auth's email templates live in the Dashboard, not in this repo's
`supabase/` project config — there's no CLI/config.toml mechanism to manage
their HTML directly. These files are the source of truth in the sense that
matters (reviewable, diffable, checked in), and get pasted into the
Dashboard by hand. See the doc comment at the top of each template for the
exact paste-in location and which `{{ .Variable }}` values it depends on.

| File | Dashboard location | Depends on |
|---|---|---|
| `confirm-signup.html` | Authentication → Email Templates → Confirm signup | `Config.emailConfirmationRedirectURL` (client), `redirect_to` on `signUpWithEmail` (client) — see `deep-linking/README.md` |

If a template's copy changes here, re-paste it into the Dashboard —
editing this file alone does not update what Supabase actually sends.
