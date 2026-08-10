// Phase 4 (docs/coaching-personalization-plan.md): the deterministic half
// of the weekly anchor-session concept -- a recurring class/activity (e.g.
// a Tuesday hot yoga class, a Saturday tennis league) the rest of the
// user's week gets built around, set at onboarding or from ProfileView.
// Same "decide here, LLM only words it" pattern as goalWork.ts's
// describeUpcomingGoalWork, split out for direct unit testing (importing
// index.ts runs Deno.serve and binds a port -- see healthkitBand.ts's own
// comment on why every decision module in this codebase lives apart from
// its Deno.serve handler).
//
// Unlike a sport goal's scheduleDays (a structured commitment this app
// itself tracks completion against), an anchor session is free text with
// no exercise/movement data attached -- this module only ever produces an
// ADVISORY prompt line trusting the model to reason about what a named
// activity typically demands (same trust already placed in sport-goal
// catalog names by describeUpcomingGoalWork), never a structured decision
// like decideFinisher/decideGoalWork.

export interface AnchorSessionInput {
  /// null/empty = no anchor session set -- degrades to no guidance at all,
  /// same "omit rather than fabricate" rule as every other optional signal
  /// in this codebase.
  name: string | null;
  /// 0=Sun..6=Sat (JS getUTCDay) -- same convention as user_goal.schedule_days,
  /// so this and a sport goal's schedule can be reasoned about identically.
  days: number[];
  /// Today's date, "YYYY-MM-DD".
  date: string;
}

function utcWeekday(dateStr: string): number {
  return new Date(`${dateStr}T00:00:00.000Z`).getUTCDay();
}

function addDaysStr(dateStr: string, days: number): string {
  const d = new Date(`${dateStr}T00:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/// One advisory sentence relating TODAY to the anchor session, or null
/// when there's nothing to say (no anchor session set, or today isn't the
/// anchor day nor adjacent to one). When today relates to the anchor day
/// in more than one way at once (e.g. a Tue/Thu anchor checked on a
/// Wednesday -- yesterday AND tomorrow both qualify), priority is: today
/// itself (most concrete) > the day BEFORE (forward-looking, same
/// direction Phase 2's describeUpcomingGoalWork already established --
/// still actionable, today's plan can still adjust for it) > the day
/// AFTER (backward-looking context only, less actionable since the
/// fatigue is already there either way).
export function describeAnchorSession(input: AnchorSessionInput): string | null {
  const name = input.name?.trim();
  if (!name || input.days.length === 0) return null;

  const today = utcWeekday(input.date);
  const tomorrow = utcWeekday(addDaysStr(input.date, 1));
  const yesterday = utcWeekday(addDaysStr(input.date, -1));

  if (input.days.includes(today)) {
    return `The user has their recurring "${name}" session on their own calendar today, separate from this workout -- keep today's session complementary and not maximally fatiguing, so they still have capacity for it. Never let this override the day's actual intensity category, injury exclusions, or equipment above.`;
  }
  if (input.days.includes(tomorrow)) {
    return `The user has their recurring "${name}" session scheduled tomorrow -- where today's other constraints allow it, avoid needlessly pre-fatiguing the muscles or energy systems that session is likely to use. Never let this override the day's actual intensity category, injury exclusions, or equipment above.`;
  }
  if (input.days.includes(yesterday)) {
    return `The user had their recurring "${name}" session yesterday -- factor in that they may still be carrying some fatigue or tightness from it.`;
  }
  return null;
}
