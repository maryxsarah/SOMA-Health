import { assertEquals } from "jsr:@std/assert";
import { languageName, normalizeLanguageCode } from "./language.ts";

Deno.test("languageName resolves every code Soma ships a UI language for", () => {
  assertEquals(languageName("en"), "English");
  assertEquals(languageName("es"), "Spanish");
  assertEquals(languageName("fr"), "French");
  assertEquals(languageName("it"), "Italian");
  assertEquals(languageName("de"), "German");
  assertEquals(languageName("ru"), "Russian");
  assertEquals(languageName("ka"), "Georgian");
  assertEquals(languageName("hy"), "Armenian");
});

Deno.test("languageName falls back to English for missing/unrecognized/non-string input", () => {
  assertEquals(languageName(undefined), "English");
  assertEquals(languageName(null), "English");
  assertEquals(languageName("ja"), "English");
  assertEquals(languageName(""), "English");
  assertEquals(languageName(42), "English");
});

Deno.test("normalizeLanguageCode returns the code itself, not the English name", () => {
  assertEquals(normalizeLanguageCode("ru"), "ru");
  assertEquals(normalizeLanguageCode("ka"), "ka");
  assertEquals(normalizeLanguageCode("hy"), "hy");
});

Deno.test("normalizeLanguageCode falls back to 'en' for missing/unrecognized/non-string input", () => {
  assertEquals(normalizeLanguageCode(undefined), "en");
  assertEquals(normalizeLanguageCode("ja"), "en");
  assertEquals(normalizeLanguageCode(123), "en");
});
