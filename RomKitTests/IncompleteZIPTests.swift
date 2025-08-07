//
//  IncompleteZIPTests.swift
//  RomKitTests
//
//  Tests for handling ZIP archives with missing ROM files
//

import Testing
import Foundation
@testable import RomKit

@Suite("Incomplete ZIP Archive Tests")
struct IncompleteZIPTests {

    @Test func testZIPWithMissingROMs() async throws {
        // Create a temporary directory for testing
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("incomplete_zip_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create test ROM data files
        let rom1Data = Data(repeating: 0x01, count: 1024)
        let rom2Data = Data(repeating: 0x02, count: 2048)
        // rom3 is intentionally not created

        // Create a ZIP with only 2 of 3 ROMs using system zip command
        let zipPath = tempDir.appendingPathComponent("testgame.zip")
        let tempRomDir = tempDir.appendingPathComponent("roms")
        try FileManager.default.createDirectory(at: tempRomDir, withIntermediateDirectories: true)

        // Write ROM files
        let rom1Path = tempRomDir.appendingPathComponent("rom1.bin")
        let rom2Path = tempRomDir.appendingPathComponent("rom2.bin")
        try rom1Data.write(to: rom1Path)
        try rom2Data.write(to: rom2Path)

        // Create ZIP using system command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-j", "-0", zipPath.path, rom1Path.path, rom2Path.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        // Verify ZIP exists
        #expect(FileManager.default.fileExists(atPath: zipPath.path))

        // Now test that we can detect the missing ROM
        let handler = FastZIPArchiveHandler()
        let entries = try handler.listContents(of: zipPath)

        // Should have 2 entries (rom3.bin is missing)
        #expect(entries.count == 2)
        #expect(entries.contains { $0.path == "rom1.bin" })
        #expect(entries.contains { $0.path == "rom2.bin" })
        #expect(!entries.contains { $0.path == "rom3.bin" })

        print("✓ Successfully detected incomplete ZIP with \(entries.count) of 3 expected ROMs")
    }

    @Test func testZIPWithCorruptROM() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt_zip_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create test ROM with known CRC
        let testData = "Hello World".data(using: .utf8)!
        let expectedCRC = HashUtilities.crc32(data: testData)

        // Create ROM with different data (wrong CRC)
        let wrongData = "Wrong Data!".data(using: .utf8)!

        // Create ZIP
        let zipPath = tempDir.appendingPathComponent("testgame.zip")
        let tempRomDir = tempDir.appendingPathComponent("roms")
        try FileManager.default.createDirectory(at: tempRomDir, withIntermediateDirectories: true)

        let romPath = tempRomDir.appendingPathComponent("test.rom")
        try wrongData.write(to: romPath)

        // Create ZIP
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-j", "-0", zipPath.path, romPath.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        // Extract and verify CRC mismatch
        let handler = FastZIPArchiveHandler()
        let entries = try handler.listContents(of: zipPath)
        #expect(entries.count == 1)

        if let entry = entries.first {
            let extractedData = try handler.extract(entry: entry, from: zipPath)
            let actualCRC = HashUtilities.crc32(data: extractedData)

            // CRCs should not match
            #expect(actualCRC != expectedCRC)
            print("✓ Detected CRC mismatch: expected \(expectedCRC), got \(actualCRC)")
        }
    }

    @Test func testCompleteZIP() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("complete_zip_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create all required ROMs
        let rom1Data = Data(repeating: 0x01, count: 1024)
        let rom2Data = Data(repeating: 0x02, count: 2048)
        let rom3Data = Data(repeating: 0x03, count: 512)

        // Create ZIP with all ROMs
        let zipPath = tempDir.appendingPathComponent("complete.zip")
        let tempRomDir = tempDir.appendingPathComponent("roms")
        try FileManager.default.createDirectory(at: tempRomDir, withIntermediateDirectories: true)

        let rom1Path = tempRomDir.appendingPathComponent("rom1.bin")
        let rom2Path = tempRomDir.appendingPathComponent("rom2.bin")
        let rom3Path = tempRomDir.appendingPathComponent("rom3.bin")

        try rom1Data.write(to: rom1Path)
        try rom2Data.write(to: rom2Path)
        try rom3Data.write(to: rom3Path)

        // Create ZIP
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-j", "-0", zipPath.path, rom1Path.path, rom2Path.path, rom3Path.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        // Verify all ROMs are present
        let handler = FastZIPArchiveHandler()
        let entries = try handler.listContents(of: zipPath)

        #expect(entries.count == 3)
        #expect(entries.contains { $0.path == "rom1.bin" })
        #expect(entries.contains { $0.path == "rom2.bin" })
        #expect(entries.contains { $0.path == "rom3.bin" })

        // Verify we can extract and validate each ROM
        for entry in entries {
            let data = try handler.extract(entry: entry, from: zipPath)
            let crc = HashUtilities.crc32(data: data)
            print("  ROM: \(entry.path), Size: \(data.count), CRC: \(crc)")
        }

        print("✓ Successfully validated complete ZIP with all \(entries.count) ROMs")
    }

    @Test
    func testEmptyZIP() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("empty_zip_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create empty ZIP by creating a dummy file and then removing it from the ZIP
        let zipPath = tempDir.appendingPathComponent("empty.zip")
        let dummyFile = tempDir.appendingPathComponent("dummy.txt")
        try Data().write(to: dummyFile)

        // Create ZIP with the dummy file
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", zipPath.path, dummyFile.lastPathComponent]
        process.currentDirectoryURL = tempDir
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        // Remove the file from the ZIP to make it empty
        let deleteProcess = Process()
        deleteProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        deleteProcess.arguments = ["-q", "-d", zipPath.path, dummyFile.lastPathComponent]
        deleteProcess.currentDirectoryURL = tempDir
        deleteProcess.standardOutput = FileHandle.nullDevice
        deleteProcess.standardError = FileHandle.nullDevice
        try deleteProcess.run()
        deleteProcess.waitUntilExit()

        // List contents - should be empty
        let handler = FastZIPArchiveHandler()
        let entries = try handler.listContents(of: zipPath)

        #expect(entries.isEmpty)
        print("✓ Successfully detected empty ZIP archive")
    }
}