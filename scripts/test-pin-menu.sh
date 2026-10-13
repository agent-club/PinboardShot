#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Native menu tracking needs a real NSApplication loop; SwiftPM's testing helper can exit without a result.
swift test --no-parallel --filter '^$'
pinboard_test_bin="$(swift build --show-bin-path)"
pinboard_menu_tmp="$(mktemp -d "${TMPDIR:-/tmp}/PinboardShot-menu-smoke.XXXXXX")"
trap 'rm -rf "$pinboard_menu_tmp"' EXIT
cat > "$pinboard_menu_tmp/main.swift" <<'SWIFT'
import AppKit
import Foundation

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard CommandLine.arguments.count == 2, let bundle = Bundle(path: CommandLine.arguments[1]) else {
    print("Cannot find native menu test bundle")
    exit(1)
}
do { try bundle.loadAndReturnError() }
catch { print("Cannot load native menu test bundle: \(error.localizedDescription)"); exit(1) }
guard let smokeType = NSClassFromString("PinboardShotNativeMenuSmoke") as? NSObject.Type else {
    print("Cannot find native menu test fixture class")
    exit(1)
}
let smoke = smokeType.init()
let timeout = Timer(timeInterval: 20, repeats: false) { _ in
    print("Native menu test timed out")
    exit(1)
}
RunLoop.main.add(timeout, forMode: .common)
RunLoop.main.add(timeout, forMode: .eventTracking)
DispatchQueue.main.async {
    smoke.perform(NSSelectorFromString("runSmoke"))
}
app.run()
print("Native menu host stopped without a completion result")
exit(1)
SWIFT
pinboard_developer_dir="$(xcode-select -p)/Platforms/MacOSX.platform/Developer"
xcrun swiftc "$pinboard_menu_tmp/main.swift" -framework AppKit \
  -Xlinker -rpath -Xlinker "$pinboard_developer_dir/Library/Frameworks" \
  -Xlinker -rpath -Xlinker "$pinboard_developer_dir/usr/lib" \
  -o "$pinboard_menu_tmp/native-menu-smoke"
"$pinboard_menu_tmp/native-menu-smoke" "$pinboard_test_bin/PinboardShotTests.xctest"
