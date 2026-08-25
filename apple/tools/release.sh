#!/usr/bin/env bash
# Archive, export and (optionally) upload a TestFlight build.
#
#   ./apple/tools/release.sh ios            # archive + export an .ipa
#   ./apple/tools/release.sh ios upload     # ...and send it to App Store Connect
#   ./apple/tools/release.sh macos
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
# The build number is the commit count, so it always increases — App Store
# Connect rejects a build number it has already seen, and hand-bumping one in
# project.yml is the kind of thing that gets forgotten exactly once.

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

BUILD_NUMBER="$(git -C "$APPLE_DIR" rev-list --count HEAD)"
ARCHIVE="${BUILD_DIR}/TimeTiles-${PLATFORM}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/${PLATFORM}"

echo "==> Team ${TEAM}, build ${BUILD_NUMBER}, ${PLATFORM}"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
mkdir -p "$BUILD_DIR"

# The project is generated, so regenerate before building from a clean checkout.
(cd "$APPLE_DIR" && xcodegen generate >/dev/null)

xcodebuild archive \
  -project "${APPLE_DIR}/Word.xcodeproj" \
  -scheme Word \
  -destination "$DESTINATION" \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
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
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates

PACKAGE="$(find "$EXPORT_DIR" -maxdepth 1 \( -name '*.ipa' -o -name '*.pkg' \) | head -1)"
echo "==> Built ${PACKAGE}"

if [ "$ACTION" != "upload" ]; then
  echo "==> Not uploading. Re-run with 'upload', or drop the package into Transporter."
  exit 0
fi

# Credentials can live in a gitignored file rather than being re-exported
# every shell, the same way the team id does.
ENV_FILE="${APPLE_DIR}/Local.env"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a; . "$ENV_FILE"; set +a
fi

if [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ]; then
  echo "ASC_KEY_ID and ASC_ISSUER_ID must be set to upload — see the notes at the" >&2
  echo "top of this script." >&2
  exit 1
fi

KEY_FILE="${HOME}/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
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
