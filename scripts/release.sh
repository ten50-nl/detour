#!/bin/zsh
# Builds a universal, Developer ID signed and notarized Detour.dmg.
# Usage: scripts/release.sh <version> [--publish]
#   --publish  create the GitHub release and update the Homebrew cask in ten50-nl/homebrew-tap
# Needs: a "Developer ID Application" certificate in the keychain and a notarytool keychain profile
#   (xcrun notarytool store-credentials detour-notary --apple-id <id> --team-id <team>).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/release.sh <version> [--publish]}
PUBLISH=${2:-}
IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}
PROFILE=${NOTARY_PROFILE:-detour-notary}
REPO=ten50-nl/detour
TAP=ten50-nl/homebrew-tap
OUT=build/release
APP=$OUT/Detour.app
DMG=$OUT/Detour.dmg

[[ -n "$IDENTITY" ]] || { echo "no Developer ID Application certificate found" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "uncommitted changes" >&2; exit 1; }
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 || {
  echo "notary profile '$PROFILE' missing: xcrun notarytool store-credentials $PROFILE --apple-id <id> --team-id <team>" >&2; exit 1; }

swift test
command -v xcodegen >/dev/null && xcodegen generate --quiet
rm -rf "$OUT"
xcodebuild -project Detour.xcodeproj -scheme Detour -configuration Release -derivedDataPath build/xc \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY="$IDENTITY" build -quiet
mkdir -p "$OUT"
ditto build/xc/Build/Products/Release/Detour.app "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$APP/Contents/Info.plist"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --deep "$APP"

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Detour -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG"

cp "$DMG" "$OUT/Detour-$VERSION.dmg"
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
echo "built $DMG ($VERSION) sha256 $SHA"

if [[ "$PUBLISH" == "--publish" ]]; then
  git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && { echo "tag v$VERSION exists" >&2; exit 1; }
  git tag -m "Detour $VERSION" "v$VERSION"
  git push origin "v$VERSION"
  NOTES=$(awk "/^## $VERSION/{f=1;next}/^## /{f=0}f" CHANGELOG.md)
  gh release create "v$VERSION" "$DMG" "$OUT/Detour-$VERSION.dmg" --repo "$REPO" --title "Detour $VERSION" --notes "$NOTES"
  TMP=$(mktemp -d)
  git clone -q "https://github.com/$TAP.git" "$TMP"
  mkdir -p "$TMP/Casks"
  sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$SHA/" scripts/cask.rb.template > "$TMP/Casks/detour.rb"
  git -C "$TMP" add Casks/detour.rb
  git -C "$TMP" -c user.name="$(git config user.name)" -c user.email="$(git config user.email)" commit -qm "feat: detour $VERSION"
  git -C "$TMP" push -q
  rm -rf "$TMP"
  SITE=../detour.ten50.nl
  if [[ -f "$SITE/public/index.html" ]]; then
    sed -i '' -E "s/\"softwareVersion\": \"[0-9.]+\"/\"softwareVersion\": \"$VERSION\"/" "$SITE/public/index.html"
    if [[ -n "$(git -C "$SITE" status --porcelain)" ]]; then
      git -C "$SITE" commit -qam "feat: version $VERSION"
      git -C "$SITE" push -q
      echo "website updated to $VERSION"
    fi
  fi
  echo "published v$VERSION"
fi
