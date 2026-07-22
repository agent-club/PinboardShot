#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"

version="${1:-}"
build="${2:-}"
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' || ! "$build" =~ '^[1-9][0-9]*$' ]]; then
  echo "Usage: ./scripts/prepare-update.sh <version> <build>" >&2
  exit 1
fi

if ! plutil -extract CFBundleShortVersionString raw -o - Resources/Info.plist | rg -qx "$version"; then
  echo "Version does not match Resources/Info.plist" >&2
  exit 1
fi
if ! plutil -extract CFBundleVersion raw -o - Resources/Info.plist | rg -qx "$build"; then
  echo "Build number does not match Resources/Info.plist" >&2
  exit 1
fi

signing_identity="${PINBOARDSHOT_CODE_SIGN_IDENTITY:-Developer ID Application}"
notary_profile="${PINBOARDSHOT_NOTARY_PROFILE:-PinboardShot-notary}"
PINBOARDSHOT_CODE_SIGN_IDENTITY="$signing_identity" ./scripts/build-app.sh
app_path=".build/app/PinboardShot.app"
if ! codesign -d --verbose=4 "$app_path" 2>&1 | rg '^Authority=Developer ID Application:' >/dev/null; then
  echo "The update app must be signed with a trusted Developer ID Application certificate." >&2
  exit 1
fi
if ! codesign -d --verbose=4 "$app_path" 2>&1 | rg 'flags=.*runtime' >/dev/null; then
  echo "The update app is missing Hardened Runtime." >&2
  exit 1
fi
if ! codesign -d --verbose=4 "$app_path" 2>&1 | rg '^Timestamp=' >/dev/null; then
  echo "The update app is missing a secure timestamp." >&2
  exit 1
fi

feed_dir=".build/update-feed"
mkdir -p "$feed_dir"
staging_dir="$(mktemp -d /private/tmp/pinboardshot-update.XXXXXX)"
trap '[[ -d "$staging_dir" ]] && /usr/bin/find "$staging_dir" -depth -delete' EXIT
archive_name="PinboardShot-${version}-${build}.zip"
submission_archive="$staging_dir/PinboardShot-notarization.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$submission_archive"
xcrun notarytool submit "$submission_archive" \
  --keychain-profile "$notary_profile" \
  --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"

feed_staging_dir="$staging_dir/feed"
mkdir -p "$feed_staging_dir"
staged_archive="$feed_staging_dir/$archive_name"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$staged_archive"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --account agent-club \
  --versions "$build" \
  --download-url-prefix "https://github.com/agent-club/PinboardShot/releases/download/v${version}/" \
  "$feed_staging_dir"

archive="$feed_dir/$archive_name"
/bin/mv "$staged_archive" "$archive"
/bin/mv "$feed_staging_dir/appcast.xml" "$feed_dir/appcast.xml"

echo "$archive"
echo "$feed_dir/appcast.xml"
