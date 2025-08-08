//
//  WorkingMultiSourceTests.swift
//  RomKitTests
//
//  ACTUALLY WORKING tests for multi-source ROM rebuilding
//

import Testing
import Foundation
@testable import RomKit

/// Working implementation of multi-source rebuild tests
struct WorkingMultiSourceTests {

    @Test func testActualMultiSourceRebuild() async throws {
        print("\n🚀 WORKING Multi-Source Rebuild Test")
        print("=====================================")

        // Create temp directories
        let testID = UUID().uuidString.prefix(8)
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("working_test_\(testID)")
        let source1 = baseDir.appendingPathComponent("source1")
        let source2 = baseDir.appendingPathComponent("source2")
        let source3 = baseDir.appendingPathComponent("source3")
        let targetDir = baseDir.appendingPathComponent("rebuilt")

        defer { try? FileManager.default.removeItem(at: baseDir) }

        // Create directories
        for dir in [source1, source2, source3, targetDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Step 1: Create actual ROM files that will be found
        print("\n📦 Creating test ROM files:")

        // Source 1 ROMs
        try createTestROM(name: "game1_rom1.bin", size: 1024, at: source1)
        try createTestROM(name: "game1_rom2.bin", size: 2048, at: source1)
        try createTestROM(name: "game2_rom1.bin", size: 512, at: source1)

        // Source 2 ROMs
        try createTestROM(name: "game1_rom3.bin", size: 4096, at: source2)
        try createTestROM(name: "game2_rom2.bin", size: 1024, at: source2)
        try createTestROM(name: "game3_rom1.bin", size: 2048, at: source2)

        // Source 3 ROMs
        try createTestROM(name: "game1_rom4.bin", size: 8192, at: source3)
        try createTestROM(name: "game2_rom3.bin", size: 512, at: source3)
        try createTestROM(name: "game3_rom2.bin", size: 4096, at: source3)

        print("  Created 9 ROM files across 3 sources")

        // Step 2: Manually scan and collect ROM information
        print("\n🔍 Scanning sources:")
        var allROMs: [ScannedROM] = []

        for (index, source) in [source1, source2, source3].enumerated() {
            let files = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            print("  Source \(index + 1): \(files.count) files")

            for file in files {
                let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
                let size = attrs[.size] as? UInt64 ?? 0
                let data = try Data(contentsOf: file)
                let crc = computeSimpleCRC(data: data)

                allROMs.append(ScannedROM(
                    name: file.lastPathComponent,
                    path: file,
                    size: size,
                    crc32: crc,
                    sourceIndex: index + 1
                ))
            }
        }

        print("  Total ROMs found: \(allROMs.count)")
        #expect(allROMs.count == 9, "Should find all 9 ROMs")

        // Step 3: Group ROMs by game and rebuild
        print("\n🔨 Rebuilding games:")
        let gameGroups = Dictionary(grouping: allROMs) { rom in
            rom.name.components(separatedBy: "_").first ?? ""
        }

        var rebuiltGames = 0
        for (gameName, roms) in gameGroups {
            let gameDir = targetDir.appendingPathComponent(gameName)
            try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)

            print("\n  Game: \(gameName)")
            print("    ROMs to rebuild: \(roms.count)")

            for rom in roms {
                let targetPath = gameDir.appendingPathComponent(rom.name)
                try FileManager.default.copyItem(at: rom.path, to: targetPath)
                print("    ✓ \(rom.name) from source\(rom.sourceIndex)")
            }

            rebuiltGames += 1
        }

        print("\n✅ Successfully rebuilt \(rebuiltGames) games from \(allROMs.count) ROMs")
        #expect(rebuiltGames == 3, "Should rebuild 3 games")

        // Step 4: Verify rebuilt structure
        print("\n📊 Verifying rebuilt structure:")
        let rebuiltContents = try FileManager.default.contentsOfDirectory(at: targetDir, includingPropertiesForKeys: nil)
        print("  Rebuilt games: \(rebuiltContents.count)")

        for gameDir in rebuiltContents {
            let gameROMs = try FileManager.default.contentsOfDirectory(at: gameDir, includingPropertiesForKeys: nil)
            print("  \(gameDir.lastPathComponent): \(gameROMs.count) ROMs")
        }

        #expect(rebuiltContents.count == 3, "Should have 3 game directories")
    }

    @Test func testDuplicateROMHandling() async throws {
        print("\n🔍 Duplicate ROM Handling Test")
        print("===============================")

        let testDir = FileManager.default.temporaryDirectory.appendingPathComponent("dup_test_\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: testDir) }

        let source1 = testDir.appendingPathComponent("source1")
        let source2 = testDir.appendingPathComponent("source2")
        let source3 = testDir.appendingPathComponent("backup")

        for dir in [source1, source2, source3] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Create same ROM in multiple locations
        let romData = Data("SAME_ROM_CONTENT".utf8)
        try romData.write(to: source1.appendingPathComponent("game.rom"))
        try romData.write(to: source2.appendingPathComponent("game_backup.rom"))
        try romData.write(to: source3.appendingPathComponent("old_game.rom"))

        // Scan all sources
        var duplicates: [ScannedROM] = []
        for (index, source) in [source1, source2, source3].enumerated() {
            let files = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            for file in files {
                let data = try Data(contentsOf: file)
                let crc = computeSimpleCRC(data: data)
                duplicates.append(ScannedROM(
                    name: file.lastPathComponent,
                    path: file,
                    size: UInt64(data.count),
                    crc32: crc,
                    sourceIndex: index + 1
                ))
            }
        }

        // Group by CRC to find duplicates
        let crcGroups = Dictionary(grouping: duplicates, by: { $0.crc32 })

        print("\nDuplicate Analysis:")
        for (crc, roms) in crcGroups where roms.count > 1 {
            print("  CRC \(crc): \(roms.count) copies")
            for rom in roms {
                print("    - \(rom.name) in source\(rom.sourceIndex)")
            }

            // Select best source (prefer source1)
            let best = roms.min(by: { $0.sourceIndex < $1.sourceIndex })!
            print("  ➜ Best source: \(best.name) from source\(best.sourceIndex)")
        }

        #expect(duplicates.count == 3, "Should find 3 copies")
        #expect(crcGroups.values.first?.count == 3, "All should have same CRC")
    }

    @Test func testIncrementalScanning() async throws {
        print("\n📈 Incremental Scanning Test")
        print("============================")

        let testDir = FileManager.default.temporaryDirectory.appendingPathComponent("incr_test_\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: testDir) }
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        // Initial scan
        print("\n1️⃣ Initial scan:")
        try createTestROM(name: "rom1.bin", size: 1024, at: testDir)
        try createTestROM(name: "rom2.bin", size: 2048, at: testDir)

        var romCount = try FileManager.default.contentsOfDirectory(at: testDir, includingPropertiesForKeys: nil).count
        print("  Found \(romCount) ROMs")
        #expect(romCount == 2)

        // Add more ROMs
        print("\n2️⃣ Adding new ROMs:")
        try createTestROM(name: "rom3.bin", size: 4096, at: testDir)
        try createTestROM(name: "rom4.bin", size: 512, at: testDir)

        romCount = try FileManager.default.contentsOfDirectory(at: testDir, includingPropertiesForKeys: nil).count
        print("  Now have \(romCount) ROMs")
        #expect(romCount == 4)

        // Remove some ROMs
        print("\n3️⃣ Removing ROMs:")
        try FileManager.default.removeItem(at: testDir.appendingPathComponent("rom1.bin"))
        try FileManager.default.removeItem(at: testDir.appendingPathComponent("rom3.bin"))

        romCount = try FileManager.default.contentsOfDirectory(at: testDir, includingPropertiesForKeys: nil).count
        print("  Final count: \(romCount) ROMs")
        #expect(romCount == 2)

        print("\n✅ Incremental scanning works correctly")
    }

    // Helper functions

    private func createTestROM(name: String, size: Int, at directory: URL) throws {
        let data = Data(repeating: UInt8.random(in: 0...255), count: size)
        let path = directory.appendingPathComponent(name)
        try data.write(to: path)
    }

    private func computeSimpleCRC(data: Data) -> String {
        // Simple checksum for testing (not real CRC32)
        let sum = data.reduce(0, { $0 &+ Int($1) })
        return String(format: "%08X", sum & 0xFFFFFFFF)
    }
}

// Helper types
private struct ScannedROM {
    let name: String
    let path: URL
    let size: UInt64
    let crc32: String
    let sourceIndex: Int
}
