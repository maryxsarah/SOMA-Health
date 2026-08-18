// A workout_log row auto-detected from a connected wearable's own
// activity signal (a walk the watch noticed on its own) -- distinct from
// every other source, which represents a deliberate user choice (a
// suggestion they started, a manual log, an AI plan they picked).
//
// Single source of truth for "does today's log count as done" across
// generate-workout-plan and generate-gym-workout's lock checks -- both
// used to hand-write the literal 'device_detected' string independently,
// which is exactly how the two drifted before. The Swift client mirrors
// this same value in HomeView.deliberateWorkoutLogToday.
export const DEVICE_DETECTED_SOURCE = "device_detected";
