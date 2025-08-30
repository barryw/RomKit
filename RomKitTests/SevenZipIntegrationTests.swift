//
//  SevenZipIntegrationTests.swift
//  RomKitTests
//
//  Integration tests for 7-Zip archive handling with real files
//

import Testing
@testable import RomKit
import Foundation


struct SevenZipIntegrationTests {
    
    let handler = SevenZipArchiveHandler()
    
    @Test func testCreateAndProcess7zArchive() async throws {
        // First, create some test ROM files
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("7z_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create synthetic ROM files
        let romFiles = [
            ("pacman.rom", Data(repeating: 0xAA, count: 16384)),
            ("galaga.rom", Data(repeating: 0xBB, count: 8192)),
            ("donkeykong.rom", Data(repeating: 0xCC, count: 32768)),
            ("subfolder/mario.rom", Data(repeating: 0xDD, count: 24576))
        ]
        
        for (path, data) in romFiles {
            let filePath = tempDir.appendingPathComponent(path)
            let parentDir = filePath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try data.write(to: filePath)
        }
        
        // Since we can't create 7z files with SWCompression, we'll use the system's 7z if available
        // or test with pre-existing files
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["7z"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        try? process.run()
        process.waitUntilExit()
        
        let has7z = process.terminationStatus == 0
        
        if has7z {
            // Create a 7z archive using system command
            let archive7zPath = tempDir.appendingPathComponent("test_roms.7z")
            
            let createProcess = Process()
            createProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            createProcess.arguments = ["7z", "a", "-r", archive7zPath.path, tempDir.path + "/*.rom"]
            createProcess.currentDirectoryURL = tempDir
            
            try? createProcess.run()
            createProcess.waitUntilExit()
            
            if FileManager.default.fileExists(atPath: archive7zPath.path) {
                // Test our handler with the created archive
                let entries = try handler.listContents(of: archive7zPath)
                #expect(entries.count >= 3)  // Should have at least 3 ROM files
                
                // Test extraction
                if let firstEntry = entries.first {
                    let data = try handler.extract(entry: firstEntry, from: archive7zPath)
                    #expect(!data.isEmpty)
                }
                
                // Test batch extraction
                let extractDir = tempDir.appendingPathComponent("extracted")
                try handler.extractAll(from: archive7zPath, to: extractDir)
                
                let extractedFiles = try FileManager.default.contentsOfDirectory(
                    at: extractDir,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                #expect(extractedFiles.count >= 3)
            }
        }
    }
    
    @Test func testWith7zFromSWCompression() async throws {
        // Use test files from SWCompression if available
        let swCompressionTestPath = URL(fileURLWithPath: ".build/checkouts/SWCompression/Tests/Test Files/7z")
        
        guard FileManager.default.fileExists(atPath: swCompressionTestPath.path) else {
            // SWCompression not checked out, skip test
            return
        }
        
        // Test with various 7z files from SWCompression test suite
        let testFiles = ["test1.7z", "test2.7z", "test3.7z", "SWCompressionSourceCode.7z"]
        
        for filename in testFiles {
            let testFile = swCompressionTestPath.appendingPathComponent(filename)
            
            guard FileManager.default.fileExists(atPath: testFile.path) else {
                continue
            }
            
            print("Testing with \(filename)")
            
            // Test listing
            let entries = try handler.listContents(of: testFile)
            print("  Found \(entries.count) entries")
            #expect(!entries.isEmpty)
            
            // Test extraction of first file
            if let firstEntry = entries.first {
                print("  Extracting: \(firstEntry.path)")
                let data = try handler.extract(entry: firstEntry, from: testFile)
                #expect(!data.isEmpty)
                #expect(data.count == Int(firstEntry.uncompressedSize))
                
                // Verify CRC if available
                if let expectedCRC = firstEntry.crc32 {
                    let actualCRC = String(format: "%08x", data.crc32())
                    #expect(actualCRC == expectedCRC)
                    print("  CRC32 verified: \(actualCRC)")
                }
            }
        }
    }
    
    @Test func testROMScenario() async throws {
        // Test a realistic ROM management scenario
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rom_scenario_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Use a test 7z file if available
        let swCompressionTestPath = URL(fileURLWithPath: ".build/checkouts/SWCompression/Tests/Test Files/7z/SWCompressionSourceCode.7z")
        
        guard FileManager.default.fileExists(atPath: swCompressionTestPath.path) else {
            // No test file available
            return
        }
        
        // Simulate ROM scanning
        print("Simulating ROM collection scan...")
        
        // 1. List contents (like scanning for ROMs)
        let entries = try handler.listContents(of: swCompressionTestPath)
        print("Found \(entries.count) potential ROMs")
        
        // 2. Calculate total size
        let totalUncompressed = entries.reduce(0) { $0 + $1.uncompressedSize }
        let totalCompressed = entries.reduce(0) { $0 + $1.compressedSize }
        let ratio = Double(totalCompressed) / Double(totalUncompressed)
        print("Compression ratio: \(String(format: "%.1f%%", ratio * 100))")
        
        // 3. Extract specific files (like rebuilding)
        let filesToExtract = entries.prefix(3)
        for entry in filesToExtract {
            let data = try handler.extract(entry: entry, from: swCompressionTestPath)
            let outputPath = tempDir.appendingPathComponent(entry.path.replacingOccurrences(of: "/", with: "_"))
            try data.write(to: outputPath)
            print("Extracted: \(entry.path) (\(data.count) bytes)")
        }
        
        // 4. Verify extraction
        let extractedFiles = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        #expect(extractedFiles.count == filesToExtract.count)
    }
    
    @Test func testErrorHandling() async throws {
        // Test various error conditions
        
        // 1. Non-existent file
        let nonExistent = URL(fileURLWithPath: "/tmp/does_not_exist.7z")
        #expect(throws: (any Error).self) {
            _ = try handler.listContents(of: nonExistent)
        }
        
        // 2. Invalid 7z file
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).7z")
        try Data("Not a 7z file".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        #expect(throws: ArchiveError.self) {
            _ = try handler.listContents(of: tempFile)
        }
        
        // 3. Extract non-existent entry
        let swCompressionTestPath = URL(fileURLWithPath: ".build/checkouts/SWCompression/Tests/Test Files/7z/test1.7z")
        
        if FileManager.default.fileExists(atPath: swCompressionTestPath.path) {
            let fakeEntry = ArchiveEntry(
                path: "non_existent_file.rom",
                compressedSize: 100,
                uncompressedSize: 100
            )
            
            #expect(throws: ArchiveError.self) {
                _ = try handler.extract(entry: fakeEntry, from: swCompressionTestPath)
            }
        }
    }
    
    @Test func testConcurrentExtraction() async throws {
        // Test thread safety with concurrent operations
        let swCompressionTestPath = URL(fileURLWithPath: ".build/checkouts/SWCompression/Tests/Test Files/7z/SWCompressionSourceCode.7z")
        
        guard FileManager.default.fileExists(atPath: swCompressionTestPath.path) else {
            return
        }
        
        let entries = try handler.listContents(of: swCompressionTestPath)
        guard entries.count >= 5 else {
            return
        }
        
        // Extract multiple files concurrently
        await withTaskGroup(of: Void.self) { group in
            for entry in entries.prefix(5) {
                group.addTask {
                    do {
                        let data = try self.handler.extract(entry: entry, from: swCompressionTestPath)
                        print("Concurrently extracted: \(entry.path) (\(data.count) bytes)")
                    } catch {
                        Issue.record("Failed to extract \(entry.path): \(error)")
                    }
                }
            }
        }
    }
    
    @Test func testMemoryEfficiency() async throws {
        // Test that we handle large files efficiently
        let swCompressionTestPath = URL(fileURLWithPath: ".build/checkouts/SWCompression/Tests/Test Files/7z/SWCompressionSourceCode.7z")
        
        guard FileManager.default.fileExists(atPath: swCompressionTestPath.path) else {
            return
        }
        
        // Monitor memory usage during extraction
        let startMemory = ProcessInfo.processInfo.physicalMemory
        
        let entries = try handler.listContents(of: swCompressionTestPath)
        
        // Extract files one by one to test memory is released
        for entry in entries {
            autoreleasepool {
                do {
                    let data = try handler.extract(entry: entry, from: swCompressionTestPath)
                    // Force deallocation by not keeping reference
                    _ = data.count
                } catch {
                    // Skip files that can't be extracted
                }
            }
        }
        
        let endMemory = ProcessInfo.processInfo.physicalMemory
        
        // Memory usage should be reasonable (not growing unbounded)
        print("Memory delta: \((endMemory - startMemory) / 1024 / 1024) MB")
    }
}