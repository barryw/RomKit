//
//  SQLiteROMIndexSimpleTests.swift
//  RomKitTests
//
//  Simple working tests for SQLiteROMIndex to improve coverage
//

import Testing
import Foundation
@testable import RomKit

struct SQLiteROMIndexSimpleTests {

    @Test("Test SQLiteROMIndex ZIP indexing")
    func testZIPIndexing() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_zip_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_zip_dir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        // Create test ZIP files
        let handler = ParallelZIPArchiveHandler()
        for index in 1...3 {
            let zipPath = testDir.appendingPathComponent("archive\(index).zip")
            let entries: [(name: String, data: Data)] = [
                ("rom1.bin", Data(repeating: UInt8(index), count: 100)),
                ("rom2.bin", Data(repeating: UInt8(index+1), count: 200))
            ]
            try handler.create(at: zipPath, with: entries)
        }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Index directory
        try await index.indexDirectory(testDir, showProgress: false, useOptimized: false)

        await index.updateStatistics()
        #expect(await index.totalROMs == 6) // 3 ZIPs x 2 ROMs each
        #expect(await index.totalSize > 0)
    }

    @Test("Test finding ROMs by name pattern")
    func testFindByName() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_name_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_name_dir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        // Create ZIP with specific ROM names
        let handler = ParallelZIPArchiveHandler()
        let zipPath = testDir.appendingPathComponent("games.zip")
        let entries: [(name: String, data: Data)] = [
            ("mario.rom", Data([0x01])),
            ("sonic.rom", Data([0x02])),
            ("zelda.rom", Data([0x03]))
        ]
        try handler.create(at: zipPath, with: entries)

        let index = try await SQLiteROMIndex(databasePath: dbPath)
        try await index.indexDirectory(testDir, showProgress: false)

        // Find by name pattern
        let marioGames = await index.findByName("%mario%")
        #expect(marioGames.count == 1)
        #expect(marioGames.first?.name == "mario.rom")

        // Find all
        let allGames = await index.findByName("%")
        #expect(allGames.count == 3)
    }

    @Test("Test duplicate detection")
    func testDuplicateDetection() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_dup_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_dup_dir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        // Create ZIPs with duplicate ROMs
        let handler = ParallelZIPArchiveHandler()
        let duplicateData = Data(repeating: 0xAB, count: 1024)

        // First ZIP with duplicate
        let zip1 = testDir.appendingPathComponent("archive1.zip")
        try handler.create(at: zip1, with: [
            ("dup1.rom", duplicateData),
            ("unique1.rom", Data([0x01]))
        ])

        // Second ZIP with same duplicate
        let zip2 = testDir.appendingPathComponent("archive2.zip")
        try handler.create(at: zip2, with: [
            ("dup2.rom", duplicateData),
            ("unique2.rom", Data([0x02]))
        ])

        let index = try await SQLiteROMIndex(databasePath: dbPath)
        try await index.indexDirectory(testDir, showProgress: false)

        // Find duplicates
        let duplicates = await index.findDuplicates()
        #expect(!duplicates.isEmpty)

        // Update statistics to count duplicates
        await index.updateStatistics()
        #expect(await index.duplicates > 0)
    }

    @Test("Test clear and vacuum operations")
    func testClearAndVacuum() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_clear_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_clear_dir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        // Create a ZIP file
        let handler = ParallelZIPArchiveHandler()
        let zipPath = testDir.appendingPathComponent("data.zip")
        try handler.create(at: zipPath, with: [
            ("file1.rom", Data(repeating: 0x01, count: 100)),
            ("file2.rom", Data(repeating: 0x02, count: 200))
        ])

        let index = try await SQLiteROMIndex(databasePath: dbPath)
        try await index.indexDirectory(testDir, showProgress: false)

        // Check has data
        await index.updateStatistics()
        let initialCount = await index.totalROMs
        #expect(initialCount == 2)

        // Vacuum should preserve data
        try await index.vacuum()
        await index.updateStatistics()
        #expect(await index.totalROMs == initialCount)

        // Clear should remove all data
        try await index.clear()
        await index.updateStatistics()
        #expect(await index.totalROMs == 0)
    }

    @Test("Test optimized indexing")
    func testOptimizedIndexing() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_opt_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_opt_dir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        // Create multiple ZIP files to test parallel processing
        let handler = ParallelZIPArchiveHandler()
        for index in 1...3 {
            let zipPath = testDir.appendingPathComponent("archive\(index).zip")
            let entries: [(name: String, data: Data)] = [
                ("rom1.bin", Data(repeating: UInt8(index), count: 100)),
                ("rom2.bin", Data(repeating: UInt8(index+1), count: 200))
            ]
            try handler.create(at: zipPath, with: entries)
        }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Test optimized indexing
        try await index.indexDirectory(testDir, showProgress: false, useOptimized: true)

        await index.updateStatistics()
        #expect(await index.totalROMs == 6) // 3 ZIPs x 2 ROMs each
    }

    @Test("Test statistics and printing")
    func testStatistics() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_stats_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Test statistics with empty index
        await index.updateStatistics()
        await index.printStatistics()

        #expect(await index.totalROMs == 0)
        #expect(await index.totalSize == 0)
        #expect(await index.duplicates == 0)
    }

    @Test("Test finding by size")
    func testFindBySize() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_size_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_size_dir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        // Create ZIP with ROMs of different sizes
        let handler = ParallelZIPArchiveHandler()
        let zipPath = testDir.appendingPathComponent("sizes.zip")
        try handler.create(at: zipPath, with: [
            ("small.rom", Data(repeating: 0x01, count: 100)),
            ("medium.rom", Data(repeating: 0x02, count: 1000)),
            ("large.rom", Data(repeating: 0x03, count: 10000))
        ])

        let index = try await SQLiteROMIndex(databasePath: dbPath)
        try await index.indexDirectory(testDir, showProgress: false)

        // Find small files
        let smallFiles = await index.findBySize(min: 0, max: 500)
        #expect(smallFiles.count == 1)
        #expect(smallFiles.first?.name == "small.rom")

        // Find large files
        let largeFiles = await index.findBySize(min: 5000, max: nil)
        #expect(largeFiles.count == 1)
        #expect(largeFiles.first?.name == "large.rom")
    }
}