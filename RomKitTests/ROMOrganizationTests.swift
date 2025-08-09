//
//  ROMOrganizationTests.swift
//  RomKitTests
//
//  Tests for ROM Organization functionality
//

import Testing
import Foundation
@testable import RomKit

@Suite("ROM Organization Tests")
struct ROMOrganizationTests {

    // MARK: - Test Data Setup

    private func createTestDATFile() -> any DATFormat {
        let games = [
            LegacyGameAdapter(game: Game(
                name: "test_game",
                description: "Test Game",
                year: "1985",
                manufacturer: "Test Corp",
                roms: [
                    ROM(name: "test.rom", size: 1024, crc: "12345678")
                ]
            )),
            LegacyGameAdapter(game: Game(
                name: "another_game",
                description: "Another Game",
                year: "1987",
                manufacturer: "Other Corp",
                roms: [
                    ROM(name: "another.rom", size: 2048, crc: "87654321")
                ]
            ))
        ]

        return TestDATFile(
            metadata: MAMEMetadata(
                name: "Test DAT",
                description: "Test DAT file for unit tests",
                version: "1.0",
                author: "Test Author",
                date: Date().description
            ),
            games: games
        )
    }

    // MARK: - Tests

    @Test("ROM renaming functionality")
    func testROMRenaming() async throws {
        // Note: This is a placeholder test since ROMOrganizer currently
        // returns empty results (as noted in the implementation)
        let datFile = createTestDATFile()
        let organizer = ROMOrganizer(datFile: datFile)

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let testDir = tempDir.appendingPathComponent("rename_test")

        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        let result = try await organizer.renameROMs(
            in: testDir,
            dryRun: true,
            preserveOriginals: false
        )

        // Verify result structure
        #expect(result.dryRun == true)
        #expect(result.renamed.isEmpty) // Current implementation returns empty
        #expect(result.skipped.isEmpty)
        #expect(result.errors.isEmpty)

        print("Rename result summary:")
        print(result.summary)

        // Cleanup
        try? FileManager.default.removeItem(at: testDir)
    }

    @Test("ROM collection organization")
    func testROMOrganization() async throws {
        // Note: This is a placeholder test since ROMOrganizer currently
        // returns empty results (as noted in the implementation)
        let datFile = createTestDATFile()
        let organizer = ROMOrganizer(datFile: datFile)

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("organized")

        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let result = try await organizer.organizeCollection(
            from: sourceDir,
            to: destDir,
            style: .byManufacturer,
            moveFiles: false
        )

        // Verify result structure
        #expect(result.organized.isEmpty) // Current implementation returns empty
        #expect(result.errors.isEmpty)
        #expect(result.folders.isEmpty)

        print("Organization result summary:")
        print(result.summary)

        // Cleanup
        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: destDir)
    }

    @Test("Organization style determination")
    func testOrganizationStyles() {
        let testGame = LegacyGameAdapter(game: Game(
            name: "test_game",
            description: "Test Game",
            year: "1985",
            manufacturer: "Test Corp"
        ))

        let datFile = createTestDATFile()
        _ = ROMOrganizer(datFile: datFile)

        // Test different organization styles
        let styles: [OrganizationStyle] = [
            .flat,
            .byManufacturer,
            .byYear,
            .byGenre,
            .byAlphabet,
            .byParentClone,
            .byStatus
        ]

        for style in styles {
            // Access the private method through reflection would be complex,
            // so we'll test the enum cases exist and can be created
            switch style {
            case .flat:
                print("✓ Flat organization style")
            case .byManufacturer:
                print("✓ By manufacturer organization style")
            case .byYear:
                print("✓ By year organization style")
            case .byGenre:
                print("✓ By genre organization style")
            case .byAlphabet:
                print("✓ By alphabet organization style")
            case .byParentClone:
                print("✓ By parent/clone organization style")
            case .byStatus:
                print("✓ By status organization style")
            case .custom(let groupBy):
                let folder = groupBy(testGame)
                print("✓ Custom organization style: \(folder)")
            }
        }
    }

    @Test("Filename cleaning functionality")
    func testFilenameCleaning() async throws {
        let datFile = createTestDATFile()
        let organizer = ROMOrganizer(datFile: datFile)

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let testDir = tempDir.appendingPathComponent("clean_test")

        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        // Create test files with "dirty" names
        let testFiles = [
            "Game (USA) v1.0.zip",
            "Another Game [!] (Japan).zip",
            "Proto Game (Beta) Rev A.zip",
            "Clean Game.zip"
        ]

        for filename in testFiles {
            let filePath = testDir.appendingPathComponent(filename)
            try "test".write(to: filePath, atomically: true, encoding: .utf8)
        }

        let result = try organizer.cleanFilenames(
            in: testDir,
            removeRegionCodes: true,
            removeVersionNumbers: true,
            removeExtraInfo: true,
            dryRun: true
        )

        // Verify result structure
        #expect(result.dryRun == true)
        print("Filename cleaning results:")
        print("- Renamed: \(result.renamed.count)")
        print("- Skipped: \(result.skipped.count)")
        print("- Errors: \(result.errors.count)")

        for (from, to) in result.renamed {
            print("  \(from) → \(to)")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: testDir)
    }
}

// MARK: - Helper Types

private struct TestDATFile: DATFormat {
    let formatName: String = "Test"
    let formatVersion: String? = "1.0"
    let metadata: any DATMetadata
    let games: [any GameEntry]
}
