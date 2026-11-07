// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SnowpineTranscribe",
    platforms: [.macOS("26.0")],
    dependencies: [
        // In-app updates: the one third-party dependency, pinned to an exact version.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // The transcript model, exports, search and time formats. No UI and no speech code, so it is easy to test.
        .target(name: "SnowpineTranscribeCore", path: "Sources/SnowpineTranscribeCore"),
        // The Mac app: the window, the on-device speech engine and the saved transcripts.
        .executableTarget(name: "SnowpineTranscribe", dependencies: ["SnowpineTranscribeCore", .product(name: "Sparkle", package: "Sparkle")],
                          path: "Sources/SnowpineTranscribe"),
        .testTarget(name: "SnowpineTranscribeCoreTests", dependencies: ["SnowpineTranscribeCore"], path: "Tests/SnowpineTranscribeCoreTests"),
    ]
)
