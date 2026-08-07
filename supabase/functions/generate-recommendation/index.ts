// generate-recommendation
//
// Called either by the on-device morning trigger (HealthKit observer /
// BGAppRefreshTask) or manually via the Home screen's "Check now" button.
// Body: { date: "YYYY-MM-DD", healthkit?: { sleepHours, hrvMs, restingHr } }
//
// `date` is supplied by the client in the user's LOCAL calendar day, not
// derived from the server's UTC clock -- otherwise a user near a timezone
// boundary could get a recommendation dated "yesterday" or "tomorrow".
//
// This function does all of the following in one place (see SETUP.md /
// plan notes for why): refreshes stored Whoop/Oura tokens if expired,
// pulls today's recovery/readiness from whichever providers are
// connected, folds in an optional on-device HealthKit snapshot, applies
// the exact decision-engine rules from the spec, and upserts the result.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";
import { assessHealthKit } from "./healthkitBand.ts";
import { EXCEPTIONAL_OURA_READINESS, EXCEPTIONAL_WHOOP_RECOVERY } from "../_shared/readinessThresholds.ts";
import { type ExperienceLevel, VOLUME_LANDMARKS } from "../_shared/volumeLandmarks.ts";

const WHOOP_TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token";
// NOTE: verify these paths against the current Whoop developer dashboard
// at setup time -- Whoop has changed API generation prefixes before.
const WHOOP_RECOVERY_URL = "https://api.prod.whoop.com/developer/v1/recovery";
const WHOOP_CYCLE_URL = "https://api.prod.whoop.com/developer/v1/cycle";
const WHOOP_SLEEP_URL = "https://api.prod.whoop.com/developer/v1/activity/sleep";
const WHOOP_WORKOUT_URL = "https://api.prod.whoop.com/developer/v1/activity/workout";

const OURA_READINESS_URL =
  "https://api.ouraring.com/v2/usercollection/daily_readiness";
const OURA_SLEEP_URL = "https://api.ouraring.com/v2/usercollection/sleep";
const OURA_WORKOUT_URL = "https://api.ouraring.com/v2/usercollection/workout";
const OURA_STRESS_URL = "https://api.ouraring.com/v2/usercollection/daily_stress";

// Whoop's own strain scale is 0-21; 15+ is what Whoop classifies as
// "strenuous". Used as a "trained hard very recently" signal for the load
// cap below, not as a recovery metric.
const WHOOP_HIGH_STRAIN_THRESHOLD = 15;

import type { Band, DataConfidence, HealthKitPayload } from "./healthkitBand.ts";
type Category = "rest" | "light" | "moderate" | "push_hard";
type Source = "whoop" | "oura" | "healthkit";

const MESSAGES: Record<Category, string> = {
  push_hard:
    "You're well recovered — today's a good day to push. Go for a hard workout or high-intensity session.",
  moderate:
    "You're in decent shape today. A moderate cardio session or a solid strength workout (30-45 min) is a good call.",
  light:
    "Take it easier today — a short walk, mobility work, or light yoga (20-30 min) is ideal.",
  rest: "Today's a recovery day. Keep movement light and let your body rest — a gentle walk is plenty.",
};

interface WearableTokenRow {
  id: string;
  provider: "whoop" | "oura";
  access_token: string;
  refresh_token: string | null;
  expires_at: string | null;
}

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const date: string | undefined = body.date;
    const healthkit: HealthKitPayload | undefined = body.healthkit;

    if (!date) {
      return jsonResponse({ error: "missing 'date' (YYYY-MM-DD)" }, 400);
    }

    const supabase = serviceRoleClient();

    // A prior "request a rest/active-recovery day" call for this date, if
    // any -- read up front so it survives this run's upsert (explicitly
    // written back below) and wins outright over every computed cap, since
    // it's the user's own direct request, not a health signal to be
    // weighed against others. Set via set-recommendation-override.
    const { data: existingRec } = await supabase
      .from("daily_recommendation")
      .select("user_requested_category")
      .eq("user_id", userId)
      .eq("date", date)
      .maybeSingle();
    const userRequestedCategory = (existingRec?.user_requested_category as Category | null) ?? null;

    const { data: tokens } = await supabase
      .from("wearable_tokens")
      .select("id, provider, access_token, refresh_token, expires_at")
      .eq("user_id", userId);

    let whoopRecovery: { recoveryScore: number; hrvMs?: number; restingHr?: number } | null = null;
    let ouraReadiness: number | null = null;
    // True if either provider shows a strenuous session in roughly the
    // last day -- feeds the recent-training-load cap alongside the
    // existing sleep/injury caps.
    let recentHighStrain = false;

    const whoopToken = (tokens ?? []).find((t: WearableTokenRow) => t.provider === "whoop");
    if (whoopToken) {
      const [recovery, whoopSleep, whoopLoad] = await Promise.all([
        safely("whoop recovery", null, () => fetchWhoopRecovery(supabase, whoopToken, date)),
        safely("whoop sleep", EMPTY_SLEEP_STAGES, () => fetchWhoopSleepHours(supabase, whoopToken, date)),
        safely(
          "whoop training load",
          { strainScore: null, recentHighStrain: false },
          () => fetchWhoopTrainingLoad(supabase, whoopToken, date),
        ),
      ]);
      whoopRecovery = recovery;
      if (whoopLoad.recentHighStrain) recentHighStrain = true;
      if (recovery || whoopSleep.totalHours !== null || whoopLoad.strainScore !== null) {
        await upsertSnapshot(supabase, userId, date, "whoop", {
          recovery_score: recovery?.recoveryScore,
          hrv_ms: recovery?.hrvMs,
          resting_hr: recovery?.restingHr,
          sleep_hours: whoopSleep.totalHours ?? undefined,
          strain_score: whoopLoad.strainScore ?? undefined,
          sleep_light_hours: whoopSleep.lightHours ?? undefined,
          sleep_deep_hours: whoopSleep.deepHours ?? undefined,
          sleep_rem_hours: whoopSleep.remHours ?? undefined,
          sleep_awake_hours: whoopSleep.awakeHours ?? undefined,
        });
      }
    }

    const ouraToken = (tokens ?? []).find((t: WearableTokenRow) => t.provider === "oura");
    if (ouraToken) {
      const emptySleepData = {
        sleepHours: null,
        hrvMs: null,
        restingHr: null,
        lightHours: null,
        deepHours: null,
        remHours: null,
        awakeHours: null,
      };
      const [readiness, ouraSleep, ouraLoad, ouraStress] = await Promise.all([
        safely("oura readiness", null, () => fetchOuraReadiness(supabase, ouraToken, date)),
        safely("oura sleep", emptySleepData, () => fetchOuraSleepData(supabase, ouraToken, date)),
        safely(
          "oura training load",
          { strainScore: null, recentHighStrain: false },
          () => fetchOuraTrainingLoad(supabase, ouraToken, date),
        ),
        safely("oura stress", null, () => fetchOuraStress(supabase, ouraToken, date)),
      ]);
      ouraReadiness = readiness;
      if (ouraLoad.recentHighStrain) recentHighStrain = true;
      if (
        readiness !== null || ouraSleep.sleepHours !== null || ouraLoad.strainScore !== null ||
        ouraStress !== null
      ) {
        await upsertSnapshot(supabase, userId, date, "oura", {
          readiness_score: readiness ?? undefined,
          sleep_hours: ouraSleep.sleepHours ?? undefined,
          hrv_ms: ouraSleep.hrvMs ?? undefined,
          resting_hr: ouraSleep.restingHr ?? undefined,
          strain_score: ouraLoad.strainScore ?? undefined,
          stress_score: ouraStress ?? undefined,
          sleep_light_hours: ouraSleep.lightHours ?? undefined,
          sleep_deep_hours: ouraSleep.deepHours ?? undefined,
          sleep_rem_hours: ouraSleep.remHours ?? undefined,
          sleep_awake_hours: ouraSleep.awakeHours ?? undefined,
        });
      }
    }

    if (healthkit) {
      await upsertSnapshot(supabase, userId, date, "healthkit", {
        sleep_hours: healthkit.sleepHours,
        hrv_ms: healthkit.hrvMs,
        resting_hr: healthkit.restingHr,
        sleep_light_hours: healthkit.sleepLightHours,
        sleep_deep_hours: healthkit.sleepDeepHours,
        sleep_rem_hours: healthkit.sleepRemHours,
        sleep_awake_hours: healthkit.sleepAwakeHours,
      });
    }

    // Sleep hours for the rest-vs-light split, plus HRV/stress for the caps
    // below -- prefer whichever connected source actually reported each
    // today, same merge shape as sleep already used.
    const { data: todaysRows } = await supabase
      .from("daily_snapshot")
      .select("source, sleep_hours, hrv_ms, stress_score")
      .eq("user_id", userId)
      .eq("date", date);

    const sleepHours = pickSleepHours(todaysRows ?? [], healthkit);
    const todaysHrv = pickTodaysMetric(todaysRows ?? [], "hrv_ms", healthkit?.hrvMs);
    // Oura-only signal (see fetchOuraStress) -- no Whoop/HealthKit source
    // reports one today, so this naturally resolves to null for them.
    const todaysStress = pickTodaysMetric(todaysRows ?? [], "stress_score", undefined);

    // Injury-based intensity cap: any noted injury caps the category at
    // moderate max for the day, same safety-first pattern as the sleep cap.
    const { data: userRow } = await supabase
      .from("users")
      .select("injury_tags, pregnancy, experience_level")
      .eq("id", userId)
      .maybeSingle();
    const hasInjury = ((userRow?.injury_tags as string[] | null) ?? []).length > 0;
    const hasPregnancy = userRow?.pregnancy === true;
    const experienceLevel = ((userRow?.experience_level as ExperienceLevel | null) ?? "moderate");

    // Any moderate/severe-tier injury protocol currently active/recovering
    // -- a soft cap (product decision), not a hard block like pregnancy:
    // the day is forced down but generation still proceeds, with the
    // contraindication map's exclusions applied by generate-workout-plan.
    // Severity-scaled: severe forces the day all the way to "light" (same
    // as the consecutive-days cap); moderate is a LESSER cap that only
    // ever knocks push_hard down to moderate, never all the way to light
    // -- mild injuries never reach this query at all (report-injury never
    // creates a recovery-state row for mild severity in the first place).
    const { data: injuryProtocolRows } = await supabase
      .from("injury_recovery_state")
      .select("severity, status")
      .eq("user_id", userId)
      .in("status", ["active", "recovering"]);
    const hasSevereInjuryProtocol = (injuryProtocolRows ?? []).some(
      (r: { severity: string }) => r.severity === "severe",
    );
    const hasModerateInjuryProtocol = (injuryProtocolRows ?? []).some(
      (r: { severity: string }) => r.severity === "moderate",
    );

    let band: Band;
    let source: Source;
    let clearlyPoorRecovery = false;
    // Only the HealthKit path can be low-confidence. Whoop and Oura report a
    // single authoritative recovery/readiness number, so there is nothing to
    // be uncertain about; HealthKit is assembled from whatever the watch
    // happened to record.
    let dataConfidence: DataConfidence = "high";
    // True only for the HealthKit path with literally zero usable signals
    // today (typically day 1, before any baseline exists) -- distinct from
    // an ordinary low-confidence read, which still has at least one signal.
    let insufficientData = false;

    if (whoopRecovery) {
      band = bandFromWhoop(whoopRecovery.recoveryScore);
      source = "whoop";
      clearlyPoorRecovery = whoopRecovery.recoveryScore < 20;
    } else if (ouraReadiness !== null) {
      band = bandFromOura(ouraReadiness);
      source = "oura";
      clearlyPoorRecovery = ouraReadiness < 50;
    } else if (healthkit) {
      // Firm baselines first; if there is not enough history yet, fall back
      // to a provisional one built from as little as two days.
      //
      // Requiring 5 days outright had a nasty side effect: on days 2-5 both
      // baselines were null, so nothing but sleep could move the band AND
      // `clearlyPoorRecovery` was pinned false -- meaning a new user whose
      // HRV had collapsed to half its usual value was told "moderate". The
      // conservative rest override disappeared during precisely the window
      // in which someone decides whether to trust the app. A provisional
      // baseline restores the protective direction; assessHealthKit refuses
      // to award positive points from it, so thin data can only hold someone
      // back, never push them.
      const [hrvFirm, rhrFirm] = await Promise.all([
        fetchMetricBaseline(supabase, userId, date, "hrv_ms"),
        fetchMetricBaseline(supabase, userId, date, "resting_hr"),
      ]);
      let hrvBaseline = hrvFirm;
      let rhrBaseline = rhrFirm;
      let provisional = false;
      if (hrvBaseline === null && rhrBaseline === null) {
        const [hrvProv, rhrProv] = await Promise.all([
          fetchMetricBaseline(supabase, userId, date, "hrv_ms", PROVISIONAL_BASELINE_DAYS),
          fetchMetricBaseline(supabase, userId, date, "resting_hr", PROVISIONAL_BASELINE_DAYS),
        ]);
        hrvBaseline = hrvProv;
        rhrBaseline = rhrProv;
        provisional = hrvBaseline !== null || rhrBaseline !== null;
      }

      const assessment = assessHealthKit(healthkit, hrvBaseline, rhrBaseline, provisional);
      band = assessment.band;
      // A provisional baseline is exactly the "thin read" the caveat exists
      // for, regardless of how many signals were present.
      dataConfidence = provisional ? "low" : assessment.confidence;
      insufficientData = assessment.signalCount === 0;
      source = "healthkit";
      clearlyPoorRecovery = hrvBaseline !== null && healthkit.hrvMs != null
        ? healthkit.hrvMs < hrvBaseline * 0.6
        : false;
    } else {
      return jsonResponse(
        { error: "no data available for today from any source" },
        422,
      );
    }

    // Recorded from the pre-cap band -- this is the diagnostic "why"
    // (e.g. "whoop_high"), independent of whether the sleep cap then
    // downgraded the final category. Matches the check constraint on
    // daily_recommendation.reason. The zero-signal case gets its own honest
    // label instead of "healthkit_medium" -- category/message stay the same
    // cautious "moderate", only the presented reason differs.
    const reason = insufficientData ? "insufficient_data" : `${source}_${band}`;
    const { category: bandCategory, injuryCapApplied, loadCapApplied, pregnancyCapApplied } =
      mapBandToCategory(
        band,
        sleepHours,
        clearlyPoorRecovery,
        hasInjury,
        recentHighStrain,
        hasPregnancy,
      );

    // Sleep cap: same post-category mechanism as consecutive-days/injury-
    // protocol/volume below, rather than the old pre-category, high-band-
    // only, <5.5h-only check (which could never fire on a "moderate" day).
    // A short-sleep night is a real risk factor on its own, independent of
    // what the wearable's own recovery/readiness score says today. SOMA has
    // no ingested sleep-QUALITY score from any provider (Oura's own 0-100
    // Sleep Score is a separate endpoint SOMA doesn't call) -- this can
    // only ever react to raw duration, not how restful/fragmented that
    // sleep actually was. DRAFTED, NOT EXPERT-REVIEWED threshold.
    const SHORT_SLEEP_HOURS = 6.5;
    const sleepCapApplied = sleepHours !== null && sleepHours < SHORT_SLEEP_HOURS &&
      (bandCategory === "moderate" || bandCategory === "push_hard");

    // HRV cap: hrv_ms is stored in daily_snapshot per source but was never
    // read back for capping before today. HRV is highly individual, so
    // this compares against the user's OWN trailing baseline (same median-
    // of-trailing-window shape as fetchMetricBaseline, generalized to any
    // connected source rather than healthkit-only) rather than a fixed
    // absolute number. DRAFTED, NOT EXPERT-REVIEWED threshold.
    const HRV_DROP_RATIO = 0.85;
    const hrvBaselineForCap = await fetchGeneralMetricBaseline(supabase, userId, date, "hrv_ms");
    const hrvCapApplied = hrvBaselineForCap !== null && todaysHrv !== null &&
      todaysHrv < hrvBaselineForCap * HRV_DROP_RATIO &&
      (bandCategory === "moderate" || bandCategory === "push_hard");

    // Stress cap: stress_score (Oura-only -- minutes spent in a high-stress
    // state today, see fetchOuraStress) is stored but was never read back
    // for capping before today. Already a same-units-every-day absolute
    // number (minutes), unlike HRV, so a flat threshold is used instead of
    // a personal baseline. DRAFTED, NOT EXPERT-REVIEWED threshold.
    const HIGH_STRESS_MINUTES = 180;
    const stressCapApplied = todaysStress !== null && todaysStress >= HIGH_STRESS_MINUTES &&
      (bandCategory === "moderate" || bandCategory === "push_hard");

    // Consecutive-training-days cap: unlike the three caps above (which act
    // on the recovery band before the category is chosen), this acts on the
    // FINAL category -- deliberately a different mechanism, since it's about
    // breaking a streak regardless of how good today's recovery signals
    // look, not about discounting those signals themselves.
    // countConsecutiveTrainingDays already only counts moderate/push_hard
    // logged days (not light/rest), so the streak itself is already a real
    // accumulated-load signal, not a blind day-count. On top of that: an
    // EXCEPTIONAL readiness day (same bar generate-workout-plan uses for
    // its finisher) skips the cap entirely -- a body that's clearly
    // recovered exceptionally well doesn't need to be forced down just
    // because of the calendar. And a streak that goes well past the
    // threshold (REST_ESCALATION_THRESHOLD) lands on full "rest" instead
    // of "light" -- the accumulated load at that point calls for more than
    // active recovery.
    const consecutiveDays = await countConsecutiveTrainingDays(supabase, userId, date);
    const exceptionalReadinessToday =
      (whoopRecovery !== null && whoopRecovery.recoveryScore >= EXCEPTIONAL_WHOOP_RECOVERY) ||
      (ouraReadiness !== null && ouraReadiness >= EXCEPTIONAL_OURA_READINESS);
    const consecutiveDaysCapApplied = consecutiveDays >= CONSECUTIVE_DAYS_THRESHOLD &&
      !exceptionalReadinessToday &&
      (bandCategory === "moderate" || bandCategory === "push_hard");
    const consecutiveDaysRestEscalated = consecutiveDaysCapApplied &&
      consecutiveDays >= REST_ESCALATION_THRESHOLD;
    // Same post-processing-on-final-category mechanism as the consecutive-
    // days cap above, and independent of it -- catches a DIFFERENT pattern:
    // hard training on most days of a rolling week even with gaps breaking
    // any consecutive streak (e.g. hard-hard-hard-rest-hard-hard-hard is
    // only a 3-day streak but 6 of the last 7 days). Reuses
    // VOLUME_LANDMARKS.full_body's MRV (session-count-shaped, unlike the
    // sets/week landmarks for upper/lower body) as the threshold, since
    // workout_log only has session-level data, not per-set volume --
    // an honest proxy, not true per-muscle-group volume tracking.
    const recentTrainingDays = await countRecentTrainingDays(supabase, userId, date);
    const volumeCapApplied = recentTrainingDays >= VOLUME_LANDMARKS.full_body[experienceLevel].mrv &&
      !exceptionalReadinessToday &&
      (bandCategory === "moderate" || bandCategory === "push_hard");
    // Same post-processing-on-final-category mechanism as the consecutive-
    // days cap just above, and independent of it -- either or both can fire.
    const injuryProtocolCapApplied = hasSevereInjuryProtocol &&
      (bandCategory === "moderate" || bandCategory === "push_hard");
    // Moderate is a LESSER cap than severe (product decision) -- only ever
    // knocks push_hard down to moderate, never all the way to light.
    // Mutually exclusive with injuryProtocolCapApplied in practice (a tag
    // is either moderate or severe, never both at once for the same
    // injury), but written independently since a user could have one
    // moderate and one severe injury simultaneously -- severe wins.
    const injuryProtocolModerateCapApplied = !hasSevereInjuryProtocol &&
      hasModerateInjuryProtocol && bandCategory === "push_hard";
    const computedCategory: Category = consecutiveDaysRestEscalated
      ? "rest"
      : (consecutiveDaysCapApplied || injuryProtocolCapApplied || volumeCapApplied ||
          sleepCapApplied || hrvCapApplied || stressCapApplied)
      ? "light"
      : injuryProtocolModerateCapApplied
      ? "moderate"
      : bandCategory;
    // The user's own rest/active-recovery request wins outright over every
    // computed cap above -- see the comment where userRequestedCategory is
    // read, near the top of this handler.
    const category: Category = userRequestedCategory ?? computedCategory;
    const message = MESSAGES[category];

    await supabase
      .from("daily_recommendation")
      .upsert(
        {
          user_id: userId,
          date,
          category,
          message,
          reason,
          sleep_cap_applied: sleepCapApplied,
          injury_cap_applied: injuryCapApplied,
          load_cap_applied: loadCapApplied,
          pregnancy_cap_applied: pregnancyCapApplied,
          volume_cap_applied: volumeCapApplied,
          consecutive_days_cap_applied: consecutiveDaysCapApplied,
          injury_protocol_cap_applied: injuryProtocolCapApplied,
          injury_protocol_moderate_cap_applied: injuryProtocolModerateCapApplied,
          hrv_cap_applied: hrvCapApplied,
          stress_cap_applied: stressCapApplied,
          // The uncapped category, so a later client re-fetch (after any
          // cap has been applied) still has access to what the
          // recommendation would have been -- the override affordance in
          // RecommendationDetailView reads this to offer "a standard
          // workout anyway" without re-deriving the recovery band client-side.
          pre_cap_category: bandCategory,
          data_confidence: dataConfidence,
          // Written back explicitly (not just left alone) so this upsert
          // never silently clears an active rest-day request just because
          // this particular call site didn't set one.
          user_requested_category: userRequestedCategory,
        },
        { onConflict: "user_id,date" },
      );

    // snake_case in the response to match the PostgREST row shape returned
    // by HomeView's plain "fetch today's recommendation" read -- the app
    // uses one Codable model for both paths.
    return jsonResponse({
      date,
      category,
      message,
      reason,
      sleep_cap_applied: sleepCapApplied,
      injury_cap_applied: injuryCapApplied,
      load_cap_applied: loadCapApplied,
      pregnancy_cap_applied: pregnancyCapApplied,
      volume_cap_applied: volumeCapApplied,
      consecutive_days_cap_applied: consecutiveDaysCapApplied,
      injury_protocol_cap_applied: injuryProtocolCapApplied,
      injury_protocol_moderate_cap_applied: injuryProtocolModerateCapApplied,
      hrv_cap_applied: hrvCapApplied,
      stress_cap_applied: stressCapApplied,
      pre_cap_category: bandCategory,
      data_confidence: dataConfidence,
      user_requested_category: userRequestedCategory,
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

// -- Decision engine ------------------------------------------------------

function bandFromWhoop(recoveryScore: number): Band {
  if (recoveryScore >= 67) return "high";
  if (recoveryScore >= 34) return "medium";
  return "low";
}

function bandFromOura(readinessScore: number): Band {
  if (readinessScore >= 85) return "high";
  if (readinessScore >= 70) return "medium_high";
  if (readinessScore >= 60) return "medium";
  return "low";
}

function mapBandToCategory(
  band: Band,
  sleepHours: number | null,
  clearlyPoorRecovery: boolean,
  hasInjury: boolean,
  recentHighStrain: boolean,
  hasPregnancy: boolean,
): {
  category: Category;
  injuryCapApplied: boolean;
  loadCapApplied: boolean;
  pregnancyCapApplied: boolean;
} {
  let effectiveBand = band;
  let injuryCapApplied = false;
  let loadCapApplied = false;
  let pregnancyCapApplied = false;

  // Injury safety cap: never push_hard with an active injury noted.
  if (effectiveBand === "high" && hasInjury) {
    effectiveBand = "medium";
    injuryCapApplied = true;
  }

  // Recent training load cap: never push_hard the day right after a
  // strenuous Whoop workout or an Oura "hard"-intensity session, even if
  // this morning's recovery/readiness looks strong -- avoids stacking two
  // max-effort days back to back. Independent of the other cap.
  if (effectiveBand === "high" && recentHighStrain) {
    effectiveBand = "medium";
    loadCapApplied = true;
  }

  // Pregnancy safety cap: never push_hard while pregnant, regardless of
  // trimester -- same independent-cap shape as the others above. This
  // replaces the old hard block (see safetyFlags.ts): generation still
  // proceeds, just never at max intensity.
  if (effectiveBand === "high" && hasPregnancy) {
    effectiveBand = "medium";
    pregnancyCapApplied = true;
  }

  if (effectiveBand === "high") {
    return { category: "push_hard", injuryCapApplied, loadCapApplied, pregnancyCapApplied };
  }
  if (effectiveBand === "medium_high" || effectiveBand === "medium") {
    return { category: "moderate", injuryCapApplied, loadCapApplied, pregnancyCapApplied };
  }

  // effectiveBand === "low": split into light vs rest.
  const severelyShortSleep = sleepHours !== null && sleepHours < 5.5;
  const category = severelyShortSleep || clearlyPoorRecovery ? "rest" : "light";
  return { category, injuryCapApplied, loadCapApplied, pregnancyCapApplied };
}

/// Consecutive prior days with a logged TRAINING workout (moderate or
/// push_hard), strictly before `date`, stopping at the first gap -- e.g.
/// training logs on d-1, d-2, d-3 but not d-4 counts as 3, regardless of
/// what happened further back.
///
/// The category filter is what makes the cap releasable: counting every
/// workout_log row meant a dutifully-logged "Full rest day" or recovery
/// walk extended the streak, and -- worse -- each capped "light" day the
/// user then logged re-extended it again, so the cap never let go and a
/// well-recovered user never saw another moderate/push_hard day. Rest and
/// light days are the streak BREAKING, not the streak continuing; that is
/// the entire point of capping to light.
const CONSECUTIVE_DAYS_THRESHOLD = 5;
/// DRAFTED, NOT EXPERT-REVIEWED -- past this many consecutive hard-training
/// days, the accumulated load calls for more than active recovery: the day
/// lands on full "rest" instead of "light".
const REST_ESCALATION_THRESHOLD = 6;

async function countConsecutiveTrainingDays(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  date: string,
): Promise<number> {
  const { data } = await supabase
    .from("workout_log")
    .select("date")
    .eq("user_id", userId)
    .in("category", ["moderate", "push_hard"])
    .gte("date", addDays(date, -7))
    .lt("date", date);

  const loggedDates = new Set((data ?? []).map((r: { date: string }) => r.date));
  let count = 0;
  let cursor = addDays(date, -1);
  while (loggedDates.has(cursor)) {
    count++;
    cursor = addDays(cursor, -1);
  }
  return count;
}

/// Rolling count of moderate/push_hard training days in the trailing 7
/// days, gaps allowed -- distinct from countConsecutiveTrainingDays above
/// (which stops at the first gap). A user who trains hard 6 of the last 7
/// days with one rest day in the middle has a LOW consecutive-streak count
/// but a real accumulated-fatigue signal this rolling count catches
/// instead. Reuses the same query as countConsecutiveTrainingDays (same
/// window, same category filter) -- only the aggregation differs.
async function countRecentTrainingDays(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  date: string,
): Promise<number> {
  const { data } = await supabase
    .from("workout_log")
    .select("date")
    .eq("user_id", userId)
    .in("category", ["moderate", "push_hard"])
    .gte("date", addDays(date, -7))
    .lt("date", date);
  return new Set((data ?? []).map((r: { date: string }) => r.date)).size;
}

function pickSleepHours(
  rows: { source: string; sleep_hours: number | null }[],
  healthkit: HealthKitPayload | undefined,
): number | null {
  const bySource = (source: string) =>
    rows.find((r) => r.source === source)?.sleep_hours ?? null;
  return (
    bySource("whoop") ??
    bySource("oura") ??
    bySource("healthkit") ??
    healthkit?.sleepHours ??
    null
  );
}

/// Same merge shape as pickSleepHours, generalized to any daily_snapshot
/// numeric column -- used for today's HRV/stress cap inputs.
function pickTodaysMetric(
  rows: { source: string; hrv_ms?: number | null; stress_score?: number | null }[],
  column: "hrv_ms" | "stress_score",
  healthkitValue: number | null | undefined,
): number | null {
  const bySource = (source: string) => rows.find((r) => r.source === source)?.[column] ?? null;
  return (
    bySource("whoop") ??
    bySource("oura") ??
    bySource("healthkit") ??
    healthkitValue ??
    null
  );
}

/// Minimum distinct days of history before a baseline means anything.
/// Previously a single prior day was enough, which made the "baseline" just
/// that day -- so today's value was compared against itself and the ratio was
/// 1.0 by construction. Combined with the client submitting a stale value
/// every day, this locked users into a permanent "medium".
const MIN_BASELINE_DAYS = 5;
/// Floor for the provisional baseline described at the call site. Two days is
/// the minimum at which a comparison says anything at all -- one day would be
/// comparing today against itself, which is the bug this constant's larger
/// sibling was introduced to fix.
const PROVISIONAL_BASELINE_DAYS = 2;
const BASELINE_WINDOW_DAYS = 30;

/// Median, not mean, of the trailing window. A single artefact reading -- and
/// passive Apple Watch SDNN produces them -- drags a 30-point mean noticeably;
/// it barely moves the median.
async function fetchMetricBaseline(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  date: string,
  column: "hrv_ms" | "resting_hr",
  minDays: number = MIN_BASELINE_DAYS,
): Promise<number | null> {
  const end = new Date(date);
  const start = new Date(end);
  start.setDate(start.getDate() - BASELINE_WINDOW_DAYS);
  const startStr = start.toISOString().slice(0, 10);
  const endStr = new Date(end.getTime() - 86400000).toISOString().slice(0, 10);

  const { data } = await supabase
    .from("daily_snapshot")
    .select(column)
    .eq("user_id", userId)
    .eq("source", "healthkit")
    .gte("date", startStr)
    .lte("date", endStr)
    .not(column, "is", null);

  if (!data || data.length < minDays) return null;

  const values = (data as Record<string, number>[])
    .map((r) => r[column])
    .filter((v): v is number => typeof v === "number")
    .sort((a, b) => a - b);
  if (values.length < minDays) return null;

  const mid = Math.floor(values.length / 2);
  return values.length % 2 === 0 ? (values[mid - 1] + values[mid]) / 2 : values[mid];
}

/// Same median-of-trailing-window shape as fetchMetricBaseline, generalized
/// across whatever connected source reported the metric each day --
/// fetchMetricBaseline is locked to source="healthkit", written for the
/// healthkit-only assessment path specifically, but Whoop/Oura users have
/// hrv_ms in daily_snapshot too and HRV is highly individual, so the HRV
/// cap needs the user's OWN trailing baseline regardless of which wearable
/// they use. Note: if a user has more than one source reporting hrv_ms on
/// the same day, each source's row contributes its own point to the
/// median rather than being merged into one per-day value first -- a minor
/// imprecision, acceptable for a single connected wearable in practice.
async function fetchGeneralMetricBaseline(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  date: string,
  column: "hrv_ms",
  minDays: number = MIN_BASELINE_DAYS,
): Promise<number | null> {
  const end = new Date(date);
  const start = new Date(end);
  start.setDate(start.getDate() - BASELINE_WINDOW_DAYS);
  const startStr = start.toISOString().slice(0, 10);
  const endStr = new Date(end.getTime() - 86400000).toISOString().slice(0, 10);

  const { data } = await supabase
    .from("daily_snapshot")
    .select(column)
    .eq("user_id", userId)
    .gte("date", startStr)
    .lte("date", endStr)
    .not(column, "is", null);

  if (!data || data.length < minDays) return null;

  const values = (data as Record<string, number>[])
    .map((r) => r[column])
    .filter((v): v is number => typeof v === "number")
    .sort((a, b) => a - b);
  if (values.length < minDays) return null;

  const mid = Math.floor(values.length / 2);
  return values.length % 2 === 0 ? (values[mid - 1] + values[mid]) / 2 : values[mid];
}

function addDays(dateStr: string, days: number): string {
  const d = new Date(`${dateStr}T00:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

// Every external Whoop/Oura call goes through this. Before this file grew
// to 3 calls per provider (recovery/readiness + sleep + workout/cycle, all
// via Promise.all), a single slow call just meant a slightly slower
// response. Now, with nothing bounding any individual call, ONE hanging or
// slow endpoint blocks the whole Promise.all -- and by extension the
// user's entire "Check now" -- until Supabase's own function timeout
// kills it. A hard per-call timeout, paired with the try/catch wrapper
// below, means a single misbehaving endpoint degrades gracefully (that
// one signal is just missing) instead of stalling or failing everything.
const PROVIDER_FETCH_TIMEOUT_MS = 8000;

async function fetchWithTimeout(url: string, options: RequestInit): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), PROVIDER_FETCH_TIMEOUT_MS);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

/// Runs a provider-fetch function and swallows ANY failure (timeout,
/// network error, malformed JSON) into the given fallback, logging the
/// cause -- one provider signal being unavailable should never crash or
/// stall the whole recommendation.
async function safely<T>(label: string, fallback: T, fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (err) {
    console.error(`${label} failed, continuing without it:`, err instanceof Error ? err.message : err);
    return fallback;
  }
}

// -- Provider fetch/refresh -------------------------------------------------

async function fetchWhoopRecovery(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
  date: string,
): Promise<{ recoveryScore: number; hrvMs?: number; restingHr?: number } | null> {
  const accessToken = await ensureFreshWhoopToken(supabase, token);
  if (!accessToken) return null;

  const start = `${date}T00:00:00.000Z`;
  const end = `${date}T23:59:59.999Z`;
  const res = await fetchWithTimeout(
    `${WHOOP_RECOVERY_URL}?start=${start}&end=${end}&limit=1`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) return null;
  const json = await res.json();
  const record = json?.records?.[0] ?? json?.[0];
  if (!record?.score) return null;

  return {
    recoveryScore: record.score.recovery_score,
    hrvMs: record.score.hrv_rmssd_milli,
    restingHr: record.score.resting_heart_rate,
  };
}

/// Real sleep hours from Whoop's own sleep data, used instead of relying
/// on an on-device HealthKit reading for Whoop users -- feeds the same
/// sleep safety cap as HealthKit/Oura sleep does.
interface SleepStageHours {
  totalHours: number | null;
  lightHours: number | null;
  deepHours: number | null;
  remHours: number | null;
  awakeHours: number | null;
}

const EMPTY_SLEEP_STAGES: SleepStageHours = {
  totalHours: null,
  lightHours: null,
  deepHours: null,
  remHours: null,
  awakeHours: null,
};

async function fetchWhoopSleepHours(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
  date: string,
): Promise<SleepStageHours> {
  const accessToken = await ensureFreshWhoopToken(supabase, token);
  if (!accessToken) return EMPTY_SLEEP_STAGES;

  const start = `${addDays(date, -1)}T00:00:00.000Z`;
  const end = `${date}T23:59:59.999Z`;
  const res = await fetchWithTimeout(
    `${WHOOP_SLEEP_URL}?start=${start}&end=${end}&limit=5`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) return EMPTY_SLEEP_STAGES;
  const json = await res.json();
  const record = (json?.records ?? json ?? [])[0];
  const stages = record?.score?.stage_summary;
  if (!stages) return EMPTY_SLEEP_STAGES;

  // Previously only the total (light+SWS+REM, no awake time) was kept --
  // the per-stage split was computed and immediately discarded. NOTE:
  // verify these exact field names against Whoop's current docs at deploy
  // time, same standing caveat this file already applies to its own URLs.
  const lightMs = stages.total_light_sleep_time_milli ?? 0;
  const deepMs = stages.total_slow_wave_sleep_time_milli ?? 0;
  const remMs = stages.total_rem_sleep_time_milli ?? 0;
  const awakeMs = stages.total_awake_time_milli ?? 0;
  const totalMs = lightMs + deepMs + remMs;
  const toHours = (ms: number) => ms > 0 ? ms / 3_600_000 : null;
  return {
    totalHours: totalMs > 0 ? totalMs / 3_600_000 : null,
    lightHours: toHours(lightMs),
    deepHours: toHours(deepMs),
    remHours: toHours(remMs),
    awakeHours: toHours(awakeMs),
  };
}

/// Yesterday's Whoop day strain (from the cycle endpoint) plus whether any
/// logged workout in the last ~day crossed the "strenuous" threshold --
/// together these feed the recent-training-load cap.
async function fetchWhoopTrainingLoad(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
  date: string,
): Promise<{ strainScore: number | null; recentHighStrain: boolean }> {
  const accessToken = await ensureFreshWhoopToken(supabase, token);
  if (!accessToken) return { strainScore: null, recentHighStrain: false };

  const start = `${addDays(date, -1)}T00:00:00.000Z`;
  const end = `${date}T23:59:59.999Z`;

  const [cycleRes, workoutRes] = await Promise.all([
    fetchWithTimeout(`${WHOOP_CYCLE_URL}?start=${start}&end=${end}&limit=2`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    }),
    fetchWithTimeout(`${WHOOP_WORKOUT_URL}?start=${start}&end=${end}&limit=5`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    }),
  ]);

  let strainScore: number | null = null;
  if (cycleRes.ok) {
    const cycleJson = await cycleRes.json();
    const record = (cycleJson?.records ?? cycleJson ?? [])[0];
    strainScore = record?.score?.strain ?? null;
  }

  let recentHighStrain = false;
  if (workoutRes.ok) {
    const workoutJson = await workoutRes.json();
    const records = workoutJson?.records ?? workoutJson ?? [];
    // deno-lint-ignore no-explicit-any
    recentHighStrain = records.some((r: any) => (r?.score?.strain ?? 0) >= WHOOP_HIGH_STRAIN_THRESHOLD);
  }

  return { strainScore, recentHighStrain };
}

/// 400/401 means the refresh grant itself is dead (RFC 6749 5.2 invalid_grant).
/// 403 is also included -- not RFC-standard for invalid_grant, but a common
/// real-world status providers use for a revoked/disabled authorization
/// (as opposed to a scope or rate-limit 403, which this endpoint can't
/// distinguish from here either way, so treating it as dead is the safer
/// default: a wrongly-flagged reconnect prompt is recoverable, a silently
/// stale connection that never re-prompts is not).
/// A 5xx/timeout says nothing about token validity and must not trigger
/// reconnect -- that distinction is the one this function exists to protect.
function isDeadRefreshTokenStatus(status: number): boolean {
  return status === 400 || status === 401 || status === 403;
}

async function ensureFreshWhoopToken(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
): Promise<string | null> {
  const isExpired = token.expires_at
    ? new Date(token.expires_at).getTime() < Date.now() + 60_000
    : false;
  if (!isExpired) return token.access_token;
  if (!token.refresh_token) return null;

  const clientId = Deno.env.get("WHOOP_CLIENT_ID")!;
  const clientSecret = Deno.env.get("WHOOP_CLIENT_SECRET")!;

  const res = await fetchWithTimeout(WHOOP_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: token.refresh_token,
      client_id: clientId,
      client_secret: clientSecret,
    }),
  });
  if (!res.ok) {
    if (isDeadRefreshTokenStatus(res.status)) {
      // Surface the dead token to the client; a failure here shouldn't
      // break this request (best-effort).
      await supabase
        .from("wearable_tokens")
        .update({ needs_reconnect: true })
        .eq("id", token.id)
        .then(null, () => {});
    }
    return null;
  }
  const json = await res.json();

  const expiresAt = new Date(Date.now() + json.expires_in * 1000).toISOString();
  await supabase
    .from("wearable_tokens")
    .update({
      access_token: json.access_token,
      refresh_token: json.refresh_token ?? token.refresh_token,
      expires_at: expiresAt,
      // A later successful refresh after a transient failure (network
      // blip, provider outage) should clear any stale flag from before.
      needs_reconnect: false,
    })
    .eq("id", token.id);

  return json.access_token;
}

async function fetchOuraReadiness(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
  date: string,
): Promise<number | null> {
  const accessToken = await ensureFreshOuraToken(supabase, token);
  if (!accessToken) return null;

  const res = await fetchWithTimeout(
    `${OURA_READINESS_URL}?start_date=${date}&end_date=${date}`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) return null;
  const json = await res.json();
  const record = json?.data?.[0];
  return record?.score ?? null;
}

/// Real sleep hours PLUS HRV and resting HR from Oura's sleep collection
/// (the longest session in the window, i.e. last night's main sleep) --
/// sleep feeds the same safety cap as HealthKit/Whoop sleep does; HRV and
/// resting HR were previously never populated for Oura snapshot rows at
/// all (only Whoop's recovery endpoint provided those).
async function fetchOuraSleepData(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
  date: string,
): Promise<
  {
    sleepHours: number | null;
    hrvMs: number | null;
    restingHr: number | null;
    lightHours: number | null;
    deepHours: number | null;
    remHours: number | null;
    awakeHours: number | null;
  }
> {
  const empty = {
    sleepHours: null,
    hrvMs: null,
    restingHr: null,
    lightHours: null,
    deepHours: null,
    remHours: null,
    awakeHours: null,
  };
  const accessToken = await ensureFreshOuraToken(supabase, token);
  if (!accessToken) return empty;

  const startDate = addDays(date, -1);
  const res = await fetchWithTimeout(
    `${OURA_SLEEP_URL}?start_date=${startDate}&end_date=${date}`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) return empty;
  const json = await res.json();
  const records = json?.data ?? [];
  if (records.length === 0) return empty;

  // deno-lint-ignore no-explicit-any
  const longest = records.reduce((a: any, b: any) =>
    (b.total_sleep_duration ?? 0) > (a.total_sleep_duration ?? 0) ? b : a
  );
  // Per-stage fields already exist on the same record -- previously only
  // total_sleep_duration/average_hrv/lowest_heart_rate were read, the rest
  // of the payload discarded. NOTE: verify these exact field names against
  // Oura's current API docs at deploy time, same standing caveat this file
  // already applies to its own URLs.
  const toHours = (seconds: number | null | undefined) => seconds ? seconds / 3600 : null;
  return {
    sleepHours: longest.total_sleep_duration ? longest.total_sleep_duration / 3600 : null,
    hrvMs: longest.average_hrv ?? null,
    // Lowest overnight HR is the standard resting-HR proxy; Oura's sleep
    // endpoint doesn't expose a separately-labeled "resting_heart_rate".
    restingHr: longest.lowest_heart_rate ?? null,
    lightHours: toHours(longest.light_sleep_duration),
    deepHours: toHours(longest.deep_sleep_duration),
    remHours: toHours(longest.rem_sleep_duration),
    awakeHours: toHours(longest.awake_time),
  };
}

/// Minutes spent in a high-stress state today -- Oura-specific; Whoop has
/// no equivalent metric.
async function fetchOuraStress(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
  date: string,
): Promise<number | null> {
  const accessToken = await ensureFreshOuraToken(supabase, token);
  if (!accessToken) return null;

  const res = await fetchWithTimeout(
    `${OURA_STRESS_URL}?start_date=${date}&end_date=${date}`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) return null;
  const json = await res.json();
  const record = json?.data?.[0];
  if (!record?.stress_high) return null;
  // stress_high is reported in seconds; store as minutes for readability.
  return Math.round(record.stress_high / 60);
}

/// Oura doesn't expose a single 0-21 strain number the way Whoop does, so
/// the count of recent "hard"-intensity workouts is used as a rough load
/// proxy; a hard-intensity session in the last ~day also feeds the
/// recent-training-load cap directly.
async function fetchOuraTrainingLoad(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
  date: string,
): Promise<{ strainScore: number | null; recentHighStrain: boolean }> {
  const accessToken = await ensureFreshOuraToken(supabase, token);
  if (!accessToken) return { strainScore: null, recentHighStrain: false };

  const startDate = addDays(date, -1);
  const res = await fetchWithTimeout(
    `${OURA_WORKOUT_URL}?start_date=${startDate}&end_date=${date}`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) return { strainScore: null, recentHighStrain: false };
  const json = await res.json();
  const records = json?.data ?? [];

  // deno-lint-ignore no-explicit-any
  const hardCount = records.filter((r: any) => r?.intensity === "hard").length;
  return { strainScore: hardCount || null, recentHighStrain: hardCount > 0 };
}

async function ensureFreshOuraToken(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
): Promise<string | null> {
  const isExpired = token.expires_at
    ? new Date(token.expires_at).getTime() < Date.now() + 60_000
    : false;
  if (!isExpired) return token.access_token;
  if (!token.refresh_token) return null;

  const clientId = Deno.env.get("OURA_CLIENT_ID")!;
  const clientSecret = Deno.env.get("OURA_CLIENT_SECRET")!;

  const res = await fetchWithTimeout("https://api.ouraring.com/oauth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: token.refresh_token,
      client_id: clientId,
      client_secret: clientSecret,
    }),
  });
  if (!res.ok) {
    // Same signal (and same 400/401-only classification) as
    // ensureFreshWhoopToken -- see its comment.
    if (isDeadRefreshTokenStatus(res.status)) {
      await supabase
        .from("wearable_tokens")
        .update({ needs_reconnect: true })
        .eq("id", token.id)
        .then(null, () => {});
    }
    return null;
  }
  const json = await res.json();

  const expiresAt = new Date(Date.now() + json.expires_in * 1000).toISOString();
  await supabase
    .from("wearable_tokens")
    .update({
      access_token: json.access_token,
      refresh_token: json.refresh_token ?? token.refresh_token,
      expires_at: expiresAt,
      needs_reconnect: false,
    })
    .eq("id", token.id);

  return json.access_token;
}

async function upsertSnapshot(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  date: string,
  source: "whoop" | "oura" | "healthkit",
  fields: Record<string, number | undefined>,
) {
  await supabase
    .from("daily_snapshot")
    .upsert(
      { user_id: userId, date, source, ...fields },
      { onConflict: "user_id,date,source" },
    );
}
