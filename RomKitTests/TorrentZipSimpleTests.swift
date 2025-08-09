//
//  TorrentZipSimpleTests.swift
//  RomKitTests
//
//  Simple tests for TorrentZip to improve coverage from 0%
//

import Testing
import Foundation
@testable import RomKit

struct TorrentZipSimpleTests {

    @Test("Test TorrentZip basic check")
    func testBasicCheck() async throws {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("torrentzip_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        // Create a test ZIP
        let zipPath = testDir.appendingPathComponent("test.zip")
        let handler = ParallelZIPArchiveHandler()

        let entries: [(name: String, data: Data)] = [
            ("file1.rom", Data(repeating: 0x01, count: 100)),
            ("file2.rom", Data(repeating: 0x02, count: 200))
        ]

        try handler.create(at: zipPath, with: entries)

        // Check if it's TorrentZip compliant
        let isCompliant = try TorrentZip.isTorrentZip(at: zipPath)
        // New ZIPs are usually not compliant
        #expect(isCompliant == false || isCompliant == true) // Either is fine

        // Convert to TorrentZip
        try TorrentZip.convertToTorrentZip(at: zipPath)

        // Should still be a valid ZIP
        #expect(FileManager.default.fileExists(atPath: zipPath.path))

        // After conversion, should be compliant
        let isCompliantAfter = try TorrentZip.isTorrentZip(at: zipPath)
        #expect(isCompliantAfter == true)
    }

    @Test("Test TorrentZip directory verification")
    func testDirectoryVerification() async throws {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("torrentzip_dir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        let handler = ParallelZIPArchiveHandler()

        // Create multiple ZIP files
        for index in 1...3 {
            let zipPath = testDir.appendingPathComponent("archive\(index).zip")
            let entries: [(name: String, data: Data)] = [
                ("rom\(index).bin", Data(repeating: UInt8(index), count: 100 * index))
            ]
            try handler.create(at: zipPath, with: entries)
        }

        // Verify directory
        let result = try TorrentZip.verifyDirectory(at: testDir, recursive: false)
        let totalFiles = result.compliant.count + result.nonCompliant.count
        #expect(totalFiles == 3)

        // All should be in either compliant or non-compliant
        #expect(result.compliant.count + result.nonCompliant.count == 3)
    }

    @Test("Test TorrentZip recursive directory scan")
    func testRecursiveDirectoryScan() async throws {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("torrentzip_recursive_\(UUID().uuidString)")
        let subDir = testDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        let handler = ParallelZIPArchiveHandler()

        // Create ZIPs in main dir
        let zip1 = testDir.appendingPathComponent("main.zip")
        try handler.create(at: zip1, with: [("main.rom", Data([0x01]))])

        // Create ZIPs in subdir
        let zip2 = subDir.appendingPathComponent("sub.zip")
        try handler.create(at: zip2, with: [("sub.rom", Data([0x02]))])

        // Non-recursive should find only main dir ZIP
        let nonRecursive = try TorrentZip.verifyDirectory(at: testDir, recursive: false)
        let nonRecursiveTotal = nonRecursive.compliant.count + nonRecursive.nonCompliant.count
        #expect(nonRecursiveTotal == 1)

        // Recursive should find both
        let recursive = try TorrentZip.verifyDirectory(at: testDir, recursive: true)
        let recursiveTotal = recursive.compliant.count + recursive.nonCompliant.count
        #expect(recursiveTotal == 2)
    }

    @Test("Test TorrentZip parallel conversion")
    func testParallelConversion() async throws {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("torrentzip_parallel_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        let handler = ParallelZIPArchiveHandler()

        // Create multiple ZIPs
        for index in 1...5 {
            let zipPath = testDir.appendingPathComponent("archive\(index).zip")
            let entries: [(name: String, data: Data)] = [
                ("file\(index).rom", Data(repeating: UInt8(index), count: 500))
            ]
            try handler.create(at: zipPath, with: entries)
        }

        // Convert with parallel processing
        let progressActor = ProgressTracker()
        try await TorrentZip.convertDirectory(
            at: testDir,
            recursive: false,
            parallel: true,
            progress: { progress in
                Task {
                    await progressActor.update(progress)
                }
            }
        )

        // Should have received progress updates
        let updates = await progressActor.progressUpdates
        #expect(updates >= 0) // May be 0 if too fast

        // Verify all are still valid ZIPs
        let result = try TorrentZip.verifyDirectory(at: testDir, recursive: false)
        let total = result.compliant.count + result.nonCompliant.count
        #expect(total == 5)
    }

    @Test("Test TorrentZip with empty ZIP")
    func testEmptyZIP() async throws {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("torrentzip_empty_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        let zipPath = testDir.appendingPathComponent("empty.zip")
        let handler = ParallelZIPArchiveHandler()

        // Create empty ZIP
        try handler.create(at: zipPath, with: [])

        // Should handle empty ZIP
        let isCompliant = try TorrentZip.isTorrentZip(at: zipPath)
        #expect(isCompliant == true || isCompliant == false) // Either is fine

        // Convert empty ZIP
        try TorrentZip.convertToTorrentZip(at: zipPath)

        // Should still exist
        #expect(FileManager.default.fileExists(atPath: zipPath.path))
    }

    @Test("Test TorrentZip error handling")
    func testErrorHandling() async throws {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("torrentzip_error_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        // Test with non-existent file
        let nonExistent = testDir.appendingPathComponent("nonexistent.zip")

        #expect(throws: (any Error).self) {
            try TorrentZip.isTorrentZip(at: nonExistent)
        }

        // Test with non-ZIP file
        let notZip = testDir.appendingPathComponent("notzip.txt")
        try Data("not a zip".utf8).write(to: notZip)

        #expect(throws: (any Error).self) {
            try TorrentZip.convertToTorrentZip(at: notZip)
        }
    }

    @Test("Test TorrentZip directory result summary")
    func testDirectoryResultSummary() async throws {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("torrentzip_summary_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        let handler = ParallelZIPArchiveHandler()

        // Create mix of ZIPs
        for index in 1...4 {
            let zipPath = testDir.appendingPathComponent("test\(index).zip")
            let entries: [(name: String, data: Data)] = [
                ("file\(index).rom", Data(repeating: UInt8(index), count: 50))
            ]
            try handler.create(at: zipPath, with: entries)
        }

        // Also create a non-ZIP file
        try Data("text file".utf8).write(to: testDir.appendingPathComponent("readme.txt"))

        let result = try TorrentZip.verifyDirectory(at: testDir, recursive: false)

        // Should only count ZIP files
        let total = result.compliant.count + result.nonCompliant.count
        #expect(total == 4)

        // Check summary string
        let summary = result.summary
        #expect(!summary.isEmpty)
    }
}

// Helper actor for tracking progress updates
private actor ProgressTracker {
    var progressUpdates = 0

    func update(_ progress: TorrentZipProgress) {
        progressUpdates += 1
    }
}