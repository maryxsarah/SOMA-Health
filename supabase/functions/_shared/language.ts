// Every AI-generation edge function receives the client's selected UI
// language as `body.language` (a code from `AppLanguage.aiRequestCode` --
// see Soma/App/LanguageManager.swift) and uses it to make the model's own
// freeform text (coaching copy, meal labels, rationale, ...) match what
// the rest of the app is showing, instead of always answering in English.

const LANGUAGE_NAMES: Record<string, string> = {
  en: "English",
  es: "Spanish",
  fr: "French",
  it: "Italian",
  de: "German",
  ru: "Russian",
  ka: "Georgian",
  hy: "Armenian",
};

/// The English name of the requested language, for embedding in a prompt
/// instruction (e.g. "Write X in ${languageName(body.language)}."). Falls
/// back to English for a missing/unrecognized code -- never a language
/// this app has no UI strings for.
export function languageName(code: unknown): string {
  return typeof code === "string" && LANGUAGE_NAMES[code] ? LANGUAGE_NAMES[code] : "English";
}

/// The validated language code itself (not the English name), for
/// functions that key a lookup table by code rather than prompt an LLM --
/// see generate-recommendation's MESSAGES.
export function normalizeLanguageCode(code: unknown): string {
  return typeof code === "string" && LANGUAGE_NAMES[code] ? code : "en";
}
