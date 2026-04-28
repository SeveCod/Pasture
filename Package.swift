// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pasture",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Pasture",
            path: "Sources/Pasture",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
