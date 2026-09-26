// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Plume",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Plume", targets: ["Plume"]),
        .library(name: "PlumeCore", targets: ["PlumeCore"]),
        // Shipped as Plume.app/Contents/Helpers/plume. Not `plume` here: on a case-insensitive
        // disk it would collide with the app's `Plume` binary in the build folder.
        .executable(name: "plume-cli", targets: ["PlumeCLI"]),
    ],
    targets: [
        .target(name: "PlumeCore"),
        .executableTarget(name: "PlumeCLI", dependencies: ["PlumeCore"]),
        .executableTarget(
            name: "Plume",
            dependencies: ["PlumeCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PlumeCoreTests",
            dependencies: ["PlumeCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
