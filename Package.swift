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
            sources: [
                "lib7z_wrapper.c",
                "7zAlloc.c",
                "7zArcIn.c",
                "7zBuf.c",
                "7zBuf2.c",
                "7zCrc.c",
                "7zCrcOpt.c",
                "7zDec.c",
                "7zFile.c",
                "7zStream.c",
                "Alloc.c",
                "CpuArch.c",
                "Delta.c",
                "LzmaDec.c",
                "Lzma2Dec.c",
                "Bcj2.c",
                "Bra.c",
                "Bra86.c",
                "BraIA64.c",
                "Ppmd7.c",
                "Ppmd7Dec.c"
            ],
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("."),
                .define("_FILE_OFFSET_BITS", to: "64"),
                .define("_LARGEFILE_SOURCE"),
                .define("_7ZIP_ST")  // Single-threaded mode for simplicity
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
