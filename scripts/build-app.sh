#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"
architectures=(${(s:,:)${PINBOARDSHOT_ARCHS:-arm64,x86_64}})
requested_signing_identity="${PINBOARDSHOT_CODE_SIGN_IDENTITY:-}"
allows_adhoc_fallback=$([[ -z "${PINBOARDSHOT_CODE_SIGN_IDENTITY:-}" ]] && print true || print false)
build_args=(-c release)
for architecture in $architectures; do
  build_args+=(--arch "$architecture")
done

swift build $build_args
bin_path="$(swift build $build_args --show-bin-path)"
mkdir -p \
  .build/app/PinboardShot.app/Contents/MacOS \
  .build/app/PinboardShot.app/Contents/Resources \
  .build/app/PinboardShot.app/Contents/Frameworks
cp "$bin_path/PinboardShot" .build/app/PinboardShot.app/Contents/MacOS/PinboardShot
cp Resources/Info.plist .build/app/PinboardShot.app/Contents/Info.plist
xcrun actool Resources/Assets.xcassets \
  --compile .build/app/PinboardShot.app/Contents/Resources \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist .build/app/asset-info.plist \
  --output-format human-readable-text \
  --warnings
sparkle_framework=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$sparkle_framework" ]]; then
  echo "Sparkle.framework was not found in SwiftPM artifacts" >&2
  exit 1
fi
/usr/bin/ditto "$sparkle_framework" .build/app/PinboardShot.app/Contents/Frameworks/Sparkle.framework
embedded_sparkle=".build/app/PinboardShot.app/Contents/Frameworks/Sparkle.framework"
sparkle_version="$embedded_sparkle/Versions/B"
if ! otool -l .build/app/PinboardShot.app/Contents/MacOS/PinboardShot | rg -q -F '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath '@executable_path/../Frameworks' .build/app/PinboardShot.app/Contents/MacOS/PinboardShot
fi
for localization in Resources/*.lproj; do
  cp -R "$localization" .build/app/PinboardShot.app/Contents/Resources/
done

sign_sparkle() {
  local signing_identity="$1"
  local hardened_runtime="$2"
  local secure_timestamp="$3"
  local sign_args=(--force --sign "$signing_identity")
  if [[ "$hardened_runtime" == true ]]; then
    sign_args+=(--options runtime)
  fi
  if [[ "$secure_timestamp" == true ]]; then
    sign_args+=(--timestamp)
  fi

  codesign $sign_args "$sparkle_version/XPCServices/Installer.xpc" || return 1
  codesign $sign_args --preserve-metadata=entitlements \
    "$sparkle_version/XPCServices/Downloader.xpc" || return 1
  codesign $sign_args "$sparkle_version/Autoupdate" || return 1
  codesign $sign_args "$sparkle_version/Updater.app" || return 1
  codesign $sign_args "$embedded_sparkle" || return 1
}

if [[ "$requested_signing_identity" == "-" ]]; then
  sign_sparkle - false false
  codesign --force --sign - \
    --requirements '=designated => identifier "com.ryanwang.PinboardShot"' \
    .build/app/PinboardShot.app
  echo "warning: using ad-hoc signing; screen recording permission may reset after each rebuild" >&2
else
  if [[ -n "$requested_signing_identity" ]]; then
    signing_candidates=("$requested_signing_identity")
  else
    signing_candidates=("Developer ID Application" "Apple Development")
  fi
  signed_with_stable_identity=false
  for signing_identity in $signing_candidates; do
    secure_timestamp=true
    if [[ "$signing_identity" == Apple\ Development* ]]; then
      secure_timestamp=false
    fi
    app_sign_args=(--force --sign "$signing_identity" --options runtime)
    if [[ "$secure_timestamp" == true ]]; then
      app_sign_args+=(--timestamp)
    fi
    if sign_sparkle "$signing_identity" true "$secure_timestamp" && \
       codesign $app_sign_args .build/app/PinboardShot.app; then
      signed_with_stable_identity=true
      break
    fi
  done

  if [[ "$signed_with_stable_identity" == true ]]; then
    echo "Signed PinboardShot with a stable code-signing identity."
  elif [[ "$allows_adhoc_fallback" == true ]]; then
    echo "warning: no stable code-signing identity available; falling back to ad-hoc signing" >&2
    echo "warning: screen recording permission may reset after each rebuild" >&2
    sign_sparkle - false false
    codesign --force --sign - \
      --requirements '=designated => identifier "com.ryanwang.PinboardShot"' \
      .build/app/PinboardShot.app
  else
    echo "Failed to sign with PINBOARDSHOT_CODE_SIGN_IDENTITY." >&2
    exit 1
  fi
fi
codesign --verify --deep --strict .build/app/PinboardShot.app
expected_architectures="${(j: :)architectures}"
actual_architectures="$(lipo -archs .build/app/PinboardShot.app/Contents/MacOS/PinboardShot)"
for architecture in $architectures; do
  if [[ " $actual_architectures " != *" $architecture "* ]]; then
    echo "Missing architecture $architecture (expected: $expected_architectures; actual: $actual_architectures)" >&2
    exit 1
  fi
done
echo .build/app/PinboardShot.app
