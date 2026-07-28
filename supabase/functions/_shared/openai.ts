// deno-lint-ignore no-explicit-any
type OpenAIResponse = any;

/**
 * Pulls the assistant's text out of an OpenAI Responses API payload.
 * `output` is an array that can include non-message items first (e.g. a
 * "reasoning" item with empty content) before the actual "message" item --
 * naively reading output[0] silently grabbed the empty reasoning block on
 * reasoning-capable models and broke every call. Find the message item by
 * type instead of assuming its position.
 */
export function extractOutputText(json: OpenAIResponse): string | undefined {
  if (typeof json.output_text === "string" && json.output_text.length > 0) {
    return json.output_text;
  }
  const messageItem = (json.output ?? []).find((item: OpenAIResponse) => item.type === "message");
  return messageItem?.content?.[0]?.text;
}
