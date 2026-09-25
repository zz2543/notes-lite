// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Plume",
    platforms: [.macOS(.v26)],
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
