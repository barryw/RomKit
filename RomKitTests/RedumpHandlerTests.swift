//
//  RedumpHandlerTests.swift
//  RomKitTests
//
//  Comprehensive tests for RedumpFormatHandler to improve code coverage
//

import Testing
import Foundation
@testable import RomKit

struct RedumpHandlerTests {

    // MARK: - Format Handler Tests

    @Test func testRedumpFormatHandler() {
        let handler = RedumpFormatHandler()

        #expect(handler.formatIdentifier == "redump")
        #expect(handler.formatName == "Redump")
        #expect(handler.supportedExtensions.contains("dat"))
        #expect(handler.supportedExtensions.contains("xml"))
        #expect(handler.supportedExtensions.count == 2)
    }

    @Test func testCreateParser() {
        let handler = RedumpFormatHandler()
        let parser = handler.createParser()

        #expect(parser is RedumpDATParser)
    }

    @Test func testCreateValidator() {
        let handler = RedumpFormatHandler()
        let validator = handler.createValidator()

        #expect(validator is RedumpROMValidator)
    }

    @Test func testCreateScanner() {
        let handler = RedumpFormatHandler()
        let metadata = RedumpMetadata(
            name: "Test Collection",
            description: "Test Description",
            url: "http://redump.org"
        )
        let datFile = RedumpDATFile(
            formatVersion: "1.0",
            games: [],
            metadata: metadata
        )

        let scanner = handler.createScanner(for: datFile)
        #expect(scanner is RedumpROMScanner)
        #expect((scanner as? RedumpROMScanner)?.datFile.metadata.name == "Test Collection")
    }

    @Test func testCreateRebuilder() {
        let handler = RedumpFormatHandler()
        let metadata = RedumpMetadata(
            name: "Test Collection",
            description: "Test Description"
        )
        let datFile = RedumpDATFile(
            formatVersion: "1.0",
            games: [],
            metadata: metadata
        )

        let rebuilder = handler.createRebuilder(for: datFile)
        #expect(rebuilder is RedumpROMRebuilder)
        #expect((rebuilder as? RedumpROMRebuilder)?.datFile.metadata.name == "Test Collection")
    }

    @Test func testCreateArchiveHandlers() {
        let handler = RedumpFormatHandler()
        let archiveHandlers = handler.createArchiveHandlers()

        #expect(archiveHandlers.count == 3)
        #expect(archiveHandlers.contains { $0 is ZIPArchiveHandler })
        #expect(archiveHandlers.contains { $0 is CHDArchiveHandler })
        #expect(archiveHandlers.contains { $0 is CUEBINArchiveHandler })
    }

    // MARK: - Model Tests

    @Test func testRedumpMetadata() {
        let metadata = RedumpMetadata(
            name: "Test Name",
            description: "Test Description",
            version: "1.0",
            author: "Test Author",
            date: "2025-01-01",
            comment: "Test Comment",
            url: "http://redump.org",
            system: "PlayStation"
        )

        #expect(metadata.name == "Test Name")
        #expect(metadata.description == "Test Description")
        #expect(metadata.version == "1.0")
        #expect(metadata.author == "Test Author")
        #expect(metadata.date == "2025-01-01")
        #expect(metadata.comment == "Test Comment")
        #expect(metadata.url == "http://redump.org")
        #expect(metadata.system == "PlayStation")
    }

    @Test func testRedumpMetadataMinimal() {
        let metadata = RedumpMetadata(
            name: "Minimal",
            description: "Minimal Description"
        )

        #expect(metadata.name == "Minimal")
        #expect(metadata.description == "Minimal Description")
        #expect(metadata.version == nil)
        #expect(metadata.author == nil)
        #expect(metadata.date == nil)
        #expect(metadata.comment == nil)
        #expect(metadata.url == nil)
        #expect(metadata.system == nil)
    }

    @Test func testRedumpGameMetadata() {
        let metadata = RedumpGameMetadata(
            year: "1994",
            manufacturer: "Sony",
            category: "Action",
            serial: "SLUS-00001",
            version: "1.0",
            region: "USA",
            languages: ["English", "French", "Spanish"],
            discNumber: 1,
            discTotal: 2
        )

        #expect(metadata.year == "1994")
        #expect(metadata.manufacturer == "Sony")
        #expect(metadata.category == "Action")
        #expect(metadata.serial == "SLUS-00001")
        #expect(metadata.version == "1.0")
        #expect(metadata.region == "USA")
        #expect(metadata.languages.count == 3)
        #expect(metadata.languages.contains("English"))
        #expect(metadata.languages.contains("French"))
        #expect(metadata.languages.contains("Spanish"))
        #expect(metadata.discNumber == 1)
        #expect(metadata.discTotal == 2)
        #expect(metadata.cloneOf == nil)
        #expect(metadata.romOf == nil)
        #expect(metadata.sampleOf == nil)
        #expect(metadata.sourceFile == nil)
    }

    @Test func testRedumpGameMetadataMinimal() {
        let metadata = RedumpGameMetadata()

        #expect(metadata.year == nil)
        #expect(metadata.manufacturer == nil)
        #expect(metadata.category == nil)
        #expect(metadata.serial == nil)
        #expect(metadata.version == nil)
        #expect(metadata.region == nil)
        #expect(metadata.languages.isEmpty)
        #expect(metadata.discNumber == nil)
        #expect(metadata.discTotal == nil)
    }

    @Test func testRedumpROM() {
        let checksums = ROMChecksums(
            crc32: "12345678",
            sha1: "0123456789abcdef",
            sha256: "fedcba9876543210",
            md5: "abcdef0123456789"
        )

        let rom = RedumpROM(
            name: "game.bin",
            size: 734003200, // ~700MB CD size
            checksums: checksums,
            status: .good,
            attributes: ROMAttributes(date: "2025-01-01")
        )

        #expect(rom.name == "game.bin")
        #expect(rom.size == 734003200)
        #expect(rom.checksums.crc32 == "12345678")
        #expect(rom.checksums.md5 == "abcdef0123456789")
        #expect(rom.checksums.sha1 == "0123456789abcdef")
        #expect(rom.checksums.sha256 == "fedcba9876543210")
        #expect(rom.status == ROMStatus.good)
        #expect(rom.attributes.date == "2025-01-01")
        #expect(rom.attributes.optional == false)
    }

    @Test func testRedumpROMDefaults() {
        let checksums = ROMChecksums(
            crc32: "abcdef12",
            sha1: nil,
            sha256: nil,
            md5: nil
        )

        let rom = RedumpROM(
            name: "disc.cue",
            size: 1024,
            checksums: checksums
        )

        #expect(rom.name == "disc.cue")
        #expect(rom.size == 1024)
        #expect(rom.status == ROMStatus.good)
        #expect(rom.attributes.date == nil)
        #expect(rom.attributes.merge == nil)
    }

    @Test func testRedumpTrack() {
        let track = RedumpTrack(
            number: 1,
            type: "data",
            name: "Track01.bin",
            size: 681984000,
            crc32: "12345678",
            md5: "abcdef0123456789abcdef0123456789",
            sha1: "1234567890abcdef1234567890abcdef12345678"
        )

        #expect(track.number == 1)
        #expect(track.type == "data")
        #expect(track.name == "Track01.bin")
        #expect(track.size == 681984000)
        #expect(track.crc32 == "12345678")
        #expect(track.md5 == "abcdef0123456789abcdef0123456789")
        #expect(track.sha1 == "1234567890abcdef1234567890abcdef12345678")
    }

    @Test func testRedumpTrackMinimal() {
        let track = RedumpTrack(
            number: 2,
            type: "audio",
            name: "Track02.bin",
            size: 44100000
        )

        #expect(track.number == 2)
        #expect(track.type == "audio")
        #expect(track.name == "Track02.bin")
        #expect(track.size == 44100000)
        #expect(track.crc32 == nil)
        #expect(track.md5 == nil)
        #expect(track.sha1 == nil)
    }

    @Test func testRedumpGame() {
        let checksums = ROMChecksums(crc32: "12345678", sha1: nil, sha256: nil, md5: nil)
        let rom = RedumpROM(name: "game.cue", size: 2048, checksums: checksums)

        let track1 = RedumpTrack(number: 1, type: "data", name: "Track01.bin", size: 681984000)
        let track2 = RedumpTrack(number: 2, type: "audio", name: "Track02.bin", size: 44100000)

        let metadata = RedumpGameMetadata(
            year: "1995",
            region: "Europe",
            discNumber: 1,
            discTotal: 1
        )

        let game = RedumpGame(
            name: "Test Game",
            description: "A test game",
            roms: [rom],
            tracks: [track1, track2],
            metadata: metadata
        )

        #expect(game.identifier == "Test Game")
        #expect(game.name == "Test Game")
        #expect(game.description == "A test game")
        #expect(game.items.count == 1)
        #expect(game.tracks.count == 2)
        #expect(game.tracks[0].number == 1)
        #expect(game.tracks[1].number == 2)
        #expect((game.metadata as? RedumpGameMetadata)?.year == "1995")
        #expect((game.metadata as? RedumpGameMetadata)?.region == "Europe")
        #expect((game.metadata as? RedumpGameMetadata)?.discNumber == 1)
    }

    @Test func testRedumpGameWithoutTracks() {
        let checksums = ROMChecksums(crc32: "abcd1234", sha1: nil, sha256: nil, md5: nil)
        let rom = RedumpROM(name: "game.iso", size: 734003200, checksums: checksums)
        let metadata = RedumpGameMetadata(year: "2000")

        let game = RedumpGame(
            name: "ISO Game",
            description: "Single ISO file",
            roms: [rom],
            metadata: metadata
        )

        #expect(game.tracks.isEmpty)
        #expect(game.items.count == 1)
    }

    @Test func testRedumpDATFile() {
        let metadata = RedumpMetadata(
            name: "PlayStation Collection",
            description: "Redump PS1 Collection",
            url: "http://redump.org",
            system: "PlayStation"
        )

        let gameMetadata = RedumpGameMetadata(year: "1997", region: "Japan")
        let checksums = ROMChecksums(crc32: "abcd1234", sha1: nil, sha256: nil, md5: nil)
        let rom = RedumpROM(name: "game1.cue", size: 1024, checksums: checksums)
        let track = RedumpTrack(number: 1, type: "data", name: "track01.bin", size: 681984000)
        let game = RedumpGame(
            name: "Game 1",
            description: "First game",
            roms: [rom],
            tracks: [track],
            metadata: gameMetadata
        )

        let datFile = RedumpDATFile(
            formatVersion: "1.0",
            games: [game],
            metadata: metadata
        )

        #expect(datFile.formatName == "Redump")
        #expect(datFile.formatVersion == "1.0")
        #expect(datFile.games.count == 1)
        #expect(datFile.games.first?.name == "Game 1")
        #expect(datFile.metadata.name == "PlayStation Collection")
        #expect((datFile.metadata as? RedumpMetadata)?.system == "PlayStation")
    }
}
