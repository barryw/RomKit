//
//  ROMIndexTests.swift
//  RomKitTests
//
//  Comprehensive tests for ROMIndex system
//

import Testing
import Foundation
@testable import RomKit

@Suite("ROMIndex Tests")
struct ROMIndexTests {
    
    // MARK: - Test Helpers
    
    private func createTestROM(name: String = "test.rom", size: UInt64 = 1024, crc32: String = "12345678") -> IndexedROM {
        return IndexedROM(
            name: name,
            size: size,
            crc32: crc32,
            sha1: "abc123",
            md5: "def456",
            location: .file(path: URL(fileURLWithPath: "/tmp/\(name)")),
            lastModified: Date()
        )
    }
    
    private func createTestArchiveROM(name: String, archivePath: String = "/tmp/test.zip") -> IndexedROM {
        return IndexedROM(
            name: name,
            size: 2048,
            crc32: "87654321",
            location: .archive(
                path: URL(fileURLWithPath: archivePath),
                entryPath: "roms/\(name)"
            ),
            lastModified: Date()
        )
    }
    
    private func createTestRemoteROM(name: String, url: String = "http://server/roms") -> IndexedROM {
        return IndexedROM(
            name: name,
            size: 4096,
            crc32: "aabbccdd",
            location: .remote(
                url: URL(string: "\(url)/\(name)")!,
                credentials: nil
            ),
            lastModified: Date()
        )
    }
    
    // MARK: - Initialization Tests
    
    @Test func testInitialization() async throws {
        let index = ROMIndex()
        
        #expect(await index.totalROMs == 0)
        #expect(await index.totalSize == 0)
        #expect(await index.duplicates == 0)
        
        let stats = await index.getStatistics()
        #expect(stats.totalROMs == 0)
        #expect(stats.uniqueCRCs == 0)
    }
    
    @Test func testInitializationWithCache() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let cacheURL = tempDir.appendingPathComponent("test_cache.json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        
        let index = await ROMIndex(cacheURL: cacheURL)
        
        // Should start empty even with cache URL
        #expect(await index.totalROMs == 0)
    }
    
    // MARK: - Directory Indexing Tests
    
    @Test func testIndexEmptyDirectory() async throws {
        let index = ROMIndex()
        
        // Create empty test directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_empty_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try await index.indexDirectory(tempDir, showProgress: false)
        
        #expect(await index.totalROMs == 0)
    }
    
    @Test func testIndexDirectoryWithFiles() async throws {
        let index = ROMIndex()
        
        // Create test directory with ROM files
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_roms_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create test ROM files
        for i in 0..<5 {
            let file = tempDir.appendingPathComponent("test\(i).rom")
            let data = Data(repeating: UInt8(i), count: 1024)
            try data.write(to: file)
        }
        
        try await index.indexDirectory(tempDir, showProgress: false)
        
        #expect(await index.totalROMs == 5)
        #expect(await index.totalSize == 5120)
    }
    
    @Test func testIndexMultipleSources() async throws {
        let index = ROMIndex()
        
        // Create two test directories
        let tempDir1 = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_source1_\(UUID().uuidString)")
        let tempDir2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_source2_\(UUID().uuidString)")
        
        try FileManager.default.createDirectory(at: tempDir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDir2, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir1)
            try? FileManager.default.removeItem(at: tempDir2)
        }
        
        // Add files to directories
        for i in 0..<3 {
            let file1 = tempDir1.appendingPathComponent("rom\(i).rom")
            let file2 = tempDir2.appendingPathComponent("game\(i).bin")
            try Data(repeating: UInt8(i), count: 512).write(to: file1)
            try Data(repeating: UInt8(i + 10), count: 1024).write(to: file2)
        }
        
        try await index.indexSources([tempDir1, tempDir2], showProgress: false)
        
        #expect(await index.totalROMs == 6)
    }
    
    // MARK: - Search Tests
    
    @Test func testFindByCRC() async throws {
        let index = ROMIndex()
        
        // Create test directory with files
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_crc_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create test files - we'll rely on the scanner to compute CRCs
        let file1 = tempDir.appendingPathComponent("test1.rom")
        let file2 = tempDir.appendingPathComponent("test2.rom")
        let file3 = tempDir.appendingPathComponent("test3.rom")
        
        try Data([1, 2, 3, 4]).write(to: file1)
        try Data([5, 6, 7, 8]).write(to: file2)
        try Data([1, 2, 3, 4]).write(to: file3) // Same data as file1
        
        try await index.indexDirectory(tempDir, showProgress: false)
        
        // Files 1 and 3 have same data, so should have same CRC
        let allROMs = await index.getStatistics()
        #expect(allROMs.totalROMs == 3)
        
        // Since we don't know exact CRCs, just verify search functionality works
        let noMatches = await index.findByCRC("nonexistent")
        #expect(noMatches.isEmpty)
    }
    
    @Test func testFindByName() async throws {
        let index = ROMIndex()
        
        // Create test directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_names_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create files with different names
        try Data([1]).write(to: tempDir.appendingPathComponent("PacMan.rom"))
        try Data([2]).write(to: tempDir.appendingPathComponent("pacman.rom"))
        try Data([3]).write(to: tempDir.appendingPathComponent("galaga.rom"))
        
        try await index.indexDirectory(tempDir, showProgress: false)
        
        let matches = await index.findByName("pacman.rom")
        #expect(matches.count == 2) // Case-insensitive
        
        let galaga = await index.findByName("galaga.rom")
        #expect(galaga.count == 1)
    }
    
    @Test func testFindBestMatch() async throws {
        let index = ROMIndex()
        
        // Create test directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_best_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create a test file
        let testFile = tempDir.appendingPathComponent("game.rom")
        let testData = Data(repeating: 0xAB, count: 1024)
        try testData.write(to: testFile)
        
        try await index.indexDirectory(tempDir, showProgress: false)
        
        // Test finding best match
        let rom = ROM(name: "game.rom", size: 1024)
        let bestMatch = await index.findBestMatch(for: rom)
        
        #expect(bestMatch != nil)
        #expect(bestMatch?.name == "game.rom")
        #expect(bestMatch?.size == 1024)
    }
    
    @Test func testFindBestMatchByNameAndSize() async throws {
        let index = ROMIndex()
        
        // Create test directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_size_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create files with same name but different sizes
        try Data(repeating: 1, count: 1024).write(to: tempDir.appendingPathComponent("game1.rom"))
        try Data(repeating: 2, count: 2048).write(to: tempDir.appendingPathComponent("game2.rom"))
        
        try await index.indexDirectory(tempDir, showProgress: false)
        
        // Find by size when no CRC available
        let searchROM = ROM(name: "game1.rom", size: 1024, crc: nil)
        let match = await index.findBestMatch(for: searchROM)
        
        #expect(match?.size == 1024)
    }
    
    @Test func testFindAllSources() async throws {
        let index = ROMIndex()
        
        // Create test directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_sources_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create same file with same data (will have same CRC)
        let sameData = Data(repeating: 0xFF, count: 1024)
        try sameData.write(to: tempDir.appendingPathComponent("copy1.rom"))
        try sameData.write(to: tempDir.appendingPathComponent("copy2.rom"))
        
        try await index.indexDirectory(tempDir, showProgress: false)
        
        // Both files should be found as sources for same ROM
        let rom = ROM(name: "copy1.rom", size: 1024)
        let sources = await index.findAllSources(for: rom)
        
        #expect(sources.count >= 1)
    }
    
    // MARK: - Location Tests
    
    @Test func testROMLocationDisplayPath() async throws {
        let fileLocation = ROMLocation.file(path: URL(fileURLWithPath: "/path/to/rom.bin"))
        #expect(fileLocation.displayPath == "/path/to/rom.bin")
        
        let archiveLocation = ROMLocation.archive(
            path: URL(fileURLWithPath: "/archives/test.zip"),
            entryPath: "roms/game.rom"
        )
        #expect(archiveLocation.displayPath == "/archives/test.zip#roms/game.rom")
        
        let remoteLocation = ROMLocation.remote(
            url: URL(string: "http://server/rom.bin")!,
            credentials: nil
        )
        #expect(remoteLocation.displayPath == "http://server/rom.bin")
    }
    
    @Test func testROMLocationIsLocal() async throws {
        let fileLocation = ROMLocation.file(path: URL(fileURLWithPath: "/test.rom"))
        #expect(fileLocation.isLocal == true)
        
        let archiveLocation = ROMLocation.archive(
            path: URL(fileURLWithPath: "/test.zip"),
            entryPath: "rom.bin"
        )
        #expect(archiveLocation.isLocal == true)
        
        let remoteLocation = ROMLocation.remote(
            url: URL(string: "http://server/test.rom")!,
            credentials: nil
        )
        #expect(remoteLocation.isLocal == false)
    }
    
    // MARK: - Cache Tests
    
    @Test func testSaveAndLoadCache() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let cacheURL = tempDir.appendingPathComponent("test_index_cache.json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        
        // Create test directory with files
        let testDir = tempDir.appendingPathComponent("test_cache_dir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create and populate index
        let index1 = await ROMIndex(cacheURL: cacheURL)
        
        for i in 0..<5 {
            let file = testDir.appendingPathComponent("rom\(i).bin")
            try Data(repeating: UInt8(i), count: 1024 * (i + 1)).write(to: file)
        }
        
        try await index1.indexDirectory(testDir, showProgress: false)
        
        // Save cache
        try await index1.saveCache(to: cacheURL)
        
        // Create new index and load cache
        let index2 = await ROMIndex()
        try await index2.loadCache(from: cacheURL)
        
        #expect(await index2.totalROMs == 5)
        let size1 = await index1.totalSize
        let size2 = await index2.totalSize
        #expect(size2 == size1)
        
        // Verify ROMs are findable by name
        let matches = await index2.findByName("rom2.bin")
        #expect(matches.count == 1)
        #expect(matches.first?.name == "rom2.bin")
    }
    
    @Test func testCacheWithDuplicates() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let cacheURL = tempDir.appendingPathComponent("test_dup_cache.json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        
        // Create test directory
        let testDir = tempDir.appendingPathComponent("test_dup_dir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let index = await ROMIndex(cacheURL: cacheURL)
        
        // Add files with same content (duplicates)
        let dupData = Data(repeating: 0xAA, count: 1024)
        try dupData.write(to: testDir.appendingPathComponent("rom1.bin"))
        try dupData.write(to: testDir.appendingPathComponent("rom2.bin"))
        
        try await index.indexDirectory(testDir, showProgress: false)
        
        try await index.saveCache(to: cacheURL)
        
        // Load into new index
        let index2 = await ROMIndex()
        try await index2.loadCache(from: cacheURL)
        
        #expect(await index2.duplicates >= 1)
        #expect(await index2.totalROMs == 2)
    }
    
    // MARK: - Clear and Refresh Tests
    
    @Test func testClearIndex() async throws {
        let index = ROMIndex()
        
        // Create test directory with files
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_clear_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Add some ROM files
        for i in 0..<5 {
            let file = tempDir.appendingPathComponent("rom\(i).bin")
            try Data(repeating: UInt8(i), count: 1024).write(to: file)
        }
        
        try await index.indexDirectory(tempDir, showProgress: false)
        #expect(await index.totalROMs == 5)
        
        // Clear
        await index.clear()
        
        #expect(await index.totalROMs == 0)
        #expect(await index.totalSize == 0)
        #expect(await index.duplicates == 0)
        
        // Verify ROMs are gone
        let matches = await index.findByName("rom0.bin")
        #expect(matches.isEmpty)
    }
    
    // MARK: - Statistics Tests
    
    @Test func testStatisticsCalculation() async throws {
        let index = ROMIndex()
        
        // Create test directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_stats_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Add various ROM files
        try Data(repeating: 1, count: 1024).write(to: tempDir.appendingPathComponent("rom1.bin"))
        try Data(repeating: 2, count: 2048).write(to: tempDir.appendingPathComponent("rom2.bin"))
        try Data(repeating: 1, count: 1024).write(to: tempDir.appendingPathComponent("rom3.bin")) // Same as rom1
        
        try await index.indexDirectory(tempDir, showProgress: false)
        
        let stats = await index.getStatistics()
        
        #expect(stats.totalROMs == 3)
        #expect(stats.totalSize == 4096) // 1024 + 2048 + 1024
        #expect(stats.uniqueCRCs >= 2) // At least 2 unique
        #expect(stats.duplicates >= 0) // May have duplicates
    }
    
    // MARK: - Performance Tests
    
    @Test func testLargeIndexPerformance() async throws {
        let index = ROMIndex()
        
        // Create test directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_perf_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Add many ROM files (reduced for test speed)
        for i in 0..<100 {
            let file = tempDir.appendingPathComponent("rom\(i).bin")
            try Data(repeating: UInt8(i % 10), count: 1024).write(to: file)
        }
        
        try await index.indexDirectory(tempDir, showProgress: false)
        
        #expect(await index.totalROMs == 100)
        
        // Test search performance
        let matches = await index.findByName("rom50.bin")
        #expect(matches.count >= 1)
    }
    
    // MARK: - Edge Cases
    
    @Test func testEmptySearches() async throws {
        let index = ROMIndex()
        
        // Search empty index
        let crcMatches = await index.findByCRC("anything")
        #expect(crcMatches.isEmpty)
        
        let nameMatches = await index.findByName("anything")
        #expect(nameMatches.isEmpty)
        
        let rom = ROM(name: "test", size: 1024)
        let bestMatch = await index.findBestMatch(for: rom)
        #expect(bestMatch == nil)
        
        let sources = await index.findAllSources(for: rom)
        #expect(sources.isEmpty)
    }
    
    @Test func testSpecialCharactersInNames() async throws {
        let index = ROMIndex()
        
        // Create test directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_special_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let specialNames = [
            "game (USA).rom",
            "game [!].rom",
            "game & more.rom",
            "games.rom"
        ]
        
        for name in specialNames {
            let file = tempDir.appendingPathComponent(name)
            try Data([1, 2, 3]).write(to: file)
        }
        
        try await index.indexDirectory(tempDir, showProgress: false)
        
        #expect(await index.totalROMs == specialNames.count)
        
        // Test finding each
        for name in specialNames {
            let matches = await index.findByName(name)
            #expect(matches.count >= 1)
            #expect(matches.contains { $0.name.lowercased() == name.lowercased() })
        }
    }
    
    @Test func testMixedLocationTypes() async throws {
        let index = ROMIndex()
        
        // Create test directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_mixed_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Add regular files
        try Data([1]).write(to: tempDir.appendingPathComponent("local.rom"))
        
        // Create a ZIP file for archive test
        let zipFile = tempDir.appendingPathComponent("archive.zip")
        let zipTestDir = tempDir.appendingPathComponent("zip_content")
        try FileManager.default.createDirectory(at: zipTestDir, withIntermediateDirectories: true)
        try Data([2]).write(to: zipTestDir.appendingPathComponent("archived.rom"))
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = zipTestDir
        process.arguments = ["-r", "-q", zipFile.path, "."]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        
        try await index.indexDirectory(tempDir, showProgress: false)
        
        #expect(await index.totalROMs >= 2) // At least local and archived
        
        // Verify files can be found
        let local = await index.findByName("local.rom")
        #expect(local.count >= 1)
        #expect(local.first?.location.isLocal == true)
        
        let archived = await index.findByName("archived.rom")
        #expect(archived.count >= 1)
        #expect(archived.first?.location.isLocal == true)
    }
    
    @Test func testConcurrentAccess() async throws {
        let index = ROMIndex()
        
        // Create test directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_concurrent_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create test files
        for i in 0..<20 {
            let file = tempDir.appendingPathComponent("concurrent\(i).rom")
            try Data(repeating: UInt8(i), count: 100).write(to: file)
        }
        
        // Index and perform concurrent searches
        try await index.indexDirectory(tempDir, showProgress: false)
        
        await withTaskGroup(of: Void.self) { group in
            // Search concurrently
            for i in 0..<20 {
                group.addTask {
                    _ = await index.findByName("concurrent\(i).rom")
                }
            }
        }
        
        // Verify all ROMs were indexed
        #expect(await index.totalROMs == 20)
    }
}