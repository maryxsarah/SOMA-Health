// generate-affirmation
//
// One kind line a day (Soma Refresh 16a/16b). Body: { date, language,
// forceRegenerate? }. Cached per (user, date) in daily_affirmation, so the
// morning background pass, the Home widget, and the Affirmations sheet all
// share a single generation. forceRegenerate ("New line" / the widget's
// refresh) bypasses the cache -- bounded by DAILY_AFFIRMATION_LIMIT rows
// of ai_generation_log source 'affirmation' per day: one automatic
// generation plus one manual regeneration ("1 new generation a day").
//
// Response: { text, generatedAt, regenerationAvailable } on success, or
// { generation_limit_reached: true, message } (HTTP 200 -- being limited
// is a normal outcome, same convention as generate-workout-plan). A
// language switch invalidates the cache like a miss; if the limit is
// already spent, the cached line is returned as-is rather than erroring
// (a stale-language line beats an empty widget).

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";
import { checkFlatDailyLimit, logGeneration } from "../_shared/generationLimits.ts";
import { languageName, normalizeLanguageCode } from "../_shared/language.ts";

// One automatic morning generation + one manual "New line" per day.
const DAILY_AFFIRMATION_LIMIT = 2;

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const MODEL = "claude-haiku-4-5";

const LIMIT_MESSAGE = "Today's new line is used up -- a fresh one arrives tomorrow morning.";

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const date: string = body.date ?? new Date().toISOString().slice(0, 10);
    const languageCode = normalizeLanguageCode(body.language);
    const forceRegenerate = body.forceRegenerate === true;

    const supabase = serviceRoleClient();

    const { data: cached } = await supabase
      .from("daily_affirmation")
      .select("text, language, generated_at, edited")
      .eq("user_id", userId)
      .eq("date", date)
      .maybeSingle();

    const regenerationAllowed = () =>
      checkFlatDailyLimit(supabase, userId, date, "affirmation", DAILY_AFFIRMATION_LIMIT);

    const cacheValid = cached != null && cached.language === languageCode;
    if (cacheValid && !forceRegenerate) {
      return jsonResponse({
        text: cached!.text,
        generatedAt: cached!.generated_at,
        regenerationAvailable: await regenerationAllowed(),
      });
    }

    const allowed = await regenerationAllowed();
    if (!allowed) {
      if (forceRegenerate || cached == null) {
        return jsonResponse({ generation_limit_reached: true, message: LIMIT_MESSAGE });
      }
      // Language switched after the day's quota was spent -- the cached
      // line in yesterday's language still beats an empty state.
      return jsonResponse({ text: cached.text, generatedAt: cached.generated_at, regenerationAvailable: false });
    }

    // Light personal context only -- an affirmation should feel written
    // for this user's day, never read like a report of their data.
    const { data: userRow } = await supabase
      .from("users")
      .select("training_emphasis, goals")
      .eq("id", userId)
      .maybeSingle();

    const { data: todaysRec } = await supabase
      .from("daily_recommendation")
      .select("category")
      .eq("user_id", userId)
      .eq("date", date)
      .maybeSingle();

    // Recent generated lines + everything the user kept/wrote -- context
    // so a new line is genuinely new, same "informational, not
    // authoritative" role recent meals play in generate-meal-recommendation.
    const since = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    const { data: recentDaily } = await supabase
      .from("daily_affirmation")
      .select("text")
      .eq("user_id", userId)
      .gte("date", since);
    const { data: keptLines } = await supabase
      .from("user_affirmations")
      .select("text")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(20);
    const avoid = [
      ...(recentDaily ?? []).map((r) => r.text),
      ...(keptLines ?? []).map((r) => r.text),
      ...(cached ? [cached.text] : []),
    ].filter(Boolean);

    const text = await callClaude({
      goalLine: userRow?.training_emphasis
        ? `Their current goal direction is "${userRow.training_emphasis}" (cut = losing fat, bulk = gaining size, recomp = body composition, maintain = staying steady).`
        : "",
      dayLine: todaysRec?.category
        ? `Today's training recommendation for them is "${todaysRec.category}" -- let the line quietly fit that kind of day without naming it.`
        : "",
      avoidLine: avoid.length > 0
        ? `Lines they've already seen or saved -- write something clearly different in both wording and idea: ${avoid.map((t) => `"${t}"`).join(", ")}.`
        : "",
      language: languageName(body.language),
    });

    // 16b "your words are never discarded": a line the user EDITED is
    // auto-promoted into their list the moment a replacement generates.
    // Untouched lines aren't promoted -- they stay readable via the 7-day
    // Recent window (past daily_affirmation rows) and just age out.
    if (cached?.edited && cached.text !== text) {
      const { data: existing } = await supabase
        .from("user_affirmations")
        .select("id")
        .eq("user_id", userId)
        .eq("text", cached.text)
        .limit(1);
      if (!existing || existing.length === 0) {
        await supabase.from("user_affirmations").insert({ user_id: userId, text: cached.text, source: "custom" });
      }
    }

    const generatedAt = new Date().toISOString();
    const { error: upsertError } = await supabase
      .from("daily_affirmation")
      .upsert(
        { user_id: userId, date, text, language: languageCode, edited: false, generated_at: generatedAt },
        { onConflict: "user_id,date" },
      );
    if (upsertError) throw new Error(`daily_affirmation upsert failed: ${upsertError.message}`);
    await logGeneration(supabase, userId, date, "affirmation");

    return jsonResponse({
      text,
      generatedAt,
      regenerationAvailable: await regenerationAllowed(),
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

interface ClaudeInput {
  goalLine: string;
  dayLine: string;
  avoidLine: string;
  language: string;
}

async function callClaude(input: ClaudeInput): Promise<string> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY")!;
  const schema = {
    type: "object",
    properties: { text: { type: "string" } },
    required: ["text"],
    additionalProperties: false,
  };

  const prompt = `You write ONE short affirmation line for a fitness app user's day -- the kind of line that lands on a home-screen widget and in a gentle push notification.

${input.goalLine}
${input.dayLine}
${input.avoidLine}

Rules for the line:
- One sentence, at most 90 characters. Second person ("you"), present tense.
- Warm and grounded -- a specific, human observation about effort, consistency, or rest. Think "You don't need a perfect day -- just ten honest minutes."
- Never toxic positivity, never about weight/appearance, never a command barked at them, never clinical.
- No emoji, no hashtags, no surrounding quotation marks, no exclamation-mark pileups.

Return { text } with just the line. Write it in ${input.language}.`;

  const res = await fetch(ANTHROPIC_API_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 200,
      output_config: { format: { type: "json_schema", schema } },
      messages: [{ role: "user", content: prompt }],
    }),
  });
  if (!res.ok) {
    const errBody = await res.text();
    throw new Error(`Anthropic API error ${res.status}: ${errBody}`);
  }
  const json = await res.json();
  // deno-lint-ignore no-explicit-any
  const textBlock = (json.content ?? []).find((b: any) => b.type === "text");
  if (!textBlock?.text) throw new Error("No text content in Anthropic response");
  const parsed = JSON.parse(textBlock.text) as { text: string };
  return parsed.text.trim();
}
