//
//  RomKitTests.swift
//  RomKitTests
//
//  Created by Barry Walker on 8/5/25.
//

import Testing
import Foundation
@testable import RomKit

struct RomKitTests {

    @Test func testDATFileModel() async throws {
        let rom = ROM(
            name: "test.bin",
            size: 1024,
            crc: "12345678",
            sha1: "abcdef1234567890",
            status: .good
        )

        #expect(rom.name == "test.bin")
        #expect(rom.size == 1024)
        #expect(rom.crc == "12345678")
        #expect(rom.status == .good)
    }

    @Test func testGameModel() async throws {
        let game = Game(
            name: "pacman",
            description: "Pac-Man",
            year: "1980",
            manufacturer: "Namco",
            roms: []
        )

        #expect(game.name == "pacman")
        #expect(game.isParent == true)
        #expect(game.isClone == false)

        let clone = Game(
            name: "pacmanf",
            description: "Pac-Man (fast)",
            cloneOf: "pacman",
            roms: []
        )

        #expect(clone.isClone == true)
        #expect(clone.isParent == false)
    }

    @Test func testHashUtilities() async throws {
        let testData = Data("Hello, World!".utf8)

        let crc = HashUtilities.crc32(data: testData)
        #expect(crc.count == 8)

        let sha1 = HashUtilities.sha1(data: testData)
        #expect(sha1.count == 40)

        let md5 = HashUtilities.md5(data: testData)
        #expect(md5.count == 32)
    }

    @Test func testFileHashMatching() async throws {
        let rom = ROM(
            name: "test.bin",
            size: 13,
            crc: "ec4e3c34",
            sha1: "0a0a9f2a6772e8146c3a8e9b8c8f3c6d7f8e9a0b1",
            status: .good
        )

        let matchingHash = FileHash(
            crc32: "EC4E3C34",
            sha1: "0a0a9f2a6772e8146c3a8e9b8c8f3c6d7f8e9a0b1",
            md5: "ignored",
            size: 13
        )

        #expect(matchingHash.matches(rom: rom) == true)

        let mismatchedHash = FileHash(
            crc32: "DEADBEEF",
            sha1: "0a0a9f2a6772e8146c3a8e9b8c8f3c6d7f8e9a0b1",
            md5: "ignored",
            size: 13
        )

        #expect(mismatchedHash.matches(rom: rom) == false)
    }

    @Test func testMAMEDATParser() async throws {
        let xmlString = """
        <?xml version="1.0"?>
        <datafile build="test">
            <header>
                <name>Test DAT</name>
                <description>Test Description</description>
                <version>1.0</version>
            </header>
            <game name="testgame">
                <description>Test Game</description>
                <year>2024</year>
                <manufacturer>Test Corp</manufacturer>
                <rom name="test.bin" size="1024" crc="12345678" sha1="abcdef"/>
            </game>
        </datafile>
        """

        let xmlData = Data(xmlString.utf8)

        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: xmlData)

        #expect(datFile.metadata.name == "Test DAT")
        #expect(datFile.metadata.description == "Test Description")
        #expect(datFile.metadata.version == "1.0")
        #expect(datFile.games.count == 1)

        let game = datFile.games.first as? MAMEGame
        #expect(game?.name == "testgame")
        #expect(game?.items.count == 1)
        #expect(game?.items.first?.name == "test.bin")
    }

    @Test func testAuditStatistics() async throws {
        let stats = AuditStatistics(
            totalGames: 100,
            completeGames: 75,
            incompleteGames: 20,
            missingGames: 5,
            totalRoms: 1000,
            goodRoms: 900,
            badRoms: 50,
            missingRoms: 50
        )

        #expect(stats.completionPercentage == 75.0)
        #expect(stats.totalGames == 100)
        #expect(stats.completeGames + stats.incompleteGames + stats.missingGames == stats.totalGames)
    }

    @Test func testRomKitInitialization() async throws {
        _ = RomKit(concurrencyLevel: 4)

        // Test generic version
        let genericKit = RomKitGeneric()
        #expect(genericKit.isLoaded == false)
        #expect(genericKit.availableFormats.contains("mame"))
        #expect(genericKit.availableFormats.contains("no-intro"))
        #expect(genericKit.availableFormats.contains("redump"))
    }

    @Test func testFormatRegistry() async throws {
        let registry = RomKitFormatRegistry.shared

        #expect(registry.handler(for: "mame") != nil)
        #expect(registry.handler(for: "no-intro") != nil)
        #expect(registry.handler(for: "redump") != nil)
        #expect(registry.handler(for: "invalid") == nil)
    }
}
