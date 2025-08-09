import Foundation
@testable import RomKit

// Create minimal test data
let game = Game(
    name: "test",
    description: "Test Game",
    year: "2020",
    manufacturer: "Test Corp",
    roms: [ROM(name: "test.rom", size: 1024, crc: "12345678")]
)

let scanResult = ScanResult(
    scannedPath: "/test",
    foundGames: [
        ScannedGame(
            game: game,
            foundRoms: [],
            missingRoms: game.roms
        )
    ],
    unknownFiles: []
)

let datFile = MockDATFormat(games: [LegacyGameAdapter(game: game)])

// Generate statistics
let stats = StatisticsGenerator.generate(from: scanResult, datFile: datFile)

// Try to generate text report
print("Generating text report...")
let report = stats.generateTextReport()
print("Report generated successfully!")
print(report.prefix(500))

// Helper types
struct MockDATFormat: DATFormat {
    let formatName = "Mock"
    let formatVersion: String? = "1.0"
    let games: [any GameEntry]
    let metadata: DATMetadata = MockDATMetadata()
}

struct MockDATMetadata: DATMetadata {
    let name = "Mock DAT"
    let description = "Mock DAT for testing"
    let version: String? = "1.0"
    let author: String? = "RomKit Test"
    let date: String? = nil
    let comment: String? = nil
    let url: String? = nil
}
