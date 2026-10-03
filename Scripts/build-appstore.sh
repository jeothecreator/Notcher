#!/usr/bin/env bash
# Builds Notcher for the Mac App Store: a sandboxed, universal app signed for
# App Store distribution and wrapped in a signed installer package,
# build/Notcher.pkg. Upload that with Apple's Transporter app, or pass
# --upload to send it to App Store Connect from here.
#
# You need, from your Apple Developer account (AppStore/README.md walks
# through each one):
#   - an "Apple Distribution" certificate (or the older "3rd Party Mac
#     Developer Application") in your keychain
#   - a "3rd Party Mac Developer Installer" certificate (shown as "Mac
#     Installer Distribution" on the developer site) in your keychain
#   - a Mac App Store provisioning profile for Notcher's App ID
#
#   APPSTORE_PROFILE=~/Downloads/Notcher.provisionprofile ./Scripts/build-appstore.sh
#
# The bundle ID and team come from the profile. Optional:
#   APPSTORE_APP_IDENTITY, APPSTORE_INSTALLER_IDENTITY   pick certificates by name
#   NOTCHER_BUILD                                        build number (must go up with every upload)
#   --upload   send the package to App Store Connect with an API key:
#              APPSTORE_API_KEY_ID, APPSTORE_API_ISSUER_ID, and the key file
#              AuthKey_<KEY_ID>.p8 in ~/.appstoreconnect/private_keys/
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Notcher.app"
PKG="build/Notcher.pkg"
UPLOAD=0
if [[ "${1:-}" == "--upload" ]]; then UPLOAD=1; fi

fail() {
  echo "✗ $*" >&2
  exit 1
}

# MARK: Provisioning profile

PROFILE="${APPSTORE_PROFILE:-}"
[[ -n "$PROFILE" && -f "$PROFILE" ]] ||
  fail "Set APPSTORE_PROFILE to your Mac App Store provisioning profile (a .provisionprofile file)."

mkdir -p build
security cms -D -i "$PROFILE" > build/profile.plist 2>/dev/null || fail "Couldn't read $PROFILE as a provisioning profile."
plist() { /usr/libexec/PlistBuddy -c "Print :$1" build/profile.plist 2>/dev/null; }

TEAM_ID="$(plist TeamIdentifier:0)" || fail "The profile has no team identifier."
FULL_APP_ID="$(plist Entitlements:com.apple.application-identifier)" || fail "The profile has no application identifier."
BUNDLE_ID="${FULL_APP_ID#"$TEAM_ID".}"
[[ "$BUNDLE_ID" != *"*"* ]] ||
  fail "This profile is for a wildcard App ID ($FULL_APP_ID). Create one for Notcher's own App ID, e.g. $TEAM_ID.app.notcher.Notcher."
if plist ProvisionedDevices >/dev/null || plist ProvisionsAllDevices >/dev/null; then
  fail "This is a development or Developer ID profile. Create a Mac App Store distribution profile instead."
fi
echo "▸ Profile: $(plist Name) — bundle ID $BUNDLE_ID, team $TEAM_ID"

# MARK: Certificates

# First identity of the given kinds that belongs to this team.
find_identity() {
  security find-identity -v -p "$1" 2>/dev/null |
    grep -oE "\"($2): [^\"]*\\($TEAM_ID\\)\"" | head -1 | tr -d '"' || true
}
APP_IDENTITY="${APPSTORE_APP_IDENTITY:-$(find_identity codesigning 'Apple Distribution|3rd Party Mac Developer Application')}"
INSTALLER_IDENTITY="${APPSTORE_INSTALLER_IDENTITY:-$(find_identity basic '3rd Party Mac Developer Installer|Mac Installer Distribution')}"
[[ -n "$APP_IDENTITY" ]] ||
  fail "No \"Apple Distribution\" certificate for team $TEAM_ID in your keychain."
[[ -n "$INSTALLER_IDENTITY" ]] ||
  fail "No \"3rd Party Mac Developer Installer\" (Mac Installer Distribution) certificate for team $TEAM_ID in your keychain."

# MARK: Build and sign

XCODE_INFO="$(xcodebuild -version 2>/dev/null)" ||
  fail "App Store builds need Xcode (not just the command line tools). Install it, then: sudo xcode-select -s /Applications/Xcode.app"
XCODE_VERSION="$(awk 'NR==1 {print $2}' <<< "$XCODE_INFO")"
XCODE_BUILD="$(awk 'NR==2 {print $3}' <<< "$XCODE_INFO")"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
SDK_BUILD="$(xcrun --sdk macosx --show-sdk-build-version)"
echo "▸ Xcode $XCODE_VERSION, macOS $SDK_VERSION SDK"
if (( ${SDK_VERSION%%.*} < 26 )); then
  echo "! App Store Connect only accepts apps built with Xcode 26 (the macOS 26 SDK) or later." >&2
fi

NOTCHER_SANDBOX=1 NOTCHER_UNIVERSAL=1 NOTCHER_BUNDLE_ID="$BUNDLE_ID" ./Scripts/build-app.sh
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
# Moves saves and ROMs from an earlier download of Notcher into the sandbox
# container the first time the App Store version starts.
cp Resources/container-migration.plist "$APP/Contents/Resources/"

# Xcode stamps these into every app it builds, and App Store Connect reads
# them to check which Xcode and SDK made the app.
INFO="$APP/Contents/Info.plist"
stamp() {
  /usr/libexec/PlistBuddy -c "Delete :$1" "$INFO" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$INFO"
}
IFS=. read -r XCODE_MAJOR XCODE_MINOR XCODE_PATCH <<< "$XCODE_VERSION"
stamp DTXcode "$(printf '%d%d%d' "$XCODE_MAJOR" "${XCODE_MINOR:-0}" "${XCODE_PATCH:-0}")"
stamp DTXcodeBuild "$XCODE_BUILD"
stamp DTSDKName "macosx$SDK_VERSION"
stamp DTSDKBuild "$SDK_BUILD"
stamp DTPlatformName macosx
stamp DTPlatformVersion "$SDK_VERSION"
stamp DTPlatformBuild "$SDK_BUILD"
stamp DTCompiler com.apple.compilers.llvm.clang.1_0
stamp BuildMachineOSBuild "$(sw_vers -buildVersion)"
/usr/libexec/PlistBuddy -c "Delete :CFBundleSupportedPlatforms" "$INFO" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms array" -c "Add :CFBundleSupportedPlatforms:0 string MacOSX" "$INFO"

# The sandbox entitlements plus the identifiers the profile grants.
cp Resources/Notcher.entitlements build/appstore.entitlements
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $FULL_APP_ID" build/appstore.entitlements
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" build/appstore.entitlements

echo "▸ Signing the app as $APP_IDENTITY"
codesign --force --timestamp --sign "$APP_IDENTITY" --entitlements build/appstore.entitlements "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "▸ Entitlements:"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - 2>/dev/null || codesign -d --entitlements :- "$APP"

echo "▸ Packaging as $INSTALLER_IDENTITY"
rm -f "$PKG"
productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"
pkgutil --check-signature "$PKG" | head -3

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
echo "▸ Built $PKG — Notcher $VERSION (build $BUILD), $BUNDLE_ID"

# MARK: Upload

if [[ "$UPLOAD" == "1" ]]; then
  [[ -n "${APPSTORE_API_KEY_ID:-}" && -n "${APPSTORE_API_ISSUER_ID:-}" ]] ||
    fail "Set APPSTORE_API_KEY_ID and APPSTORE_API_ISSUER_ID to upload (or upload $PKG with Transporter)."
  AUTH=(--apiKey "$APPSTORE_API_KEY_ID" --apiIssuer "$APPSTORE_API_ISSUER_ID")
  echo "▸ Validating with App Store Connect"
  xcrun altool --validate-app -f "$PKG" -t macos "${AUTH[@]}"
  echo "▸ Uploading to App Store Connect"
  xcrun altool --upload-app -f "$PKG" -t macos "${AUTH[@]}"
  echo "▸ Uploaded. The build shows up in App Store Connect (TestFlight tab) after Apple processes it, usually within 30 minutes."
else
  echo "Next: open Transporter, sign in, drag in $PKG and click Deliver. Or run this script again with --upload."
fi
