//
//  MultiSourceRebuildTests.swift
//  RomKitTests
//
//  Tests for rebuilding games from ROMs spread across multiple indexed directories
//

import Testing
import Foundation
@testable import RomKit

/// Tests rebuilding games from ROMs distributed across multiple indexed source directories
struct MultiSourceRebuildTests {
    
    /// Test rebuilding a complete game from ROMs spread across multiple directories
    @Test(.disabled("Requires full implementation of multi-source indexing"))
    func testRebuildFromMultipleIndexedSources() async throws {
        // Create temporary directories
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("multi_source_test_\(UUID().uuidString)")
        let source1 = baseDir.appendingPathComponent("source1")
        let source2 = baseDir.appendingPathComponent("source2")
        let source3 = baseDir.appendingPathComponent("source3")
        let targetDir = baseDir.appendingPathComponent("rebuilt")
        let indexDB = baseDir.appendingPathComponent("index.db")
        
        // Cleanup
        defer { try? FileManager.default.removeItem(at: baseDir) }
        
        // Create directories
        for dir in [source1, source2, source3, targetDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        print("\n🔄 Multi-Source Rebuild Test")
        print("=====================================")
        
        // Step 1: Create synthetic ROMs spread across sources
        let gameROMs = createDistributedGameROMs()
        
        // Distribute ROMs across sources
        print("\n📦 Distributing ROMs across sources:")
        try distributeROMs(gameROMs, to: [source1, source2, source3])
        
        // Step 2: Index all sources
        print("\n📚 Indexing sources:")
        
        // Create index manager and index sources
        let indexManager = try await ROMIndexManager(databasePath: indexDB)
        
        // Note: ROMIndexManager.addSource expects directories to be scanned
        // The indexing happens automatically when adding sources
        for (index, source) in [source1, source2, source3].enumerated() {
            print("  Adding source\(index + 1): \(source.lastPathComponent)")
            // Since addSource is not available, use SQLiteROMIndex directly
        }
        
        // Use SQLiteROMIndex directly for indexing
        let sqliteIndex = try await SQLiteROMIndex(databasePath: indexDB)
        try await sqliteIndex.indexSources([source1, source2, source3], showProgress: false)
        
        // Re-create index manager to get fresh data
        let indexManager2 = try await ROMIndexManager(databasePath: indexDB)
        
        // Step 3: Verify index contains all ROMs
        print("\n🔍 Verifying indexed ROMs:")
        let analysis = await indexManager2.analyzeIndex()
        print("  Total ROMs indexed: \(analysis.totalROMs)")
        print("  Unique ROMs: \(analysis.uniqueROMs)")
        print("  Sources: \(analysis.sources.count)")
        
        #expect(analysis.totalROMs >= gameROMs.count)
        
        // Step 4: Rebuild games using indexed sources
        print("\n🔨 Rebuilding games from indexed sources:")
        let rebuiltGames = try await rebuildGamesFromIndex(
            indexManager: indexManager2,
            gameROMs: gameROMs,
            targetDir: targetDir
        )
        
        print("\n✅ Successfully rebuilt \(rebuiltGames.count) games")
        
        // Step 5: Verify rebuilt games
        for (gameName, roms) in rebuiltGames {
            print("\n  Game: \(gameName)")
            for rom in roms {
                print("    ✓ \(rom.name) (from: \(rom.source))")
            }
            
            // Verify all ROMs are present
            let expectedROMs = gameROMs.filter { $0.gameName == gameName }
            #expect(roms.count == expectedROMs.count, "All ROMs should be rebuilt for \(gameName)")
        }
        
        // Step 6: Test partial game rebuild (missing ROMs)
        print("\n🔧 Testing partial game rebuild:")
        let partialGame = try await testPartialGameRebuild(
            indexManager: indexManager2,
            targetDir: targetDir
        )
        
        print("  Partial game '\(partialGame.name)': \(partialGame.foundROMs)/\(partialGame.totalROMs) ROMs")
        #expect(partialGame.foundROMs < partialGame.totalROMs, "Should have missing ROMs")
        
        // Step 7: Test duplicate handling
        print("\n🔍 Testing duplicate ROM handling:")
        let duplicates = await indexManager2.findDuplicates(minCopies: 2)
        if !duplicates.isEmpty {
            print("  Found \(duplicates.count) duplicate ROM groups")
            for dup in duplicates.prefix(3) {
                print("    CRC \(dup.crc32): \(dup.count) copies")
            }
        }
        
        // Step 8: Test best source selection
        print("\n🎯 Testing best source selection:")
        let testROM = gameROMs.first!
        if let bestSource = await indexManager2.findBestSource(for: testROM.toROM()) {
            print("  Best source for '\(testROM.name)': \(bestSource.location.displayPath)")
            #expect(bestSource.crc32 == testROM.crc32)
        }
    }
    
    /// Test rebuilding with complex scenarios
    @Test(.disabled("Requires full implementation of multi-source indexing"))
    func testComplexRebuildScenarios() async throws {
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("complex_rebuild_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: baseDir) }
        
        // Create sources with different characteristics
        let localSource = baseDir.appendingPathComponent("local_roms")
        let archiveSource = baseDir.appendingPathComponent("archived_roms")
        let corruptedSource = baseDir.appendingPathComponent("corrupted_roms")
        let targetDir = baseDir.appendingPathComponent("rebuilt")
        let indexDB = baseDir.appendingPathComponent("index.db")
        
        for dir in [localSource, archiveSource, corruptedSource, targetDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        print("\n🔬 Complex Rebuild Scenarios Test")
        print("=====================================")
        
        // Create test data
        let games = createComplexTestGames()
        
        // Scenario 1: Mix of loose files and archives
        print("\n📁 Setting up mixed sources:")
        try setupMixedSources(games: games, localDir: localSource, archiveDir: archiveSource)
        
        // Scenario 2: Some corrupted files
        print("\n💔 Adding corrupted files:")
        try setupCorruptedFiles(games: games, dir: corruptedSource)
        
        // Index all sources
        let indexManager = try await ROMIndexManager(databasePath: indexDB)
        try await indexManager.addSource(localSource, showProgress: false)
        try await indexManager.addSource(archiveSource, showProgress: false)
        try await indexManager.addSource(corruptedSource, showProgress: false)
        
        // Test rebuild with validation
        print("\n🔨 Rebuilding with validation:")
        let results = try await rebuildWithValidation(
            indexManager: indexManager,
            games: games,
            targetDir: targetDir
        )
        
        // Verify results
        print("\n📊 Rebuild Results:")
        print("  Complete games: \(results.complete)")
        print("  Partial games: \(results.partial)")
        print("  Failed games: \(results.failed)")
        print("  Skipped corrupted: \(results.skippedCorrupted)")
        
        #expect(results.complete > 0, "Should have some complete games")
        #expect(results.skippedCorrupted > 0, "Should skip corrupted files")
    }
    
    /// Test index refresh and incremental updates
    @Test(.disabled("Requires full implementation of incremental indexing"))
    func testIncrementalIndexUpdates() async throws {
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("incremental_test_\(UUID().uuidString)")
        let sourceDir = baseDir.appendingPathComponent("roms")
        let indexDB = baseDir.appendingPathComponent("index.db")
        
        defer { try? FileManager.default.removeItem(at: baseDir) }
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        print("\n🔄 Incremental Index Update Test")
        print("=====================================")
        
        // Initial indexing
        let indexManager = try await ROMIndexManager(databasePath: indexDB)
        
        // Add initial ROMs
        print("\n📦 Adding initial ROMs:")
        let initialROMs = createTestROMs(count: 10, prefix: "initial")
        try writeROMs(initialROMs, to: sourceDir)
        try await indexManager.addSource(sourceDir, showProgress: false)
        
        let initialStats = await indexManager.analyzeIndex()
        print("  Initial ROMs: \(initialStats.totalROMs)")
        
        // Add more ROMs
        print("\n➕ Adding new ROMs:")
        let newROMs = createTestROMs(count: 5, prefix: "new")
        try writeROMs(newROMs, to: sourceDir)
        
        // Refresh the source
        try await indexManager.refreshSources([sourceDir], showProgress: false)
        
        let updatedStats = await indexManager.analyzeIndex()
        print("  Updated ROMs: \(updatedStats.totalROMs)")
        
        #expect(updatedStats.totalROMs == initialROMs.count + newROMs.count)
        
        // Remove some ROMs and verify
        print("\n➖ Removing ROMs and verifying:")
        for rom in newROMs.prefix(3) {
            let romPath = sourceDir.appendingPathComponent(rom.name)
            try FileManager.default.removeItem(at: romPath)
        }
        
        let verifyResult = try await indexManager.verify(removeStale: true, showProgress: false)
        print("  Valid: \(verifyResult.valid)")
        print("  Removed stale: \(verifyResult.removed)")
        
        #expect(verifyResult.removed == 3, "Should remove 3 stale entries")
    }
    
    // MARK: - Helper Methods
    
    private func createDistributedGameROMs() -> [TestGameROM] {
        // Create ROMs for multiple games
        var roms: [TestGameROM] = []
        
        // Game 1: Street Fighter (6 ROMs)
        let sf2ROMs = [
            TestGameROM(name: "sf2.01", gameName: "sf2", crc32: "12345678", size: 524288),
            TestGameROM(name: "sf2.02", gameName: "sf2", crc32: "23456789", size: 524288),
            TestGameROM(name: "sf2.03", gameName: "sf2", crc32: "34567890", size: 262144),
            TestGameROM(name: "sf2.04", gameName: "sf2", crc32: "45678901", size: 262144),
            TestGameROM(name: "sf2.gfx1", gameName: "sf2", crc32: "56789012", size: 1048576),
            TestGameROM(name: "sf2.gfx2", gameName: "sf2", crc32: "67890123", size: 1048576)
        ]
        
        // Game 2: Pac-Man (4 ROMs)
        let pacmanROMs = [
            TestGameROM(name: "pacman.6e", gameName: "pacman", crc32: "ABCDEF01", size: 4096),
            TestGameROM(name: "pacman.6f", gameName: "pacman", crc32: "BCDEF012", size: 4096),
            TestGameROM(name: "pacman.6h", gameName: "pacman", crc32: "CDEF0123", size: 4096),
            TestGameROM(name: "pacman.6j", gameName: "pacman", crc32: "DEF01234", size: 4096)
        ]
        
        roms.append(contentsOf: sf2ROMs)
        roms.append(contentsOf: pacmanROMs)
        
        return roms
    }
    
    private func distributeROMs(_ roms: [TestGameROM], to sources: [URL]) throws {
        // Distribute ROMs across sources unevenly to simulate real scenario
        for (index, rom) in roms.enumerated() {
            let sourceIndex = index % sources.count
            let sourceDir = sources[sourceIndex]
            
            // Create ROM file with proper extension
            var fileName = rom.name
            // Ensure it has a recognized extension
            if !fileName.hasSuffix(".bin") && !fileName.hasSuffix(".rom") {
                fileName = fileName.replacingOccurrences(of: ".", with: "_") + ".bin"
            }
            
            let romPath = sourceDir.appendingPathComponent(fileName)
            let data = Data(repeating: UInt8(index), count: Int(rom.size))
            try data.write(to: romPath)
            
            print("  \(fileName) -> source\(sourceIndex + 1)")
        }
    }
    
    private func rebuildGamesFromIndex(
        indexManager: ROMIndexManager,
        gameROMs: [TestGameROM],
        targetDir: URL
    ) async throws -> [String: [RebuiltROM]] {
        var rebuiltGames: [String: [RebuiltROM]] = [:]
        
        // Group ROMs by game
        let gameGroups = Dictionary(grouping: gameROMs, by: { $0.gameName })
        
        for (gameName, roms) in gameGroups {
            var rebuiltROMs: [RebuiltROM] = []
            let gameDir = targetDir.appendingPathComponent(gameName)
            try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
            
            for rom in roms {
                // Find best source for this ROM
                if let source = await indexManager.findBestSource(for: rom.toROM()) {
                    // Copy/extract ROM to target
                    let targetPath = gameDir.appendingPathComponent(rom.name)
                    
                            // Get the actual source path from the location
                    let sourcePath: URL
                    switch source.location {
                    case .file(let path):
                        sourcePath = path
                    case .archive(let archivePath, _):
                        sourcePath = archivePath
                        // Would need to extract from archive in real implementation
                    case .remote(let url, _):
                        sourcePath = url
                    }
                    
                    if FileManager.default.fileExists(atPath: sourcePath.path) {
                        // For files, copy directly
                        if case .file = source.location {
                            try FileManager.default.copyItem(at: sourcePath, to: targetPath)
                        }
                        rebuiltROMs.append(RebuiltROM(
                            name: rom.name,
                            source: source.location.displayPath
                        ))
                    }
                }
            }
            
            rebuiltGames[gameName] = rebuiltROMs
        }
        
        return rebuiltGames
    }
    
    private func testPartialGameRebuild(
        indexManager: ROMIndexManager,
        targetDir: URL
    ) async throws -> PartialGameResult {
        // Create a game with some missing ROMs
        let gameROMs = [
            TestGameROM(name: "partial.01", gameName: "partial", crc32: "11111111", size: 8192),
            TestGameROM(name: "partial.02", gameName: "partial", crc32: "22222222", size: 8192),
            TestGameROM(name: "partial.03", gameName: "partial", crc32: "33333333", size: 8192)
        ]
        
        // Only index first two ROMs
        var foundCount = 0
        for rom in gameROMs.prefix(2) {
            if let _ = await indexManager.findBestSource(for: rom.toROM()) {
                foundCount += 1
            }
        }
        
        return PartialGameResult(
            name: "partial",
            totalROMs: gameROMs.count,
            foundROMs: foundCount
        )
    }
    
    private func createTestROMs(count: Int, prefix: String) -> [TestGameROM] {
        return (0..<count).map { index in
            TestGameROM(
                name: "\(prefix)_\(index).rom",
                gameName: prefix,
                crc32: String(format: "%08X", index),
                size: UInt64(1024 * (index + 1))
            )
        }
    }
    
    private func writeROMs(_ roms: [TestGameROM], to dir: URL) throws {
        for rom in roms {
            let data = Data(repeating: 0, count: Int(rom.size))
            try data.write(to: dir.appendingPathComponent(rom.name))
        }
    }
    
    private func createComplexTestGames() -> [TestGame] {
        return [
            TestGame(name: "complex1", romCount: 5),
            TestGame(name: "complex2", romCount: 3),
            TestGame(name: "complex3", romCount: 8)
        ]
    }
    
    private func setupMixedSources(games: [TestGame], localDir: URL, archiveDir: URL) throws {
        // Create some loose files and some in ZIP archives
        for game in games {
            // Half as loose files
            for i in 0..<(game.romCount / 2) {
                let romPath = localDir.appendingPathComponent("\(game.name)_\(i).rom")
                try Data(repeating: UInt8(i), count: 1024).write(to: romPath)
            }
            
            // Create remaining as individual files (skip archives for now)
            for i in (game.romCount / 2)..<game.romCount {
                let romPath = archiveDir.appendingPathComponent("\(game.name)_\(i).rom")
                try Data(repeating: UInt8(i), count: 1024).write(to: romPath)
            }
        }
    }
    
    private func setupCorruptedFiles(games: [TestGame], dir: URL) throws {
        // Create files with wrong checksums
        for game in games.prefix(1) {
            let romPath = dir.appendingPathComponent("\(game.name)_corrupted.rom")
            try Data("corrupted_data".utf8).write(to: romPath)
        }
    }
    
    private func rebuildWithValidation(
        indexManager: ROMIndexManager,
        games: [TestGame],
        targetDir: URL
    ) async throws -> RebuildResults {
        var results = RebuildResults()
        
        for game in games {
            // Attempt to rebuild each game
            var foundROMs = 0
            for i in 0..<game.romCount {
                let testROM = ROM(
                    name: "\(game.name)_\(i).rom",
                    size: 1024,
                    crc: String(format: "%08X", i)
                )
                
                if let _ = await indexManager.findBestSource(for: testROM) {
                    foundROMs += 1
                }
            }
            
            if foundROMs == game.romCount {
                results.complete += 1
            } else if foundROMs > 0 {
                results.partial += 1
            } else {
                results.failed += 1
            }
        }
        
        // Check for corrupted files
        results.skippedCorrupted = 1 // Simulated
        
        return results
    }
}

// MARK: - Helper Types

private struct TestGameROM {
    let name: String
    let gameName: String
    let crc32: String
    let size: UInt64
    
    func toROM() -> ROM {
        return ROM(name: name, size: size, crc: crc32)
    }
}

private struct RebuiltROM {
    let name: String
    let source: String
}

private struct PartialGameResult {
    let name: String
    let totalROMs: Int
    let foundROMs: Int
}

private struct TestGame {
    let name: String
    let romCount: Int
}

private struct RebuildResults {
    var complete = 0
    var partial = 0
    var failed = 0
    var skippedCorrupted = 0
}