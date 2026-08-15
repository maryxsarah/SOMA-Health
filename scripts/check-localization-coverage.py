#!/usr/bin/env python3
"""Cross-references source against Localizable.xcstrings (O-21, docs/bug-log.md).

Neither SwiftLint custom rule (.swiftlint.yml) can do this -- they see only
source syntax, not the catalog's contents. This is the "extract_keys.py-style"
permanent tool that BUG-106/107/119/123 each re-invented ad hoc.

Two independent checks:
  1. Every `String(localized: "key", ...)` call site -- the key must exist in
     the catalog with ALL 9 languages (including "en": these keys are rarely
     valid English text themselves).
  2. Every literal string passed to a LocalizedStringKey-typed call shape
     (Text("..."), Button("..."), .navigationTitle("..."), title: "...", etc.)
     -- the literal (used as the catalog key verbatim, SwiftUI's own
     convention) must exist in the catalog with all 8 non-English languages.
     "en" is not required here since the key already IS the English text --
     see [[xcstrings-manual-edit-needs-en]].

Broader than the SwiftLint `raw_localizable_literal` rule on purpose: that
rule requires an embedded space to cut noise, which is exactly why one-word
gaps ("Settings", "Streak", "Mood", ...) kept shipping untranslated (BUG-119,
BUG-123). This script has no such filter -- it relies on matching only
confirmed LocalizedStringKey call shapes instead, and filters out SF Symbol
identifiers (e.g. "flame.fill") structurally rather than by length/spacing.

Usage:
  scripts/check-localization-coverage.py            whole repo (Soma/), text report
  scripts/check-localization-coverage.py --json      machine-readable report
  scripts/check-localization-coverage.py path1 path2 scope to specific files/dirs

Exit code 1 if anything is missing/incomplete (for CI use later, per O-21).
"""
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = REPO_ROOT / "Soma/Resources/Localizable.xcstrings"
REQUIRED_NON_EN = {"de", "es", "fr", "hy", "it", "ka", "ru", "sr"}
REQUIRED_ALL = REQUIRED_NON_EN | {"en"}

# LocalizedStringKey call shapes actually used in this codebase (grepped from
# every `: LocalizedStringKey` declaration site -- not guessed).
POSITIONAL_CALLS = [
    "Text", "Button", "Label", "TextField", "Section", "Stepper", "DatePicker",
    "Picker", "SomaButton", "SomaChip", "ToolbarItem", "Toggle",
]
NAMED_PARAMS = [
    "title", "subtitle", "label", "headline", "eyebrow", "text", "sub",
    "prompt", "placeholder", "closedLabel", "openLabel", "ringUnit",
]

STRING_LIT = r'"((?:[^"\\]|\\.)*)"'
LOCALIZED_CALL_RE = re.compile(r'String\(localized:\s*' + STRING_LIT)
POSITIONAL_RE = re.compile(
    r'\b(?:' + "|".join(POSITIONAL_CALLS) + r')\(\s*' + STRING_LIT
)
NAV_TITLE_RE = re.compile(r'\.navigationTitle\(\s*' + STRING_LIT + r'\)')
NAMED_PARAM_RE = re.compile(
    r'\b(?:' + "|".join(NAMED_PARAMS) + r'):\s*' + STRING_LIT
)

SF_SYMBOL_RE = re.compile(r'^[a-z][a-zA-Z0-9]*(\.[a-zA-Z0-9]+)+$')  # "flame.fill"
FORMAT_ONLY_RE = re.compile(r'^[%\d\s./:\-]+$')  # "%.1f", "%02d", "/ 8"


def unescape(s):
    return s.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")


def is_noise(literal):
    if not literal or not literal[0].isalpha():
        return True
    if SF_SYMBOL_RE.match(literal):
        return True
    if FORMAT_ONLY_RE.match(literal):
        return True
    return False


def strip_previews(text):
    """Blank out #Preview { ... } blocks (Xcode canvas only, never shown to
    real users) so their placeholder strings don't count as production gaps.
    Preserves byte offsets/line numbers by replacing with spaces/newlines."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        m = re.compile(r'#Preview\b').search(text, i)
        if not m:
            out.append(text[i:])
            break
        out.append(text[i:m.start()])
        j = text.find("{", m.end())
        if j == -1:
            out.append(text[m.start():])
            break
        out.append(" " * (j + 1 - m.start()))
        depth = 1
        k = j + 1
        while k < n and depth > 0:
            if text[k] == "{":
                depth += 1
            elif text[k] == "}":
                depth -= 1
            k += 1
        block = text[j + 1:k]
        out.append("\n" * block.count("\n"))  # keep line numbers aligned, drop content
        i = k
    return "".join(out)


def strip_interpolated(text):
    """Regex can't compute the compiled catalog key for Swift string
    interpolation (\\(expr) becomes a type-dependent format specifier, not
    literal text) -- blank those string literals out rather than report a
    guaranteed-wrong key."""
    return re.sub(r'"(?:[^"\\]|\\.)*\\\((?:[^"\\]|\\.)*"', '""', text)


def scan_file(path, rel_path):
    text = path.read_text(encoding="utf-8", errors="replace")
    text = strip_previews(text)
    text = strip_interpolated(text)
    hits = []  # (key, kind, line_no)

    def record_all(pattern, kind):
        for m in pattern.finditer(text):
            key = unescape(m.group(1))
            if kind != "localized_call" and is_noise(key):
                continue
            if not key.strip():
                continue
            line_no = text.count("\n", 0, m.start()) + 1
            hits.append((key, kind, line_no))

    record_all(LOCALIZED_CALL_RE, "localized_call")
    record_all(POSITIONAL_RE, "literal_key")
    record_all(NAV_TITLE_RE, "literal_key")
    record_all(NAMED_PARAM_RE, "literal_key")
    return hits


def main():
    args = [a for a in sys.argv[1:] if a != "--json"]
    as_json = "--json" in sys.argv[1:]
    targets = [REPO_ROOT / a for a in args] if args else [REPO_ROOT / "Soma"]

    with open(CATALOG_PATH, encoding="utf-8") as f:
        catalog = json.load(f)["strings"]

    findings = {}  # key -> {"kind":.., "sites": [(file,line)], "status":.., "missing_langs": set}

    swift_files = []
    for target in targets:
        if target.is_file() and target.suffix == ".swift":
            swift_files.append(target)
        elif target.is_dir():
            swift_files.extend(sorted(target.rglob("*.swift")))

    for path in swift_files:
        rel = path.relative_to(REPO_ROOT)
        if any(part in {"Tests", "SnapshotTests", "UITests", "DerivedData"} for part in rel.parts):
            continue
        for key, kind, line_no in scan_file(path, rel):
            entry = findings.setdefault(key, {"kind": kind, "sites": [], "status": None, "missing_langs": set()})
            entry["sites"].append(f"{rel}:{line_no}")
            if kind == "localized_call":
                entry["kind"] = "localized_call"  # localized_call wins if seen via both paths

    identifier_shaped = re.compile(r'^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z0-9]+)+$')
    for key, entry in findings.items():
        # "en" is only required when the key ISN'T itself displayable English
        # text (a dotted identifier like "profile.hub.notifications.off") --
        # plain-literal keys (LocalizedStringKey convention, e.g. "Settings",
        # "TODAY", "kcal") fall back to the key text correctly with no "en"
        # block, regardless of which API happened to look them up.
        required = REQUIRED_ALL if identifier_shaped.match(key) else REQUIRED_NON_EN
        cat_entry = catalog.get(key)
        if cat_entry is None or not cat_entry.get("localizations"):
            entry["status"] = "MISSING"
            entry["missing_langs"] = required
        else:
            have = set(cat_entry["localizations"].keys())
            missing = required - have
            if missing:
                entry["status"] = "INCOMPLETE"
                entry["missing_langs"] = missing
            else:
                entry["status"] = "OK"

    problems = {k: v for k, v in findings.items() if v["status"] != "OK"}

    if as_json:
        out = {k: {**v, "missing_langs": sorted(v["missing_langs"]), "sites": v["sites"]} for k, v in problems.items()}
        print(json.dumps(out, ensure_ascii=False, indent=2))
    else:
        if not problems:
            print(f"OK -- {len(findings)} distinct localizable strings checked, all fully translated.")
        else:
            missing = {k: v for k, v in problems.items() if v["status"] == "MISSING"}
            incomplete = {k: v for k, v in problems.items() if v["status"] == "INCOMPLETE"}
            print(f"Checked {len(findings)} distinct localizable strings across {len(swift_files)} files.")
            print(f"{len(missing)} MISSING entirely, {len(incomplete)} INCOMPLETE (partial language coverage).\n")
            for status, group in (("MISSING", missing), ("INCOMPLETE", incomplete)):
                if not group:
                    continue
                print(f"=== {status} ({len(group)}) ===")
                for key, entry in sorted(group.items(), key=lambda kv: kv[1]["sites"][0]):
                    langs = ",".join(sorted(entry["missing_langs"]))
                    sites = "; ".join(entry["sites"][:3])
                    more = f" (+{len(entry['sites']) - 3} more)" if len(entry["sites"]) > 3 else ""
                    print(f"  [{langs}] {key!r}")
                    print(f"      {sites}{more}")
                print()

    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
