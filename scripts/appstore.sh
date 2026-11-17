#!/bin/zsh
# Builds the sandboxed App Store edition and uploads it to App Store Connect.
# Usage: scripts/appstore.sh <version> [--upload]
# Needs Xcode signed in with the team's Apple ID (Xcode → Settings → Accounts) and an app record in App Store Connect.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/appstore.sh <version> [--upload]}
BUILD=$(date +%Y%m%d%H%M)
OUT=build/appstore
TEAM=$(awk -F': ' '/DEVELOPMENT_TEAM/ {print $2; exit}' project.yml)

swift test
command -v xcodegen >/dev/null && xcodegen generate --quiet
rm -rf "$OUT"
xcodebuild -project Detour.xcodeproj -scheme "Detour (App Store)" -configuration Release \
  -archivePath "$OUT/Detour.xcarchive" -allowProvisioningUpdates \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" archive -quiet

DESTINATION=export
[[ "${2:-}" == "--upload" ]] && DESTINATION=upload
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$DESTINATION</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/Detour.xcarchive" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" -allowProvisioningUpdates
echo "App Store build $VERSION ($BUILD): $DESTINATION done"
