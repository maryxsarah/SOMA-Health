// generate-meal-recommendation
//
// Two modes, one shared prompt/generation core (promptContext.ts,
// claudeGeneration.ts):
//
// - On-demand ("What can I make?", body: { ingredients: string }) --
//   turns a freeform description of what's in the user's fridge/pantry
//   (typed or dictated, see Soma's SpeechRecognizer) into ONE complete
//   recipe suggestion. Unchanged behavior/contract from before pantry_items
//   existed -- still works with zero saved pantry items.
// - Daily autopilot (body: { mode: "daily", date: "YYYY-MM-DD" }) --
//   reads the user's persisted pantry_items instead of an ad-hoc string,
//   and caches the result in daily_meal_plan keyed on (user_id, date,
//   pantry_signature) so repeat calls with an unchanged pantry that same
//   day are free (see pantrySignature.ts). A cache miss --new day, or the
//   pantry changed since the last generation-- regenerates. Empty pantry
//   returns { empty: true }, no generation attempted.
//
// Both modes: why it fits what's left of today's nutrition target and
// goal direction, exact ingredient quantities, and step-by-step prep
// instructions using ONLY equipment the user actually owns
// (users.household_equipment). Recipe response shape: { name,
// whyThisMeal, ingredients: [{name, quantity}], steps: string[],
// equipmentUsed: string[], totalTimeMinutes, calories, proteinG, carbsG,
// fatG }. Daily mode wraps that in { date, category, recommendation }.
//
// Like parse-meal-text, a recipe is a SUGGESTION, never auto-saved
// server-side -- the client shows it back and only writes to meal_log if
// the user taps "Log this meal" (source 'recipe_ai', see the migration
// that widens meal_log_source_check alongside this function).

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";
import { checkFlatDailyLimit, logGeneration } from "../_shared/generationLimits.ts";
import { languageName } from "../_shared/language.ts";
import { buildPromptContext } from "./promptContext.ts";
import { callClaude, toResponse } from "./claudeGeneration.ts";
import { computePantrySignature, pantryToIngredientsDescription, type PantryItemRow } from "./pantrySignature.ts";

// A user asking "what can I make?" a few times while actually standing in
// the kitchen deciding is the real use case -- generous like
// parse-meal-text's own limit, still bounded against a scripted account.
const FLAT_DAILY_LIMIT = 20;

// The daily-autopilot generation gets its own, much smaller flat cap --
// this one only fires on a real cache miss (new day or an edited pantry),
// not on every screen open, so a handful of edits while unpacking
// groceries is the realistic ceiling, not repeated manual requests.
const FLAT_DAILY_LIMIT_DAILY = 5;

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const supabase = serviceRoleClient();

    if (body.mode === "daily") {
      return await handleDailyMode(supabase, userId, body);
    }
    return await handleOnDemandMode(supabase, userId, body);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

// MARK: - On-demand ("What can I make?", unchanged contract)

// deno-lint-ignore no-explicit-any
async function handleOnDemandMode(supabase: SupabaseClient, userId: string, body: any): Promise<Response> {
  const ingredients: string | undefined = body.ingredients;
  if (!ingredients || !ingredients.trim()) {
    return jsonResponse({ error: "missing 'ingredients'" }, 400);
  }

  const date = new Date().toISOString().slice(0, 10);
  const allowed = await checkFlatDailyLimit(supabase, userId, date, "meal_recommendation", FLAT_DAILY_LIMIT);
  if (!allowed) {
    return jsonResponse({ error: "Too many meal ideas today. Try again tomorrow." }, 429);
  }

  const context = await buildPromptContext(supabase, userId, date);
  const recommendation = await callClaude({
    ingredients: ingredients.trim(),
    equipmentOptions: context.equipmentOptions,
    equipmentDescriptionForPrompt: context.equipmentDescriptionForPrompt,
    remainingLine: context.remainingLine,
    recoveryLine: context.recoveryLine,
    goalLine: context.goalLine,
    recentLine: context.recentLine,
    language: languageName(body.language),
  });

  await logGeneration(supabase, userId, date, "meal_recommendation");
  return jsonResponse(toResponse(recommendation));
}

// MARK: - Daily autopilot ("Today's meal plan", cached by pantry_signature)

// deno-lint-ignore no-explicit-any
async function handleDailyMode(supabase: SupabaseClient, userId: string, body: any): Promise<Response> {
  const date: string | undefined = body.date;
  if (!date) {
    return jsonResponse({ error: "missing 'date'" }, 400);
  }

  const { data: pantryRows, error: pantryError } = await supabase
    .from("pantry_items")
    .select("name, quantity, unit")
    .eq("user_id", userId);
  if (pantryError) throw new Error(`could not read pantry_items: ${pantryError.message}`);
  const pantryItems: PantryItemRow[] = pantryRows ?? [];
  // No saved pantry yet -- the graceful "add what you have" empty state,
  // not an error, and nothing is generated or cached.
  if (pantryItems.length === 0) {
    return jsonResponse({ empty: true });
  }

  const pantrySignature = computePantrySignature(pantryItems);

  // One cache row per (user, date, pantry signature): a hit means today's
  // pantry hasn't changed since the last generation for this date, so
  // repeat NutritionView opens are free. A miss covers both "new day" and
  // "pantry edited since the last generation."
  const { data: cached, error: cacheReadError } = await supabase
    .from("daily_meal_plan")
    .select("category, recommendation, pantry_signature")
    .eq("user_id", userId)
    .eq("date", date)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (cacheReadError) throw new Error(`could not read daily_meal_plan: ${cacheReadError.message}`);
  if (cached && cached.pantry_signature === pantrySignature) {
    return jsonResponse({ date, category: cached.category, recommendation: cached.recommendation });
  }

  const allowed = await checkFlatDailyLimit(supabase, userId, date, "meal_recommendation_daily", FLAT_DAILY_LIMIT_DAILY);
  if (!allowed) {
    return jsonResponse({ error: "Too many meal plan regenerations today. Try again tomorrow." }, 429);
  }

  const context = await buildPromptContext(supabase, userId, date);
  const recommendation = await callClaude({
    ingredients: pantryToIngredientsDescription(pantryItems),
    equipmentOptions: context.equipmentOptions,
    equipmentDescriptionForPrompt: context.equipmentDescriptionForPrompt,
    remainingLine: context.remainingLine,
    recoveryLine: context.recoveryLine,
    goalLine: context.goalLine,
    recentLine: context.recentLine,
    language: languageName(body.language),
  });

  const response = toResponse(recommendation);
  const { error: insertError } = await supabase.from("daily_meal_plan").insert({
    user_id: userId,
    date,
    pantry_signature: pantrySignature,
    category: context.category,
    recommendation: response,
  });
  if (insertError) throw new Error(`could not write daily_meal_plan: ${insertError.message}`);

  await logGeneration(supabase, userId, date, "meal_recommendation_daily");
  return jsonResponse({ date, category: context.category, recommendation: response });
}
