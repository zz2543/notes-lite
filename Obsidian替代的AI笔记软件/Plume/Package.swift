// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Plume",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Plume", targets: ["Plume"]),
        .library(name: "PlumeCore", targets: ["PlumeCore"]),
    ],
    targets: [
        .target(name: "PlumeCore"),
        .executableTarget(name: "Plume", dependencies: ["PlumeCore"]),
        .testTarget(
            name: "PlumeCoreTests",
            dependencies: ["PlumeCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
