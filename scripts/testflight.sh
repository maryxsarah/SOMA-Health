#!/usr/bin/env bash
#
# One-command TestFlight upload.
#
#   1. Bumps CFBundleVersion in project.yml (+1) -- Apple rejects re-uploading
#      the same build number under the same CFBundleShortVersionString.
#   2. Regenerates Soma.xcodeproj (pinned XcodeGen 2.42.0, per SETUP.md).
#   3. Archives Release for a generic iOS device, creating/downloading the
#      provisioning profile headlessly via the App Store Connect API key
#      (-allowProvisioningUpdates) -- no interactive Xcode login required.
#   4. Exports + uploads the build to App Store Connect / TestFlight.
#
# Credentials are read from scripts/asc-api.env (gitignored). Copy
# scripts/asc-api.env.example and fill it in first. See
# scripts/README-testflight.md for where to get the API key.
#
# Usage:
#   scripts/testflight.sh              # bump, archive, upload
#   scripts/testflight.sh --no-bump    # keep current build number
#   scripts/testflight.sh --archive-only   # build the archive, skip upload

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="Soma"
PROJECT="Soma.xcodeproj"
ARCHIVE_PATH="build/Soma.xcarchive"
EXPORT_PATH="build/export"
ENV_FILE="scripts/asc-api.env"
EXPORT_OPTIONS="scripts/ExportOptions.plist"

# Prefer the pinned XcodeGen (SETUP.md), fall back to whatever is on PATH.
if [[ -x "./.xcodegen-2.42.0/bin/xcodegen" ]]; then
    XCODEGEN="./.xcodegen-2.42.0/bin/xcodegen"
elif command -v xcodegen >/dev/null 2>&1; then
    XCODEGEN="$(command -v xcodegen)"
else
    echo "error: xcodegen not found (expected ./.xcodegen-2.42.0/bin/xcodegen or on PATH)." >&2
    echo "       See SETUP.md section 1." >&2
    exit 1
fi

BUMP=1
UPLOAD=1
for arg in "$@"; do
    case "$arg" in
        --no-bump) BUMP=0 ;;
        --archive-only) UPLOAD=0 ;;
        *) echo "error: unknown argument '$arg'" >&2; exit 1 ;;
    esac
done

# --- credentials -----------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
    echo "error: $ENV_FILE not found." >&2
    echo "       cp scripts/asc-api.env.example $ENV_FILE  and fill it in." >&2
    exit 1
fi
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
: "${ASC_KEY_ID:?set ASC_KEY_ID in $ENV_FILE}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID in $ENV_FILE}"
: "${ASC_KEY_PATH:?set ASC_KEY_PATH in $ENV_FILE}"
# Expand a leading ~ so the .p8 can live in ~/.appstoreconnect/private_keys.
ASC_KEY_PATH="${ASC_KEY_PATH/#\~/$HOME}"
if [[ ! -f "$ASC_KEY_PATH" ]]; then
    echo "error: API key not found at ASC_KEY_PATH=$ASC_KEY_PATH" >&2
    exit 1
fi

# --- bump build number (source of truth is project.yml) --------------------
CURRENT="$(grep -E '^[[:space:]]*CFBundleVersion:' project.yml | grep -oE '[0-9]+' | head -1)"
if [[ -z "$CURRENT" ]]; then
    echo "error: could not read CFBundleVersion from project.yml" >&2
    exit 1
fi
if [[ "$BUMP" -eq 1 ]]; then
    NEXT=$((CURRENT + 1))
    # BSD sed (macOS) in-place edit; only the CFBundleVersion line, not
    # CFBundleShortVersionString.
    sed -i.bak -E "s/^([[:space:]]*CFBundleVersion:[[:space:]]*)\"[0-9]+\"/\1\"$NEXT\"/" project.yml
    rm -f project.yml.bak
    echo "==> Build number: $CURRENT -> $NEXT"
else
    NEXT="$CURRENT"
    echo "==> Build number: $NEXT (unchanged)"
fi

# --- regenerate project ----------------------------------------------------
echo "==> Regenerating $PROJECT with $XCODEGEN"
"$XCODEGEN" generate

# --- archive ---------------------------------------------------------------
echo "==> Archiving (Release, generic/platform=iOS)"
rm -rf "$ARCHIVE_PATH"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"

if [[ "$UPLOAD" -eq 0 ]]; then
    echo "==> Archive ready at $ARCHIVE_PATH (upload skipped)."
    exit 0
fi

# --- export + upload -------------------------------------------------------
echo "==> Exporting and uploading build $NEXT to TestFlight"
rm -rf "$EXPORT_PATH"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo ""
echo "==> Uploaded build $NEXT (version 1.0) to App Store Connect."
echo "    Processing takes a few minutes to ~1h; you'll get an email, then it"
echo "    appears under TestFlight. Commit the bump when you're happy:"
echo "      git add project.yml && git commit -m \"Bump build number to $NEXT for TestFlight upload\""
