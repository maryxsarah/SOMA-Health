# CLAUDE.md

Instructions for any Claude Code / agent session working in this repo.
This file accumulates process rules as the project matures — see each
section for the doc it's grounded in.

## Migration & Deploy Approval Gate

Before doing any of the following, **stop and get explicit user go-ahead —
do not proceed autonomously**, even if the fix seems obvious or the user's
request implies it should just be done:

- Applying a Supabase migration (`supabase db push`, or hand-applying SQL
  via the Dashboard).
- Repairing or resetting the migration ledger (`supabase migration
  repair`, `supabase db reset` against the linked project).
- Redeploying an edge function (`supabase functions deploy`).

Present all three of the following before asking for the go-ahead:

1. **Risk classification** — additive/reversible or destructive/
   irreversible, per the classification in
   [docs/deployment-runbook.md](docs/deployment-runbook.md#1-migration-risk-classification).
2. **Rollback plan** — the down-migration or the "how we'd recover" note,
   per [docs/deployment-runbook.md](docs/deployment-runbook.md#2-rollback-plan).
3. **Production scope** — this repo has one linked Supabase project, no
   staging; state application method (`db push` vs. hand-applied) and, for
   any ledger repair, confirm local (`ls supabase/migrations/`) and remote
   (`supabase migration list --linked`) actually agree first, per
   [docs/deployment-runbook.md](docs/deployment-runbook.md#3-production-scope-statement).

For edge functions, also run the diff-against-live step in
[docs/deployment-runbook.md](docs/deployment-runbook.md#4-edge-function-redeploys-must-diff-against-whats-live)
(`supabase functions download <name>` and diff) before presenting the
go-ahead request — "here's what's live vs. what I'm about to push" is part
of the scope statement, not optional context.

This gate exists because this repo has already had a production incident
from skipping it: commit `73d7e05` shipped two migrations whose ledger
entries collided with unrelated ones, silently leaving `users.known_lifts`
and `daily_mood` missing from the remote schema while the ledger reported
them applied. See docs/deployment-runbook.md for the full account.

## Plans Require Acceptance Checks

Every plan for work touching more than one file, or any backend/migration
change, must include an **Acceptance Checks** block before implementation
starts — use [docs/plan-template.md](docs/plan-template.md). The block
uses a fixed vocabulary ("Simulator verifies: ...", "Phone/TestFlight
verifies: ...", "Edge function deployed and checked against live state:
...", "No unresolved error remains without a follow-up commit or passing
test") and each item needs evidence (screenshot, test name, log line) to
be marked done — not "looks right." A change isn't complete until every
applicable check in the block is ticked with evidence, not when the diff
merely looks correct.

## Commit Message Convention

Every commit subject line must match `type(scope?): subject`, where `type`
is one of `feat fix refactor test docs chore perf build ci`. This is
enforced locally by a `commit-msg` git hook (`scripts/hooks/commit-msg`,
installed per clone via `scripts/install-hooks.sh` — see
[SETUP.md](SETUP.md#0b-git-commit-hooks-conventional-commits)), not just
documented — a commit with a non-conforming subject line will be rejected.
Write commit messages (including agent-authored ones) in this format from
the start rather than relying on the hook to catch it; merge/revert
commits are exempt. See `.gitmessage` for the full template and examples.

## Simplification Pass Before Marking Work Complete

Before marking any multi-file change complete, do a deliberate
simplification pass: look for dead code, duplicated logic, and any
function or file that grew past ~400-500 lines during this change. Either
clean it up in the same change, or log it in
[docs/oversized-files-backlog.md](docs/oversized-files-backlog.md) (with
line count, why it grew, and a proposed split) rather than letting it go
unrecorded. This is how that backlog stays current instead of drifting out
of sync with the codebase the way its seed numbers already had by the
time this doc was first written.
