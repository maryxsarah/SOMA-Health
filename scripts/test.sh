#!/usr/bin/env bash
# One entry point for every test layer (see UITests/CASES.md).
#
#   scripts/test.sh unit                fast logic tests (SomaTests)
#   scripts/test.sh snapshot            screen-state snapshots (SomaSnapshotTests)
#   scripts/test.sh snapshot --record   re-record reference PNGs (after intended UI changes)
#   scripts/test.sh ui                  XCUITest journeys (SomaUITests, stubbed network)
#   scripts/test.sh deno                server decision logic (supabase/functions)
#   scripts/test.sh all                 everything, fast layers first
set -euo pipefail
cd "$(dirname "$0")/.."

# Snapshots are pinned to this simulator; keep the same destination for all
# layers so there is exactly one simulator to boot and reason about.
DEST='platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'

xcb() {
  local scheme="$1"; shift
  xcodebuild test -project Soma.xcodeproj -scheme "$scheme" -destination "$DEST" "$@"
}

run_unit()     { xcb Soma; }
run_snapshot() {
  local record_env=()
  [[ "${1:-}" == "--record" ]] && record_env=(TEST_RUNNER_SNAPSHOT_RECORD=1)
  env "${record_env[@]}" xcodebuild test -project Soma.xcodeproj \
    -scheme SomaSnapshotTests -destination "$DEST"
}
run_ui()       { xcb SomaUITests; }
# --no-check: the functions reference npm:@types/node, which isn't installed
# locally; runtime behavior is what these tests pin, and CI-less type safety
# comes from `deno check` when the env is set up (see SETUP.md).
run_deno()     { (cd supabase/functions && deno test --allow-read --no-check); }

case "${1:-all}" in
  unit)     run_unit ;;
  snapshot) run_snapshot "${2:-}" ;;
  ui)       run_ui ;;
  deno)     run_deno ;;
  all)      run_deno; run_unit; run_snapshot; run_ui ;;
  *) echo "usage: scripts/test.sh [unit|snapshot [--record]|ui|deno|all]" >&2; exit 64 ;;
esac
