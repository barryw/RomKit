//
//  SQLiteROMIndexTests.swift
//  RomKitTests
//
//  Comprehensive tests for SQLiteROMIndex database operations
//

import Testing
import Foundation
import SQLite3
@testable import RomKit

@Suite("SQLiteROMIndex Tests")
struct SQLiteROMIndexTests {

    // MARK: - Test Helpers

    private func createTestDatabasePath() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("test_index_\(UUID().uuidString).db")
    }

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

    private func createTestDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rom_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createTestFiles(in directory: URL, count: Int = 5) throws {
        for itemIdx in 0..<count {
            let file = directory.appendingPathComponent("rom\(itemIdx).bin")
            let data = Data(repeating: UInt8(itemIdx), count: 1024 + itemIdx * 100)
            try data.write(to: file)
        }
    }

    // MARK: - Initialization Tests

    @Test func testInitialization() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        #expect(await index.totalROMs == 0)
        #expect(await index.totalSize == 0)
        #expect(await index.duplicates == 0)

        // Database file should exist
        #expect(FileManager.default.fileExists(atPath: dbPath.path))
    }

    @Test func testInitializationWithDefaultPath() async throws {
        let index = try await SQLiteROMIndex(databasePath: nil)

        #expect(await index.totalROMs == 0)

        // Clean up default cache
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let romkitDir = cacheDir.appendingPathComponent("RomKit")
            try? FileManager.default.removeItem(at: romkitDir)
        }
    }

    @Test func testDatabaseCreation() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        _ = try await SQLiteROMIndex(databasePath: dbPath)

        // Verify database structure
        var db: OpaquePointer?
        sqlite3_open(dbPath.path, &db)
        defer { sqlite3_close(db) }

        // Check if tables exist
        let query = "SELECT name FROM sqlite_master WHERE type='table'"
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }

        var tables: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 0) {
                tables.append(String(cString: name))
            }
        }

        #expect(tables.contains("roms"))
        #expect(tables.contains("sources"))
        #expect(tables.contains("duplicates"))
    }

    // MARK: - Indexing Tests

    @Test func testIndexDirectory() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let testDir = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }

        try createTestFiles(in: testDir, count: 5)

        let index = try await SQLiteROMIndex(databasePath: dbPath)
        try await index.indexDirectory(testDir, showProgress: false)

        await index.updateStatistics()
        #expect(await index.totalROMs == 5)
        #expect(await index.totalSize > 0)
    }

    @Test func testIndexMultipleSources() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let testDir1 = try createTestDirectory()
        let testDir2 = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: testDir1)
            try? FileManager.default.removeItem(at: testDir2)
        }

        try createTestFiles(in: testDir1, count: 3)
        try createTestFiles(in: testDir2, count: 4)

        let index = try await SQLiteROMIndex(databasePath: dbPath)
        try await index.indexSources([testDir1, testDir2], showProgress: false)

        #expect(await index.totalROMs == 7)

        // Check sources were recorded
        let sources = await index.getSources()
        #expect(sources.count == 2)
    }

    @Test func testIndexArchive() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        // Create a test ZIP file
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("zip_content_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        // Create test files
        for itemIdx in 0..<3 {
            let file = testDir.appendingPathComponent("rom\(itemIdx).bin")
            try Data(repeating: UInt8(itemIdx), count: 1024).write(to: file)
        }

        // Create ZIP
        let zipPath = tempDir.appendingPathComponent("test_archive.zip")
        defer { try? FileManager.default.removeItem(at: zipPath) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = testDir
        process.arguments = ["-r", "-q", zipPath.path, "."]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        // Index the directory containing the archive
        let index = try await SQLiteROMIndex(databasePath: dbPath)
        try await index.indexDirectory(tempDir, showProgress: false)

        await index.updateStatistics()
        #expect(await index.totalROMs >= 3)
    }

    @Test func testTransactionHandling() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Test transaction rollback on error
        do {
            try await index.execute("BEGIN TRANSACTION")
            try await index.execute("INSERT INTO roms (name, size, location_type, location_path, last_modified) VALUES (?, ?, ?, ?, ?)",
                                  parameters: ["test.rom", 1024, "file", "/test.rom", Int(Date().timeIntervalSince1970)])

            // Force an error
            try await index.execute("INSERT INTO nonexistent_table VALUES (?)", parameters: ["test"])

            try await index.execute("COMMIT")
        } catch {
            try? await index.execute("ROLLBACK")
        }

        // Transaction should have been rolled back
        await index.updateStatistics()
        #expect(await index.totalROMs == 0)
    }

    // MARK: - Search Tests

    @Test func testFindByCRC() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Insert test ROMs
        for itemIdx in 0..<5 {
            try await index.execute("""
                INSERT INTO roms (name, size, crc32, location_type, location_path, last_modified)
                VALUES (?, ?, ?, ?, ?, ?)
                """, parameters: [
                    "rom\(itemIdx).bin",
                    1024 + itemIdx * 100,
                    itemIdx < 3 ? "duplicate" : "unique\(itemIdx)",
                    "file",
                    "/tmp/rom\(itemIdx).bin",
                    Int(Date().timeIntervalSince1970)
                ])
        }

        let duplicates = await index.findByCRC("duplicate")
        #expect(duplicates.count == 3)

        let unique = await index.findByCRC("unique4")
        #expect(unique.count == 1)

        let notFound = await index.findByCRC("nonexistent")
        #expect(notFound.isEmpty)
    }

    @Test func testFindByName() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Insert test ROMs with various names
        let names = ["game.rom", "Game.ROM", "another.bin", "test (USA).rom"]
        for name in names {
            try await index.execute("""
                INSERT INTO roms (name, size, crc32, location_type, location_path, last_modified)
                VALUES (?, ?, ?, ?, ?, ?)
                """, parameters: [
                    name,
                    1024,
                    "crc123",
                    "file",
                    "/tmp/\(name)",
                    Int(Date().timeIntervalSince1970)
                ])
        }

        // Test case-insensitive search
        let gameMatches = await index.findByName("game.rom")
        #expect(gameMatches.count == 2)

        // Test wildcard search
        let wildcardMatches = await index.findByName("%USA%")
        #expect(wildcardMatches.count == 1)

        // Test exact match
        let exactMatch = await index.findByName("another.bin")
        #expect(exactMatch.count == 1)
    }

    @Test func testFindBySize() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Insert ROMs with various sizes
        let sizes: [UInt64] = [512, 1024, 2048, 4096, 8192]
        for (idx, size) in sizes.enumerated() {
            try await index.execute("""
                INSERT INTO roms (name, size, crc32, location_type, location_path, last_modified)
                VALUES (?, ?, ?, ?, ?, ?)
                """, parameters: [
                    "rom\(idx).bin",
                    Int(size),
                    "crc\(idx)",
                    "file",
                    "/tmp/rom\(idx).bin",
                    Int(Date().timeIntervalSince1970)
                ])
        }

        // Test range queries
        let small = await index.findBySize(min: nil, max: 1024)
        #expect(small.count == 2) // 512 and 1024

        let medium = await index.findBySize(min: 1025, max: 4096)
        #expect(medium.count == 2) // 2048 and 4096

        let large = await index.findBySize(min: 4096, max: nil)
        #expect(large.count == 2) // 4096 and 8192

        let exact = await index.findBySize(min: 2048, max: 2048)
        #expect(exact.count == 1)
    }

    @Test func testFindBestMatch() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Insert multiple versions of same ROM
        try await index.execute("""
            INSERT INTO roms (name, size, crc32, location_type, location_path, last_modified)
            VALUES (?, ?, ?, ?, ?, ?)
            """, parameters: [
                "game.rom",
                1024,
                "abc123",
                "file",
                "/tmp/game.rom",
                Int(Date().timeIntervalSince1970)
            ])

        try await index.execute("""
            INSERT INTO roms (name, size, crc32, location_type, location_path, last_modified)
            VALUES (?, ?, ?, ?, ?, ?)
            """, parameters: [
                "game.rom",
                1024,
                "abc123",
                "archive",
                "/tmp/archive.zip",
                Int(Date().timeIntervalSince1970)
            ])

        let rom = ROM(name: "game.rom", size: 1024, crc: "abc123")
        let bestMatch = await index.findBestMatch(for: rom)

        #expect(bestMatch != nil)
        #expect(bestMatch?.crc32 == "abc123")
    }

    @Test func testFindDuplicates() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Insert duplicates
        for itemIdx in 0..<10 {
            let crc = itemIdx < 5 ? "dup1" : (itemIdx < 8 ? "dup2" : "unique\(itemIdx)")
            try await index.execute("""
                INSERT INTO roms (name, size, crc32, location_type, location_path, last_modified)
                VALUES (?, ?, ?, ?, ?, ?)
                """, parameters: [
                    "rom\(itemIdx).bin",
                    1024,
                    crc,
                    "file",
                    "/tmp/rom\(itemIdx).bin",
                    Int(Date().timeIntervalSince1970)
                ])
        }

        let duplicates = await index.findDuplicates()

        #expect(duplicates.count == 2) // dup1 and dup2

        if let dup1 = duplicates.first(where: { $0.crc32 == "dup1" }) {
            #expect(dup1.count == 5)
            #expect(dup1.locations.count == 5)
        }

        if let dup2 = duplicates.first(where: { $0.crc32 == "dup2" }) {
            #expect(dup2.count == 3)
            #expect(dup2.locations.count == 3)
        }
    }

    // MARK: - Statistics Tests

    @Test func testUpdateStatistics() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Insert test data
        for itemIdx in 0..<10 {
            try await index.execute("""
                INSERT INTO roms (name, size, crc32, location_type, location_path, last_modified)
                VALUES (?, ?, ?, ?, ?, ?)
                """, parameters: [
                    "rom\(itemIdx).bin",
                    1024 * (itemIdx + 1),
                    itemIdx < 5 ? "duplicate" : "unique\(itemIdx)",
                    "file",
                    "/tmp/rom\(itemIdx).bin",
                    Int(Date().timeIntervalSince1970)
                ])
        }

        await index.updateStatistics()

        #expect(await index.totalROMs == 10)
        #expect(await index.totalSize == 55 * 1024) // Sum of 1024 * (1+2+...+10)
        #expect(await index.duplicates == 1) // One CRC with duplicates
    }

    @Test func testGetStatistics() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Add some test data
        for itemIdx in 0..<5 {
            try await index.execute("""
                INSERT INTO roms (name, size, crc32, location_type, location_path, last_modified)
                VALUES (?, ?, ?, ?, ?, ?)
                """, parameters: [
                    "rom\(itemIdx).bin",
                    1024,
                    "crc\(itemIdx)",
                    "file",
                    "/tmp/rom\(itemIdx).bin",
                    Int(Date().timeIntervalSince1970)
                ])
        }

        // Add a source
        try await index.execute("""
            INSERT INTO sources (path, last_scan, rom_count, total_size)
            VALUES (?, ?, ?, ?)
            """, parameters: [
                "/tmp/source1",
                Int(Date().timeIntervalSince1970),
                5,
                5120
            ])

        await index.updateStatistics()

        #expect(await index.totalROMs == 5)
        #expect(await index.totalSize == 5120)

        // Check source count separately
        let sources = await index.getSources()
        #expect(sources.count == 1)
    }

    // MARK: - Maintenance Tests

    @Test func testVacuum() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Add and remove data to create fragmentation
        for itemIdx in 0..<100 {
            try await index.execute("""
                INSERT INTO roms (name, size, crc32, location_type, location_path, last_modified)
                VALUES (?, ?, ?, ?, ?, ?)
                """, parameters: [
                    "rom\(itemIdx).bin",
                    1024,
                    "crc\(itemIdx)",
                    "file",
                    "/tmp/rom\(itemIdx).bin",
                    Int(Date().timeIntervalSince1970)
                ])
        }

        // Delete half
        try await index.execute("DELETE FROM roms WHERE CAST(substr(name, 4) AS INTEGER) < 50")

        // Vacuum should work without error
        try await index.vacuum()

        // Database should still be functional
        await index.updateStatistics()
        #expect(await index.totalROMs == 50)
    }

    @Test func testClear() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Add data
        for itemIdx in 0..<10 {
            try await index.execute("""
                INSERT INTO roms (name, size, crc32, location_type, location_path, last_modified)
                VALUES (?, ?, ?, ?, ?, ?)
                """, parameters: [
                    "rom\(itemIdx).bin",
                    1024,
                    "crc\(itemIdx)",
                    "file",
                    "/tmp/rom\(itemIdx).bin",
                    Int(Date().timeIntervalSince1970)
                ])
        }

        try await index.execute("""
            INSERT INTO sources (path, last_scan, rom_count, total_size)
            VALUES (?, ?, ?, ?)
            """, parameters: [
                "/tmp/source",
                Int(Date().timeIntervalSince1970),
                10,
                10240
            ])

        await index.updateStatistics()
        #expect(await index.totalROMs == 10)

        // Clear everything
        try await index.clear()

        #expect(await index.totalROMs == 0)
        #expect(await index.totalSize == 0)

        // Verify tables are empty
        let sources = await index.getSources()
        #expect(sources.isEmpty)
    }

    @Test func testRemoveSource() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Add ROMs from two sources
        for itemIdx in 0..<5 {
            try await index.execute("""
                INSERT INTO roms (name, size, crc32, location_type, location_path, last_modified)
                VALUES (?, ?, ?, ?, ?, ?)
                """, parameters: [
                    "rom\(itemIdx).bin",
                    1024,
                    "crc\(itemIdx)",
                    "file",
                    "/source1/rom\(itemIdx).bin",
                    Int(Date().timeIntervalSince1970)
                ])
        }

        for itemIdx in 5..<10 {
            try await index.execute("""
                INSERT INTO roms (name, size, crc32, location_type, location_path, last_modified)
                VALUES (?, ?, ?, ?, ?, ?)
                """, parameters: [
                    "rom\(itemIdx).bin",
                    1024,
                    "crc\(itemIdx)",
                    "file",
                    "/source2/rom\(itemIdx).bin",
                    Int(Date().timeIntervalSince1970)
                ])
        }

        await index.updateStatistics()
        #expect(await index.totalROMs == 10)

        // Remove one source
        let removed = try await index.removeSource(URL(fileURLWithPath: "/source1"))
        #expect(removed == 5)

        await index.updateStatistics()
        #expect(await index.totalROMs == 5)
    }

    @Test func testVerify() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Create actual test files
        let tempDir = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        for itemIdx in 0..<3 {
            let file = tempDir.appendingPathComponent("rom\(itemIdx).bin")
            try Data(repeating: UInt8(itemIdx), count: 100).write(to: file)

            try await index.execute("""
                INSERT INTO roms (name, size, crc32, location_type, location_path, last_modified)
                VALUES (?, ?, ?, ?, ?, ?)
                """, parameters: [
                    "rom\(itemIdx).bin",
                    100,
                    "crc\(itemIdx)",
                    "file",
                    file.path,
                    Int(Date().timeIntervalSince1970)
                ])
        }

        // Add non-existent files
        for itemIdx in 3..<5 {
            try await index.execute("""
                INSERT INTO roms (name, size, crc32, location_type, location_path, last_modified)
                VALUES (?, ?, ?, ?, ?, ?)
                """, parameters: [
                    "missing\(itemIdx).bin",
                    100,
                    "crc\(itemIdx)",
                    "file",
                    "/nonexistent/missing\(itemIdx).bin",
                    Int(Date().timeIntervalSince1970)
                ])
        }

        // Verify without removing
        let (valid1, stale1) = try await index.verify(removeStale: false)
        #expect(valid1 == 3)
        #expect(stale1 == 2)

        await index.updateStatistics()
        #expect(await index.totalROMs == 5) // Should still have all

        // Verify with removal
        let (valid2, stale2) = try await index.verify(removeStale: true)
        #expect(valid2 == 3)
        #expect(stale2 == 2)

        await index.updateStatistics()
        #expect(await index.totalROMs == 3) // Stale entries removed
    }

    // MARK: - Performance Tests

    @Test func testLargeDatasetPerformance() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Insert many ROMs
        try await index.execute("BEGIN TRANSACTION")

        for itemIdx in 0..<1000 {
            try await index.execute("""
                INSERT INTO roms (name, size, crc32, location_type, location_path, last_modified)
                VALUES (?, ?, ?, ?, ?, ?)
                """, parameters: [
                    "rom\(itemIdx).bin",
                    1024 + itemIdx,
                    "crc\(itemIdx % 100)", // Create some duplicates
                    "file",
                    "/tmp/rom\(itemIdx).bin",
                    Int(Date().timeIntervalSince1970)
                ])
        }

        try await index.execute("COMMIT")

        // Test query performance
        let startSearch = Date()
        let results = await index.findByCRC("crc50")
        let searchDuration = Date().timeIntervalSince(startSearch)

        #expect(results.count == 10) // Should find 10 matches
        #expect(searchDuration < 0.1) // Should be fast with index
    }

    // MARK: - Edge Cases

    @Test func testNullValues() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Insert ROM with null optional fields
        try await index.execute("""
            INSERT INTO roms (name, size, crc32, sha1, md5, location_type, location_path, location_entry, last_modified)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, parameters: [
                "test.rom",
                1024,
                NSNull(), // null CRC
                NSNull(), // null SHA1
                NSNull(), // null MD5
                "file",
                "/tmp/test.rom",
                NSNull(), // null entry
                Int(Date().timeIntervalSince1970)
            ])

        let results = await index.findByName("test.rom")
        #expect(results.count == 1)

        if let rom = results.first {
            #expect(rom.crc32.isEmpty)
            #expect(rom.sha1 == nil)
            #expect(rom.md5 == nil)
        }
    }

    @Test func testSpecialCharactersInPaths() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        let specialPaths = [
            "/path/with spaces/rom.bin",
            "/path/with'quotes/rom.bin",
            "/path/with\"doublequotes/rom.bin",
            "/path/with;semicolon/rom.bin",
            "/日本語/パス/rom.bin"
        ]

        for (idx, path) in specialPaths.enumerated() {
            try await index.execute("""
                INSERT INTO roms (name, size, crc32, location_type, location_path, last_modified)
                VALUES (?, ?, ?, ?, ?, ?)
                """, parameters: [
                    "rom\(idx).bin",
                    1024,
                    "crc\(idx)",
                    "file",
                    path,
                    Int(Date().timeIntervalSince1970)
                ])
        }

        await index.updateStatistics()
        #expect(await index.totalROMs == specialPaths.count)
    }

    @Test func testConcurrentDatabaseAccess() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Perform concurrent operations
        await withTaskGroup(of: Void.self) { group in
            // Concurrent inserts
            for itemIdx in 0..<50 {
                group.addTask {
                    try? await index.execute("""
                        INSERT INTO roms (name, size, crc32, location_type, location_path, last_modified)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """, parameters: [
                            "concurrent\(itemIdx).bin",
                            1024,
                            "crc\(itemIdx)",
                            "file",
                            "/tmp/concurrent\(itemIdx).bin",
                            Int(Date().timeIntervalSince1970)
                        ])
                }
            }

            // Concurrent reads
            for itemIdx in 0..<50 {
                group.addTask {
                    _ = await index.findByCRC("crc\(itemIdx)")
                }
            }
        }

        await index.updateStatistics()
        #expect(await index.totalROMs > 0)
    }

    @Test func testLongRunningTransaction() async throws {
        let dbPath = createTestDatabasePath()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await SQLiteROMIndex(databasePath: dbPath)

        // Start long transaction
        try await index.execute("BEGIN TRANSACTION")

        // Perform many operations
        for itemIdx in 0..<100 {
            try await index.execute("""
                INSERT INTO roms (name, size, crc32, location_type, location_path, last_modified)
                VALUES (?, ?, ?, ?, ?, ?)
                """, parameters: [
                    "batch\(itemIdx).bin",
                    1024,
                    "crc\(itemIdx)",
                    "file",
                    "/tmp/batch\(itemIdx).bin",
                    Int(Date().timeIntervalSince1970)
                ])
        }

        // Commit should succeed
        try await index.execute("COMMIT")

        await index.updateStatistics()
        #expect(await index.totalROMs == 100)
    }
}
