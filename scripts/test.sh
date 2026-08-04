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
# One xcodebuild invocation per journey, with one retry. Running all 14 in
# a single invocation reliably crashes the simulator's SpringBoard on a
# 16 GB host (the app then gets SIGKILLed and auto-relaunched WITHOUT the
# fixture launch args) -- every journey passes in isolation.
UI_TESTS=(
  test_SGP_A4_betaToggleOpensCatalog
  test_SGP_B1_createJumpGoal
  test_SGP_B4_createCoachTask
  test_SGP_C3_restDayRequestAndUndo
  test_SGP_D1_completeWorkoutCountsSession
  test_SGP_D2_missedSessionsSlideEta
  test_SGP_D4_restDayDefersRetest
  test_SGP_D5_retestOpenOnModerateDay
  test_SGP_D6_withinNoiseReadsNoChange
  test_SGP_D7_confirmBaselineOnDay5
  test_SGP_E1_pauseAndResume
  test_SGP_E5_finalRetestAchievedOffersNextBlock
  test_SGP_E5_finalRetestMissedStaysNeutral
  test_SGP_E7_endGoalOffersPauseInsteadFirst
  test_SGP_E8_coachTaskHubCountsSessionsAndExports
)

run_ui() {
  xcodebuild build-for-testing -project Soma.xcodeproj -scheme SomaUITests \
    -destination "$DEST" -quiet
  local failed=()
  local log
  log=$(mktemp -d)
  # No `| grep -q` on the live pipe: grep exiting at first match SIGPIPEs
  # xcodebuild mid-run and (with pipefail) randomly marks passing tests
  # failed. xcodebuild's own exit code is the verdict.
  run_one() {
    xcodebuild test-without-building -project Soma.xcodeproj \
      -scheme SomaUITests -destination "$DEST" -testPlan SomaUITests \
      -only-testing:"SomaUITests/SportGoalJourneyTests/$1" \
      > "$log/$1.log" 2>&1
  }
  for t in "${UI_TESTS[@]}"; do
    if ! run_one "$t"; then
      echo "retrying $t..."
      run_one "$t" || failed+=("$t")
    fi
    echo "done: $t"
  done
  if [ ${#failed[@]} -gt 0 ]; then
    printf 'FAILED: %s\n' "${failed[@]}"
    echo "logs: $log"
    return 1
  fi
  echo "UI: all ${#UI_TESTS[@]} journeys passed"
}
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
