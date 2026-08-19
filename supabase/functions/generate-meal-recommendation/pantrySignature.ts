// Pure, unit-testable pieces of generate-meal-recommendation's daily-
// autopilot mode -- pulled out specifically so the signature/description
// logic is directly testable without importing index.ts itself
// (top-level Deno.serve), same reason recoveryDayAdjustment.ts lives in
// its own file.

export interface PantryItemRow {
  name: string;
  quantity: number | null;
  unit: string | null;
}

/// Deterministic fingerprint of the user's current pantry -- sorted by
/// name (case-insensitive) so add/remove order never changes the
/// signature, then joined into one string. Same plain sorted+joined-text
/// convention gym_workout_plan's own equipment_signature already uses
/// (see 20260728020000_add_gym_workout_plan_cache.sql) -- no hashing
/// needed, this never leaves the server and is only ever compared for
/// equality against the previous call's signature.
///
/// Computed here, server-side, from whatever pantry_items actually holds
/// right now -- the client never supplies or influences this value, so it
/// can't force a stale cache hit or an unnecessary regeneration.
export function computePantrySignature(items: PantryItemRow[]): string {
  return [...items]
    .sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()))
    .map((item) => `${item.name.trim().toLowerCase()}|${item.quantity ?? ""}|${(item.unit ?? "").trim().toLowerCase()}`)
    .join(";");
}

/// The same natural-language ingredients string the on-demand flow's free-
/// text field expects (e.g. "2 cups rice, chicken breast, onion") -- lets
/// the daily-autopilot path reuse callClaude's existing prompt-building
/// code unchanged rather than duplicating it.
export function pantryToIngredientsDescription(items: PantryItemRow[]): string {
  return items
    .map((item) => {
      const quantityPart = item.quantity != null ? String(item.quantity) : null;
      const amount = [quantityPart, item.unit].filter(Boolean).join(" ");
      return amount ? `${amount} ${item.name}` : item.name;
    })
    .join(", ");
}
