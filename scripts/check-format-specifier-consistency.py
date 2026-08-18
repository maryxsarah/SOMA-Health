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

A THIRD, distinct check lives here too (find_call_site_type_mismatches):
BUG-129 was a `%@` hand-typed for an `Int` argument in ALL 9 languages --
consistent across languages, so the cross-language check above passed clean.
That bug is only visible by comparing the catalog against the Swift call
site's actual argument TYPES, which is what this check does (heuristically --
see its own docstring for the precision/recall tradeoffs).

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
SOMA_SRC = REPO_ROOT / "Soma"
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


CALL_SITE_RE = re.compile(
    r'String\(\s*localized:\s*"(?P<key>[^"]+)"\s*,\s*defaultValue:\s*"(?P<default>(?:[^"\\]|\\.)*)"'
)
NUMERIC_TYPES = r'Int8|Int16|Int32|Int64|Int|UInt8|UInt16|UInt32|UInt64|UInt|Double|Float|CGFloat'
# (?<!\.) excludes `case .name: String(...)`/`case .name: Int(...)` --
# without it, a switch case whose body happens to start with a type-shaped
# call (extremely common for `case .x: String(localized: ...)`, the
# dominant pattern for enum displayName/explanation properties in this
# codebase) reads identically to a real `name: Type` annotation, silently
# polluting global_map with the case's own label under the wrong kind.
PROP_NUMERIC_RE = re.compile(r'(?<!\.)\b(\w+)\s*:\s*(?:' + NUMERIC_TYPES + r')\??\b')
PROP_STRING_RE = re.compile(r'(?<!\.)\b(\w+)\s*:\s*String\??\b')
LOCAL_ASSIGN_RE = re.compile(r'\b(?:let|var)\s+(\w+)\s*=\s*([^\n]+)')
# `func name(...) -> ReturnType`, tolerating async/throws/rethrows before the arrow.
FUNC_RETURN_RE = re.compile(
    r'\bfunc\s+(\w+)\s*\([^()]*(?:\([^()]*\)[^()]*)*\)\s*(?:async\s+)?(?:throws\s+|rethrows\s+)?->\s*(\w+)'
)
NUMERIC_CTOR_RE = re.compile(r'^(?:' + NUMERIC_TYPES + r')\(')
STRING_CTOR_OR_LITERAL_RE = re.compile(r'^(?:String\(|")')
NUMERIC_LITERAL_RE = re.compile(r'^-?\d+(\.\d+)?\b')
NUMERIC_SUFFIXES = (".count", ".rounded()")
STRINGY_MARKERS = (".formatted(", ".description", ".lowercased()", ".uppercased()",
                    ".capitalized", ".displayName", ".displayTitle", ".shortDate(",
                    ".joined(", "String(")

# Conversion chars from SPECIFIER_RE that expect an object (%@) vs a number.
OBJECT_CONV = {"@"}
NUMBER_CONV = {"d", "i", "u", "ld", "lu", "lld", "llu", "f", "e", "g", "x", "X", "D", "U", "F"}


# A call that spans the WHOLE expression, dotted-method calls included --
# `goal.targetRangeText(unit: unit)`, not just a bare `formatted(x)` -- the
# greedy `.*\)$` is safe here because we only care whether the outermost
# call's name is a *known* helper; anything else falls through to "unknown".
OUTER_CALL_RE = re.compile(r'^(?:[A-Za-z_]\w*\.)*([A-Za-z_]\w*)\(.*\)$')


def classify_expr(expr, local_map, global_map, func_return_map):
    """Heuristically classifies a Swift interpolation expression as
    'numeric', 'string', or 'unknown' (never guess when unsure -- an
    'unknown' is silently skipped by the caller, so false negatives are the
    accepted cost of avoiding false positives on this repo's real code).

    `local_map` (this file's own `let x = ...` bindings, keyed to the RAW
    set of kinds seen -- may have 2 elements if the same name is bound to
    different types in different functions in the same file) is checked
    before `global_map` (cross-file property/param annotations, already
    pre-filtered to unambiguous names). A name local to this file always
    wins over the global map, INCLUDING when it's locally ambiguous -- that
    case returns 'unknown' rather than falling through to a same-named but
    unrelated global property, which would just trade one collision for
    another (e.g. `target` is a String in one function here and an Int in
    another; a leftover global `target: Int` elsewhere in the codebase is
    not evidence about either)."""
    e = expr.strip()
    if STRING_CTOR_OR_LITERAL_RE.match(e):
        return "string"
    if NUMERIC_CTOR_RE.match(e):
        return "numeric"
    if NUMERIC_LITERAL_RE.match(e):
        return "numeric"
    for marker in STRINGY_MARKERS:
        if marker in e:
            return "string"
    for suf in NUMERIC_SUFFIXES:
        if e.endswith(suf):
            return "numeric"
    # A call to a locally-defined helper function or method, e.g.
    # `formatted(value)` or `goal.targetRangeText(unit: unit)`, where
    # `func formatted(...) -> String` / `func targetRangeText(...) -> String?`
    # is declared somewhere in Soma/.
    call_m = OUTER_CALL_RE.match(e)
    if call_m and call_m.group(1) in func_return_map:
        return func_return_map[call_m.group(1)]
    # Bare identifier or simple dotted member-access chain, e.g. `horizon.low`,
    # `trend.percent` -- resolve via this file's own bindings first, then the
    # codebase-wide name->type map.
    if re.fullmatch(r'[A-Za-z_]\w*(\.[A-Za-z_]\w*)*', e):
        tail = e.split(".")[-1]
        if tail in local_map:
            types = local_map[tail]
            if types == {"numeric"}:
                return "numeric"
            if types == {"string"}:
                return "string"
            return "unknown"  # locally ambiguous -- do NOT fall through to global_map
        types = global_map.get(tail)
        if types == {"numeric"}:
            return "numeric"
        if types == {"string"}:
            return "string"
    return "unknown"


def _single_kind(kinds_set):
    return next(iter(kinds_set)) if len(kinds_set) == 1 else None


def trim_rhs(rhs):
    """`let x = EXPR` capture is greedy to end-of-line, which over-grabs for
    `if let x = y.z { ... }` / `guard let x = y.z else { ... }` (the `{...}`
    block is the enclosing statement's body, not part of EXPR). Cuts at the
    first top-level (paren/bracket-depth 0) `{`, then drops a trailing bare
    `else` left over from the guard-let form."""
    depth = 0
    cut = len(rhs)
    for i, c in enumerate(rhs):
        if c in '([':
            depth += 1
        elif c in ')]':
            depth -= 1
        elif c == '{' and depth == 0:
            cut = i
            break
    trimmed = re.sub(r'\belse\s*$', '', rhs[:cut].rstrip()).rstrip()
    return trimmed


def build_type_maps():
    """Returns (global_map, func_return_map, local_maps):
    - global_map: name -> {'numeric','string'} from explicit `name: Int`/
      `name: String`-shaped annotations anywhere (struct/class properties,
      tuple labels, function params) across every .swift file under Soma/.
      A name with conflicting types across the codebase (common short names
      like `value`/`count`) is intentionally left ambiguous.
    - func_return_map: function name -> 'numeric'/'string', from
      `func name(...) -> ReturnType` declarations (any return type outside
      those two buckets is just omitted, not tracked as ambiguous).
    - local_maps: {file path: {name -> {'numeric'} | {'string'} |
      {'numeric','string'}}} from that file's own `let/var x = <expr>`
      bindings -- scoped per-file, not per-function, so a name bound to two
      different types in two different functions in the same file comes
      back with BOTH kinds in its set (classify_expr treats that as
      'locally ambiguous' and stops there, rather than falling through to
      an unrelated global property of the same name)."""
    global_raw = {}

    def add_global(name, kind):
        global_raw.setdefault(name, set()).add(kind)

    func_return_map = {}
    file_texts = {}
    file_prop_raw = {}  # path -> {name: {kinds}} -- this file's own `name: Type` shapes
    for path in SOMA_SRC.rglob("*.swift"):
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        file_texts[path] = text
        prop_raw = {}
        for m in PROP_NUMERIC_RE.finditer(text):
            add_global(m.group(1), "numeric")
            prop_raw.setdefault(m.group(1), set()).add("numeric")
        for m in PROP_STRING_RE.finditer(text):
            add_global(m.group(1), "string")
            prop_raw.setdefault(m.group(1), set()).add("string")
        file_prop_raw[path] = prop_raw
        for m in FUNC_RETURN_RE.finditer(text):
            name, ret = m.group(1), m.group(2)
            if re.fullmatch(NUMERIC_TYPES, ret):
                func_return_map.setdefault(name, "numeric")
            elif ret == "String":
                func_return_map.setdefault(name, "string")

    global_map = {name: kinds for name, kinds in global_raw.items() if _single_kind(kinds)}

    local_maps = {}
    for path, text in file_texts.items():
        # Seed with this file's own `name: Type` shapes first (e.g. a
        # no-initializer `var freq: String` declared once, then assigned
        # conditionally later -- LOCAL_ASSIGN_RE below can't see a
        # declaration with no `=`, so without this seed it would be
        # invisible here even though it's genuinely this file's type for
        # that name) -- see build_type_maps' docstring on local ambiguity.
        local_raw = {name: set(kinds) for name, kinds in file_prop_raw[path].items()}
        for m in LOCAL_ASSIGN_RE.finditer(text):
            name, rhs = m.group(1), trim_rhs(m.group(2))
            kind = classify_expr(rhs, local_raw, global_map, func_return_map)
            if kind != "unknown":
                local_raw.setdefault(name, set()).add(kind)
        local_maps[path] = local_raw

    return global_map, func_return_map, local_maps


def extract_interpolations(default_value):
    """Ordered list of the Swift expressions inside each \\(...) in a
    defaultValue literal, paren-depth aware (so `\\(a.formatted())` doesn't
    truncate at the first `)`)."""
    out = []
    i = 0
    while True:
        idx = default_value.find('\\(', i)
        if idx == -1:
            break
        depth = 1
        j = idx + 2
        while j < len(default_value) and depth > 0:
            if default_value[j] == '(':
                depth += 1
            elif default_value[j] == ')':
                depth -= 1
            j += 1
        out.append(default_value[idx + 2:j - 1])
        i = j
    return out


def find_call_site_type_mismatches(catalog):
    """BUG-129 class: for every String(localized: KEY, defaultValue: "...")
    call site, pair each \\(expr) positionally against the catalog's `en`
    specifier list for KEY and flag numeric-typed expr <-> %@, or
    string-typed expr <-> a numeric specifier (%lld/%.1f/...) -- both
    directions crash the same way (Foundation formats the CATALOG's stored
    text, so a mismatched specifier there reads garbage off the real
    argument regardless of which direction it's wrong)."""
    global_map, func_return_map, local_maps = build_type_maps()
    mismatches = []
    seen_keys = set()  # first call site wins if a key is used from multiple places
    for path, local_map in local_maps.items():
        text = path.read_text(encoding="utf-8", errors="ignore")
        for m in CALL_SITE_RE.finditer(text):
            key, default_value = m.group("key"), m.group("default")
            if key in seen_keys:
                continue
            entry = catalog.get(key)
            if not entry:
                continue
            en = entry.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value")
            if not en:
                continue
            interps = extract_interpolations(default_value)
            if not interps:
                continue
            ref_sig = extract_signature(en)
            if not ref_sig or len(ref_sig) != len(interps):
                continue  # count mismatches are the cross-language check's job
            seen_keys.add(key)
            for (pos, conv), expr in zip(ref_sig, interps):
                kind = classify_expr(expr, local_map, global_map, func_return_map)
                if kind == "numeric" and conv in OBJECT_CONV:
                    mismatches.append((key, expr, conv, "numeric Swift value stored as %@ (object) in the catalog", str(path.relative_to(REPO_ROOT))))
                elif kind == "string" and conv in NUMBER_CONV:
                    mismatches.append((key, expr, conv, "String Swift value stored as a numeric specifier in the catalog", str(path.relative_to(REPO_ROOT))))
    return mismatches


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
    type_mismatches = find_call_site_type_mismatches(catalog)

    if as_json:
        print(json.dumps({
            "mismatches": problems,
            "orphan_percents": orphans,
            "call_site_type_mismatches": [
                {"key": k, "expr": e, "specifier": f"%{c}", "reason": r, "file": f}
                for k, e, c, r, f in type_mismatches
            ],
        }, ensure_ascii=False, indent=2))
    else:
        if not problems and not orphans and not type_mismatches:
            print(f"OK -- checked {sum(1 for e in catalog.values() if e.get('localizations'))} translated entries, "
                  f"format specifiers consistent across all languages, no orphan '%' characters, "
                  f"no call-site type mismatches found.")
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
        if type_mismatches:
            print(f"{len(type_mismatches)} call site(s) where the catalog's specifier type doesn't match the Swift argument (BUG-129 class):\n")
            for key, expr, conv, reason, file in type_mismatches:
                print(f"  KEY: {key!r}  ({file})")
                print(f"    \\({expr}) -> stored as %{conv}  <-- {reason}")
                print()
    sys.exit(1 if (problems or orphans or type_mismatches) else 0)


if __name__ == "__main__":
    main()
