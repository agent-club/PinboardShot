// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PinboardShot",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PinboardShot", targets: ["PinboardShot"]),
        .executable(name: "PinboardShotBrowserHost", targets: ["PinboardShotBrowserHost"]),
        .library(name: "BrowserCaptureBridge", targets: ["BrowserCaptureBridge"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4")
    ],
    targets: [
        .executableTarget(
            name: "PinboardShot",
            dependencies: [.product(name: "Sparkle", package: "Sparkle"), "BrowserCaptureBridge"]
        ),
        .target(name: "BrowserCaptureBridge"),
        .executableTarget(
            name: "PinboardShotBrowserHost",
            dependencies: ["BrowserCaptureBridge"]
        ),
        .testTarget(name: "BrowserCaptureBridgeTests", dependencies: ["BrowserCaptureBridge"]),
        .testTarget(name: "PinboardShotTests", dependencies: ["PinboardShot"])
    ]
)
