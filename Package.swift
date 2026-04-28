// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pasture",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Pasture",
            path: "Sources/Pasture"
        )
    ]
)
