// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RomKit",
    platforms: [
        .macOS(.v14)  // Updated for Swift 6 compatibility
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
            path: "RomKit",
            resources: [
                .process("Utilities/HashCompute.metal")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .executableTarget(
            name: "RomKitCLI",
            dependencies: [
                "RomKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "RomKitCLI",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "RomKitTests",
            dependencies: ["RomKit"],
            path: "RomKitTests",
            resources: [
                .copy("TestData")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
