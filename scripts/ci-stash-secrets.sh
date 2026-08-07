#!/usr/bin/env bash
#
# One-time (or whenever secrets change): copy this working copy's gitignored
# secrets into ~/.soma-ci so the self-hosted GitHub Actions runner can restore
# them into its fresh checkout. See scripts/README-testflight.md.
#
# Run this from a normal local clone that already has the real secret files.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

STASH="$HOME/.soma-ci"
mkdir -p "$STASH"

copy() {
    local src="$1"
    if [[ ! -f "$src" ]]; then
        echo "error: missing $src -- fill it in locally first (see SETUP.md)." >&2
        exit 1
    fi
    cp "$src" "$STASH/$(basename "$src")"
    echo "  stashed $(basename "$src")"
}

# Optional: skip (don't fail) if absent. AppDelegate guards Firebase on this
# file's presence, so the app builds fine without it -- analytics just stays off.
copy_optional() {
    local src="$1"
    if [[ -f "$src" ]]; then
        cp "$src" "$STASH/$(basename "$src")"
        echo "  stashed $(basename "$src")"
    else
        echo "  skipped $(basename "$src") (not present locally -- Firebase analytics will be off)"
    fi
}

echo "Stashing secrets into $STASH:"
copy "Config/Config-Debug.xcconfig"
copy "Config/Config-Release.xcconfig"
copy "scripts/asc-api.env"
copy_optional "Soma/Resources/GoogleService-Info.plist"

echo "Done. The .p8 key stays at the absolute ASC_KEY_PATH in scripts/asc-api.env"
echo "(recommended: ~/.appstoreconnect/private_keys/) and is read from there directly."
