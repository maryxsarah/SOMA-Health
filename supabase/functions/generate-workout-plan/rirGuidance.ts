// DRAFTED, NOT EXPERT-REVIEWED -- same standing caveat as volumeLandmarks.ts.
// Generic, widely-published RIR (Reps in Reserve) / RPE autoregulation
// ranges by goal x experience x category. Feeds prompt guidance for what to
// WRITE into the existing free-text `intensity` field on each exercise --
// see index.ts's schema decision (extend the free-text field rather than
// add a structured rir_target, since nothing downstream parses intensity
// programmatically today).

import type { ExperienceLevel } from "../_shared/volumeLandmarks.ts";

/// goals is the raw comma-joined string already built in buildPrompt --
/// checked with simple substring matches rather than re-parsing, consistent
/// with how loosely `goals` is already handled there.
export function describeRirGuidance(goals: string, experience: ExperienceLevel, category: string): string {
  if (category === "rest" || category === "light") {
    return "";
  }

  const strengthFocused = /build_strength|gain_muscle|grow_glutes|stronger_core/.test(goals);
  const enduranceFocused = /cardio_endurance|lose_weight|leaner_toned|lose_belly_fat|lean_out_legs|toned_arms|more_visible_abs/.test(goals);

  // Working-set RIR/RPE band -- the LAST 1-2 sets of a movement can push
  // toward the bottom of the range; earlier sets should stay a rep or two
  // further from failure. Newbies stay further from failure across the
  // board regardless of goal, since technical breakdown near failure is a
  // bigger risk before movement patterns are grooved.
  if (experience === "newbie") {
    return "Autoregulation guidance: keep working sets around RIR 3-4 (RPE 6-7) -- a few reps short of failure. Write this into each exercise's intensity field in whatever form reads clearest (RIR or RPE), don't push a newbie closer to failure than that.";
  }

  if (strengthFocused && category === "push_hard") {
    return "Autoregulation guidance: top sets on the main compound lift(s) can approach RIR 1-2 (RPE 8-9), with earlier sets and accessory work staying around RIR 2-3 (RPE 7-8). Write this into each exercise's intensity field.";
  }
  if (enduranceFocused) {
    return "Autoregulation guidance: keep most working sets around RIR 2-3 (RPE 7-8) -- controlled effort that's sustainable across a higher-volume or conditioning-focused session, not grinding singles. Write this into each exercise's intensity field.";
  }
  return "Autoregulation guidance: keep working sets around RIR 2 (RPE 8) for main movements, RIR 2-3 (RPE 7-8) for accessories. Write this into each exercise's intensity field.";
}
