#!/usr/bin/env bash
# Builds Notcher.app from the Swift package.
#   ./Scripts/build-app.sh            → build/Notcher.app (release)
#   ./Scripts/build-app.sh --zip      → also build/Notcher.zip
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
VERSION="${NOTCHER_VERSION:-0.1.0}"
BUILD="${NOTCHER_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
OUT="$ROOT/build"
APP="$OUT/Notcher.app"

echo "▸ Building Notcher $VERSION ($BUILD)"
swift build -c release --product Notcher
BIN="$(swift build -c release --product Notcher --show-bin-path)/Notcher"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Notcher"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"

# App icon from the 1024px master.
if [[ -f Resources/AppIcon.png ]] && command -v iconutil >/dev/null; then
  ICONSET="$OUT/AppIcon.iconset"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

# Ad-hoc signature so the app launches locally. Use your Developer ID to distribute.
codesign --force --deep --sign "${NOTCHER_SIGN_IDENTITY:--}" "$APP" >/dev/null
echo "▸ Built $APP"

if [[ "${1:-}" == "--zip" ]]; then
  (cd "$OUT" && rm -f Notcher.zip && ditto -c -k --keepParent Notcher.app Notcher.zip)
  echo "▸ Zipped $OUT/Notcher.zip"
fi
