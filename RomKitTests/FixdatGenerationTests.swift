//
//  FixdatGenerationTests.swift
//  RomKitTests
//
//  Tests for Fixdat generation functionality
//

import Testing
import Foundation
@testable import RomKit

@Suite("Fixdat Generation Tests")
struct FixdatGenerationTests {

    // MARK: - Test Data Setup

    private func createTestScanResult() -> ScanResult {
        let completeGame = createCompleteGame()
        let incompleteGame = createIncompleteGame()
        let missingGame = createMissingGame()

        let completeScanned = createCompleteScannedGame(completeGame)
        let incompleteScanned = createIncompleteScannedGame(incompleteGame)
        let missingScanned = createMissingScannedGame(missingGame)

        return ScanResult(
            scannedPath: "/test/roms",
            foundGames: [completeScanned, incompleteScanned, missingScanned],
            unknownFiles: ["/test/unknown.zip", "/test/extra.rom"]
        )
    }

    private func createCompleteGame() -> Game {
        Game(
            name: "complete_game",
            description: "A Complete Game",
            year: "1985",
            manufacturer: "Test Corp",
            roms: [
                ROM(name: "complete.rom", size: 1024, crc: "12345678"),
                ROM(name: "complete2.rom", size: 2048, crc: "87654321")
            ]
        )
    }

    private func createIncompleteGame() -> Game {
        Game(
            name: "incomplete_game",
            description: "An Incomplete Game",
            cloneOf: "parent_game",
            year: "1987",
            manufacturer: "Test Corp",
            roms: [
                ROM(name: "found.rom", size: 512, crc: "abcd1234"),
                ROM(name: "missing.rom", size: 1024, crc: "efgh5678"),
                ROM(name: "also_missing.rom", size: 256, crc: "ijkl9012")
            ]
        )
    }

    private func createMissingGame() -> Game {
        Game(
            name: "missing_game",
            description: "A Missing Game",
            year: "1990",
            manufacturer: "Other Corp",
            roms: [
                ROM(name: "nowhere.rom", size: 4096, crc: "missing1"),
                ROM(name: "gone.rom", size: 8192, crc: "missing2")
            ]
        )
    }

    private func createCompleteScannedGame(_ game: Game) -> ScannedGame {
        ScannedGame(
            game: game,
            foundRoms: [
                ScannedROM(
                    rom: game.roms[0],
                    filePath: "/test/complete.rom",
                    hash: FileHash(crc32: "12345678", sha1: "aaa", md5: "bbb", size: 1024),
                    status: .good
                ),
                ScannedROM(
                    rom: game.roms[1],
                    filePath: "/test/complete2.rom",
                    hash: FileHash(crc32: "87654321", sha1: "ccc", md5: "ddd", size: 2048),
                    status: .good
                )
            ],
            missingRoms: []
        )
    }

    private func createIncompleteScannedGame(_ game: Game) -> ScannedGame {
        ScannedGame(
            game: game,
            foundRoms: [
                ScannedROM(
                    rom: game.roms[0],
                    filePath: "/test/found.rom",
                    hash: FileHash(crc32: "abcd1234", sha1: "eee", md5: "fff", size: 512),
                    status: .good
                )
            ],
            missingRoms: [
                game.roms[1], // missing.rom
                game.roms[2]  // also_missing.rom
            ]
        )
    }

    private func createMissingScannedGame(_ game: Game) -> ScannedGame {
        ScannedGame(
            game: game,
            foundRoms: [],
            missingRoms: game.roms
        )
    }

    private func createTestDATFile() -> any DATFormat {
        let games = [
            LegacyGameAdapter(game: createCompleteGame()),
            LegacyGameAdapter(game: createIncompleteGame()),
            LegacyGameAdapter(game: createMissingGame()),
            LegacyGameAdapter(game: Game(
                name: "extra_game",
                description: "Not Scanned",
                year: "1991",
                manufacturer: "Extra Corp",
                roms: [
                    ROM(name: "extra.rom", size: 3072, crc: "extra123")
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

    @Test("Generate Fixdat from scan results")
    func testFixdatGeneration() throws {
        let scanResult = createTestScanResult()
        let datFile = createTestDATFile()

        let fixdat = FixdatGenerator.generateFixdat(
            from: scanResult,
            originalDAT: datFile
        )

        // Should contain games with missing ROMs
        #expect(fixdat.games.count == 2) // incomplete_game and missing_game
        #expect(fixdat.metadata.name.contains("Fix for"))
        #expect(fixdat.metadata.author == "RomKit")

        // Check that incomplete_game only has missing ROMs
        let incompleteFixGame = fixdat.games.first { $0.name == "incomplete_game" }
        #expect(incompleteFixGame != nil)
        #expect(incompleteFixGame?.items.count == 2) // 2 missing ROMs

        // Check missing_game has all ROMs
        let missingFixGame = fixdat.games.first { $0.name == "missing_game" }
        #expect(missingFixGame != nil)
        #expect(missingFixGame?.items.count == 2) // All ROMs missing
    }

    @Test("Generate Logiqx XML format")
    func testLogiqxXMLGeneration() throws {
        let scanResult = createTestScanResult()
        let datFile = createTestDATFile()

        let fixdat = FixdatGenerator.generateFixdat(from: scanResult, originalDAT: datFile)
        let xml = FixdatGenerator.generateLogiqxXML(from: fixdat)

        // Verify XML structure
        #expect(xml.contains("<?xml version=\"1.0\"?>"))
        #expect(xml.contains("<!DOCTYPE datafile"))
        #expect(xml.contains("<datafile>"))
        #expect(xml.contains("<header>"))
        #expect(xml.contains("<name>"))
        #expect(xml.contains("<game name=\"incomplete_game\">"))
        #expect(xml.contains("<rom name=\"missing.rom\""))
        #expect(xml.contains("crc=\"efgh5678\""))
        #expect(xml.contains("size=\"1024\""))
        #expect(xml.contains("</datafile>"))

        print("Generated Logiqx XML:")
        print(String(repeating: "=", count: 50))
        print(xml.prefix(1000))
        print(String(repeating: "=", count: 50))
    }

    @Test("Generate ClrMamePro format")
    func testClrMameProGeneration() throws {
        let scanResult = createTestScanResult()
        let datFile = createTestDATFile()

        let fixdat = FixdatGenerator.generateFixdat(from: scanResult, originalDAT: datFile)
        let dat = FixdatGenerator.generateClrMameProDAT(from: fixdat)

        // Verify ClrMamePro structure
        #expect(dat.contains("clrmamepro ("))
        #expect(dat.contains("name \""))
        #expect(dat.contains("game ("))
        #expect(dat.contains("name \"incomplete_game\""))
        #expect(dat.contains("rom ( name \"missing.rom\""))
        #expect(dat.contains("crc efgh5678"))
        #expect(dat.contains("size 1024"))

        print("Generated ClrMamePro DAT:")
        print(String(repeating: "=", count: 50))
        print(dat.prefix(1000))
        print(String(repeating: "=", count: 50))
    }

    @Test("Save Fixdat to file")
    func testFixdatSaving() throws {
        let scanResult = createTestScanResult()
        let datFile = createTestDATFile()
        let fixdat = FixdatGenerator.generateFixdat(from: scanResult, originalDAT: datFile)

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let logiqxPath = tempDir.appendingPathComponent("test_fixdat.xml").path
        let clrmamePath = tempDir.appendingPathComponent("test_fixdat.dat").path

        // Test Logiqx XML saving
        try fixdat.save(to: logiqxPath, format: .logiqxXML)
        #expect(FileManager.default.fileExists(atPath: logiqxPath))

        let xmlContent = try String(contentsOfFile: logiqxPath)
        #expect(xmlContent.contains("<?xml version=\"1.0\"?>"))
        #expect(xmlContent.contains("<game name=\"incomplete_game\">"))

        // Test ClrMamePro saving
        try fixdat.save(to: clrmamePath, format: .clrmamepro)
        #expect(FileManager.default.fileExists(atPath: clrmamePath))

        let datContent = try String(contentsOfFile: clrmamePath)
        #expect(datContent.contains("clrmamepro ("))
        #expect(datContent.contains("name \"incomplete_game\""))

        // Cleanup
        try? FileManager.default.removeItem(atPath: logiqxPath)
        try? FileManager.default.removeItem(atPath: clrmamePath)
    }
}

// MARK: - Helper Types

private struct TestDATFile: DATFormat {
    let formatName: String = "Test"
    let formatVersion: String? = "1.0"
    let metadata: any DATMetadata
    let games: [any GameEntry]
}
