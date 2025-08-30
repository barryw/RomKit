//
//  TestLib7z.swift
//  RomKit
//
//  Test lib7z integration
//

import Testing
import Foundation
@testable import RomKit

@Test("lib7z can handle real 7z files")
func testLib7zRealFile() throws {
    let handler = SevenZipArchiveHandler()
    
    // Create a test 7z file
    let testDir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("test_lib7z_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: testDir) }
    
    // Create test files
    let testFile1 = testDir.appendingPathComponent("test1.txt")
    let testFile2 = testDir.appendingPathComponent("test2.txt")
    try "Hello from lib7z".data(using: .utf8)!.write(to: testFile1)
    try "Testing 7z integration".data(using: .utf8)!.write(to: testFile2)
    
    // Create 7z archive using command line tool
    let archivePath = testDir.appendingPathComponent("test.7z")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = ["7z", "a", archivePath.path, testFile1.path, testFile2.path]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    
    try task.run()
    task.waitUntilExit()
    
    #expect(task.terminationStatus == 0, "Failed to create 7z archive")
    
    // Test canHandle
    #expect(handler.canHandle(url: archivePath))
    
    // Test listContents
    let contents = try handler.listContents(of: archivePath)
    #expect(contents.count == 2)
    
    // Find test1.txt entry
    let test1Entry = contents.first { $0.path.contains("test1.txt") }
    #expect(test1Entry != nil)
    
    if let entry = test1Entry {
        // Test extraction
        let extractedData = try handler.extract(entry: entry, from: archivePath)
        let extractedString = String(data: extractedData, encoding: .utf8)
        #expect(extractedString == "Hello from lib7z")
    }
    
    // Test extractAll
    let extractDir = testDir.appendingPathComponent("extracted")
    try handler.extractAll(from: archivePath, to: extractDir)
    
    // Verify extracted files
    let extractedFile1 = extractDir.appendingPathComponent("test1.txt")
    let extractedFile2 = extractDir.appendingPathComponent("test2.txt")
    
    #expect(FileManager.default.fileExists(atPath: extractedFile1.path))
    #expect(FileManager.default.fileExists(atPath: extractedFile2.path))
    
    let content1 = try String(contentsOf: extractedFile1, encoding: .utf8)
    let content2 = try String(contentsOf: extractedFile2, encoding: .utf8)
    
    #expect(content1 == "Hello from lib7z")
    #expect(content2 == "Testing 7z integration")
}

@Test("lib7z handles invalid files gracefully")
func testLib7zInvalidFiles() {
    let handler = SevenZipArchiveHandler()
    
    // Test non-existent file
    let nonExistent = URL(fileURLWithPath: "/tmp/does_not_exist.7z")
    #expect(!handler.canHandle(url: nonExistent))
    
    // Test invalid file (not a 7z)
    let tempFile = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("invalid.7z")
    try? "Not a 7z file".data(using: .utf8)!.write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }
    
    #expect(!handler.canHandle(url: tempFile))
    #expect(throws: (any Error).self) {
        _ = try handler.listContents(of: tempFile)
    }
}