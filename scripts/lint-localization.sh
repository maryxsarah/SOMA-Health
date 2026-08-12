#!/usr/bin/env bash
# Runs the two localization-coverage SwiftLint custom rules (.swiftlint.yml,
# see its own header comment for what each catches and why).
#
#   scripts/lint-localization.sh            changed files only (default) --
#                                            diffed against origin/main,
#                                            falls back to the working tree
#                                            if origin/main isn't available
#   scripts/lint-localization.sh --all       whole repo, both rules
#                                            (raw_localizable_literal is
#                                            noisy here by design -- ~247
#                                            pre-existing hits as of
#                                            2026-08-12, all already
#                                            correctly localized; use this
#                                            for a manual sweep, not CI)
#   scripts/lint-localization.sh --returns   raw_string_return only, whole
#                                            repo (low-noise, safe to run
#                                            untargeted or wire into CI)
set -euo pipefail
cd "$(dirname "$0")/.."

command -v swiftlint >/dev/null || { echo "swiftlint not found -- brew install swiftlint" >&2; exit 1; }

run_rule() {
  local rule="$1"; shift
  swiftlint lint --config .swiftlint.yml --quiet "$@" 2>&1 | grep "($rule)" || true
}

case "${1:-}" in
  --all)
    swiftlint lint --config .swiftlint.yml --quiet Soma
    ;;
  --returns)
    run_rule raw_string_return Soma
    ;;
  *)
    base="origin/main"
    git fetch --quiet origin main 2>/dev/null || true
    if ! git rev-parse --verify --quiet "$base" >/dev/null; then
      echo "origin/main not available -- diffing against the working tree instead" >&2
      base="HEAD"
    fi
    mapfile -t files < <(git diff --name-only --diff-filter=ACM "$base" -- '*.swift')
    if [ ${#files[@]} -eq 0 ]; then
      echo "No changed Swift files vs $base."
      exit 0
    fi
    swiftlint lint --config .swiftlint.yml --quiet "${files[@]}"
    ;;
esac
