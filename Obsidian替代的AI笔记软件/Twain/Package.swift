// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Twain",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Twain", targets: ["Twain"]),
        .library(name: "TwainCore", targets: ["TwainCore"]),
        // Shipped as Twain.app/Contents/Helpers/twain. Not `twain` here: on a case-insensitive
        // disk it would collide with the app's `Twain` binary in the build folder.
        .executable(name: "twain-cli", targets: ["TwainCLI"]),
    ],
    targets: [
        .target(name: "TwainCore", swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(name: "TwainCLI", dependencies: ["TwainCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(
            name: "Twain",
            dependencies: ["TwainCore"],
            resources: [.process("Resources"), .copy("Render")]
        ),
        .testTarget(
            name: "TwainCoreTests",
            dependencies: ["TwainCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ],
    swiftLanguageModes: [.v5]
)
