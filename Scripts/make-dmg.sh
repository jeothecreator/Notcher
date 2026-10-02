#!/usr/bin/env bash
# Packs build/Notcher.app into build/Notcher.dmg (open it, drag Notcher to
# Applications). Run ./Scripts/build-app.sh first.
#
# Without credentials the DMG is unsigned, and macOS asks people to approve
# the app in System Settings the first time. To make one that opens on any
# Mac without warnings, sign and notarize it with your Developer ID:
#
#   NOTCHER_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   plus either
#     NOTARY_PROFILE=notcher      (saved with: xcrun notarytool store-credentials notcher)
#   or
#     NOTARY_APPLE_ID, NOTARY_TEAM_ID and NOTARY_PASSWORD (an app-specific password)
#
# Writes the outcome (notarized, signed or unsigned) to build/dmg-status.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Notcher.app"
DMG="build/Notcher.dmg"
IDENTITY="${NOTCHER_SIGN_IDENTITY:--}"

if [[ ! -d "$APP" ]]; then
  echo "No $APP yet. Run ./Scripts/build-app.sh first." >&2
  exit 1
fi

has_notary_credentials() {
  [[ -n "${NOTARY_PROFILE:-}" ]] ||
    [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_TEAM_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]
}

# Submits a file to Apple's notary service and waits for the verdict.
notarize() {
  local file="$1"
  local auth=()
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    auth=(--keychain-profile "$NOTARY_PROFILE")
  else
    auth=(--apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD")
  fi
  echo "▸ Notarizing $(basename "$file") (usually a few minutes)"
  xcrun notarytool submit "$file" "${auth[@]}" --wait --timeout 30m --output-format json > build/notary.json || true
  local status id
  status="$(plutil -extract status raw -o - build/notary.json 2>/dev/null || echo "no answer")"
  id="$(plutil -extract id raw -o - build/notary.json 2>/dev/null || echo "")"
  if [[ "$status" != "Accepted" ]]; then
    echo "✗ Apple's notary service returned: $status" >&2
    cat build/notary.json >&2 || true
    if [[ -n "$id" ]]; then
      xcrun notarytool log "$id" "${auth[@]}" >&2 || true
    fi
    exit 1
  fi
  echo "▸ Notarized ($id)"
}

STATUS="unsigned"
if [[ "$IDENTITY" != "-" ]]; then
  STATUS="signed"
  if has_notary_credentials; then
    # Notarize the app itself and staple the ticket, so it also opens offline
    # once it's been copied out of the DMG.
    ditto -c -k --keepParent "$APP" build/Notcher-notarize.zip
    notarize build/Notcher-notarize.zip
    rm -f build/Notcher-notarize.zip
    xcrun stapler staple "$APP"
  else
    echo "▸ No notary credentials: signing without notarizing"
  fi
fi

echo "▸ Making $DMG"
STAGE="build/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Notcher.app"
ln -s /Applications "$STAGE/Applications"
# hdiutil occasionally reports "Resource busy" on CI machines; try again.
for attempt in 1 2 3; do
  if hdiutil create -volname "Notcher" -srcfolder "$STAGE" -fs HFS+ -format UDZO \
      -imagekey zlib-level=9 -ov "$DMG" >/dev/null; then
    break
  fi
  if [[ "$attempt" == 3 ]]; then
    echo "✗ hdiutil couldn't create the disk image" >&2
    exit 1
  fi
  sleep 3
done
rm -rf "$STAGE"

if [[ "$IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  if has_notary_credentials; then
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    STATUS="notarized"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" || true
  fi
fi

echo "$STATUS" > build/dmg-status
echo "▸ Built $DMG ($STATUS)"
