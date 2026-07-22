#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"

version="${1:-}"
build="${2:-}"
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' || ! "$build" =~ '^[1-9][0-9]*$' ]]; then
  echo "Usage: ./scripts/release-artifacts.sh <version> <build>" >&2
  exit 1
fi

signing_identity="${PINBOARDSHOT_CODE_SIGN_IDENTITY:-Developer ID Application}"
notary_profile="${PINBOARDSHOT_NOTARY_PROFILE:-PinboardShot-notary}"
feed_dir=".build/update-feed"
archive="$feed_dir/PinboardShot-${version}-${build}.zip"
dmg="$feed_dir/PinboardShot-${version}-${build}.dmg"
appcast="$feed_dir/appcast.xml"

echo "==> Building, signing, notarizing app, and generating Sparkle update feed"
./scripts/prepare-update.sh "$version" "$build"

if [[ ! -f "$archive" || ! -f "$appcast" ]]; then
  echo "Expected update feed artifacts were not created." >&2
  exit 1
fi

if [[ -e "$dmg" ]]; then
  backup="/private/tmp/$(basename "$dmg").previous.$(date +%Y%m%d%H%M%S)"
  /bin/mv "$dmg" "$backup"
  echo "Moved existing DMG to $backup"
fi

echo "==> Creating signed and notarized DMG"
hdiutil create \
  -volname PinboardShot \
  -srcfolder .build/app/PinboardShot.app \
  -format UDZO \
  "$dmg"
codesign --force --sign "$signing_identity" --timestamp "$dmg"
xcrun notarytool submit "$dmg" \
  --keychain-profile "$notary_profile" \
  --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"

echo "==> Verifying app, DMG, appcast, and ZIP contents"
codesign --verify --deep --strict --verbose=2 .build/app/PinboardShot.app
spctl --assess --type execute --verbose=2 .build/app/PinboardShot.app
codesign --verify --verbose=2 "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
if ! rg -q "releases/download/v${version}/PinboardShot-${version}-${build}\\.zip" "$appcast"; then
  echo "appcast.xml does not point at the expected release ZIP." >&2
  exit 1
fi
if unzip -l "$archive" | rg -q '(^|/)(Sources|Tests|website|Package\.swift|\.env|AGENTS\.md)(/|$)'; then
  echo "Release ZIP contains source, website, project metadata, or sensitive-looking files." >&2
  exit 1
fi

echo "==> Final SHA-256"
shasum -a 256 "$archive" "$dmg" "$appcast"

echo
echo "Artifacts ready:"
echo "$archive"
echo "$dmg"
echo "$appcast"
