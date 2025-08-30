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
            name: "Lib7z",
            path: "RomKit/Lib7Zip",
            sources: ["lib7z_wrapper.c", "7zAlloc.c"],
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("../../External/lib7z/include"),
                .define("_FILE_OFFSET_BITS", to: "64"),
                .define("_LARGEFILE_SOURCE")
            ],
            linkerSettings: [
                // Link the lib7z.a file directly
                .unsafeFlags(["RomKit/Lib7Zip/lib7z.a"])
            ]
        ),
        .target(
            name: "RomKit",
            dependencies: ["Lib7z"],
            path: "RomKit",
            exclude: ["Lib7Zip"],
            resources: [
                .process("Shaders/HashCompute.metal"),
                .process("Shaders/Compression.metal")
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
