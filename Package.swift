// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SnowpineTranscribe",
    platforms: [.macOS("26.0")],
    targets: [
        // The transcript model, exports, search and time formats. No UI and no speech code, so it is easy to test.
        .target(name: "SnowpineTranscribeCore", path: "Sources/SnowpineTranscribeCore"),
        // The Mac app: the window, the on-device speech engine and the saved transcripts.
        .executableTarget(name: "SnowpineTranscribe", dependencies: ["SnowpineTranscribeCore"], path: "Sources/SnowpineTranscribe"),
        .testTarget(name: "SnowpineTranscribeCoreTests", dependencies: ["SnowpineTranscribeCore"], path: "Tests/SnowpineTranscribeCoreTests"),
    ]
)
