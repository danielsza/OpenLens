// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenLens",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // The reusable core: models + Aperture library reader/writer.
        .library(name: "OpenLensKit", targets: ["OpenLensKit"]),
        // A command-line tool to inspect a library (proves the reader works).
        .executable(name: "openlens-cli", targets: ["openlens-cli"]),
        // The SwiftUI app. Runs via `swift run OpenLensApp` for development.
        // See docs/building.md for promoting this to a full Xcode app target.
        .executable(name: "OpenLensApp", targets: ["OpenLensApp"]),
    ],
    targets: [
        .target(
            name: "OpenLensKit"
            // No external dependencies: SQLite is used via the system
            // `SQLite3` module, and plists via Foundation.
        ),
        .executableTarget(
            name: "openlens-cli",
            dependencies: ["OpenLensKit"]
        ),
        .executableTarget(
            name: "OpenLensApp",
            dependencies: ["OpenLensKit"]
        ),
        .testTarget(
            name: "OpenLensKitTests",
            dependencies: ["OpenLensKit"]
        ),
    ]
)
