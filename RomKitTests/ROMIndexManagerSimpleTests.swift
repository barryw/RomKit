//
//  ROMIndexManagerSimpleTests.swift
//  RomKitTests
//
//  Simple tests for ROMIndexManager to improve coverage
//

import Testing
import Foundation
@testable import RomKit

@Suite(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "Skipping index manager tests in CI"))
struct ROMIndexManagerSimpleTests {

    @Test("Test ROMIndexManager basic initialization")
    func testBasicInitialization() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("manager_basic_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let manager = try await ROMIndexManager(databasePath: dbPath)

        // Test that manager was created
        let sources = await manager.listSources()
        #expect(sources.isEmpty)

        // Test analyze on empty index
        let analysis = await manager.analyzeIndex()
        #expect(analysis.totalROMs == 0)
        #expect(analysis.uniqueROMs == 0)
        #expect(analysis.totalSize == 0)
    }

    @Test("Test ROMIndexManager with ZIP sources")
    func testZIPSources() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("manager_zip_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let manager = try await ROMIndexManager(databasePath: dbPath)

        // Create test directory with ZIPs
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("manager_source_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }

        // Create test ZIPs
        let handler = ParallelZIPArchiveHandler()
        for index in 1...3 {
            let zipPath = source.appendingPathComponent("game\(index).zip")
            try handler.create(at: zipPath, with: [
                ("rom\(index).bin", Data(repeating: UInt8(index), count: 100))
            ])
        }

        // Add source
        try await manager.addSource(source, showProgress: false)

        // List sources
        let sources = await manager.listSources()
        #expect(sources.count == 1)
        #expect(sources.first?.path == source.path)

        // Find by pattern
        let roms = await manager.findByName(pattern: "%rom%")
        #expect(roms.count == 3)

        // Analyze
        let analysis = await manager.analyzeIndex()
        #expect(analysis.totalROMs == 3)
        #expect(analysis.sources.count == 1)
    }

    @Test("Test ROMIndexManager clear operations")
    func testClearOperations() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("manager_clear_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let manager = try await ROMIndexManager(databasePath: dbPath)

        // Create test directory with a ZIP
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("manager_clear_src_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }

        let handler = ParallelZIPArchiveHandler()
        let zipPath = source.appendingPathComponent("data.zip")
        try handler.create(at: zipPath, with: [
            ("file.rom", Data([0x01, 0x02, 0x03]))
        ])

        // Add source
        try await manager.addSource(source, showProgress: false)

        // Verify data exists
        let beforeClear = await manager.analyzeIndex()
        #expect(beforeClear.totalROMs > 0)

        // Clear all
        try await manager.clearAll()

        // Verify data is gone
        let afterClear = await manager.analyzeIndex()
        #expect(afterClear.totalROMs == 0)
        #expect(afterClear.sources.isEmpty)
    }

    @Test("Test ROMIndexManager find by CRC")
    func testFindByCRC() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("manager_crc_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let manager = try await ROMIndexManager(databasePath: dbPath)

        // Create test directory
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("manager_crc_src_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }

        // Create ZIP with known ROM
        let testData = Data([0x01, 0x02, 0x03, 0x04])
        let crc32 = HashUtilities.crc32(data: testData)

        let handler = ParallelZIPArchiveHandler()
        let zipPath = source.appendingPathComponent("test.zip")
        try handler.create(at: zipPath, with: [
            ("known.rom", testData)
        ])

        // Add source
        try await manager.addSource(source, showProgress: false)

        // Find by CRC
        let romInfo = try await manager.findROM(crc32: crc32)
        #expect(romInfo != nil)
        #expect(romInfo?.name == "known.rom")
        #expect(romInfo?.crc32 == crc32)
        #expect(romInfo?.size == 4)
    }

    @Test("Test ROMIndexManager remove source")
    func testRemoveSource() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("manager_remove_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let manager = try await ROMIndexManager(databasePath: dbPath)

        // Create two test directories
        let source1 = FileManager.default.temporaryDirectory
            .appendingPathComponent("manager_rm_src1_\(UUID().uuidString)")
        let source2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("manager_rm_src2_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: source1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source2, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: source1)
            try? FileManager.default.removeItem(at: source2)
        }

        // Create ZIPs in both
        let handler = ParallelZIPArchiveHandler()
        try handler.create(at: source1.appendingPathComponent("s1.zip"), with: [("s1.rom", Data([0x01]))])
        try handler.create(at: source2.appendingPathComponent("s2.zip"), with: [("s2.rom", Data([0x02]))])

        // Add both sources
        try await manager.addSource(source1, showProgress: false)
        try await manager.addSource(source2, showProgress: false)

        // Verify both added
        let sourcesBeforeRemove = await manager.listSources()
        #expect(sourcesBeforeRemove.count == 2)

        // Remove source1
        try await manager.removeSource(source1, showProgress: false)

        // Verify only source2 remains
        let sourcesAfterRemove = await manager.listSources()
        #expect(sourcesAfterRemove.count == 1)
        #expect(sourcesAfterRemove.first?.path == source2.path)

        // Verify ROMs from source1 are gone
        let roms = await manager.findByName(pattern: "%s1%")
        if !roms.isEmpty {
            print("DEBUG: Found ROMs after removal:")
            for rom in roms {
                print("  - \(rom.name) at \(rom.location)")
            }
            print("Expected path prefix: \(source1.path)")
            print("Resolved path: \(source1.resolvingSymlinksInPath().path)")
        }
        #expect(roms.isEmpty)

        // Verify ROMs from source2 still exist
        let roms2 = await manager.findByName(pattern: "%s2%")
        #expect(!roms2.isEmpty)
    }
}
