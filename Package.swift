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
        // Cuarto target: servidor MCP. main.swift fino + cero deps externas (SEC-M10).
        .executableTarget(
            name: "pasture-mcp",
            dependencies: ["PastureKit"],
            path: "Sources/pasture-mcp"
        ),
        .testTarget(
            name: "PastureKitTests",
            dependencies: ["PastureKit"],
            path: "Tests/PastureKitTests"
        )
    ]
)
