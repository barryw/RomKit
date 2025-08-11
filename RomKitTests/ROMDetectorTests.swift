//
//  ROMDetectorTests.swift
//  RomKitTests
//
//  Tests for content-based ROM detection
//

import Testing
import Foundation
@testable import RomKit

@Suite("ROM Content Detection")
struct ROMDetectorTests {

    @Test("Detect NES ROM by header")
    func testNESDetection() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a file with NES header but wrong extension
        var nesData = Data()
        nesData.append(contentsOf: [0x4E, 0x45, 0x53, 0x1A]) // "NES\x1A"
        nesData.append(contentsOf: [0x02, 0x01, 0x01, 0x00]) // PRG/CHR banks
        nesData.append(Data(count: 16384)) // Add some ROM data

        let nesFile = tempDir.appendingPathComponent("game.dat") // Wrong extension!
        try nesData.write(to: nesFile)

        // Test detection
        #expect(ROMDetector.isLikelyROM(at: nesFile), "Should detect NES ROM by header")
        #expect(ROMDetector.shouldIndexFile(at: nesFile), "Should index NES ROM with .dat extension")
    }

    @Test("Reject text files")
    func testTextFileRejection() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a text file with no extension
        let textData = Data("This is just a text file\nWith multiple lines\nNot a ROM at all".utf8)
        let textFile = tempDir.appendingPathComponent("readme")
        try textData.write(to: textFile)

        #expect(!ROMDetector.isLikelyROM(at: textFile), "Should reject text file")
        #expect(!ROMDetector.shouldIndexFile(at: textFile), "Should not index text file")
    }

    @Test("Detect ROM with no extension")
    func testNoExtensionROM() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a binary file with no extension (high entropy)
        var binaryData = Data()
        for index in 0..<1024 {
            binaryData.append(UInt8(index & 0xFF))
        }

        let romFile = tempDir.appendingPathComponent("GAME")
        try binaryData.write(to: romFile)

        #expect(ROMDetector.isLikelyROM(at: romFile), "Should detect binary file as potential ROM")
        #expect(ROMDetector.shouldIndexFile(at: romFile), "Should index binary file with no extension")
    }

    @Test("Scanner with content detection")
    func testScannerContentDetection() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create various files
        // 1. NES ROM with wrong extension
        var nesData = Data()
        nesData.append(contentsOf: [0x4E, 0x45, 0x53, 0x1A]) // NES header
        nesData.append(Data(count: 32768))
        try nesData.write(to: tempDir.appendingPathComponent("mario.game"))

        // 2. Binary file with no extension
        let binaryData = Data((0..<2048).map { UInt8($0 & 0xFF) })
        try binaryData.write(to: tempDir.appendingPathComponent("SONIC"))

        // 3. Text file that should be ignored
        let textData = Data("README file contents".utf8)
        try textData.write(to: tempDir.appendingPathComponent("README"))

        // 4. Standard ROM with correct extension
        try Data(count: 1024).write(to: tempDir.appendingPathComponent("zelda.nes"))

        // Scan with content detection
        let scanner = ConcurrentScanner(useContentDetection: true)
        let results = try await scanner.scanDirectory(at: tempDir, computeHashes: false)

        let foundFiles = results.map { $0.url.lastPathComponent }.sorted()
        print("Scanner found: \(foundFiles)")

        // Should find the NES header file, binary file, and .nes file, but NOT the text file
        #expect(foundFiles.contains("mario.game"), "Should find NES ROM with wrong extension")
        #expect(foundFiles.contains("SONIC"), "Should find binary file with no extension")
        #expect(foundFiles.contains("zelda.nes"), "Should find file with correct extension")
        #expect(!foundFiles.contains("README"), "Should NOT index text file")

        #expect(results.count >= 3, "Should find at least 3 ROM files")
    }

    @Test("Index with content detection")
    func testIndexingWithContentDetection() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create ROM with unusual extension
        var genesisData = Data(count: 0x100) // Padding to position 0x100
        genesisData.append(contentsOf: [0x53, 0x45, 0x47, 0x41]) // "SEGA" at 0x100
        genesisData.append(Data(count: 65536)) // Add more data

        let romFile = tempDir.appendingPathComponent("streets_of_rage.rom123")
        try genesisData.write(to: romFile)

        // Also create a text file that shouldn't be indexed
        try Data("Just a text file".utf8).write(to: tempDir.appendingPathComponent("notes.txt"))

        // Index with content detection (put DB in different directory)
        let dbDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("db_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dbDir) }

        let dbPath = dbDir.appendingPathComponent("index.db")
        let indexManager = try await ROMIndexManager(databasePath: dbPath)
        try await indexManager.addSource(tempDir, showProgress: false)

        let indexed = await indexManager.loadIndexIntoMemory()
        let fileNames = indexed.flatMap { $0.value.map { $0.name } }.sorted()

        print("Indexed files: \(fileNames)")

        #expect(fileNames.contains("streets_of_rage.rom123"), "Should index ROM with unusual extension")
        #expect(!fileNames.contains("notes.txt"), "Should not index text file")
    }
}