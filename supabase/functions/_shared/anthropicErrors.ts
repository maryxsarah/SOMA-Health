// Shared classification for the top-level catch block in every generation
// function that calls an LLM (generate-workout-plan -> Anthropic,
// generate-gym-workout's wording pass -> OpenAI). Before this, ANY failure
// -- a real bug, a bad request, or the LLM API itself being
// unavailable/out of credits -- collapsed into the same flat
// `{ error: msg }` at 500, which the client then showed as "Couldn't
// generate a plan right now. Try again in a moment." That's actively
// misleading for a vendor-side failure (wrong API key, exhausted credit
// balance, rate limit): retrying can't fix it, and the message implies a
// transient client-side hiccup instead of something the team needs to go
// look at. `service_unavailable` lets the client tell those two cases
// apart (see SupabaseClient.swift's serviceUnavailable case).
export function classifyGenerationError(err: unknown): { status: number; body: Record<string, unknown> } {
  const msg = err instanceof Error ? err.message : String(err);

  if (msg === "unauthorized") {
    return { status: 401, body: { error: msg } };
  }
  const isVendorFailure = msg.startsWith("Anthropic API error")
    || msg.startsWith("OpenAI API error")
    || msg === "No text content in Anthropic response";
  if (isVendorFailure) {
    // Server-side visibility: this is exactly the kind of failure that
    // needs a human to check the provider account (rate limit, credit
    // balance, API key validity), not just a retry.
    console.error("LLM generation failure:", msg);
    return { status: 502, body: { error: msg, service_unavailable: true } };
  }
  return { status: 500, body: { error: msg } };
}
