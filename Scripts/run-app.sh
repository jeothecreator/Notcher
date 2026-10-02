#!/usr/bin/env bash
# Opens build/Notcher.app, quitting any Notcher that's already running first.
# Notcher lives in the menu bar, so an older copy keeps running in the
# background; without this, `open` would just bring that old copy forward
# instead of launching the build you just made.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Notcher.app"

if pgrep -x Notcher >/dev/null 2>&1; then
  echo "▸ Quitting the Notcher that's already running"
  pkill -TERM -x Notcher 2>/dev/null || true
  for _ in $(seq 1 50); do
    pgrep -x Notcher >/dev/null 2>&1 || break
    sleep 0.1
  done
  pkill -KILL -x Notcher 2>/dev/null || true
fi

open "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo '?')"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist" 2>/dev/null || echo '?')"
echo "▸ Opened Notcher $VERSION (build $BUILD). Hover the notch to play, or drag a ROM onto it."
