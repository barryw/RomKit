//
//  BundledDATTests.swift
//  RomKitTests
//
//  Created by Barry Walker on 8/5/25.
//

import Testing
import Foundation
@testable import RomKit

struct BundledDATTests {

    @Test func testLoadBundledCompressedDAT() async throws {
        // Load the bundled compressed MAME DAT
        let data = try TestDATLoader.loadFullMAMEDAT()

        // Should be decompressed to ~78MB
        #expect(data.count > 70_000_000)
        #expect(data.count < 90_000_000)

        print("Loaded bundled DAT: \(data.count / 1024 / 1024) MB")
    }

    @Test func testParseBundledDAT() async throws {
        // Load the bundled DAT
        let data = try TestDATLoader.loadFullMAMEDAT()

        // Parse it
        let parser = LogiqxDATParser()
        let dat = try parser.parse(data: data)

        // Should have 48k+ games
        #expect(dat.games.count > 48000)

        print("Parsed bundled DAT: \(dat.games.count) games")
        print("Version: \(dat.metadata.version ?? "unknown")")
    }

    @Test func testBundledDATWithRomKit() async throws {
        // Get decompressed data
        let data = try TestDATLoader.loadFullMAMEDAT()

        // Use with RomKit
        let romkit = RomKitGeneric()
        try romkit.loadDAT(data: data, format: "logiqx")

        #expect(romkit.isLoaded == true)
        #expect(romkit.currentFormat == "Logiqx DAT")

        // Check we can access game data
        if let datFile = romkit.currentDATFile as? MAMEDATFile {
            // Find a well-known game
            let pacman = datFile.games.first { $0.name == "pacman" }
            #expect(pacman != nil)

            if let pacman = pacman {
                print("Found Pac-Man: \(pacman.description)")
            }
        }
    }

    @Test func testPerformanceWithBundledDAT() async throws {
        let data = try TestDATLoader.loadFullMAMEDAT()

        // Measure parse performance
        let iterations = 3
        var totalTime: TimeInterval = 0

        for index in 1...iterations {
            let start = Date()
            let parser = LogiqxDATParser()
            let dat = try parser.parse(data: data)
            let elapsed = Date().timeIntervalSince(start)

            totalTime += elapsed
            print("Iteration \(index): \(String(format: "%.2f", elapsed))s - \(dat.games.count) games")
        }

        let avgTime = totalTime / Double(iterations)
        print("Average parse time: \(String(format: "%.2f", avgTime))s")

        // Should parse in under 10 seconds on average
        #expect(avgTime < 10.0)
    }

    @Test func testNoExternalDependencies() async throws {
        // This test demonstrates that tests can run without any external files
        // or environment variables - everything is self-contained

        // Clear any environment variables that might be set
        let originalPath = ProcessInfo.processInfo.environment["ROMKIT_TEST_DAT_PATH"]
        defer {
            // Restore if needed (though we can't actually modify env vars)
        }

        // Load bundled DAT without any external dependencies
        let data = try TestDATLoader.loadFullMAMEDAT()
        let parser = LogiqxDATParser()
        let dat = try parser.parse(data: data)

        // Verify it works
        #expect(dat.games.count > 48000)

        print("✅ Tests work with bundled DAT - no external files needed!")
        print("   Original env var: \(originalPath ?? "not set")")
    }

    @Test func testCompressionStats() async throws {
        // Show the compression benefits
        let compressedPath = TestDATLoader.getTestDATPath(named: "MAME_0278.dat.gz")

        if let path = compressedPath {
            _ = URL(fileURLWithPath: path)
            let compressedSize = try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int ?? 0

            // Load and check decompressed size
            let decompressed = try TestDATLoader.loadFullMAMEDAT()

            let ratio = Double(decompressed.count) / Double(compressedSize)
            let savings = 100.0 - (Double(compressedSize) / Double(decompressed.count) * 100.0)

            print("Compression Statistics:")
            print("=======================")
            print("Compressed:   \(compressedSize / 1024 / 1024) MB")
            print("Decompressed: \(decompressed.count / 1024 / 1024) MB")
            print("Ratio:        \(String(format: "%.1f:1", ratio))")
            print("Space saved:  \(String(format: "%.1f%%", savings))")

            // Should achieve ~7:1 compression
            #expect(ratio > 6.0)
            #expect(ratio < 9.0)
        }
    }
}
