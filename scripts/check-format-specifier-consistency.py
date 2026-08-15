#!/usr/bin/env python3
"""Scans Localizable.xcstrings for the BUG-118 crash class: a printf-style
format specifier (%@, %lld, %.1f, %%, %1$@, ...) present in one language's
translation but missing, extra, or differently-typed in another. Foundation
resolves `String(localized:)` by pulling the CATALOG's stored text for the
current locale and formatting it with however many arguments the call site
actually supplied -- if a translated string has a different specifier count
than the reference, that specific locale crashes (SIGSEGV reading garbage
off the argument list) even though English/the source never would.

This is a different, complementary check from check-localization-coverage.py
(which only proves a translation EXISTS, not that its internal format
specifiers are consistent with the reference).

Usage:
  scripts/check-format-specifier-consistency.py            whole catalog
  scripts/check-format-specifier-consistency.py --json      machine-readable

Exit code 1 if any inconsistency is found.
"""
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = REPO_ROOT / "Soma/Resources/Localizable.xcstrings"
LANGS = ["de", "en", "es", "fr", "hy", "it", "ka", "ru", "sr"]

# A printf/ICU-style conversion specifier: optional %N$ position, optional
# flags/width/precision, then a conversion char. %% (escaped literal percent)
# is matched separately and does NOT count as a specifier.
SPECIFIER_RE = re.compile(r'%(\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(@|d|i|u|ld|lu|lld|llu|f|e|g|s|c|x|X|D|U|F)')
ESCAPED_PERCENT_RE = re.compile(r'%%')
# Same specifier grammar as SPECIFIER_RE, plus %% -- used to find leftover/orphan "%" (see find_orphan_percents).
SPECIFIER_OR_ESCAPE = re.compile(r'%%|%(\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(@|d|i|u|ld|lu|lld|llu|f|e|g|s|c|x|X|D|U|F)')


def extract_signature(text):
    """Returns a normalized list of (position, type) for each real specifier,
    ignoring %% -- order-independent (positional %N$ resolves position;
    bare %@ sequences are numbered by appearance order)."""
    if text is None:
        return None
    stripped = ESCAPED_PERCENT_RE.sub("\x00", text)  # placeholder so %% doesn't get re-matched
    sig = []
    auto_pos = 0
    for m in SPECIFIER_RE.finditer(stripped):
        pos_group, conv = m.group(1), m.group(2)
        if pos_group:
            pos = int(pos_group[:-1])
        else:
            auto_pos += 1
            pos = auto_pos
        sig.append((pos, conv))
    return sorted(sig)


def find_orphan_percents(catalog):
    """A lone "%" that isn't "%%" and isn't part of a complete, valid
    specifier is exactly BUG-118's mechanism in miniature: Foundation's
    format resolver can still treat it as needing an argument (or, worse,
    a stray letter right after it can accidentally complete a real specifier
    -- e.g. "25 % d'air" parses as "%d" with a space flag, a genuine printf
    flag). Zero tolerance: every literal "%" must be doubled to "%%"."""
    orphans = {}
    for key, entry in catalog.items():
        localizations = entry.get("localizations")
        if not localizations:
            continue
        for lang, loc in localizations.items():
            for value in variant_values(loc):
                if value is None or "%" not in value:
                    continue
                remainder = SPECIFIER_OR_ESCAPE.sub("", value)
                if "%" in remainder:
                    orphans.setdefault(key, {})[lang] = value
    return orphans


def variant_values(loc):
    """A localization entry is either a flat {"stringUnit": {"value": ...}}
    or a pluralized {"variations": {"plural": {"one": {...}, "other": {...},
    ...}}}. Returns every stringUnit value found, since ALL plural branches
    must agree with the reference's specifier count/type (a translator
    fixing grammar in the "few" branch but not "other" is the same crash
    class, just per-plural-category instead of per-language)."""
    if "stringUnit" in loc:
        return [loc["stringUnit"].get("value")]
    if "variations" in loc:
        plural = loc["variations"].get("plural", {})
        return [v.get("stringUnit", {}).get("value") for v in plural.values() if "stringUnit" in v]
    return []


def main():
    as_json = "--json" in sys.argv[1:]
    with open(CATALOG_PATH, encoding="utf-8") as f:
        catalog = json.load(f)["strings"]

    problems = {}
    for key, entry in catalog.items():
        localizations = entry.get("localizations")
        if not localizations:
            continue
        # Reference signature: explicit "en" wins; otherwise the key text
        # itself is the English source (plain-literal LocalizedStringKey
        # convention used throughout this catalog).
        en_values = variant_values(localizations["en"]) if "en" in localizations else None
        reference_text = en_values[0] if en_values else key
        reference_sig = extract_signature(reference_text)
        if not reference_sig:
            continue  # no specifiers at all -- nothing to check

        mismatches = {}
        for lang in LANGS:
            if lang == "en" and en_values is None:
                continue  # no explicit en block; key itself IS the reference, not a separate check
            loc = localizations.get(lang)
            if not loc:
                continue  # coverage gaps are check-localization-coverage.py's job, not this one
            for value in variant_values(loc):
                sig = extract_signature(value)
                if sig != reference_sig:
                    mismatches.setdefault(lang, []).append({"value": value, "signature": sig})

        if mismatches:
            problems[key] = {
                "reference_text": reference_text,
                "reference_signature": reference_sig,
                "mismatches": mismatches,
            }

    orphans = find_orphan_percents(catalog)

    if as_json:
        print(json.dumps({"mismatches": problems, "orphan_percents": orphans}, ensure_ascii=False, indent=2))
    else:
        if not problems and not orphans:
            print(f"OK -- checked {sum(1 for e in catalog.values() if e.get('localizations'))} translated entries, "
                  f"format specifiers consistent across all languages, no orphan '%' characters.")
        if problems:
            print(f"{len(problems)} keys with inconsistent format specifiers across languages:\n")
            for key, info in problems.items():
                print(f"  KEY: {key!r}")
                print(f"    reference [{info['reference_text']!r}] -> {info['reference_signature']}")
                for lang, ms in info["mismatches"].items():
                    for m in ms:
                        print(f"    [{lang}] {m['value']!r} -> {m['signature']}  <-- MISMATCH")
                print()
        if orphans:
            print(f"{len(orphans)} keys with an unescaped literal '%' (should be '%%'):\n")
            for key, langs in orphans.items():
                print(f"  KEY: {key!r}")
                for lang, value in langs.items():
                    print(f"    [{lang}] {value!r}  <-- unescaped %")
                print()
    sys.exit(1 if (problems or orphans) else 0)


if __name__ == "__main__":
    main()
