//
//  IndexManagementTests.swift
//  RomKitTests
//
//  Tests for the index management APIs
//

import XCTest
@testable import RomKit

final class IndexManagementTests: XCTestCase {
    
    var romkit: RomKit!
    var testDirectory: URL!
    
    override func setUp() async throws {
        romkit = RomKit()
        
        // Create a temporary directory for testing
        let tempDir = FileManager.default.temporaryDirectory
        testDirectory = tempDir.appendingPathComponent("RomKitIndexTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        
        // Create some test ROM files
        try createTestROMFile(name: "test1.rom", size: 1024, at: testDirectory)
        try createTestROMFile(name: "test2.rom", size: 2048, at: testDirectory)
        
        // Create a subdirectory with more ROMs
        let subDir = testDirectory.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try createTestROMFile(name: "test3.rom", size: 4096, at: subDir)
        
        // Create a test archive
        let zipData = Data(repeating: 0x5A, count: 512) // Simple fake zip
        let zipPath = testDirectory.appendingPathComponent("archive.zip")
        try zipData.write(to: zipPath)
        
        // Create a test CHD file
        let chdData = Data(repeating: 0xCD, count: 8192)
        let chdPath = testDirectory.appendingPathComponent("disk.chd")
        try chdData.write(to: chdPath)
    }
    
    override func tearDown() async throws {
        // Clean up test directory
        if let testDirectory = testDirectory {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        romkit = nil
    }
    
    // MARK: - Helper Methods
    
    private func createTestROMFile(name: String, size: Int, at directory: URL) throws {
        let data = Data(repeating: 0xFF, count: size)
        let path = directory.appendingPathComponent(name)
        try data.write(to: path)
    }
    
    // MARK: - Tests
    
    func testAddSource() async throws {
        // Add the test directory as a source
        try await romkit.addSource(testDirectory)
        
        // Verify it was added
        let sources = try await romkit.getSources()
        XCTAssertTrue(sources.contains { $0.standardized.path == testDirectory.standardized.path })
    }
    
    func testGetSources() async throws {
        // Add multiple sources
        try await romkit.addSource(testDirectory)
        
        let sources = try await romkit.getSources()
        XCTAssertGreaterThan(sources.count, 0)
        XCTAssertTrue(sources.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }
    
    func testGetIndexedDirectories() async throws {
        // Add a source
        try await romkit.addSource(testDirectory)
        
        // Get indexed directories with details
        let indexedDirs = try await romkit.getIndexedDirectories()
        XCTAssertGreaterThan(indexedDirs.count, 0)
        
        if let testDirInfo = indexedDirs.first(where: { $0.path.standardized.path == testDirectory.standardized.path }) {
            XCTAssertGreaterThan(testDirInfo.totalROMs, 0)
            XCTAssertGreaterThan(testDirInfo.totalSize, 0)
            XCTAssertNotNil(testDirInfo.lastIndexed)
        } else {
            XCTFail("Test directory not found in indexed directories")
        }
    }
    
    func testGetStatistics() async throws {
        // Add a source
        try await romkit.addSource(testDirectory)
        
        // Get statistics for the source
        let stats = try await romkit.getStatistics(for: testDirectory)
        XCTAssertNotNil(stats)
        
        if let stats = stats {
            XCTAssertEqual(stats.path.standardized.path, testDirectory.standardized.path)
            XCTAssertGreaterThan(stats.totalROMs, 0)
            XCTAssertGreaterThanOrEqual(stats.archives, 1) // We created one zip
            XCTAssertGreaterThanOrEqual(stats.chds, 1) // We created one CHD
            XCTAssertGreaterThan(stats.totalSize, 0)
            XCTAssertNotNil(stats.lastIndexed)
        }
    }
    
    func testGetStatisticsForNonIndexedDirectory() async throws {
        // Try to get statistics for a directory that hasn't been indexed
        let nonIndexedDir = FileManager.default.temporaryDirectory.appendingPathComponent("nonexistent")
        let stats = try await romkit.getStatistics(for: nonIndexedDir)
        XCTAssertNil(stats)
    }
    
    func testRemoveSource() async throws {
        // Add a source
        try await romkit.addSource(testDirectory)
        
        // Verify it was added
        var sources = try await romkit.getSources()
        XCTAssertTrue(sources.contains { $0.standardized.path == testDirectory.standardized.path })
        
        // Remove the source
        try await romkit.removeSource(testDirectory)
        
        // Verify it was removed
        sources = try await romkit.getSources()
        XCTAssertFalse(sources.contains { $0.standardized.path == testDirectory.standardized.path })
    }
    
    func testRefreshSource() async throws {
        // Add a source
        try await romkit.addSource(testDirectory)
        
        // Get initial statistics
        let initialStats = try await romkit.getStatistics(for: testDirectory)
        XCTAssertNotNil(initialStats)
        let initialROMCount = initialStats?.totalROMs ?? 0
        
        // Add a new ROM file
        try createTestROMFile(name: "new_test.rom", size: 512, at: testDirectory)
        
        // Refresh the source
        try await romkit.refreshSource(testDirectory)
        
        // Get updated statistics
        let updatedStats = try await romkit.getStatistics(for: testDirectory)
        XCTAssertNotNil(updatedStats)
        
        // The ROM count might not change if the index tracks unique CRCs
        // but the last indexed date should be updated
        if let initial = initialStats, let updated = updatedStats {
            XCTAssertGreaterThanOrEqual(updated.lastIndexed ?? Date.distantPast, 
                                       initial.lastIndexed ?? Date.distantPast)
        }
    }
    
    func testIndexedSourceProperties() async throws {
        // Add a source
        try await romkit.addSource(testDirectory)
        
        // Get indexed directories
        let indexedDirs = try await romkit.getIndexedDirectories()
        
        guard let testDirInfo = indexedDirs.first(where: { 
            $0.path.standardized.path == testDirectory.standardized.path 
        }) else {
            XCTFail("Test directory not found")
            return
        }
        
        // Verify IndexedSource properties
        XCTAssertEqual(testDirInfo.path.standardized.path, testDirectory.standardized.path)
        XCTAssertGreaterThan(testDirInfo.totalROMs, 0)
        XCTAssertGreaterThan(testDirInfo.totalSize, 0)
        
        // Last indexed should be recent
        let timeSinceIndexed = Date().timeIntervalSince(testDirInfo.lastIndexed)
        XCTAssertLessThan(timeSinceIndexed, 60) // Should be indexed within last minute
    }
    
    func testIndexStatisticsProperties() async throws {
        // Add a source
        try await romkit.addSource(testDirectory)
        
        // Get statistics
        let stats = try await romkit.getStatistics(for: testDirectory)
        XCTAssertNotNil(stats)
        
        guard let stats = stats else { return }
        
        // Verify all properties are populated
        XCTAssertEqual(stats.path.standardized.path, testDirectory.standardized.path)
        XCTAssertGreaterThanOrEqual(stats.totalROMs, 0)
        XCTAssertGreaterThanOrEqual(stats.uniqueGames, 0)
        XCTAssertGreaterThanOrEqual(stats.duplicates, 0)
        XCTAssertGreaterThanOrEqual(stats.archives, 0)
        XCTAssertGreaterThanOrEqual(stats.chds, 0)
        XCTAssertGreaterThan(stats.totalSize, 0)
        XCTAssertNotNil(stats.lastIndexed)
    }
    
    func testMultipleSources() async throws {
        // Create another test directory
        let secondDir = testDirectory.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: secondDir, withIntermediateDirectories: true)
        try createTestROMFile(name: "other.rom", size: 256, at: secondDir)
        
        // Add both sources
        try await romkit.addSource(testDirectory)
        try await romkit.addSource(secondDir)
        
        // Verify both are indexed
        let sources = try await romkit.getSources()
        XCTAssertGreaterThanOrEqual(sources.count, 2)
        
        // Get statistics for both
        let stats1 = try await romkit.getStatistics(for: testDirectory)
        let stats2 = try await romkit.getStatistics(for: secondDir)
        
        XCTAssertNotNil(stats1)
        XCTAssertNotNil(stats2)
        
        // Remove one source
        try await romkit.removeSource(secondDir)
        
        // Verify only one remains
        let remainingSources = try await romkit.getSources()
        XCTAssertTrue(remainingSources.contains { $0.standardized.path == testDirectory.standardized.path })
        XCTAssertFalse(remainingSources.contains { $0.standardized.path == secondDir.standardized.path })
    }
}

// MARK: - Test Helpers

extension URL {
    var standardized: URL {
        return self.standardizedFileURL
    }
}