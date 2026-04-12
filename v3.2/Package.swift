// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "GyLogSync",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GyLogSync", targets: ["GyLogSync"]),
        .executable(name: "GyLogSyncTest", targets: ["GyLogSyncTest"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "GyLogSync",
            dependencies: [],
            path: "Sources/GyLogSync"
        ),
        .executableTarget(
            name: "GyLogSyncTest",
            dependencies: [],
            path: "Sources/GyLogSyncTest"
        )
    ]
)
