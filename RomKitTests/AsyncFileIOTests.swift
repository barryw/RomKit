//
//  AsyncFileIOTests.swift
//  RomKitTests
//
//  Tests for AsyncFileIO to improve code coverage
//

import Testing
import Foundation
@testable import RomKit

struct AsyncFileIOTests {
    
    @Test func testAsyncReadData() async throws {
        // Create a test file
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_read_\(UUID()).txt")
        let testContent = "Hello, World!\nThis is a test file.\nLine 3\nLine 4\nLine 5"
        try testContent.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        // Test reading entire file
        let content = try await AsyncFileIO.readData(from: tempFile)
        #expect(content == Data(testContent.utf8))
    }
    
    @Test func testAsyncWriteData() async throws {
        // Create test data
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_write_\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        let testData = Data("Test content for async write".utf8)
        
        // Write file
        try await AsyncFileIO.writeData(testData, to: tempFile)
        
        // Verify file was written
        #expect(FileManager.default.fileExists(atPath: tempFile.path))
        
        let readData = try Data(contentsOf: tempFile)
        #expect(readData == testData)
    }
    
    @Test func testAsyncReadDataStreaming() async throws {
        // Create a large test file
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_stream_\(UUID()).txt")
        let lineCount = 100
        var content = ""
        for i in 0..<lineCount {
            content += "Line \(i): This is test content that will be streamed in chunks\n"
        }
        try content.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        // Read file with streaming
        var chunks: [Data] = []
        try await AsyncFileIO.readDataStreaming(from: tempFile) { chunk in
            chunks.append(chunk)
        }
        
        #expect(chunks.count > 0)
        
        // Verify total content
        let totalData = chunks.reduce(Data()) { $0 + $1 }
        #expect(totalData == Data(content.utf8))
    }
    
    @Test func testAsyncWriteDataStreaming() async throws {
        // Create test data
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_write_stream_\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        // Create large data
        let testString = String(repeating: "Test data for streaming write. ", count: 1000)
        let testData = Data(testString.utf8)
        
        // Write with streaming
        try await AsyncFileIO.writeDataStreaming(testData, to: tempFile)
        
        // Verify file was written
        #expect(FileManager.default.fileExists(atPath: tempFile.path))
        
        let readData = try Data(contentsOf: tempFile)
        #expect(readData == testData)
    }
    
    @Test func testConcurrentFileOperations() async throws {
        // Create multiple files concurrently
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("concurrent_\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Write multiple files concurrently
        let fileCount = 10
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<fileCount {
                group.addTask {
                    let file = tempDir.appendingPathComponent("file_\(i).txt")
                    let data = Data("Content \(i)".utf8)
                    try? await AsyncFileIO.writeData(data, to: file)
                }
            }
        }
        
        // Verify all files were created
        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        #expect(contents.count == fileCount)
    }
    
    @Test func testLargeFileHandling() async throws {
        // Create a large file
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("large_\(UUID()).dat")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        // Create 10MB of data
        let largeData = Data(repeating: 0x42, count: 10 * 1024 * 1024)
        
        // Write large file
        try await AsyncFileIO.writeData(largeData, to: tempFile)
        
        // Read it back
        let readData = try await AsyncFileIO.readData(from: tempFile)
        
        #expect(readData.count == largeData.count)
        #expect(readData == largeData)
    }
    
    @Test func testFileExtensions() async throws {
        // Test the Data extension for async write
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("ext_\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        let testData = Data("Testing Data extension".utf8)
        
        // Use the Data extension
        try await testData.writeAsync(to: tempFile)
        
        // Verify
        let readData = try Data(contentsOf: tempFile)
        #expect(readData == testData)
    }
    
    @Test func testParallelReads() async throws {
        // Create test files
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("parallel_\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let fileCount = 5
        var files: [URL] = []
        
        for i in 0..<fileCount {
            let file = tempDir.appendingPathComponent("file_\(i).txt")
            try "Content \(i)".write(to: file, atomically: true, encoding: .utf8)
            files.append(file)
        }
        
        // Read all files in parallel
        let results = await withTaskGroup(of: Data?.self) { group in
            for file in files {
                group.addTask {
                    try? await AsyncFileIO.readData(from: file)
                }
            }
            
            var results: [Data] = []
            for await data in group {
                if let data = data {
                    results.append(data)
                }
            }
            return results
        }
        
        #expect(results.count == fileCount)
    }
}