// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pasture",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "PastureKit",
            path: "Sources/PastureKit"
        ),
        .executableTarget(
            name: "Pasture",
            dependencies: ["PastureKit"],
            path: "Sources/Pasture"
        ),
        .testTarget(
            name: "PastureKitTests",
            dependencies: ["PastureKit"],
            path: "Tests/PastureKitTests"
        )
    ]
)
