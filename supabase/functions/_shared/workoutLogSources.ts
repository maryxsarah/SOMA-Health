// A workout_log row logged from a connected wearable's own auto-detected
// session (a run Whoop/Oura/HealthKit noticed on its own). Historically
// this source meant "written silently, with zero user input" and was
// excluded from every "does today already have a workout" lock check --
// but that silent write path is gone: HomeView.confirmDetectedWorkout is
// now the only writer of this source, and it only ever runs after an
// explicit "Yes, that was my workout" tap (see DetectedWorkoutConfirmationView).
// A device_detected row is therefore exactly as deliberate as any other
// source today, and generate-workout-plan/generate-gym-workout's lock
// checks no longer exclude it. Kept as its own constant (mirrored
// Swift-side by WorkoutLogEntry.deviceDetectedSource) since the source
// string itself is still meaningful for display (e.g. the "Detected
// automatically" eyebrow label), even though no lock check reads it.
export const DEVICE_DETECTED_SOURCE = "device_detected";
