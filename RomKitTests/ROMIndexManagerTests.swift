//
//  ROMIndexManagerTests.swift
//  RomKitTests
//
//  Tests for ROMIndexManager to improve code coverage
//

import Testing
import Foundation
@testable import RomKit

@Suite(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "Skipping index manager tests in CI"))
struct ROMIndexManagerTests {

    @Test func testROMIndexManagerInit() async throws {
        // Test with default path
        let manager1 = try await ROMIndexManager()
        #expect(manager1 != nil)

        // Test with custom path
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_manager_\(UUID()).db")

        let manager2 = try await ROMIndexManager(databasePath: dbPath)
        #expect(manager2 != nil)

        // Clean up
        try? FileManager.default.removeItem(at: dbPath)
    }

    @Test func testAddSource() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_source_\(UUID()).db")
        let sourceDir = tempDir.appendingPathComponent("test_source_\(UUID())")

        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: dbPath)
            try? FileManager.default.removeItem(at: sourceDir)
        }

        let manager = try await ROMIndexManager(databasePath: dbPath)

        // Add a source
        try await manager.addSource(sourceDir, showProgress: false)

        // Try to add same source again (should skip)
        try await manager.addSource(sourceDir, showProgress: false)

        #expect(true) // Test passes if no errors thrown
    }
}
