//
//  MissingReportTests.swift
//  RomKitTests
//
//  Tests for Missing Report generation functionality
//

import Testing
import Foundation
@testable import RomKit

@Suite("Missing Report Tests")
struct MissingReportTests {

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
            metadata: DATMetadata(
                name: "Test DAT",
                description: "Test DAT file for unit tests",
                version: "1.0",
                author: "Test Author",
                date: Date()
            ),
            games: games
        )
    }

    // MARK: - Tests

    @Test("Generate missing report with default options")
    func testMissingReportGeneration() throws {
        let scanResult = createTestScanResult()
        let datFile = createTestDATFile()

        let report = MissingReportGenerator.generate(
            from: scanResult,
            datFile: datFile
        )

        // Verify statistics
        #expect(report.totalGames == 3)
        #expect(report.completeGames == 1)
        #expect(report.partialGames == 1)
        #expect(report.missingGames == 1)
        #expect(report.totalROMs > 0)
        #expect(report.foundROMs > 0)
        #expect(report.missingROMs > 0)
        #expect(report.totalSize > 0)
        #expect(report.missingSize > 0)

        // Should have missing games categorized
        #expect(!report.missingByCategory.isEmpty)
        print("Missing by category: \(report.missingByCategory.keys)")
    }

    @Test("Generate HTML report")
    func testHTMLReportGeneration() throws {
        let scanResult = createTestScanResult()
        let datFile = createTestDATFile()

        let report = MissingReportGenerator.generate(from: scanResult, datFile: datFile)
        let html = report.generateHTML()

        // Verify HTML structure
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("<title>Missing ROMs Report</title>"))
        #expect(html.contains("Missing ROMs Report"))
        #expect(html.contains("Complete Games"))
        #expect(html.contains("ROMs Found"))
        #expect(html.contains("Collection Size"))
        #expect(html.contains("incomplete_game"))
        #expect(html.contains("missing.rom"))

        // Save for manual inspection
        let tempPath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("missing_report.html").path
        try html.write(toFile: tempPath, atomically: true, encoding: .utf8)
        print("HTML report saved to: \(tempPath)")
    }

    @Test("Generate text report")
    func testTextReportGeneration() throws {
        let scanResult = createTestScanResult()
        let datFile = createTestDATFile()

        let report = MissingReportGenerator.generate(from: scanResult, datFile: datFile)
        let text = report.generateText()

        // Verify text structure
        #expect(text.contains("MISSING ROMS REPORT"))
        #expect(text.contains("SUMMARY"))
        #expect(text.contains("Complete Games:"))
        #expect(text.contains("Missing ROMs:"))
        #expect(text.contains("DETAILED MISSING LIST"))
        #expect(text.contains("incomplete_game"))
        #expect(text.contains("missing.rom"))

        print("Generated Text Report:")
        print("=" * 80)
        print(text.prefix(2000))
        print("=" * 80)
    }

    @Test("Missing report with custom options")
    func testMissingReportWithOptions() throws {
        let scanResult = createTestScanResult()
        let datFile = createTestDATFile()

        let options = MissingReportOptions(
            groupByParent: true,
            includeDevices: false,
            includeBIOS: true,
            includeClones: true,
            showAlternatives: true,
            sortBy: .missingCount
        )

        let report = MissingReportGenerator.generate(
            from: scanResult,
            datFile: datFile,
            options: options
        )

        #expect(report.options.groupByParent == true)
        #expect(report.options.includeClones == true)
        #expect(report.options.sortBy == .missingCount)

        // Should have parent/clone groups when enabled
        if !report.parentCloneGroups.isEmpty {
            print("Parent/Clone groups found: \(report.parentCloneGroups.count)")
        }
    }
}

// MARK: - Helper Types

private struct TestDATFile: DATFormat {
    let metadata: DATMetadata
    let games: [any DATGame]
}
