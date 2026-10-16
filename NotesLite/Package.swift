// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotesLite",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "NotesLite", targets: ["NotesLite"])],
    targets: [
        .target(name: "NotesCore"),
        .executableTarget(name: "NotesLite", dependencies: ["NotesCore"], resources: [.copy("Render"), .copy("Shaders")]),
        .testTarget(name: "NotesCoreTests", dependencies: ["NotesCore"]),
        .testTarget(name: "NotesLiteUITests", dependencies: ["NotesLite", "NotesCore"])
    ],
    swiftLanguageModes: [.v5]
)
