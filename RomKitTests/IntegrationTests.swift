//
//  IntegrationTests.swift
//  RomKitTests
//
//  Created by Barry Walker on 8/5/25.
//

import Testing
import Foundation
@testable import RomKit

struct IntegrationTests {

    let testDataPath = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .appendingPathComponent("TestData")

    @Test func testRealMAMEDATParser() async throws {
        let datPath = testDataPath.appendingPathComponent("mame_sample.xml")
        let data = try Data(contentsOf: datPath)

        let parser = MAMEDATParser()
        #expect(parser.canParse(data: data) == true)

        let datFile = try parser.parse(data: data)

        // Verify header
        #expect(datFile.formatName == "MAME")
        if let mameMetadata = datFile.metadata as? MAMEMetadata {
            #expect(mameMetadata.name.contains("0.261") || mameMetadata.build?.contains("0.261") == true)
        }

        // Verify game count
        #expect(datFile.games.count == 5)

        // Find specific games
        let puckman = datFile.games.first { ($0 as? MAMEGame)?.name == "puckman" } as? MAMEGame
        let pacman = datFile.games.first { ($0 as? MAMEGame)?.name == "pacman" } as? MAMEGame
        let mspacman = datFile.games.first { ($0 as? MAMEGame)?.name == "mspacman" } as? MAMEGame
        let galaga = datFile.games.first { ($0 as? MAMEGame)?.name == "galaga" } as? MAMEGame
        let dkong = datFile.games.first { ($0 as? MAMEGame)?.name == "dkong" } as? MAMEGame

        #expect(puckman != nil)
        #expect(pacman != nil)
        #expect(mspacman != nil)
        #expect(galaga != nil)
        #expect(dkong != nil)
    }

    @Test func testParentCloneRelationships() async throws {
        let datPath = testDataPath.appendingPathComponent("mame_sample.xml")
        let data = try Data(contentsOf: datPath)

        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: data)

        // Test Pac-Man clone relationship
        let puckman = datFile.games.first { ($0 as? MAMEGame)?.name == "puckman" } as? MAMEGame
        let pacman = datFile.games.first { ($0 as? MAMEGame)?.name == "pacman" } as? MAMEGame

        #expect(puckman != nil)
        #expect(pacman != nil)

        // Puckman is the parent
        let puckmanMeta = puckman?.metadata as? MAMEGameMetadata
        #expect(puckmanMeta?.cloneOf == nil)

        // Pacman is a clone of puckman
        let pacmanMeta = pacman?.metadata as? MAMEGameMetadata
        #expect(pacmanMeta?.cloneOf == "puckman")
        #expect(pacmanMeta?.romOf == "puckman")
    }

    @Test func testROMDetails() async throws {
        let datPath = testDataPath.appendingPathComponent("mame_sample.xml")
        let data = try Data(contentsOf: datPath)

        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: data)

        let puckman = datFile.games.first { ($0 as? MAMEGame)?.name == "puckman" } as? MAMEGame
        #expect(puckman != nil)

        // Check ROM count
        #expect(puckman?.items.count == 14)

        // Check specific ROM details
        if let firstRom = puckman?.items.first as? MAMEROM {
            #expect(firstRom.name == "pm1_prg1.6e")
            #expect(firstRom.size == 2048)
            #expect(firstRom.checksums.crc32 == "f36e88ab")
            #expect(firstRom.checksums.sha1 == "813cecf44bf5464b1aed64b36f5047e4c79ba176")
            #expect(firstRom.region == "maincpu")
        }
    }

    @Test func testMergedROMs() async throws {
        let datPath = testDataPath.appendingPathComponent("mame_sample.xml")
        let data = try Data(contentsOf: datPath)

        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: data)

        let pacman = datFile.games.first { ($0 as? MAMEGame)?.name == "pacman" } as? MAMEGame
        #expect(pacman != nil)

        // Find merged ROMs
        let mergedRoms = pacman?.items.compactMap { item -> MAMEROM? in
            guard let rom = item as? MAMEROM else { return nil }
            return rom.attributes.merge != nil ? rom : nil
        }

        #expect(mergedRoms?.count ?? 0 > 0)

        // Check a merged ROM
        if let mergedRom = mergedRoms?.first {
            #expect(mergedRom.attributes.merge == mergedRom.name)
        }
    }

    @Test func testGameMetadata() async throws {
        let datPath = testDataPath.appendingPathComponent("mame_sample.xml")
        let data = try Data(contentsOf: datPath)

        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: data)

        // Test different games' metadata
        let games = datFile.games.compactMap { $0 as? MAMEGame }

        for game in games {
            #expect(!game.description.isEmpty)
            #expect(game.metadata.year != nil)
            #expect(game.metadata.manufacturer != nil)

            // Check source file is parsed
            if let meta = game.metadata as? MAMEGameMetadata {
                #expect(meta.sourceFile != nil)
            }
        }
    }

    @Test func testPerformanceWithRealDAT() async throws {
        let datPath = testDataPath.appendingPathComponent("mame_sample.xml")
        let data = try Data(contentsOf: datPath)

        let parser = MAMEDATParser()

        // Measure parsing time
        let startTime = Date()
        let datFile = try parser.parse(data: data)
        let endTime = Date()

        let parseTime = endTime.timeIntervalSince(startTime)

        // Should parse small DAT very quickly
        #expect(parseTime < 1.0)

        print("Parsed \(datFile.games.count) games in \(parseTime) seconds")

        // Calculate total ROM count
        let totalRoms = datFile.games.reduce(0) { count, game in
            count + ((game as? MAMEGame)?.items.count ?? 0)
        }

        print("Total ROMs: \(totalRoms)")
        #expect(totalRoms > 0)
    }

    @Test func testRomKitWithRealDAT() async throws {
        let datPath = testDataPath.appendingPathComponent("mame_sample.xml")

        let romKit = RomKitGeneric()
        try romKit.loadDAT(from: datPath, format: "mame")

        #expect(romKit.isLoaded == true)
        #expect(romKit.currentFormat == "MAME")

        // Verify we can access the loaded data
        if let datFile = romKit.currentDATFile as? MAMEDATFile {
            #expect(datFile.games.count == 5)
        }
    }

    @Test func testValidatorWithRealChecksums() async throws {
        let validator = MAMEROMValidator()

        // Test with known data
        let testData = "Hello, MAME!".data(using: .utf8)!
        let checksums = validator.computeChecksums(for: testData)

        #expect(checksums.crc32 != nil)
        #expect(checksums.sha1 != nil)
        #expect(checksums.md5 != nil)

        // Create a mock ROM to validate against
        let rom = MAMEROM(
            name: "test.rom",
            size: UInt64(testData.count),
            checksums: checksums,
            status: .good
        )

        let result = validator.validate(item: rom, against: testData)
        #expect(result.isValid == true)
        #expect(result.errors.isEmpty)
    }
}
