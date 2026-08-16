#!/usr/bin/env bash
#
# One-command git hook install for this clone.
#
#   1. Symlinks scripts/hooks/commit-msg into .git/hooks/commit-msg --
#      .git/hooks/ isn't tracked by git, so every clone needs this run once
#      before the Conventional Commits check actually enforces anything.
#   2. Points this clone's commit.template at .gitmessage, so `git commit`
#      (no -m) opens with the format reminder pre-loaded.
#
# Usage:
#   scripts/install-hooks.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

HOOK_SRC="scripts/hooks/commit-msg"
HOOK_DST=".git/hooks/commit-msg"

if [[ ! -d ".git" ]]; then
    echo "error: no .git directory here -- run this from the repo root." >&2
    exit 1
fi

if [[ ! -f "$HOOK_SRC" ]]; then
    echo "error: $HOOK_SRC not found." >&2
    exit 1
fi

chmod +x "$HOOK_SRC"

mkdir -p ".git/hooks"
if [[ -e "$HOOK_DST" && ! -L "$HOOK_DST" ]]; then
    echo "error: $HOOK_DST already exists and isn't a symlink -- remove it manually" >&2
    echo "       if you want scripts/install-hooks.sh to manage it, then re-run." >&2
    exit 1
fi
ln -sf "../../$HOOK_SRC" "$HOOK_DST"
echo "==> Installed commit-msg hook: $HOOK_DST -> $HOOK_SRC"

git config commit.template ".gitmessage"
echo "==> Set commit.template = .gitmessage for this clone"

echo ""
echo "Done. Commits with a subject line that doesn't match"
echo "'type(scope?): subject' (feat|fix|refactor|test|docs|chore|perf|build|ci)"
echo "will now be rejected. Bypass for one commit: git commit --no-verify"
