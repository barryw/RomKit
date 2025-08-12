//
//  RomKitAPITests.swift
//  RomKitTests
//
//  Created by RomKit on 8/5/25.
//

import XCTest
@testable import RomKit

final class RomKitAPITests: XCTestCase {

    func testDATHeaderAccess() async throws {
        let romKit = RomKit()

        // Load a test DAT file
        guard let testDATPath = Bundle.module.url(forResource: "mame_sample", withExtension: "xml", subdirectory: "TestData") else {
            XCTFail("Could not find test DAT file")
            return
        }

        try await romKit.loadDAT(from: testDATPath.path)

        // Verify DAT header is accessible
        XCTAssertNotNil(romKit.datHeader)
        guard let header = romKit.datHeader else {
            XCTFail("DAT header should not be nil")
            return
        }

        // Check header properties
        XCTAssertFalse(header.name.isEmpty)
        XCTAssertFalse(header.description.isEmpty)
        XCTAssertFalse(header.version.isEmpty)
    }

    func testGamesAccess() async throws {
        let romKit = RomKit()

        // Load a test DAT file
        guard let testDATPath = Bundle.module.url(forResource: "mame_sample", withExtension: "xml", subdirectory: "TestData") else {
            XCTFail("Could not find test DAT file")
            return
        }

        try await romKit.loadDAT(from: testDATPath.path)

        // Verify games are accessible
        XCTAssertFalse(romKit.games.isEmpty)
        XCTAssertGreaterThan(romKit.gameCount, 0)

        // Check first game has expected properties
        guard let firstGame = romKit.games.first else {
            XCTFail("Should have at least one game")
            return
        }
        XCTAssertFalse(firstGame.name.isEmpty)
        XCTAssertNotNil(firstGame.description)

        // Check ROMs
        if !firstGame.roms.isEmpty {
            guard let firstROM = firstGame.roms.first else { return }
            XCTAssertFalse(firstROM.name.isEmpty)
            XCTAssertGreaterThan(firstROM.size, 0)
            XCTAssertFalse(firstROM.crc.isEmpty)
        }
    }

    func testQuickAccessProperties() async throws {
        let romKit = RomKit()

        // Before loading, should return default values
        XCTAssertFalse(romKit.isDATLoaded)
        XCTAssertEqual(romKit.gameCount, 0)
        XCTAssertEqual(romKit.totalROMCount, 0)
        XCTAssertEqual(romKit.datFormat, .unknown)

        // Load a test DAT file
        guard let testDATPath = Bundle.module.url(forResource: "mame_sample", withExtension: "xml", subdirectory: "TestData") else {
            XCTFail("Could not find test DAT file")
            return
        }

        try await romKit.loadDAT(from: testDATPath.path)

        // After loading, should have actual values
        XCTAssertTrue(romKit.isDATLoaded)
        XCTAssertGreaterThan(romKit.gameCount, 0)
        XCTAssertGreaterThanOrEqual(romKit.totalROMCount, 0)
        // The format might be logiqx or mame, just check it's not unknown
        XCTAssertTrue(romKit.datFormat == .logiqx || romKit.datFormat == .mameXML, "Expected format to be logiqx or mame, but got \(romKit.datFormat)")
    }

    func testFindGameByName() async throws {
        let romKit = RomKit()

        // Load a test DAT file
        guard let testDATPath = Bundle.module.url(forResource: "mame_sample", withExtension: "xml", subdirectory: "TestData") else {
            XCTFail("Could not find test DAT file")
            return
        }

        try await romKit.loadDAT(from: testDATPath.path)

        // Find a known game
        if let firstGame = romKit.games.first {
            let foundGame = romKit.findGame(name: firstGame.name)
            XCTAssertNotNil(foundGame)
            XCTAssertEqual(foundGame?.name, firstGame.name)
        }

        // Try to find non-existent game
        let notFound = romKit.findGame(name: "non_existent_game_xyz")
        XCTAssertNil(notFound)
    }

    func testFindGamesByCRC() async throws {
        let romKit = RomKit()

        // Load a test DAT file
        guard let testDATPath = Bundle.module.url(forResource: "mame_sample", withExtension: "xml", subdirectory: "TestData") else {
            XCTFail("Could not find test DAT file")
            return
        }

        try await romKit.loadDAT(from: testDATPath.path)

        // Find games by CRC if any ROMs exist
        if let gameWithROMs = romKit.games.first(where: { !$0.roms.isEmpty }),
           let firstROM = gameWithROMs.roms.first {

            let foundGames = romKit.findGamesByCRC(firstROM.crc)
            XCTAssertFalse(foundGames.isEmpty)
            XCTAssertTrue(foundGames.contains { $0.name == gameWithROMs.name })
        }
    }

    func testGetAllGameNames() async throws {
        let romKit = RomKit()

        // Load a test DAT file
        guard let testDATPath = Bundle.module.url(forResource: "mame_sample", withExtension: "xml", subdirectory: "TestData") else {
            XCTFail("Could not find test DAT file")
            return
        }

        try await romKit.loadDAT(from: testDATPath.path)

        let gameNames = romKit.getAllGameNames()
        XCTAssertEqual(gameNames.count, romKit.gameCount)
        XCTAssertFalse(gameNames.isEmpty)

        // Verify all names are non-empty
        for name in gameNames {
            XCTAssertFalse(name.isEmpty)
        }
    }

    func testParentCloneFiltering() async throws {
        let romKit = RomKit()

        // Load a MAME DAT that has parent/clone relationships
        let testDATPath = Bundle.module.url(forResource: "mame_sample", withExtension: "xml", subdirectory: "TestData")

        // If MAME test DAT exists, test parent/clone functionality
        if let datPath = testDATPath {
            try await romKit.loadDAT(from: datPath.path)

            let parents = romKit.getParentGames()
            let clones = romKit.getCloneGames()

            // Parents should have no cloneOf field
            for parent in parents {
                XCTAssertNil(parent.cloneOf)
            }

            // Clones should have cloneOf field
            for clone in clones {
                XCTAssertNotNil(clone.cloneOf)
            }

            // Test getting clones of a specific parent
            if let parent = parents.first {
                let parentClones = romKit.getClones(of: parent.name)
                for clone in parentClones {
                    XCTAssertEqual(clone.cloneOf, parent.name)
                }
            }
        }
    }

    func testExampleUsage() async throws {
        // This test demonstrates the example usage from the requirements
        let romKit = RomKit()

        // Load a test DAT file
        guard let testDATPath = Bundle.module.url(forResource: "mame_sample", withExtension: "xml", subdirectory: "TestData") else {
            XCTFail("Could not find test DAT file")
            return
        }

        try await romKit.loadDAT(from: testDATPath.path)

        // Access parsed data as shown in the example
        let header = romKit.datHeader
        let gameCount = romKit.gameCount
        let games = romKit.games

        XCTAssertNotNil(header)
        XCTAssertGreaterThan(gameCount, 0)
        XCTAssertFalse(games.isEmpty)

        print("Loaded \(header?.name ?? "Unknown") with \(gameCount) games")

        // This should work exactly as specified in the requirements
        XCTAssertTrue(true)
    }
}
