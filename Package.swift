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
        .executable(
            name: "romkit",
            targets: ["RomKitCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "RomKit",
            dependencies: [],
            path: "RomKit"
        ),
        .executableTarget(
            name: "RomKitCLI",
            dependencies: [
                "RomKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "RomKitCLI"
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