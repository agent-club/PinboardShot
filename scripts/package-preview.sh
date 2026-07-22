#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"

# This preview channel intentionally avoids Apple Developer credentials.
# macOS will identify the app as coming from an unknown developer, so the
# website must keep the corresponding Gatekeeper warning visible.
PINBOARDSHOT_ARCHS="${PINBOARDSHOT_ARCHS:-arm64,x86_64}" \
PINBOARDSHOT_CODE_SIGN_IDENTITY="-" \
  ./scripts/build-app.sh

version="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
build="$(plutil -extract CFBundleVersion raw Resources/Info.plist)"
archive="dist/PinboardShot-${version}-${build}-universal-preview.zip"
checksum="${archive}.sha256"

mkdir -p dist website/public
rm -f "$archive" "$checksum"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent .build/app/PinboardShot.app "$archive"

digest="$(shasum -a 256 "$archive" | awk '{print $1}')"
print -r -- "$digest  ${archive:t}" > "$checksum"

cp "$archive" website/public/PinboardShot.zip
print -r -- "$digest  PinboardShot.zip" > website/public/PinboardShot.zip.sha256

echo "$archive"
echo "$checksum"
