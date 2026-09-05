#!/usr/bin/env bash
# Archive, export and (optionally) upload a TestFlight build.
#
#   ./apple/tools/release.sh ios            # archive + export an .ipa
#   ./apple/tools/release.sh ios upload     # ...and send it to App Store Connect
#   ./apple/tools/release.sh macos
#
# This is also what CI runs (.github/workflows/release.yml) — the runner writes
# the same two gitignored files a developer keeps, so there is one release path
# rather than a CI copy of one that drifts out of step.
#
# Before the first upload you need, once:
#
#   1. An app record in App Store Connect for dev.nana.TimeTiles. Apps can't be
#      created from the CLI — App Store Connect → Apps → +.
#   2. An App Store Connect API key (Users and Access → Integrations → keys),
#      with the .p8 saved as ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8,
#      and its two ids either exported or dropped in apple/Local.env
#      (gitignored, and read automatically):
#
#        ASC_KEY_ID=XXXXXXXXXX
#        ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#
# The build number comes from tools/next-build-number.py: the commit count,
# raised past anything App Store Connect has already accepted. Hand-bumping a
# field in project.yml is the kind of thing that gets forgotten exactly once,
# and the commit count alone goes *backwards* over a squash merge.

set -euo pipefail

PLATFORM="${1:-ios}"
ACTION="${2:-export}"
HERE="$(cd "$(dirname "$0")" && pwd)"
APPLE_DIR="$(dirname "$HERE")"
BUILD_DIR="${APPLE_DIR}/.release"

case "$PLATFORM" in
  ios)   DESTINATION="generic/platform=iOS"; ALTOOL_TYPE="ios" ;;
  macos) DESTINATION="generic/platform=macOS"; ALTOOL_TYPE="macos" ;;
  *) echo "usage: release.sh [ios|macos] [export|upload]" >&2; exit 2 ;;
esac

# The team id lives in Local.xcconfig (gitignored), same as for a debug build.
CONFIG="${APPLE_DIR}/Local.xcconfig"
if [ ! -f "$CONFIG" ]; then
  echo "No ${CONFIG}. Run ./apple/bootstrap.sh and add your Team ID." >&2
  exit 1
fi
TEAM="$(sed -n 's/^WORD_DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*//p' "$CONFIG" | tr -d '[:space:]')"
if [ -z "$TEAM" ]; then
  echo "WORD_DEVELOPMENT_TEAM is empty in ${CONFIG}." >&2
  exit 1
fi

# Credentials can live in a gitignored file rather than being re-exported every
# shell, the same way the team id does. Sourced before the archive, not just
# before the upload, because the build number is derived from what App Store
# Connect already holds.
ENV_FILE="${APPLE_DIR}/Local.env"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a; . "$ENV_FILE"; set +a
fi

KEY_FILE="${HOME}/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID:-missing}.p8"

# Given the API key, xcodebuild can issue and download the signing assets
# itself instead of asking an Apple ID that a CI runner hasn't got signed in.
# Locally it saves the same trip through Xcode's UI.
AUTH=()
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -f "$KEY_FILE" ]; then
  AUTH=(-authenticationKeyPath "$KEY_FILE"
        -authenticationKeyID "$ASC_KEY_ID"
        -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

# The number has to be stamped into the archive, so it is settled before it.
BUILD_NUMBER="$("${HERE}/next-build-number.py")"
ARCHIVE="${BUILD_DIR}/TimeTiles-${PLATFORM}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/${PLATFORM}"

echo "==> Team ${TEAM}, build ${BUILD_NUMBER}, ${PLATFORM}"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
mkdir -p "$BUILD_DIR"

# The project is generated, so regenerate before building from a clean checkout.
(cd "$APPLE_DIR" && xcodegen generate >/dev/null)

# How the export signs. With an API key and no Apple ID signed into Xcode,
# automatic signing reaches for Apple's cloud-managed distribution certificate
# and fails if the key isn't allowed one ("Cloud signing permission error") —
# which is the runner's situation. So on iOS the export signs *manually*, with
# the distribution certificate in the keychain and an App Store profile that
# ensure-profile.py finds or creates through the API. If that can't be done
# (no API key, no matching certificate — a laptop signed into Xcode, say),
# automatic signing is left to work the way it always has.
SIGNING=""
if [ "$PLATFORM" = "ios" ] && [ ${#AUTH[@]} -gt 0 ]; then
  if PROFILE="$("${HERE}/ensure-profile.py" ios)"; then
    echo "==> Signing with the keychain's distribution certificate and profile \"${PROFILE}\""
    SIGNING="	<key>signingStyle</key><string>manual</string>
	<key>signingCertificate</key><string>Apple Distribution</string>
	<key>provisioningProfiles</key>
	<dict>
		<key>dev.nana.TimeTiles</key><string>${PROFILE}</string>
	</dict>"
  else
    echo "==> No App Store profile could be ensured; exporting with automatic signing."
  fi
fi

# The archive's signature is thrown away when the export re-signs, so when the
# export is going to sign manually the archive needs no identity whatsoever.
# That matters on a runner: automatic signing insists on a *development*
# identity to produce that throwaway signature, the fresh keychain hasn't got
# one, and -allowProvisioningUpdates duly asks Apple for a new certificate on
# every single run. Ad-hoc signing is not the answer — iOS refuses to archive
# without a real profile even when the signature is discarded.
if [ -n "$SIGNING" ]; then
  ARCHIVE_SIGNING=(CODE_SIGNING_ALLOWED=NO)
else
  ARCHIVE_SIGNING=(-allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"})
fi

xcodebuild archive \
  -project "${APPLE_DIR}/Word.xcodeproj" \
  -scheme Word \
  -destination "$DESTINATION" \
  -archivePath "$ARCHIVE" \
  ${ARCHIVE_SIGNING[@]+"${ARCHIVE_SIGNING[@]}"} \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

cat > "${BUILD_DIR}/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>teamID</key><string>${TEAM}</string>
	<key>uploadSymbols</key><true/>
	<key>destination</key><string>export</string>
${SIGNING}
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  ${AUTH[@]+"${AUTH[@]}"}

PACKAGE="$(find "$EXPORT_DIR" -maxdepth 1 \( -name '*.ipa' -o -name '*.pkg' \) | head -1)"
echo "==> Built ${PACKAGE}"

if [ "$ACTION" != "upload" ]; then
  echo "==> Not uploading. Re-run with 'upload', or drop the package into Transporter."
  exit 0
fi

if [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ]; then
  echo "ASC_KEY_ID and ASC_ISSUER_ID must be set to upload — see the notes at the" >&2
  echo "top of this script." >&2
  exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
  echo "No ${KEY_FILE}." >&2
  echo "The .p8 downloads once and only once — if it's lost, revoke the key and" >&2
  echo "make a new one." >&2
  exit 1
fi

echo "==> Validating"
xcrun altool --validate-app -f "$PACKAGE" -t "$ALTOOL_TYPE" \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo "==> Uploading"
xcrun altool --upload-app -f "$PACKAGE" -t "$ALTOOL_TYPE" \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo "==> Uploaded. App Store Connect takes a few minutes to process it, then it"
echo "    appears under TestFlight."
