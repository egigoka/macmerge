// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacMerge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacMerge", targets: ["MacMerge"]),
        .library(name: "MacMergeCore", targets: ["MacMergeCore"])
    ],
    targets: [
        .target(
            name: "CXDiff",
            path: "Sources/CXDiff",
            publicHeadersPath: "include"
        ),
        .target(
            name: "MacMergeCore",
            dependencies: ["CXDiff"]
        ),
        .executableTarget(
            name: "MacMerge",
            dependencies: ["MacMergeCore"]
        ),
        .testTarget(
            name: "MacMergeCoreTests",
            dependencies: ["MacMergeCore", "CXDiff"]
        ),
        .testTarget(
            name: "MacMergeAppTests",
            dependencies: ["MacMerge", "MacMergeCore"]
        )
    ]
)
