//
//  CollectionStatisticsTests.swift
//  RomKitTests
//
//  Tests for Collection Statistics generation functionality
//

import Testing
import Foundation
@testable import RomKit

@Suite("Collection Statistics Tests")
struct CollectionStatisticsTests {

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

    @Test("Generate collection statistics")
    func testCollectionStatistics() throws {
        let scanResult = createTestScanResult()
        let datFile = createTestDATFile()

        let stats = StatisticsGenerator.generate(from: scanResult, datFile: datFile)

        // Verify basic statistics
        #expect(stats.totalGames == 3)
        #expect(stats.completeGames == 1)
        #expect(stats.partialGames == 1)
        #expect(stats.missingGames == 1)
        #expect(stats.completionPercentage > 0)
        #expect(stats.completionPercentage < 100)

        #expect(stats.totalROMs > 0)
        #expect(stats.foundROMs > 0)
        #expect(stats.missingROMs > 0)
        #expect(stats.romCompletionPercentage > 0)

        #expect(stats.totalSize > 0)
        #expect(stats.collectionSize > 0)
        #expect(stats.missingSize > 0)

        // Should have breakdown by year and manufacturer
        #expect(!stats.byYear.isEmpty)
        #expect(!stats.byManufacturer.isEmpty)

        print("Collection Statistics:")
        print("- Total Games: \(stats.totalGames)")
        print("- Complete: \(stats.completeGames) (\(String(format: "%.1f", stats.completionPercentage))%)")
        print("- ROMs Found: \(stats.foundROMs)/\(stats.totalROMs)")
        print("- Health Score: \(String(format: "%.0f", stats.healthScore))%")
        print("- Years: \(stats.byYear.keys.sorted())")
        print("- Manufacturers: \(stats.byManufacturer.keys.sorted())")
    }

    @Test("Generate statistics text report")
    func testStatisticsTextReport() throws {
        let scanResult = createTestScanResult()
        let datFile = createTestDATFile()

        let stats = StatisticsGenerator.generate(from: scanResult, datFile: datFile)
        let textReport = stats.generateTextReport()

        // Verify report structure
        #expect(textReport.contains("COLLECTION STATISTICS REPORT"))
        #expect(textReport.contains("OVERALL SUMMARY"))
        #expect(textReport.contains("Total Games:"))
        #expect(textReport.contains("Complete:"))
        #expect(textReport.contains("Health Score:"))
        #expect(textReport.contains("ROM STATISTICS"))
        #expect(textReport.contains("STORAGE USAGE"))
        #expect(textReport.contains("TOP MANUFACTURERS"))

        print("Statistics Text Report:")
        print(String(repeating: "=", count: 80))
        print(textReport.prefix(1500))
        print(String(repeating: "=", count: 80))
    }

    @Test("Generate statistics HTML report")
    func testStatisticsHTMLReport() throws {
        let scanResult = createTestScanResult()
        let datFile = createTestDATFile()

        let stats = StatisticsGenerator.generate(from: scanResult, datFile: datFile)
        let htmlReport = stats.generateHTMLReport()

        // Verify HTML structure
        #expect(htmlReport.contains("<!DOCTYPE html>"))
        #expect(htmlReport.contains("<title>Collection Statistics</title>"))
        #expect(htmlReport.contains("Collection Statistics"))
        #expect(htmlReport.contains("Collection Completion"))
        #expect(htmlReport.contains("Health Score"))
        #expect(htmlReport.contains("canvas id=\"yearChart\""))
        #expect(htmlReport.contains("Top Manufacturers"))

        // Save for manual inspection
        let tempPath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("collection_stats.html").path
        try htmlReport.write(toFile: tempPath, atomically: true, encoding: .utf8)
        print("HTML statistics report saved to: \(tempPath)")
    }

    @Test("Collection health score calculation")
    func testHealthScoreCalculation() throws {
        let scanResult = createTestScanResult()
        let datFile = createTestDATFile()

        let stats = StatisticsGenerator.generate(from: scanResult, datFile: datFile)

        // Health score should be between 0 and 100
        #expect(stats.healthScore >= 0)
        #expect(stats.healthScore <= 100)

        // With our test data (1 complete, 1 partial, 1 missing),
        // health score should be reasonable
        #expect(stats.healthScore > 0) // Should have some score
        #expect(stats.healthScore < 100) // Should not be perfect

        // Issues should be detected
        print("Health Score: \(String(format: "%.0f", stats.healthScore))%")
        print("Issues found: \(stats.issues.count)")
        for issue in stats.issues {
            print("- \(issue.description) (severity: \(issue.severity))")
        }
    }
}

// MARK: - Helper Types

private struct TestDATFile: DATFormat {
    let formatName: String = "Test"
    let formatVersion: String? = "1.0"
    let metadata: any DATMetadata
    let games: [any GameEntry]
}
