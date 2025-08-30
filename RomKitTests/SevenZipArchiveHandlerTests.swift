//
//  SevenZipArchiveHandlerTests.swift
//  RomKitTests
//
//  Tests for 7-Zip archive handling
//

import Testing
@testable import RomKit
import Foundation

@Suite("SevenZip Archive Handler Tests")
struct SevenZipArchiveHandlerTests {
    
    let handler = SevenZipArchiveHandler()
    let testDataDir = Bundle.module.url(forResource: "TestData", withExtension: nil)!
    
    @Test func testCanHandle() {
        // Valid 7z extensions
        #expect(handler.canHandle(url: URL(fileURLWithPath: "test.7z")))
        #expect(handler.canHandle(url: URL(fileURLWithPath: "test.7Z")))
        #expect(handler.canHandle(url: URL(fileURLWithPath: "test.7z".uppercased())))
        
        // Invalid extensions
        #expect(!handler.canHandle(url: URL(fileURLWithPath: "test.zip")))
        #expect(!handler.canHandle(url: URL(fileURLWithPath: "test.rar")))
        #expect(!handler.canHandle(url: URL(fileURLWithPath: "test.tar")))
        #expect(!handler.canHandle(url: URL(fileURLWithPath: "test")))
    }
    
    @Test func testCreateTest7zFile() async throws {
        // Create a test 7z file for testing
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create test files
        let testFiles = [
            ("file1.txt", "Hello, World!"),
            ("file2.txt", "This is a test file"),
            ("subfolder/file3.txt", "File in subfolder")
        ]
        
        for (path, content) in testFiles {
            let filePath = tempDir.appendingPathComponent(path)
            let parentDir = filePath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try content.write(to: filePath, atomically: true, encoding: .utf8)
        }
        
        // Note: Since SWCompression doesn't support creating 7z archives,
        // we would need pre-created test archives for comprehensive testing
        // For now, we'll test with what we can
        
        // Test that create throws unsupported error
        #expect(throws: ArchiveError.self) {
            try handler.create(at: tempDir.appendingPathComponent("test.7z"), 
                             with: [("test.txt", Data("test".utf8))])
        }
    }
    
    @Test func testListContents() async throws {
        // This test requires a pre-created 7z file in TestData
        // Skip if not available
        let test7zPath = testDataDir.appendingPathComponent("test.7z")
        
        guard FileManager.default.fileExists(atPath: test7zPath.path) else {
            // Skip test if no test file
            return
        }
        
        let entries = try handler.listContents(of: test7zPath)
        
        #expect(!entries.isEmpty)
        
        for entry in entries {
            #expect(!entry.path.isEmpty)
            #expect(entry.uncompressedSize > 0)
            print("Found entry: \(entry.path) - \(entry.uncompressedSize) bytes")
        }
    }
    
    @Test func testExtractSingleFile() async throws {
        // This test requires a pre-created 7z file in TestData
        let test7zPath = testDataDir.appendingPathComponent("test.7z")
        
        guard FileManager.default.fileExists(atPath: test7zPath.path) else {
            // Skip test if no test file
            return
        }
        
        let entries = try handler.listContents(of: test7zPath)
        guard let firstEntry = entries.first else {
            Issue.record("No entries found in test archive")
            return
        }
        
        let data = try handler.extract(entry: firstEntry, from: test7zPath)
        
        #expect(!data.isEmpty)
        #expect(data.count == Int(firstEntry.uncompressedSize))
    }
    
    @Test func testExtractAll() async throws {
        // This test requires a pre-created 7z file in TestData
        let test7zPath = testDataDir.appendingPathComponent("test.7z")
        
        guard FileManager.default.fileExists(atPath: test7zPath.path) else {
            // Skip test if no test file
            return
        }
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try handler.extractAll(from: test7zPath, to: tempDir)
        
        // Verify files were extracted
        let extractedFiles = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        
        #expect(!extractedFiles.isEmpty)
    }
    
    @Test func testBatchExtraction() async throws {
        // This test requires a pre-created 7z file in TestData
        let test7zPath = testDataDir.appendingPathComponent("test.7z")
        
        guard FileManager.default.fileExists(atPath: test7zPath.path) else {
            // Skip test if no test file
            return
        }
        
        let entries = try handler.listContents(of: test7zPath)
        guard entries.count >= 2 else {
            // Need at least 2 entries for batch test
            return
        }
        
        let entriesToExtract = Array(entries.prefix(2))
        let extractedData = try await handler.extractMultiple(
            entries: entriesToExtract,
            from: test7zPath
        )
        
        #expect(extractedData.count == entriesToExtract.count)
        
        for entry in entriesToExtract {
            #expect(extractedData[entry.path] != nil)
        }
    }
    
    @Test func testInvalid7zFile() {
        // Create an invalid file
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).7z")
        
        let invalidData = Data("This is not a 7z file".utf8)
        try? invalidData.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        #expect(!handler.canHandle(url: tempFile))
        
        #expect(throws: ArchiveError.self) {
            _ = try handler.listContents(of: tempFile)
        }
    }
    
    @Test func testCRC32Calculation() {
        let testData = Data("Hello, World!".utf8)
        let crc32 = testData.crc32()
        
        // Known CRC32 for "Hello, World!" is 0xEC4AC3D0
        #expect(crc32 == 0xEC4AC3D0)
    }
    
    @Test func testPerformanceComparison() async throws {
        // Compare performance with ZIP if both test files exist
        let test7zPath = testDataDir.appendingPathComponent("large_test.7z")
        let testZipPath = testDataDir.appendingPathComponent("large_test.zip")
        
        guard FileManager.default.fileExists(atPath: test7zPath.path),
              FileManager.default.fileExists(atPath: testZipPath.path) else {
            // Skip performance test if files don't exist
            return
        }
        
        // Measure 7z extraction time
        let start7z = Date()
        _ = try handler.listContents(of: test7zPath)
        let time7z = Date().timeIntervalSince(start7z)
        
        // Measure ZIP extraction time
        let zipHandler = ZIPArchiveHandler()
        let startZip = Date()
        _ = try zipHandler.listContents(of: testZipPath)
        let timeZip = Date().timeIntervalSince(startZip)
        
        print("7z listing time: \(time7z)s")
        print("ZIP listing time: \(timeZip)s")
        print("7z is \(time7z / timeZip)x the time of ZIP")
        
        // 7z should typically be slower but with better compression
        #expect(time7z > 0)
        #expect(timeZip > 0)
    }
}