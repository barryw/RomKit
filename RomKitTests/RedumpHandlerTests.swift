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

    // MARK: - CUE/BIN Archive Handler Tests

    @Test func testCUEBINArchiveHandler() {
        let handler = CUEBINArchiveHandler()

        #expect(handler.supportedExtensions.contains("cue"))
        #expect(handler.supportedExtensions.contains("bin"))
        #expect(handler.supportedExtensions.contains("iso"))
        #expect(handler.supportedExtensions.contains("img"))
        #expect(handler.supportedExtensions.count == 4)
    }

    @Test func testCUEBINArchiveHandlerCanHandle() {
        let handler = CUEBINArchiveHandler()

        let cueURL = URL(fileURLWithPath: "/test/game.cue")
        let binURL = URL(fileURLWithPath: "/test/game.bin")
        let isoURL = URL(fileURLWithPath: "/test/game.iso")
        let imgURL = URL(fileURLWithPath: "/test/game.img")
        let zipURL = URL(fileURLWithPath: "/test/game.zip")
        let txtURL = URL(fileURLWithPath: "/test/readme.txt")

        #expect(handler.canHandle(url: cueURL) == true)
        #expect(handler.canHandle(url: binURL) == true)
        #expect(handler.canHandle(url: isoURL) == true)
        #expect(handler.canHandle(url: imgURL) == true)
        #expect(handler.canHandle(url: zipURL) == false)
        #expect(handler.canHandle(url: txtURL) == false)
    }

    @Test func testCUEBINArchiveHandlerCanHandleCaseInsensitive() {
        let handler = CUEBINArchiveHandler()

        let upperURL = URL(fileURLWithPath: "/test/game.CUE")
        let mixedURL = URL(fileURLWithPath: "/test/game.BiN")

        #expect(handler.canHandle(url: upperURL) == true)
        #expect(handler.canHandle(url: mixedURL) == true)
    }

    @Test func testCUEBINArchiveHandlerListContentsThrows() throws {
        let handler = CUEBINArchiveHandler()
        let testURL = URL(fileURLWithPath: "/test/game.cue")

        #expect(throws: ArchiveError.self) {
            try handler.listContents(of: testURL)
        }
    }

    @Test func testCUEBINArchiveHandlerExtractThrows() throws {
        let handler = CUEBINArchiveHandler()
        let testURL = URL(fileURLWithPath: "/test/game.cue")
        let entry = ArchiveEntry(
            path: "test",
            compressedSize: 0,
            uncompressedSize: 0,
            modificationDate: nil,
            crc32: nil
        )

        #expect(throws: ArchiveError.self) {
            try handler.extract(entry: entry, from: testURL)
        }
    }

    @Test func testCUEBINArchiveHandlerExtractAllThrows() throws {
        let handler = CUEBINArchiveHandler()
        let sourceURL = URL(fileURLWithPath: "/test/game.cue")
        let destURL = URL(fileURLWithPath: "/dest/")

        #expect(throws: ArchiveError.self) {
            try handler.extractAll(from: sourceURL, to: destURL)
        }
    }

    @Test func testCUEBINArchiveHandlerCreateThrows() throws {
        let handler = CUEBINArchiveHandler()
        let testURL = URL(fileURLWithPath: "/test/game.cue")
        let entries: [(name: String, data: Data)] = [("test", Data())]

        #expect(throws: ArchiveError.self) {
            try handler.create(at: testURL, with: entries)
        }
    }

    // MARK: - Parser Tests

    @Test func testRedumpDATParser() {
        let parser = RedumpDATParser()

        // Test canParse with valid Redump XML
        let validXML = """
        <?xml version="1.0"?>
        <!DOCTYPE datafile PUBLIC "-//Logiqx//DTD ROM Management Datafile//EN" "http://www.logiqx.com/Dats/datafile.dtd">
        <datafile>
            <header>
                <name>Sony - PlayStation</name>
                <description>Sony - PlayStation (redump.org)</description>
                <version>2025-01-01</version>
                <url>http://redump.org</url>
            </header>
        </datafile>
        """.data(using: .utf8)!

        #expect(parser.canParse(data: validXML) == true)
    }

    @Test func testRedumpDATParserInvalidData() {
        let parser = RedumpDATParser()

        // Test with non-XML data
        let invalidData = "This is not XML".data(using: .utf8)!
        #expect(parser.canParse(data: invalidData) == false)

        // Test with empty data
        let emptyData = Data()
        #expect(parser.canParse(data: emptyData) == false)

        // Test with XML but no redump.org reference
        let wrongXML = """
        <?xml version="1.0"?>
        <!DOCTYPE datafile>
        <datafile>
            <header>
                <name>Other Collection</name>
            </header>
        </datafile>
        """.data(using: .utf8)!
        #expect(parser.canParse(data: wrongXML) == false)
    }

    @Test func testRedumpDATParserParse() throws {
        let parser = RedumpDATParser()

        let xmlData = """
        <?xml version="1.0"?>
        <!DOCTYPE datafile>
        <datafile>
            <header>
                <name>Test</name>
                <url>http://redump.org</url>
            </header>
        </datafile>
        """.data(using: .utf8)!

        let datFile = try parser.parse(data: xmlData)
        #expect(datFile.formatVersion == "1.0")
        #expect(datFile.metadata.name == "Redump Collection")
        #expect(datFile.metadata.description == "Redump DAT File")
        #expect((datFile.metadata as? RedumpMetadata)?.url == "http://redump.org")
        #expect(datFile.games.isEmpty)
    }

    @Test func testRedumpDATParserParseFromURL() throws {
        let parser = RedumpDATParser()

        // Create a temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("redump_test.dat")
        let xmlData = """
        <?xml version="1.0"?>
        <!DOCTYPE datafile>
        <datafile>
            <header>
                <name>Redump Test</name>
                <url>http://redump.org</url>
            </header>
        </datafile>
        """.data(using: .utf8)!

        try xmlData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let datFile = try parser.parse(url: tempURL)
        #expect(datFile.formatVersion == "1.0")
        #expect(datFile.games.isEmpty)
        #expect((datFile.metadata as? RedumpMetadata)?.url == "http://redump.org")
    }

    // MARK: - Validator Tests

    @Test func testRedumpROMValidator() {
        let validator = RedumpROMValidator()

        // Test computeChecksums
        let testData = "PlayStation Game Data".data(using: .utf8)!
        let checksums = validator.computeChecksums(for: testData)

        #expect(checksums.crc32 != nil)
        #expect(checksums.md5 != nil)
        #expect(checksums.sha1 != nil)
    }

    @Test func testRedumpROMValidatorValidateData() {
        let validator = RedumpROMValidator()

        let testData = "Test Disc Image Data".data(using: .utf8)!
        let checksums = validator.computeChecksums(for: testData)

        let rom = RedumpROM(
            name: "game.bin",
            size: UInt64(testData.count),
            checksums: checksums
        )

        let result = validator.validate(item: rom, against: testData)
        #expect(result.isValid == true)
        #expect(result.errors.isEmpty)
    }

    @Test func testRedumpROMValidatorValidateMismatch() {
        let validator = RedumpROMValidator()

        let testData = "Correct Data".data(using: .utf8)!
        let wrongData = "Wrong Data".data(using: .utf8)!

        let checksums = validator.computeChecksums(for: testData)

        let rom = RedumpROM(
            name: "game.iso",
            size: UInt64(testData.count),
            checksums: checksums
        )

        let result = validator.validate(item: rom, against: wrongData)
        #expect(result.isValid == false)
        #expect(!result.errors.isEmpty)
    }

    @Test func testRedumpROMValidatorValidateAtURL() throws {
        let validator = RedumpROMValidator()

        // Create a temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_disc.bin")
        let testData = "PlayStation Disc Image".data(using: .utf8)!
        try testData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let checksums = validator.computeChecksums(for: testData)
        let rom = RedumpROM(
            name: "test_disc.bin",
            size: UInt64(testData.count),
            checksums: checksums
        )

        let result = try validator.validate(item: rom, at: tempURL)
        #expect(result.isValid == true)
    }

    // MARK: - Scanner Tests

    @Test func testRedumpROMScanner() async throws {
        let metadata = RedumpMetadata(
            name: "PS1 Collection",
            description: "Test",
            system: "PlayStation"
        )
        let datFile = RedumpDATFile(
            formatVersion: "1.0",
            games: [],
            metadata: metadata
        )
        let validator = RedumpROMValidator()
        let archiveHandlers: [any ArchiveHandler] = [CUEBINArchiveHandler()]

        let scanner = RedumpROMScanner(
            datFile: datFile,
            validator: validator,
            archiveHandlers: archiveHandlers
        )

        #expect(scanner.datFile.metadata.name == "PS1 Collection")
        #expect(scanner.archiveHandlers.count == 1)
        #expect(scanner.archiveHandlers.first is CUEBINArchiveHandler)
    }

    @Test func testRedumpROMScannerScanDirectory() async throws {
        let metadata = RedumpMetadata(name: "Test", description: "Test")
        let datFile = RedumpDATFile(formatVersion: "1.0", games: [], metadata: metadata)
        let validator = RedumpROMValidator()
        let scanner = RedumpROMScanner(
            datFile: datFile,
            validator: validator,
            archiveHandlers: []
        )

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("redump_scan")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let results = try await scanner.scan(directory: tempDir)

        #expect(results.scannedPath == tempDir.path)
        #expect(results.foundGames.isEmpty)
        #expect(results.unknownFiles.isEmpty)
        #expect(results.errors.isEmpty)
        #expect(results.scanDate.timeIntervalSinceNow < 1)
    }

    @Test func testRedumpROMScannerScanFiles() async throws {
        let metadata = RedumpMetadata(name: "Test", description: "Test")
        let datFile = RedumpDATFile(formatVersion: "1.0", games: [], metadata: metadata)
        let validator = RedumpROMValidator()
        let scanner = RedumpROMScanner(
            datFile: datFile,
            validator: validator,
            archiveHandlers: []
        )

        // Create test files
        let tempFile1 = FileManager.default.temporaryDirectory.appendingPathComponent("game1.cue")
        let tempFile2 = FileManager.default.temporaryDirectory.appendingPathComponent("game2.bin")

        try "CUE data".data(using: .utf8)!.write(to: tempFile1)
        try "BIN data".data(using: .utf8)!.write(to: tempFile2)
        defer {
            try? FileManager.default.removeItem(at: tempFile1)
            try? FileManager.default.removeItem(at: tempFile2)
        }

        let results = try await scanner.scan(files: [tempFile1, tempFile2])

        #expect(results.scannedPath == "")
        #expect(results.foundGames.isEmpty)
        #expect(results.unknownFiles.count == 2)
        #expect(results.unknownFiles.contains(tempFile1))
        #expect(results.unknownFiles.contains(tempFile2))
    }

    @Test func testRedumpScanResults() {
        let scanDate = Date()
        let error = ScanError(file: URL(fileURLWithPath: "/test/file.cue"), message: "Invalid CUE format")
        let results = RedumpScanResults(
            scannedPath: "/test/path",
            foundGames: [],
            unknownFiles: [URL(fileURLWithPath: "/test/unknown.bin")],
            scanDate: scanDate,
            errors: [error]
        )

        #expect(results.scannedPath == "/test/path")
        #expect(results.foundGames.isEmpty)
        #expect(results.unknownFiles.count == 1)
        #expect(results.scanDate == scanDate)
        #expect(results.errors.count == 1)
        #expect(results.errors.first?.message == "Invalid CUE format")
    }

    // MARK: - Rebuilder Tests

    @Test func testRedumpROMRebuilder() async throws {
        let metadata = RedumpMetadata(name: "Test", description: "Test", system: "PlayStation")
        let datFile = RedumpDATFile(formatVersion: "1.0", games: [], metadata: metadata)
        let archiveHandlers: [any ArchiveHandler] = [CUEBINArchiveHandler(), ZIPArchiveHandler()]

        let rebuilder = RedumpROMRebuilder(
            datFile: datFile,
            archiveHandlers: archiveHandlers
        )

        #expect(rebuilder.datFile.metadata.name == "Test")
        #expect(rebuilder.archiveHandlers.count == 2)
        #expect(rebuilder.archiveHandlers.contains { $0 is CUEBINArchiveHandler })
        #expect(rebuilder.archiveHandlers.contains { $0 is ZIPArchiveHandler })
    }

    @Test func testRedumpROMRebuilderRebuild() async throws {
        let metadata = RedumpMetadata(name: "Test", description: "Test")
        let datFile = RedumpDATFile(formatVersion: "1.0", games: [], metadata: metadata)
        let rebuilder = RedumpROMRebuilder(
            datFile: datFile,
            archiveHandlers: []
        )

        let sourceDir = FileManager.default.temporaryDirectory.appendingPathComponent("redump_source")
        let destDir = FileManager.default.temporaryDirectory.appendingPathComponent("redump_dest")

        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: destDir)
        }

        let options = RebuildOptions()
        let results = try await rebuilder.rebuild(from: sourceDir, to: destDir, options: options)

        #expect(results.rebuilt == 0)
        #expect(results.skipped == 0)
        #expect(results.failed == 0)
    }

    // MARK: - Edge Cases and Error Conditions

    @Test func testRedumpMultiDiscGame() {
        let checksums1 = ROMChecksums(crc32: "11111111", sha1: nil, sha256: nil, md5: nil)
        let checksums2 = ROMChecksums(crc32: "22222222", sha1: nil, sha256: nil, md5: nil)

        let rom1 = RedumpROM(name: "game_disc1.cue", size: 1024, checksums: checksums1)
        let rom2 = RedumpROM(name: "game_disc2.cue", size: 1024, checksums: checksums2)

        let metadata1 = RedumpGameMetadata(discNumber: 1, discTotal: 2)
        let metadata2 = RedumpGameMetadata(discNumber: 2, discTotal: 2)

        let game1 = RedumpGame(
            name: "Multi-Disc Game (Disc 1)",
            description: "First disc",
            roms: [rom1],
            metadata: metadata1
        )

        let game2 = RedumpGame(
            name: "Multi-Disc Game (Disc 2)",
            description: "Second disc",
            roms: [rom2],
            metadata: metadata2
        )

        #expect((game1.metadata as? RedumpGameMetadata)?.discNumber == 1)
        #expect((game1.metadata as? RedumpGameMetadata)?.discTotal == 2)
        #expect((game2.metadata as? RedumpGameMetadata)?.discNumber == 2)
        #expect((game2.metadata as? RedumpGameMetadata)?.discTotal == 2)
    }

    @Test func testRedumpMultiTrackGame() {
        // Test a typical mixed-mode CD with data and audio tracks
        var tracks: [RedumpTrack] = []

        // Data track
        tracks.append(RedumpTrack(
            number: 1,
            type: "data",
            name: "Track01.bin",
            size: 600_000_000, // ~600MB data track
            crc32: "DEADBEEF",
            md5: "1234567890abcdef1234567890abcdef",
            sha1: "1234567890abcdef1234567890abcdef12345678"
        ))

        // Audio tracks
        for i in 2...10 {
            tracks.append(RedumpTrack(
                number: i,
                type: "audio",
                name: String(format: "Track%02d.bin", i),
                size: 44_100_000, // ~44MB per audio track
                crc32: String(format: "%08X", i),
                md5: nil,
                sha1: nil
            ))
        }

        let checksums = ROMChecksums(crc32: "MASTER", sha1: nil, sha256: nil, md5: nil)
        let rom = RedumpROM(name: "game.cue", size: 2048, checksums: checksums)
        let metadata = RedumpGameMetadata(year: "1996", region: "Japan")

        let game = RedumpGame(
            name: "Mixed Mode CD Game",
            description: "Game with data and audio tracks",
            roms: [rom],
            tracks: tracks,
            metadata: metadata
        )

        #expect(game.tracks.count == 10)
        #expect(game.tracks.first?.type == "data")
        #expect(game.tracks[1].type == "audio")
        #expect(game.tracks.last?.number == 10)
    }
}
