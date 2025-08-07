//
//  FastZIPHandlerTests.swift
//  RomKitTests
//
//  Comprehensive tests for FastZIPHandler archive operations
//

import Testing
import Foundation
import zlib
@testable import RomKit

@Suite("FastZIPHandler Tests")
struct FastZIPHandlerTests {
    
    // MARK: - Test Helpers
    
    private func createTestData(size: Int = 1024, pattern: UInt8 = 0xAB) -> Data {
        return Data(repeating: pattern, count: size)
    }
    
    private func createTestZIPFile() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let zipPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).zip")
        
        // Create a simple ZIP file using the system zip command
        let testDir = tempDir.appendingPathComponent("zip_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create test files
        let file1 = testDir.appendingPathComponent("test1.rom")
        let file2 = testDir.appendingPathComponent("test2.bin")
        let file3 = testDir.appendingPathComponent("subdir/test3.rom")
        
        try createTestData(size: 1024).write(to: file1)
        try createTestData(size: 2048, pattern: 0xCD).write(to: file2)
        
        try FileManager.default.createDirectory(
            at: testDir.appendingPathComponent("subdir"),
            withIntermediateDirectories: true
        )
        try createTestData(size: 512, pattern: 0xEF).write(to: file3)
        
        // Create ZIP using system command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = testDir
        process.arguments = ["-r", "-q", zipPath.path, ".", "-x", ".*"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw ArchiveError.cannotCreateArchive(zipPath.path)
        }
        
        return zipPath
    }
    
    private func createCorruptedZIPFile() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let zipPath = tempDir.appendingPathComponent("corrupt_\(UUID().uuidString).zip")
        
        // Create corrupted ZIP data
        var data = Data()
        
        // Add invalid ZIP header
        data.append(contentsOf: [0x50, 0x4B, 0xFF, 0xFF]) // Invalid signature
        
        // Add random garbage
        data.append(Data(repeating: 0x00, count: 1024))
        
        try data.write(to: zipPath)
        
        return zipPath
    }
    
    private func createEmptyZIPFile() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let zipPath = tempDir.appendingPathComponent("empty_\(UUID().uuidString).zip")
        
        // Create empty ZIP using system command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", zipPath.path, "-r", "-"]
        process.standardInput = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        
        // Close stdin to signal no files
        if let input = process.standardInput as? Pipe {
            input.fileHandleForWriting.closeFile()
        }
        
        process.waitUntilExit()
        
        // If that doesn't work, create minimal valid empty ZIP
        if !FileManager.default.fileExists(atPath: zipPath.path) {
            let emptyZIP = Data([
                0x50, 0x4B, 0x05, 0x06, // End of central directory signature
                0x00, 0x00, // Number of this disk
                0x00, 0x00, // Disk where central directory starts
                0x00, 0x00, // Number of central directory records on this disk
                0x00, 0x00, // Total number of central directory records
                0x00, 0x00, 0x00, 0x00, // Size of central directory
                0x00, 0x00, 0x00, 0x00, // Offset of start of central directory
                0x00, 0x00  // Comment length
            ])
            try emptyZIP.write(to: zipPath)
        }
        
        return zipPath
    }
    
    // MARK: - Initialization Tests
    
    @Test func testInitialization() async throws {
        let handler = FastZIPArchiveHandler()
        
        #expect(handler.supportedExtensions.contains("zip"))
        #expect(handler.supportedExtensions.count == 1)
    }
    
    @Test func testCanHandle() async throws {
        let handler = FastZIPArchiveHandler()
        
        // Test supported extensions
        #expect(handler.canHandle(url: URL(fileURLWithPath: "/test.zip")) == true)
        #expect(handler.canHandle(url: URL(fileURLWithPath: "/test.ZIP")) == true)
        #expect(handler.canHandle(url: URL(fileURLWithPath: "/test.Zip")) == true)
        
        // Test unsupported extensions
        #expect(handler.canHandle(url: URL(fileURLWithPath: "/test.7z")) == false)
        #expect(handler.canHandle(url: URL(fileURLWithPath: "/test.rar")) == false)
        #expect(handler.canHandle(url: URL(fileURLWithPath: "/test.tar")) == false)
        #expect(handler.canHandle(url: URL(fileURLWithPath: "/test")) == false)
    }
    
    // MARK: - List Contents Tests
    
    @Test func testListContents() async throws {
        let handler = FastZIPArchiveHandler()
        let zipFile = try createTestZIPFile()
        defer { try? FileManager.default.removeItem(at: zipFile) }
        
        let entries = try handler.listContents(of: zipFile)
        
        #expect(entries.count >= 3)
        
        // Check for expected files
        let fileNames = entries.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        #expect(fileNames.contains("test1.rom"))
        #expect(fileNames.contains("test2.bin"))
        #expect(fileNames.contains("test3.rom"))
        
        // Check sizes
        if let test1 = entries.first(where: { $0.path.contains("test1.rom") }) {
            #expect(test1.uncompressedSize == 1024)
        }
        
        if let test2 = entries.first(where: { $0.path.contains("test2.bin") }) {
            #expect(test2.uncompressedSize == 2048)
        }
    }
    
    @Test func testListEmptyArchive() async throws {
        let handler = FastZIPArchiveHandler()
        let emptyZip = try createEmptyZIPFile()
        defer { try? FileManager.default.removeItem(at: emptyZip) }
        
        let entries = try handler.listContents(of: emptyZip)
        #expect(entries.isEmpty)
    }
    
    @Test func testListNonExistentFile() async throws {
        let handler = FastZIPArchiveHandler()
        let nonExistent = URL(fileURLWithPath: "/nonexistent/file.zip")
        
        #expect(throws: Error.self) {
            _ = try handler.listContents(of: nonExistent)
        }
    }
    
    @Test func testListCorruptedArchive() async throws {
        let handler = FastZIPArchiveHandler()
        let corruptZip = try createCorruptedZIPFile()
        defer { try? FileManager.default.removeItem(at: corruptZip) }
        
        #expect(throws: Error.self) {
            _ = try handler.listContents(of: corruptZip)
        }
    }
    
    // MARK: - Extract Tests
    
    @Test func testExtractSingleEntry() async throws {
        let handler = FastZIPArchiveHandler()
        let zipFile = try createTestZIPFile()
        defer { try? FileManager.default.removeItem(at: zipFile) }
        
        // List contents first
        let entries = try handler.listContents(of: zipFile)
        
        guard let entry = entries.first(where: { $0.path.contains("test1.rom") }) else {
            Issue.record("Could not find test1.rom in archive")
            return
        }
        
        // Extract the entry
        let data = try handler.extract(entry: entry, from: zipFile)
        
        #expect(data.count == 1024)
        #expect(data.first == 0xAB) // Check pattern
    }
    
    @Test func testExtractMultipleEntries() async throws {
        let handler = FastZIPArchiveHandler()
        let zipFile = try createTestZIPFile()
        defer { try? FileManager.default.removeItem(at: zipFile) }
        
        let entries = try handler.listContents(of: zipFile)
        
        // Extract all ROM files
        for entry in entries where entry.path.hasSuffix(".rom") || entry.path.hasSuffix(".bin") {
            let data = try handler.extract(entry: entry, from: zipFile)
            #expect(data.count > 0)
        }
    }
    
    @Test func testExtractNonExistentEntry() async throws {
        let handler = FastZIPArchiveHandler()
        let zipFile = try createTestZIPFile()
        defer { try? FileManager.default.removeItem(at: zipFile) }
        
        let fakeEntry = ArchiveEntry(
            path: "nonexistent.rom",
            compressedSize: 100,
            uncompressedSize: 100,
            modificationDate: Date(),
            crc32: "12345678"
        )
        
        #expect(throws: Error.self) {
            _ = try handler.extract(entry: fakeEntry, from: zipFile)
        }
    }
    
    // MARK: - Extract All Tests
    
    @Test func testExtractAll() async throws {
        let handler = FastZIPArchiveHandler()
        let zipFile = try createTestZIPFile()
        defer { try? FileManager.default.removeItem(at: zipFile) }
        
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("extract_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destination) }
        
        try handler.extractAll(from: zipFile, to: destination)
        
        // Verify extracted files
        let test1 = destination.appendingPathComponent("test1.rom")
        let test2 = destination.appendingPathComponent("test2.bin")
        let test3 = destination.appendingPathComponent("subdir/test3.rom")
        
        #expect(FileManager.default.fileExists(atPath: test1.path))
        #expect(FileManager.default.fileExists(atPath: test2.path))
        #expect(FileManager.default.fileExists(atPath: test3.path))
        
        // Verify sizes
        if let attrs1 = try? FileManager.default.attributesOfItem(atPath: test1.path),
           let size1 = attrs1[.size] as? Int {
            #expect(size1 == 1024)
        }
        
        if let attrs2 = try? FileManager.default.attributesOfItem(atPath: test2.path),
           let size2 = attrs2[.size] as? Int {
            #expect(size2 == 2048)
        }
    }
    
    // MARK: - Create Archive Tests
    
    @Test func testCreateArchive() async throws {
        let handler = FastZIPArchiveHandler()
        
        let tempDir = FileManager.default.temporaryDirectory
        let newZip = tempDir.appendingPathComponent("created_\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: newZip) }
        
        // Create test entries
        let entries: [(name: String, data: Data)] = [
            ("file1.rom", createTestData(size: 512, pattern: 0x11)),
            ("file2.bin", createTestData(size: 1024, pattern: 0x22)),
            ("subdir/file3.rom", createTestData(size: 256, pattern: 0x33))
        ]
        
        try handler.create(at: newZip, with: entries)
        
        #expect(FileManager.default.fileExists(atPath: newZip.path))
        
        // Verify the created archive by listing contents
        let contents = try handler.listContents(of: newZip)
        #expect(contents.count >= 3)
        
        // Verify we can extract from it
        if let entry = contents.first {
            let data = try handler.extract(entry: entry, from: newZip)
            #expect(data.count > 0)
        }
    }
    
    @Test func testCreateEmptyArchive() async throws {
        let handler = FastZIPArchiveHandler()
        
        let tempDir = FileManager.default.temporaryDirectory
        let emptyZip = tempDir.appendingPathComponent("empty_created_\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: emptyZip) }
        
        try handler.create(at: emptyZip, with: [])
        
        #expect(FileManager.default.fileExists(atPath: emptyZip.path))
    }
    
    @Test func testCreateWithLargeFiles() async throws {
        let handler = FastZIPArchiveHandler()
        
        let tempDir = FileManager.default.temporaryDirectory
        let largeZip = tempDir.appendingPathComponent("large_\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: largeZip) }
        
        // Create large test data
        let largeData = createTestData(size: 1024 * 1024, pattern: 0xFF) // 1MB
        
        let entries: [(name: String, data: Data)] = [
            ("large1.rom", largeData),
            ("large2.bin", largeData)
        ]
        
        try handler.create(at: largeZip, with: entries)
        
        #expect(FileManager.default.fileExists(atPath: largeZip.path))
        
        // Verify file size is reasonable (should be compressed)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: largeZip.path),
           let size = attrs[.size] as? Int {
            // Highly repetitive data should compress well
            #expect(size < 2 * 1024 * 1024) // Should be less than uncompressed size
        }
    }
    
    // MARK: - Compression/Decompression Tests
    
    @Test func testCRC32Calculation() async throws {
        // Test CRC32 through archive creation and listing
        let handler = FastZIPArchiveHandler()
        
        let tempDir = FileManager.default.temporaryDirectory
        let testZip = tempDir.appendingPathComponent("crc_test_\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: testZip) }
        
        // Create archive with known data
        let testData = Data("Hello, World!".utf8)
        try handler.create(at: testZip, with: [("test.txt", testData)])
        
        // List contents to get CRC
        let entries = try handler.listContents(of: testZip)
        #expect(entries.count == 1)
        #expect(entries.first?.crc32 != nil)
    }
    
    @Test func testCompressionRoundTrip() async throws {
        // Test compression through archive creation and extraction
        let handler = FastZIPArchiveHandler()
        
        let tempDir = FileManager.default.temporaryDirectory
        let testZip = tempDir.appendingPathComponent("compress_test_\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: testZip) }
        
        let originalData = createTestData(size: 4096, pattern: 0xAA)
        
        // Create archive (will compress)
        try handler.create(at: testZip, with: [("test.bin", originalData)])
        
        // Verify compression occurred by checking file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: testZip.path),
           let size = attrs[.size] as? Int {
            #expect(size < 4096) // Should be compressed
        }
        
        // Extract and verify (will decompress)
        let entries = try handler.listContents(of: testZip)
        if let entry = entries.first {
            let decompressed = try handler.extract(entry: entry, from: testZip)
            #expect(decompressed == originalData)
        }
    }
    
    @Test func testVariousDataPatterns() async throws {
        // Test compression with various data patterns
        let handler = FastZIPArchiveHandler()
        
        let tempDir = FileManager.default.temporaryDirectory
        let testZip = tempDir.appendingPathComponent("patterns_\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: testZip) }
        
        // Test with different data patterns
        let entries: [(name: String, data: Data)] = [
            ("repetitive.bin", createTestData(size: 1024, pattern: 0xAA)), // Highly compressible
            ("random.bin", Data((0..<1024).map { UInt8($0 & 0xFF) })), // Less compressible
            ("small.bin", Data([1, 2, 3, 4, 5])), // Small file
            ("empty.bin", Data()) // Empty file
        ]
        
        try handler.create(at: testZip, with: entries)
        
        // Extract and verify all entries
        let contents = try handler.listContents(of: testZip)
        #expect(contents.count == entries.count)
        
        for (index, entry) in contents.enumerated() {
            let extracted = try handler.extract(entry: entry, from: testZip)
            #expect(extracted == entries[index].data)
        }
    }
    
    // MARK: - Performance Tests
    
    @Test func testLargeArchivePerformance() async throws {
        let handler = FastZIPArchiveHandler()
        
        let tempDir = FileManager.default.temporaryDirectory
        let perfZip = tempDir.appendingPathComponent("perf_\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: perfZip) }
        
        // Create archive with many small files
        var entries: [(name: String, data: Data)] = []
        for i in 0..<100 {
            let data = createTestData(size: 1024, pattern: UInt8(i & 0xFF))
            entries.append(("file\(i).rom", data))
        }
        
        let startCreate = Date()
        try handler.create(at: perfZip, with: entries)
        let createDuration = Date().timeIntervalSince(startCreate)
        
        print("Created 100-file archive in \(createDuration) seconds")
        #expect(createDuration < 10.0) // Should complete in reasonable time
        
        // Test listing performance
        let startList = Date()
        let contents = try handler.listContents(of: perfZip)
        let listDuration = Date().timeIntervalSince(startList)
        
        print("Listed \(contents.count) entries in \(listDuration) seconds")
        #expect(listDuration < 1.0) // Listing should be fast
        #expect(contents.count == 100)
    }
    
    // MARK: - Edge Cases
    
    @Test func testSpecialCharactersInFilenames() async throws {
        let handler = FastZIPArchiveHandler()
        
        let tempDir = FileManager.default.temporaryDirectory
        let specialZip = tempDir.appendingPathComponent("special_\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: specialZip) }
        
        // Create entries with special characters
        let entries: [(name: String, data: Data)] = [
            ("file (1).rom", createTestData(size: 100)),
            ("file [!].bin", createTestData(size: 100)),
            ("file & more.rom", createTestData(size: 100)),
            ("file's game.bin", createTestData(size: 100))
        ]
        
        try handler.create(at: specialZip, with: entries)
        
        let contents = try handler.listContents(of: specialZip)
        #expect(contents.count == entries.count)
    }
    
    @Test func testZeroSizeFiles() async throws {
        let handler = FastZIPArchiveHandler()
        
        let tempDir = FileManager.default.temporaryDirectory
        let zeroZip = tempDir.appendingPathComponent("zero_\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: zeroZip) }
        
        // Create entries with zero-size data
        let entries: [(name: String, data: Data)] = [
            ("empty1.rom", Data()),
            ("empty2.bin", Data()),
            ("normal.rom", createTestData(size: 100))
        ]
        
        try handler.create(at: zeroZip, with: entries)
        
        let contents = try handler.listContents(of: zeroZip)
        #expect(contents.count == 3)
        
        // Extract and verify zero-size files
        for entry in contents where entry.path.contains("empty") {
            let data = try handler.extract(entry: entry, from: zeroZip)
            #expect(data.count == 0)
        }
    }
    
    @Test func testDeepDirectoryStructure() async throws {
        let handler = FastZIPArchiveHandler()
        
        let tempDir = FileManager.default.temporaryDirectory
        let deepZip = tempDir.appendingPathComponent("deep_\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: deepZip) }
        
        // Create entries with deep paths
        let entries: [(name: String, data: Data)] = [
            ("level1/level2/level3/level4/deep.rom", createTestData(size: 100)),
            ("level1/level2/another.bin", createTestData(size: 100)),
            ("root.rom", createTestData(size: 100))
        ]
        
        try handler.create(at: deepZip, with: entries)
        
        let contents = try handler.listContents(of: deepZip)
        #expect(contents.count == 3)
        
        // Extract to verify directory structure
        let extractDir = tempDir.appendingPathComponent("deep_extract_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: extractDir) }
        
        try handler.extractAll(from: deepZip, to: extractDir)
        
        let deepFile = extractDir.appendingPathComponent("level1/level2/level3/level4/deep.rom")
        #expect(FileManager.default.fileExists(atPath: deepFile.path))
    }
    
    @Test func testConcurrentOperations() async throws {
        let handler = FastZIPArchiveHandler()
        let zipFile = try createTestZIPFile()
        defer { try? FileManager.default.removeItem(at: zipFile) }
        
        // Perform concurrent reads
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    do {
                        _ = try handler.listContents(of: zipFile)
                    } catch {
                        Issue.record("Concurrent list failed: \(error)")
                    }
                }
            }
        }
        
        // All operations should complete without errors
        #expect(true) // If we get here, concurrent operations succeeded
    }
    
    @Test func testInvalidZIPData() async throws {
        let handler = FastZIPArchiveHandler()
        
        let tempDir = FileManager.default.temporaryDirectory
        
        // Test with non-ZIP file
        let textFile = tempDir.appendingPathComponent("notzip.txt")
        try "This is not a ZIP file".write(to: textFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: textFile) }
        
        #expect(throws: Error.self) {
            _ = try handler.listContents(of: textFile)
        }
        
        // Test with truncated ZIP
        let truncatedZip = tempDir.appendingPathComponent("truncated.zip")
        let zipHeader = Data([0x50, 0x4B, 0x03, 0x04]) // Just the header
        try zipHeader.write(to: truncatedZip)
        defer { try? FileManager.default.removeItem(at: truncatedZip) }
        
        #expect(throws: Error.self) {
            _ = try handler.listContents(of: truncatedZip)
        }
    }
}