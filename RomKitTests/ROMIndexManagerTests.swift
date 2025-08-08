//
//  ROMIndexManagerTests.swift
//  RomKitTests
//
//  Tests for ROMIndexManager to improve code coverage
//

import Testing
import Foundation
@testable import RomKit

struct ROMIndexManagerTests {

    @Test func testIndexManagerCreation() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempDB) }

        // Test creation with custom path
        _ = try await ROMIndexManager(databasePath: tempDB)
        // Successfully created without error
        #expect(true)

        // Test creation with default path
        _ = try await ROMIndexManager()
        // Successfully created without error
        #expect(true)
    }

    @Test func testAddAndRemoveSource() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).db")
        let sourceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("source_\(UUID().uuidString)")

        defer {
            try? FileManager.default.removeItem(at: tempDB)
            try? FileManager.default.removeItem(at: sourceDir)
        }

        // Create source directory with test files
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("test".utf8).write(to: sourceDir.appendingPathComponent("test.rom"))

        let manager = try await ROMIndexManager(databasePath: tempDB)

        // Test adding source
        try await manager.addSource(sourceDir, showProgress: false)
        let sources = await manager.listSources()
        #expect(!sources.isEmpty)

        // Test removing source
        try await manager.removeSource(sourceDir, showProgress: false)
        let sourcesAfter = await manager.listSources()
        #expect(sourcesAfter.count == sources.count - 1)
    }

    @Test func testFindROM() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempDB) }

        let manager = try await ROMIndexManager(databasePath: tempDB)

        // Test finding non-existent ROM
        let result = try await manager.findROM(crc32: "12345678")
        #expect(result == nil)

        // Test finding by name pattern
        let nameResults = await manager.findByName(pattern: "test%", limit: 10)
        #expect(nameResults.isEmpty)
    }

    @Test func testFindDuplicates() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempDB) }

        let manager = try await ROMIndexManager(databasePath: tempDB)

        // Test finding duplicates (should be empty initially)
        let duplicates = await manager.findDuplicates(minCopies: 2)
        #expect(duplicates.isEmpty)
    }

    @Test func testAnalyzeIndex() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempDB) }

        let manager = try await ROMIndexManager(databasePath: tempDB)

        // Test analysis
        let analysis = await manager.analyzeIndex()
        #expect(analysis.totalROMs >= 0)
        #expect(analysis.uniqueROMs >= 0)
        #expect(analysis.duplicatePercentage >= 0)
        // Average duplication factor can be 0 if no ROMs are indexed
        #expect(analysis.averageDuplicationFactor >= 0)
    }

    @Test func testVerifyIndex() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempDB) }

        let manager = try await ROMIndexManager(databasePath: tempDB)

        // Test verification
        let result = try await manager.verify(removeStale: false, showProgress: false)
        #expect(result.valid >= 0)
        #expect(result.stale >= 0)
        #expect(result.removed == 0) // Since removeStale is false
    }

    @Test func testOptimizeAndClear() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempDB) }

        let manager = try await ROMIndexManager(databasePath: tempDB)

        // Test optimize
        try await manager.optimize()

        // Test clear
        try await manager.clearAll()

        let analysis = await manager.analyzeIndex()
        #expect(analysis.totalROMs == 0)
    }

    @Test func testExportStatistics() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).db")
        let exportFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("stats_\(UUID().uuidString).json")

        defer {
            try? FileManager.default.removeItem(at: tempDB)
            try? FileManager.default.removeItem(at: exportFile)
        }

        let manager = try await ROMIndexManager(databasePath: tempDB)

        // Test export
        try await manager.exportStatistics(to: exportFile)
        #expect(FileManager.default.fileExists(atPath: exportFile.path))

        // Verify JSON is valid
        let data = try Data(contentsOf: exportFile)
        _ = try JSONDecoder().decode(IndexAnalysis.self, from: data)
    }

    @Test func testRefreshSources() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).db")
        let sourceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("source_\(UUID().uuidString)")

        defer {
            try? FileManager.default.removeItem(at: tempDB)
            try? FileManager.default.removeItem(at: sourceDir)
        }

        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let manager = try await ROMIndexManager(databasePath: tempDB)

        // Test refresh with no sources
        try await manager.refreshSources(nil, showProgress: false)

        // Test refresh with specific sources
        try await manager.refreshSources([sourceDir], showProgress: false)
    }

    @Test func testFindBestSource() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempDB) }

        let manager = try await ROMIndexManager(databasePath: tempDB)

        // Test finding best source for ROM
        let testROM = ROM(name: "test.rom", size: 1024, crc: "ABCD1234")
        let bestSource = await manager.findBestSource(for: testROM)
        #expect(bestSource == nil) // No sources indexed yet
    }
}
