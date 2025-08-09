//
//  IndexBugTests.swift
//  RomKitTests
//
//  Tests to diagnose indexing issues with ZIP files
//

import Testing
import Foundation
@testable import RomKit

struct IndexBugTests {
    
    @Test("Test ZIP indexing extracts all entries")
    func testZIPIndexing() async throws {
        // Create a test directory
        let testDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_index_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create a sample ZIP with multiple entries
        let zipPath = testDir.appendingPathComponent("test.zip")
        let handler = FastZIPArchiveHandler()
        
        // Create test ROM data with different CRCs
        let entries: [(name: String, data: Data)] = [
            ("rom1.bin", Data(repeating: 0x01, count: 1024)),
            ("rom2.bin", Data(repeating: 0x02, count: 1024)),
            ("rom3.bin", Data(repeating: 0x03, count: 1024)),
            ("subdir/rom4.bin", Data(repeating: 0x04, count: 1024)),
            ("subdir/rom5.bin", Data(repeating: 0x05, count: 1024))
        ]
        
        try handler.create(at: zipPath, with: entries)
        
        // Verify ZIP was created and can be read
        let readEntries = try handler.listContents(of: zipPath)
        print("ZIP contains \(readEntries.count) entries")
        for entry in readEntries {
            print("  - \(entry.path): CRC=\(entry.crc32 ?? "none")")
        }
        
        // Now test indexing
        let dbPath = testDir.appendingPathComponent("test_index.db")
        let manager = try await ROMIndexManager(databasePath: dbPath)
        
        print("\nIndexing directory: \(testDir.path)")
        try await manager.addSource(testDir, showProgress: true)
        
        // Check statistics via the index
        let analysis = await manager.analyzeIndex()
        print("\nIndex Statistics:")
        print("  Total ROMs: \(analysis.totalROMs)")
        print("  Unique ROMs: \(analysis.uniqueROMs)")
        print("  Total Size: \(analysis.totalSize)")
        
        // List sources
        let sources = await manager.listSources()
        for source in sources {
            print("\nSource: \(source.path)")
            print("  ROMs: \(source.romCount)")
            print("  Size: \(source.totalSize)")
        }
        
        // Find all indexed ROMs
        let allROMs = await manager.findByName(pattern: "*")
        print("\nIndexed ROMs:")
        for rom in allROMs {
            print("  - \(rom.name): CRC=\(rom.crc32), Location=\(rom.location)")
        }
        
        // Test should find 5 ROMs from the ZIP
        #expect(analysis.totalROMs == 5, "Should index all 5 ROMs from ZIP")
        #expect(analysis.uniqueROMs == 5, "All 5 ROMs should be unique")
    }
    
    @Test("Test multiple ZIPs in directory")
    func testMultipleZIPs() async throws {
        let testDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_multi_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let handler = FastZIPArchiveHandler()
        
        // Create multiple ZIP files
        for i in 1...3 {
            let zipPath = testDir.appendingPathComponent("game\(i).zip")
            let entries: [(name: String, data: Data)] = [
                ("rom_a.bin", Data(repeating: UInt8(i), count: 1024)),
                ("rom_b.bin", Data(repeating: UInt8(i + 10), count: 1024))
            ]
            try handler.create(at: zipPath, with: entries)
        }
        
        // Index the directory
        let dbPath = testDir.appendingPathComponent("test_index.db")
        let manager = try await ROMIndexManager(databasePath: dbPath)
        
        print("\nIndexing directory with 3 ZIPs...")
        try await manager.addSource(testDir, showProgress: true)
        
        let analysis = await manager.analyzeIndex()
        print("\nResults:")
        print("  Total ROMs: \(analysis.totalROMs)")
        print("  Unique ROMs: \(analysis.uniqueROMs)")
        
        // Should find 6 ROMs total (2 per ZIP × 3 ZIPs)
        #expect(analysis.totalROMs == 6, "Should index 6 ROMs from 3 ZIPs")
    }
}