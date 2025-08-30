//
//  SevenZipRealFileTests.swift
//  RomKitTests
//
//  Tests for 7-Zip archive handling with actual 7z files
//

import Testing
@testable import RomKit
import Foundation

@Suite("SevenZip Real File Tests")
struct SevenZipRealFileTests {
    
    let handler = SevenZipArchiveHandler()
    let testDataDir = Bundle.module.url(forResource: "TestData", withExtension: nil)!
    
    @Test func testSimple7zFile() async throws {
        let test7zPath = testDataDir.appendingPathComponent("test_rom.7z")
        
        // Verify the file exists and is a valid 7z
        #expect(FileManager.default.fileExists(atPath: test7zPath.path))
        #expect(handler.canHandle(url: test7zPath))
        
        // List contents
        let entries = try handler.listContents(of: test7zPath)
        #expect(entries.count == 1)
        #expect(entries[0].path == "test.rom")
        
        // Extract the file
        let data = try handler.extract(entry: entries[0], from: test7zPath)
        let content = String(data: data, encoding: .utf8)
        #expect(content?.trimmingCharacters(in: .whitespacesAndNewlines) == "Test ROM data")
        
        // Test CRC32
        if let crc = entries[0].crc32 {
            let calculatedCRC = String(format: "%08x", data.crc32())
            print("Expected CRC: \(crc), Calculated: \(calculatedCRC)")
        }
    }
    
    @Test func testComplex7zFile() async throws {
        let test7zPath = testDataDir.appendingPathComponent("complex_test.7z")
        
        guard FileManager.default.fileExists(atPath: test7zPath.path) else {
            Issue.record("complex_test.7z not found in TestData")
            return
        }
        
        // List contents
        let entries = try handler.listContents(of: test7zPath)
        #expect(entries.count == 3)
        
        // Expected files
        let expectedFiles = ["dk.rom", "galaga.rom", "pacman.rom"]
        let actualFiles = entries.map { $0.path }.sorted()
        
        for expected in expectedFiles {
            #expect(actualFiles.contains { $0.contains(expected) })
        }
        
        // Extract all files
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try handler.extractAll(from: test7zPath, to: tempDir)
        
        // Verify extracted files
        let extractedFiles = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        
        #expect(extractedFiles.count >= 3)
        
        // Check content of extracted files
        for file in extractedFiles {
            let data = try Data(contentsOf: file)
            #expect(!data.isEmpty)
            print("Extracted: \(file.lastPathComponent) - \(data.count) bytes")
        }
    }
    
    @Test func testBatchExtraction() async throws {
        let test7zPath = testDataDir.appendingPathComponent("complex_test.7z")
        
        guard FileManager.default.fileExists(atPath: test7zPath.path) else {
            return
        }
        
        let entries = try handler.listContents(of: test7zPath)
        
        // Extract multiple files at once
        let results = try await handler.extractMultiple(entries: entries, from: test7zPath)
        
        #expect(results.count == entries.count)
        
        for entry in entries {
            #expect(results[entry.path] != nil)
            if let data = results[entry.path] {
                print("Batch extracted: \(entry.path) - \(data.count) bytes")
            }
        }
    }
    
    @Test func testROMWorkflow() async throws {
        // Simulate a complete ROM management workflow
        let test7zPath = testDataDir.appendingPathComponent("complex_test.7z")
        
        guard FileManager.default.fileExists(atPath: test7zPath.path) else {
            return
        }
        
        // 1. Scan archive (like finding ROMs)
        print("Step 1: Scanning archive...")
        let entries = try handler.listContents(of: test7zPath)
        print("Found \(entries.count) ROMs")
        
        // 2. Validate ROMs (check sizes, CRCs)
        print("\nStep 2: Validating ROMs...")
        for entry in entries {
            print("  \(entry.path):")
            print("    Size: \(entry.uncompressedSize) bytes")
            if let crc = entry.crc32 {
                print("    CRC32: \(crc)")
            }
        }
        
        // 3. Extract specific ROM (like for playing)
        print("\nStep 3: Extracting ROM for use...")
        if let pacmanEntry = entries.first(where: { $0.path.contains("pacman") }) {
            let romData = try handler.extract(entry: pacmanEntry, from: test7zPath)
            print("Extracted \(pacmanEntry.path): \(romData.count) bytes")
            
            // Verify CRC
            let calculatedCRC = String(format: "%08x", romData.crc32())
            if let expectedCRC = pacmanEntry.crc32 {
                #expect(calculatedCRC == expectedCRC)
                print("CRC32 verified: \(calculatedCRC)")
            }
        }
        
        // 4. Rebuild to new location (extract all)
        print("\nStep 4: Rebuilding ROM set...")
        let rebuildDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rebuilt_roms_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rebuildDir) }
        
        try handler.extractAll(from: test7zPath, to: rebuildDir)
        
        let rebuiltFiles = try FileManager.default.contentsOfDirectory(
            at: rebuildDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        
        #expect(rebuiltFiles.count == entries.count)
        print("Rebuilt \(rebuiltFiles.count) ROMs successfully")
    }
    
    @Test func testPerformance() async throws {
        let test7zPath = testDataDir.appendingPathComponent("complex_test.7z")
        
        guard FileManager.default.fileExists(atPath: test7zPath.path) else {
            return
        }
        
        // Measure listing performance
        let listStart = Date()
        let entries = try handler.listContents(of: test7zPath)
        let listTime = Date().timeIntervalSince(listStart)
        print("Listed \(entries.count) entries in \(String(format: "%.3f", listTime))s")
        
        // Measure extraction performance
        let extractStart = Date()
        for entry in entries {
            _ = try handler.extract(entry: entry, from: test7zPath)
        }
        let extractTime = Date().timeIntervalSince(extractStart)
        print("Extracted \(entries.count) files in \(String(format: "%.3f", extractTime))s")
        
        // Performance should be reasonable
        #expect(listTime < 1.0)  // Listing should be fast
        #expect(extractTime < 5.0)  // Extraction should complete quickly
    }
}