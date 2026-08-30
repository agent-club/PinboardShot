// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PinboardShot",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PinboardShot", targets: ["PinboardShot"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4")
    ],
    targets: [
        .executableTarget(
            name: "PinboardShot",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")]
        ),
        .testTarget(name: "PinboardShotTests", dependencies: ["PinboardShot"])
    ]
)
