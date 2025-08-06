// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RomKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "RomKit",
            targets: ["RomKit"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "RomKit",
            dependencies: [],
            path: "RomKit"
        ),
        .testTarget(
            name: "RomKitTests",
            dependencies: ["RomKit"],
            path: "RomKitTests",
            resources: [
                .copy("TestData")
            ]
        ),
    ]
)