// Simple year-diff age calculation, shared by anything that needs an
// actual age number (nutritionTargets.ts's BMR formula, the Goal Body
// adult-only gate) rather than just caution language. Mirrors
// generate-workout-plan's own local ageFromDOB exactly -- left as a
// separate copy there rather than refactored to import this, to avoid
// touching that function's existing behavior for an unrelated feature.
export function ageFromDOB(dob: string): number {
  const birth = new Date(dob);
  const now = new Date();
  let age = now.getUTCFullYear() - birth.getUTCFullYear();
  const hasHadBirthdayThisYear = now.getUTCMonth() > birth.getUTCMonth() ||
    (now.getUTCMonth() === birth.getUTCMonth() && now.getUTCDate() >= birth.getUTCDate());
  if (!hasHadBirthdayThisYear) age -= 1;
  return age;
}

export const ADULT_AGE = 18;
