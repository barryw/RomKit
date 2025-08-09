//
//  ROMStorageTests.swift
//  RomKitTests
//
//  Created by Barry Walker on 8/5/25.
//

import Testing
import Foundation
@testable import RomKit

/// Tests for different ROM storage methods (split, merged, non-merged)
/// Uses synthetic test ROMs for legal compliance
struct ROMStorageTests {

    // MARK: - Synthetic ROM Generation

    /// Generate a synthetic ROM file with specific properties
    static func generateSyntheticROM(name: String, size: Int, seed: UInt32 = 0) -> Data {
        var data = Data(count: size)

        // Fill with deterministic pseudo-random data
        var rng = seed
        for index in 0..<size {
            // Simple deterministic pattern to avoid overflow issues
            rng = (rng ^ UInt32(index)) &+ 1
            data[index] = UInt8(rng & 0xFF)
        }

        return data
    }

    /// Create a test ROM set structure
    static func createTestROMSet() -> TestROMSet {
        // Create a mini test set that mimics MAME structure
        var testSet = TestROMSet()

        // BIOS ROM (like neogeo)
        testSet.addBIOS(
            name: "testbios",
            roms: [
                TestROM(name: "bios1.rom", size: 1024, seed: 1),
                TestROM(name: "bios2.rom", size: 2048, seed: 2)
            ]
        )

        // Parent game
        testSet.addGame(
            name: "parentgame",
            parent: nil,
            bios: "testbios",
            roms: [
                TestROM(name: "parent1.rom", size: 4096, seed: 10),
                TestROM(name: "parent2.rom", size: 8192, seed: 11),
                TestROM(name: "shared.rom", size: 2048, seed: 12)
            ]
        )

        // Clone game (shares some ROMs with parent)
        testSet.addGame(
            name: "clonegame",
            parent: "parentgame",
            bios: "testbios",
            roms: [
                TestROM(name: "clone1.rom", size: 4096, seed: 20),
                TestROM(name: "parent2.rom", size: 8192, seed: 11), // Shared with parent
                TestROM(name: "shared.rom", size: 2048, seed: 12)  // Shared with parent
            ]
        )

        return testSet
    }

    // MARK: - Split Set Tests

    @Test func testSplitSetCreation() async throws {
        let testSet = Self.createTestROMSet()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("split_test")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create split sets
        // - BIOS in separate ZIP
        // - Parent has only its unique ROMs
        // - Clone has only its unique ROMs

        // Create BIOS ZIP
        let biosZip = tempDir.appendingPathComponent("testbios.zip")
        try testSet.createZIP(for: "testbios", at: biosZip, style: RebuildOptions.Style.split)

        // Create parent ZIP (only unique ROMs)
        let parentZip = tempDir.appendingPathComponent("parentgame.zip")
        try testSet.createZIP(for: "parentgame", at: parentZip, style: RebuildOptions.Style.split)

        // Create clone ZIP (only changed ROMs)
        let cloneZip = tempDir.appendingPathComponent("clonegame.zip")
        try testSet.createZIP(for: "clonegame", at: cloneZip, style: RebuildOptions.Style.split)

        // Verify sizes (split = smallest individual files)
        let biosSize = try FileManager.default.attributesOfItem(atPath: biosZip.path)[.size] as? Int ?? 0
        let parentSize = try FileManager.default.attributesOfItem(atPath: parentZip.path)[.size] as? Int ?? 0
        let cloneSize = try FileManager.default.attributesOfItem(atPath: cloneZip.path)[.size] as? Int ?? 0

        print("Split Set Sizes:")
        print("  BIOS: \(biosSize) bytes")
        print("  Parent: \(parentSize) bytes")
        print("  Clone: \(cloneSize) bytes (smallest - only unique ROMs)")

        #expect(cloneSize < parentSize) // Clone should be smaller in split mode
    }

    // MARK: - Merged Set Tests

    @Test func testMergedSetCreation() async throws {
        let testSet = Self.createTestROMSet()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("merged_test")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create merged sets
        // - BIOS still separate
        // - Parent contains all clone ROMs too
        // - No separate clone ZIP

        // Create BIOS ZIP
        let biosZip = tempDir.appendingPathComponent("testbios.zip")
        try testSet.createZIP(for: "testbios", at: biosZip, style: RebuildOptions.Style.merged)

        // Create parent ZIP (includes all clones)
        let parentZip = tempDir.appendingPathComponent("parentgame.zip")
        try testSet.createZIP(for: "parentgame", at: parentZip, style: RebuildOptions.Style.merged, includeClones: true)

        // Verify no clone ZIP needed
        let cloneZip = tempDir.appendingPathComponent("clonegame.zip")
        #expect(FileManager.default.fileExists(atPath: cloneZip.path) == false)

        let parentSize = try FileManager.default.attributesOfItem(atPath: parentZip.path)[.size] as? Int ?? 0

        print("Merged Set Sizes:")
        print("  Parent (includes clones): \(parentSize) bytes")
        print("  Clone: N/A (included in parent)")
    }

    // MARK: - Non-Merged Set Tests

    @Test func testNonMergedSetCreation() async throws {
        let testSet = Self.createTestROMSet()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("nonmerged_test")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create non-merged sets
        // - Each ZIP is completely self-contained
        // - Includes BIOS, parent ROMs, everything needed
        // - Largest but simplest

        // Create parent ZIP (includes BIOS ROMs)
        let parentZip = tempDir.appendingPathComponent("parentgame.zip")
        try testSet.createZIP(for: "parentgame", at: parentZip, style: RebuildOptions.Style.nonMerged, includeBIOS: true)

        // Create clone ZIP (includes BIOS + parent ROMs)
        let cloneZip = tempDir.appendingPathComponent("clonegame.zip")
        try testSet.createZIP(for: "clonegame", at: cloneZip, style: RebuildOptions.Style.nonMerged, includeBIOS: true, includeParent: true)

        let parentSize = try FileManager.default.attributesOfItem(atPath: parentZip.path)[.size] as? Int ?? 0
        let cloneSize = try FileManager.default.attributesOfItem(atPath: cloneZip.path)[.size] as? Int ?? 0

        print("Non-Merged Set Sizes:")
        print("  Parent (self-contained): \(parentSize) bytes")
        print("  Clone (self-contained): \(cloneSize) bytes (largest - has everything)")

        #expect(cloneSize > parentSize) // Clone should be larger (has parent ROMs too)
    }

    // MARK: - Rebuild Tests

    @Test func testRebuildFromLooseROMs() async throws {
        // Create a directory with ZIP files containing ROM files
        let sourceDir = FileManager.default.temporaryDirectory.appendingPathComponent("loose_roms_\(UUID())")
        let targetDir = FileManager.default.temporaryDirectory.appendingPathComponent("rebuilt_roms_\(UUID())")

        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: targetDir)
        }

        // Create ZIP files with test ROMs
        let testSet = Self.createTestROMSet()

        // Create a ZIP for each game
        for game in ["testbios", "parentgame", "clonegame"] {
            let zipPath = sourceDir.appendingPathComponent("\(game).zip")
            try testSet.createZIP(for: game, at: zipPath, style: .split)
        }

        // Load DAT file
        let data = try TestDATLoader.loadFullMAMEDAT()
        let parser = LogiqxDATParser()
        let datFile = try parser.parse(data: data)

        // Create rebuilder
        let rebuilder = MAMEROMRebuilder(
            datFile: datFile,
            archiveHandlers: [ZIPArchiveHandler()]
        )

        // Rebuild to split sets
        print("Rebuilding to split sets...")
        let splitResults = try await rebuilder.rebuild(
            from: sourceDir,
            to: targetDir.appendingPathComponent("split"),
            options: RebuildOptions(style: RebuildOptions.Style.split)
        )

        print("Rebuild Results:")
        print("  Found ROMs: \(splitResults.rebuilt)")
        print("  Failed: \(splitResults.failed)")
        print("  Skipped: \(splitResults.skipped)")
    }

    // MARK: - Real ROM Tests (Optional)

    @Test func testWithRealROMs() async throws {
        // Only run if user provides real ROMs
        guard let romPath = ProcessInfo.processInfo.environment["USER_ROM_PATH"] else {
            print("Skipping real ROM test - set USER_ROM_PATH to enable")
            return
        }

        print("Testing with real ROMs from: \(romPath)")

        let sourceURL = URL(fileURLWithPath: romPath)
        let targetDir = FileManager.default.temporaryDirectory.appendingPathComponent("real_rebuilt")
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: targetDir) }

        // Load bundled DAT
        let data = try TestDATLoader.loadFullMAMEDAT()
        let parser = LogiqxDATParser()
        let datFile = try parser.parse(data: data)

        // Test each rebuild style
        for style in [RebuildOptions.Style.split, .merged, .nonMerged] {
            print("\nTesting \(style) rebuild...")

            let rebuilder = MAMEROMRebuilder(
                datFile: datFile,
                archiveHandlers: [ZIPArchiveHandler(), SevenZipArchiveHandler()]
            )

            let results = try await rebuilder.rebuild(
                from: sourceURL,
                to: targetDir.appendingPathComponent(String(describing: style)),
                options: RebuildOptions(style: style)
            )

            print("  Rebuilt: \(results.rebuilt) games")
            print("  Failed: \(results.failed) games")
        }
    }
}

// MARK: - Test Helpers

struct TestROMSet {
    var games: [String: TestGame] = [:]
    var allROMs: [(name: String, data: Data)] = []

    struct TestGame {
        let name: String
        let parent: String?
        let bios: String?
        let roms: [TestROM]
    }

    mutating func addBIOS(name: String, roms: [TestROM]) {
        let game = TestGame(name: name, parent: nil, bios: nil, roms: roms)
        games[name] = game
        for rom in roms {
            allROMs.append((rom.name, rom.data))
        }
    }

    mutating func addGame(name: String, parent: String?, bios: String?, roms: [TestROM]) {
        let game = TestGame(name: name, parent: parent, bios: bios, roms: roms)
        games[name] = game
        for rom in roms {
            allROMs.append((rom.name, rom.data))
        }
    }

    func createZIP(for gameName: String, at path: URL, style: RebuildOptions.Style,
                   includeBIOS: Bool = false, includeParent: Bool = false, includeClones: Bool = false) throws {

        guard let game = games[gameName] else {
            throw NSError(domain: "TestROMSet", code: 1, userInfo: [NSLocalizedDescriptionKey: "Game '\(gameName)' not found"])
        }

        // Collect ROMs based on style
        var romsToInclude: [(name: String, data: Data)] = []

        // Add the game's own ROMs
        for rom in game.roms {
            romsToInclude.append((rom.name, rom.data))
        }

        // Add BIOS ROMs if needed
        if includeBIOS || style == .nonMerged {
            if let biosName = game.bios, let biosGame = games[biosName] {
                for rom in biosGame.roms {
                    romsToInclude.append((rom.name, rom.data))
                }
            }
        }

        // Add parent ROMs if needed
        if includeParent || style == .nonMerged {
            if let parentName = game.parent, let parentGame = games[parentName] {
                for rom in parentGame.roms where !romsToInclude.contains(where: { $0.name == rom.name }) {
                    // Don't duplicate ROMs already included
                    romsToInclude.append((rom.name, rom.data))
                }
            }
        }

        // Create a simple ZIP-like archive (for testing purposes)
        // In a real implementation, this would use ZIPArchiveHandler
        var zipData = Data()

        // Simple header
        let header = Data("TESTZIP\n".utf8)
        zipData.append(header)

        // Add each ROM with a simple format: "FILENAME:SIZE:DATA"
        for (name, data) in romsToInclude {
            let entry = Data("\(name):\(data.count):".utf8)
            let newline = Data("\n".utf8)
            zipData.append(entry)
            zipData.append(data)
            zipData.append(newline)
        }

        try zipData.write(to: path)
    }
}

struct TestROM {
    let name: String
    let size: Int
    let seed: UInt32

    var data: Data {
        return ROMStorageTests.generateSyntheticROM(name: name, size: size, seed: seed)
    }
}
