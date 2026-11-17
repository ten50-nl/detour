#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${SIGN_IDENTITY:--}"
APP=build/Detour.app

swift build -c release --product Detour
BIN=$(swift build -c release --show-bin-path)/Detour

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Detour"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
echo "built $APP"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e 'tell application id "nl.ten50.detour" to quit' 2>/dev/null || true
  pkill -x Detour 2>/dev/null || true
  sleep 1
  rm -rf /Applications/Detour.app
  cp -R "$APP" /Applications/Detour.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Detour.app
  open /Applications/Detour.app
  echo "installed /Applications/Detour.app"
fi
