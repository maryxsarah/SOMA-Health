# Sport goal programs — user case registry

User-facing cases for the sport goal programs beta and where each one is
covered. This file is version-controlled (unlike `docs/`) so it changes in
the same commit as the tests that cover it. Spec: `docs/features/
sport-skill-programs.md`; failure modes seeded from BUG-71…BUG-80.

## Layers & how to run

| Layer | What it covers | Run |
|---|---|---|
| `snapshot` | One screen state rendered against a reference PNG (SomaSnapshotTests, pinned to **iPhone 17 Pro / iOS 26.5**). Reference PNGs are machine-local (git-ignored) — on a fresh checkout run `scripts/test.sh snapshot --record` once, eyeball the PNGs, then `scripts/test.sh snapshot` guards against regressions | `scripts/test.sh snapshot` |
| `uitest` | A cross-screen journey via XCUITest + stubbed network (SomaUITests, launch arg `--ui-test-fixtures`, scenario via `UITEST_SCENARIO` env) | `scripts/test.sh ui` |
| `unit` | Pure logic in SomaTests | `scripts/test.sh unit` |
| `deno` | Server decision logic (`supabase/functions/**/*_test.ts`) | `scripts/test.sh deno` |
| `manual` | Needs a live backend / SQL / App Store build — checklist only, run before flipping a sport to `beta` |

Statuses: `automated` (test exists and passes) · `planned` (agreed, not yet
written) · `covered` (already covered by a pre-existing test) · `manual`.

Case IDs are referenced from test names, e.g. `test_SGP_D2_etaSlipLine`.

---

## A. Discovery / enable

| ID | Type | Case | Layer | Status |
|---|---|---|---|---|
| SGP-A1 | state | Catalog dark (empty `sports` fetch): no promo card on Home, goal flow shows the calm "Goals aren't available right now" card — never an error | snapshot | automated |
| SGP-A2 | negative | Catalog fetch **failed** (network error ≠ dark): same card but "Couldn't load the goal catalog. Pull down to try again." | snapshot | automated |
| SGP-A3 | journey | As an internal tester I'm inserted into `internal_testers` and the catalog appears without an app update | manual (SETUP.md §10) + deno (RLS visibility gate in `create-goal`/`generate-workout-plan`) | covered |
| SGP-A4 | journey | Sport at `status='beta'` + Profile → Account → "Sport goals (beta)" toggle ON → catalog appears; OFF → disappears (unless a goal already exists) | uitest **J14** (stub models the RLS gate) + manual against the real backend | automated / manual |
| SGP-A5 | state | First tap on the Home promo card shows the 4-slide beta onboarding popup; "Skip — I'll find it later" closes it; next tap goes straight to the sport list | uitest (inside J1) | automated |
| SGP-A6 | negative | Catalog ships dark: seed leaves all 4 sports `internal` | deno (`sportGoalSeed_test.ts`) | covered |
| SGP-A7 | negative | Emergency kill: `Config.enableSportGoals = false` hides every entry point even with a visible catalog | manual (compile-time) | manual |

## B. Goal creation

| ID | Type | Case | Layer | Status |
|---|---|---|---|---|
| SGP-B1 | journey | **"I want to raise my vertical jump":** Home promo → onboarding popup → Volleyball → Standing vertical jump → measurement protocol shown → baseline via ruler → live target reveal ("+3–6 cm in 10–12 weeks · re-test around …") → "Start the block" → Home shows the goal row | uitest **J1** | automated |
| SGP-B2 | state | Milestone goal (Crow pose): stage chips instead of ruler, target = next rung of the ladder, no invented numbers | snapshot | automated |
| SGP-B3 | state | Baseline outside every evidence band: "Baseline recorded" card, promises nothing | snapshot | automated |
| SGP-B4 | journey | Custom coach goal: form requires the workout text, creation lands on the coach-task hub ("COACH ALEX", 0 of 16 sessions) | uitest **J7** + snapshot | automated |
| SGP-B5 | negative | Second active goal → HTTP 409 → "You already have an active goal…" error shown, nothing created | manual + deno (partial unique index; create-goal) | covered |
| SGP-B6 | negative | Goal created but baseline insert failed → button retries **only** the baseline (no duplicate goal; BUG-78) | unit (`GoalCreationFlowTests`) | automated |
| SGP-B7 | state | Safety conflict at create (e.g. pregnancy × unsafe goal keywords): warning card requires explicit acknowledgment | snapshot + deno (`goalConflicts_test.ts`) | automated |

## C. Daily training

| ID | Type | Case | Layer | Status |
|---|---|---|---|---|
| SGP-C1 | journey | Plan carries a goal block: first block gets the "<GOAL> · GOAL BLOCK" eyebrow — and only when the plan's `goal_block` marker is real (BUG-77) | uitest **J2** + unit (`SportGoalsDecodingTests` marker tests) | automated |
| SGP-C2 | behavior | Readiness scales the block: moderate/push → phase concept; light degrades toward mobility, never up; rest → optional 5-min mobility or nothing | deno (`goalWork_test.ts`) | covered |
| SGP-C3 | journey | "Not feeling it today?" → Rest day: request persists and is undoable in place; server side (block degrades, custom day-shifts) in deno | uitest **J5** (client) + deno (server) | automated |
| SGP-C4 | behavior | Dose caps & spacing: ≤60 plyo contacts, hangs never on consecutive days, ≤3 padel wall sessions/wk | deno | covered |
| SGP-C5 | behavior | Custom coach text emitted byte-identical, "Built with Coach X" | deno | covered |
| SGP-C6 | behavior | Goal exercises union into the vocabulary **before** equipment/level/exclusion filters (BUG-73) | deno | covered |

## D. Progress & re-test

| ID | Type | Case | Layer | Status |
|---|---|---|---|---|
| SGP-D1 | journey | **"I close workouts and my progress counts":** goal-block day + "Complete workout" → hub sessions/ETA reflect it; unrelated workouts never count (BUG-75) | uitest **J2** + deno (`deriveEtaInputs`) | automated |
| SGP-D2 | journey | **"I skipped workouts — what happens":** week 4, 2 missed sessions + 3 low-readiness days → hub shows neutral "Moved +9 days — …", goal is NOT failed | uitest **J3** + snapshot + deno (ETA-slip suite) | automated |
| SGP-D3 | state | Re-test ladder locked between events: "Re-test opens in N weeks/days" row | snapshot | automated |
| SGP-D4 | state | Rest/light day closes the re-test window: "Not today — recovery is low." | snapshot | automated |
| SGP-D5 | journey | **Re-test open (day 28+, moderate day):** up to 3 attempts, best counts, result card in place | uitest **J4** | automated |
| SGP-D6 | journey | |delta| ≤ noise band → "No change yet — normal at this stage." — honest, not dressed up as progress | uitest **J9** + snapshot | automated |
| SGP-D7 | journey | Day-5 baseline confirm: "Confirm your baseline" → save → "official starting point"; week-1 hub shows the "second attempts usually score higher" line | uitest **J8** + snapshot | automated |
| SGP-D8 | state | Progress chart: 0 points ("your baseline starts the chart"), 1 point, trend | snapshot | automated |

## E. Lifecycle edges

| ID | Type | Case | Layer | Status |
|---|---|---|---|---|
| SGP-E1 | journey | Pause → calm "On hold — not counting. Resume anytime." → Resume restores the active goal in place | uitest **J13** + snapshot | automated |
| SGP-E2 | state | Safety auto-pause: "Safely paused" + "Switch to a safe goal"; never alarm-red | snapshot + deno (`decideSafetyPause`) | automated |
| SGP-E3 | state | Resume after >28 measurement-free days: "Your starting point moved — we'll re-measure first." re-baseline notice | snapshot | automated |
| SGP-E4 | state | Sport went dark mid-goal: "Temporarily unavailable" banner, data readable, re-tests stop | snapshot | automated |
| SGP-E5 | journey | Final re-test, both endings: achieved → earned celebration + "Next block"; missed → neutral + "Extend the block", never fake praise | uitest **J11/J12** + snapshot ×2 | automated |
| SGP-E6 | journey | "Next block" from the achievement card pre-fills the fresh result — start screen opens with the target already revealed | uitest **J11** | automated |
| SGP-E7 | journey | "End this goal" always offers "Pause instead" first; "your measurements stay" — rows never deleted | uitest **J10** | automated |
| SGP-E8 | journey | Coach's task: sessions counted ("3 of 16"), coach export card after ≥1 session, fixed re-check date | uitest **J6** | automated |

---

## Journeys (SomaUITests)

All journeys launch the app with `--ui-test-fixtures` and a `UITEST_SCENARIO`
environment value. The stub (`UITestSupport.swift` in the app target, DEBUG
only) fakes the Supabase session and serves PostgREST/Edge-Function wire
JSON, so decoding runs for real. Referral bonus is faked far-future so the
Superwall paywall never gates the detail sheet.

| Journey | Scenario | Covers |
|---|---|---|
| J1 `test_SGP_B1_createJumpGoal` | `catalogOpen` | SGP-A5, SGP-B1 |
| J2 `test_SGP_D1_completeWorkoutCountsSession` | `activeGoalWeek2` | SGP-C1, SGP-D1 |
| J3 `test_SGP_D2_missedSessionsSlideEta` | `activeGoalWeek4Slipped` | SGP-D2 |
| J4 `test_SGP_D5_retestOpenOnModerateDay` | `activeGoalDay28` | SGP-D5 (progress card) |
| — `test_SGP_D4_restDayDefersRetest` | `activeGoalDay28Rest` | SGP-D4 |
| J5 `test_SGP_C3_restDayRequestAndUndo` | `activeGoalWeek2` | SGP-C3 client side |
| J6 `test_SGP_E8_coachTaskHubCountsSessionsAndExports` | `customGoalWeek2` | SGP-E8, session counting (+ snapshot of the export hub) |
| J7 `test_SGP_B4_createCoachTask` | `customCoachFlow` | SGP-B4 |
| J8 `test_SGP_D7_confirmBaselineOnDay5` | `activeGoalDay6` | SGP-D7 |
| J9 `test_SGP_D6_withinNoiseReadsNoChange` | `activeGoalDay28` | SGP-D6 |
| J10 `test_SGP_E7_endGoalOffersPauseInsteadFirst` | `activeGoalWeek2` | SGP-E7 |
| J11 `test_SGP_E5_finalRetestAchievedOffersNextBlock` | `activeGoalAtEta` | SGP-E5, SGP-E6 |
| J12 `test_SGP_E5_finalRetestMissedStaysNeutral` | `activeGoalAtEta` | SGP-E5 (neutral ending) |
| J13 `test_SGP_E1_pauseAndResume` | `activeGoalWeek4Slipped` | SGP-E1 |
| J14 `test_SGP_A4_betaToggleOpensCatalog` | `betaGate` | SGP-A4 (stubbed RLS gate) |

## Known non-coverage

- No live E2E until a sport flips to `beta` (decision 2026-08-04): contract
  drift between fixtures and the real PostgREST schema is caught only by
  the Deno seed tests + a manual TestFlight pass (SGP-A3/A4 checklist).
- Goal notifications and streaks are not part of the feature — nothing to
  test.
- `sport_goal_completions` Superwall mirror is analytics-only — verified by
  eyeballing PostHog/Superwall dashboards, not automated.
