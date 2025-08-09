//
//  NoIntroHandlerTests.swift
//  RomKitTests
//
//  Comprehensive tests for NoIntroFormatHandler to improve code coverage
//

import Testing
import Foundation
@testable import RomKit

struct NoIntroHandlerTests {

    // MARK: - Format Handler Tests

    @Test func testNoIntroFormatHandler() {
        let handler = NoIntroFormatHandler()

        #expect(handler.formatIdentifier == "no-intro")
        #expect(handler.formatName == "No-Intro")
        #expect(handler.supportedExtensions.contains("dat"))
        #expect(handler.supportedExtensions.contains("xml"))
        #expect(handler.supportedExtensions.count == 2)
    }

    @Test func testCreateParser() {
        let handler = NoIntroFormatHandler()
        let parser = handler.createParser()

        #expect(parser is NoIntroDATParser)
    }

    @Test func testCreateValidator() {
        let handler = NoIntroFormatHandler()
        let validator = handler.createValidator()

        #expect(validator is NoIntroROMValidator)
    }

    @Test func testCreateScanner() {
        let handler = NoIntroFormatHandler()
        let metadata = NoIntroMetadata(
            name: "Test Collection",
            description: "Test Description"
        )
        let datFile = NoIntroDATFile(
            formatVersion: "1.0",
            games: [],
            metadata: metadata
        )

        let scanner = handler.createScanner(for: datFile)
        #expect(scanner is NoIntroROMScanner)
        #expect((scanner as? NoIntroROMScanner)?.datFile.metadata.name == "Test Collection")
    }

    @Test func testCreateRebuilder() {
        let handler = NoIntroFormatHandler()
        let metadata = NoIntroMetadata(
            name: "Test Collection",
            description: "Test Description"
        )
        let datFile = NoIntroDATFile(
            formatVersion: "1.0",
            games: [],
            metadata: metadata
        )

        let rebuilder = handler.createRebuilder(for: datFile)
        #expect(rebuilder is NoIntroROMRebuilder)
        #expect((rebuilder as? NoIntroROMRebuilder)?.datFile.metadata.name == "Test Collection")
    }

    @Test func testCreateArchiveHandlers() {
        let handler = NoIntroFormatHandler()
        let archiveHandlers = handler.createArchiveHandlers()

        #expect(archiveHandlers.count == 2)
        #expect(archiveHandlers.contains { $0 is ZIPArchiveHandler })
        #expect(archiveHandlers.contains { $0 is SevenZipArchiveHandler })
    }

    // MARK: - Model Tests

    @Test func testNoIntroMetadata() {
        let metadata = NoIntroMetadata(
            name: "Test Name",
            description: "Test Description",
            version: "1.0",
            author: "Test Author",
            date: "2025-01-01",
            comment: "Test Comment",
            url: "http://test.com",
            category: "Test Category"
        )

        #expect(metadata.name == "Test Name")
        #expect(metadata.description == "Test Description")
        #expect(metadata.version == "1.0")
        #expect(metadata.author == "Test Author")
        #expect(metadata.date == "2025-01-01")
        #expect(metadata.comment == "Test Comment")
        #expect(metadata.url == "http://test.com")
        #expect(metadata.category == "Test Category")
    }

    @Test func testNoIntroMetadataMinimal() {
        let metadata = NoIntroMetadata(
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
        #expect(metadata.category == nil)
    }

    @Test func testNoIntroGameMetadata() {
        let metadata = NoIntroGameMetadata(
            year: "1985",
            manufacturer: "Nintendo",
            category: "Platform",
            serial: "NES-SM",
            revision: "A",
            region: "USA",
            language: "English"
        )

        #expect(metadata.year == "1985")
        #expect(metadata.manufacturer == "Nintendo")
        #expect(metadata.category == "Platform")
        #expect(metadata.serial == "NES-SM")
        #expect(metadata.revision == "A")
        #expect(metadata.region == "USA")
        #expect(metadata.language == "English")
        #expect(metadata.cloneOf == nil)
        #expect(metadata.romOf == nil)
        #expect(metadata.sampleOf == nil)
        #expect(metadata.sourceFile == nil)
    }

    @Test func testNoIntroGameMetadataMinimal() {
        let metadata = NoIntroGameMetadata()

        #expect(metadata.year == nil)
        #expect(metadata.manufacturer == nil)
        #expect(metadata.category == nil)
        #expect(metadata.serial == nil)
        #expect(metadata.revision == nil)
        #expect(metadata.region == nil)
        #expect(metadata.language == nil)
    }

    @Test func testNoIntroROM() {
        let checksums = ROMChecksums(
            crc32: "12345678",
            sha1: "0123456789abcdef",
            sha256: nil,
            md5: "abcdef0123456789"
        )

        let rom = NoIntroROM(
            name: "test.rom",
            size: 1024,
            checksums: checksums,
            status: .good,
            attributes: ROMAttributes(date: "2025-01-01")
        )

        #expect(rom.name == "test.rom")
        #expect(rom.size == 1024)
        #expect(rom.checksums.crc32 == "12345678")
        #expect(rom.status == ROMStatus.good)
        #expect(rom.attributes.date == "2025-01-01")
        #expect(rom.attributes.optional == false)
    }

    @Test func testNoIntroROMDefaults() {
        let checksums = ROMChecksums(
            crc32: "12345678",
            sha1: nil,
            sha256: nil,
            md5: nil
        )

        let rom = NoIntroROM(
            name: "test.rom",
            size: 512,
            checksums: checksums
        )

        #expect(rom.name == "test.rom")
        #expect(rom.size == 512)
        #expect(rom.status == ROMStatus.good)
        #expect(rom.attributes.date == nil)
    }

    @Test func testNoIntroGame() {
        let checksums = ROMChecksums(crc32: "12345678", sha1: nil, sha256: nil, md5: nil)
        let rom = NoIntroROM(name: "game.rom", size: 2048, checksums: checksums)
        let metadata = NoIntroGameMetadata(year: "1990", region: "Japan")

        let game = NoIntroGame(
            name: "Test Game",
            description: "A test game",
            roms: [rom],
            metadata: metadata
        )

        #expect(game.identifier == "Test Game")
        #expect(game.name == "Test Game")
        #expect(game.description == "A test game")
        #expect(game.items.count == 1)
        #expect((game.metadata as? NoIntroGameMetadata)?.year == "1990")
        #expect((game.metadata as? NoIntroGameMetadata)?.region == "Japan")
    }

    @Test func testNoIntroDATFile() {
        let metadata = NoIntroMetadata(
            name: "Collection",
            description: "Test Collection"
        )

        let gameMetadata = NoIntroGameMetadata(year: "1985")
        let checksums = ROMChecksums(crc32: "abcd1234", sha1: nil, sha256: nil, md5: nil)
        let rom = NoIntroROM(name: "game1.rom", size: 1024, checksums: checksums)
        let game = NoIntroGame(
            name: "Game 1",
            description: "First game",
            roms: [rom],
            metadata: gameMetadata
        )

        let datFile = NoIntroDATFile(
            formatVersion: "1.0",
            games: [game],
            metadata: metadata
        )

        #expect(datFile.formatName == "No-Intro")
        #expect(datFile.formatVersion == "1.0")
        #expect(datFile.games.count == 1)
        #expect(datFile.games.first?.name == "Game 1")
        #expect(datFile.metadata.name == "Collection")
    }

    // MARK: - Parser Tests

    @Test func testNoIntroDATParser() {
        let parser = NoIntroDATParser()

        // Test canParse with valid No-Intro XML
        let validXML = Data("""
        <?xml version="1.0"?>
        <!DOCTYPE datafile PUBLIC "-//Logiqx//DTD ROM Management Datafile//EN" "http://www.logiqx.com/Dats/datafile.dtd">
        <datafile>
            <header>
                <name>No-Intro Collection</name>
                <description>Test DAT</description>
            </header>
        </datafile>
        """.utf8)

        #expect(parser.canParse(data: validXML) == true)
    }

    @Test func testNoIntroDATParserClrmamepro() {
        let parser = NoIntroDATParser()

        // Test canParse with clrmamepro format
        let clrmameXML = Data("""
        <?xml version="1.0"?>
        <!DOCTYPE datafile PUBLIC "-//clrmamepro//DTD">
        <datafile>
            <header>
                <name>Collection</name>
            </header>
        </datafile>
        """.utf8)

        #expect(parser.canParse(data: clrmameXML) == true)
    }

    @Test func testNoIntroDATParserInvalidData() {
        let parser = NoIntroDATParser()

        // Test with non-XML data
        let invalidData = Data("This is not XML".utf8)
        #expect(parser.canParse(data: invalidData) == false)

        // Test with empty data
        let emptyData = Data()
        #expect(parser.canParse(data: emptyData) == false)

        // Test with wrong XML format
        let wrongXML = Data("""
        <?xml version="1.0"?>
        <root>
            <item>Not a DAT file</item>
        </root>
        """.utf8)
        #expect(parser.canParse(data: wrongXML) == false)
    }

    @Test func testNoIntroDATParserParse() throws {
        let parser = NoIntroDATParser()

        let xmlData = Data("""
        <?xml version="1.0"?>
        <!DOCTYPE datafile>
        <datafile>
            <header>
                <name>Test</name>
            </header>
        </datafile>
        """.utf8)

        let datFile = try parser.parse(data: xmlData)
        #expect(datFile.formatVersion == "1.0")
        #expect(datFile.metadata.name == "No-Intro Collection")
        #expect(datFile.metadata.description == "No-Intro DAT File")
        #expect(datFile.games.isEmpty)
    }

    @Test func testNoIntroDATParserParseFromURL() throws {
        let parser = NoIntroDATParser()

        // Create a temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.dat")
        let xmlData = Data("""
        <?xml version="1.0"?>
        <!DOCTYPE datafile>
        <datafile>
            <header>
                <name>Test</name>
            </header>
        </datafile>
        """.utf8)

        try xmlData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let datFile = try parser.parse(url: tempURL)
        #expect(datFile.formatVersion == "1.0")
        #expect(datFile.games.isEmpty)
    }

    // MARK: - Validator Tests

    @Test func testNoIntroROMValidator() {
        let validator = NoIntroROMValidator()

        // Test computeChecksums
        let testData = Data("Hello, World!".utf8)
        let checksums = validator.computeChecksums(for: testData)

        #expect(checksums.crc32 != nil)
        #expect(checksums.md5 != nil)
        #expect(checksums.sha1 != nil)
    }

    @Test func testNoIntroROMValidatorValidateData() {
        let validator = NoIntroROMValidator()

        let testData = Data("Test ROM Data".utf8)
        let checksums = validator.computeChecksums(for: testData)

        let rom = NoIntroROM(
            name: "test.rom",
            size: UInt64(testData.count),
            checksums: checksums
        )

        let result = validator.validate(item: rom, against: testData)
        #expect(result.isValid == true)
        #expect(result.errors.isEmpty)
    }

    @Test func testNoIntroROMValidatorValidateMismatch() {
        let validator = NoIntroROMValidator()

        let testData = Data("Test ROM Data".utf8)
        let wrongData = Data("Wrong Data".utf8)

        let checksums = validator.computeChecksums(for: testData)

        let rom = NoIntroROM(
            name: "test.rom",
            size: UInt64(testData.count),
            checksums: checksums
        )

        let result = validator.validate(item: rom, against: wrongData)
        #expect(result.isValid == false)
        #expect(!result.errors.isEmpty)
    }

    @Test func testNoIntroROMValidatorValidateAtURL() throws {
        let validator = NoIntroROMValidator()

        // Create a temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.rom")
        let testData = Data("Test ROM Content".utf8)
        try testData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let checksums = validator.computeChecksums(for: testData)
        let rom = NoIntroROM(
            name: "test.rom",
            size: UInt64(testData.count),
            checksums: checksums
        )

        let result = try validator.validate(item: rom, at: tempURL)
        #expect(result.isValid == true)
    }

    // MARK: - Scanner Tests

    @Test func testNoIntroROMScanner() async throws {
        let metadata = NoIntroMetadata(
            name: "Test Collection",
            description: "Test"
        )
        let datFile = NoIntroDATFile(
            formatVersion: "1.0",
            games: [],
            metadata: metadata
        )
        let validator = NoIntroROMValidator()
        let archiveHandlers: [any ArchiveHandler] = [ZIPArchiveHandler()]

        let scanner = NoIntroROMScanner(
            datFile: datFile,
            validator: validator,
            archiveHandlers: archiveHandlers
        )

        #expect(scanner.datFile.metadata.name == "Test Collection")
        #expect(scanner.archiveHandlers.count == 1)
    }

    @Test func testNoIntroROMScannerScanDirectory() async throws {
        let metadata = NoIntroMetadata(name: "Test", description: "Test")
        let datFile = NoIntroDATFile(formatVersion: "1.0", games: [], metadata: metadata)
        let validator = NoIntroROMValidator()
        let scanner = NoIntroROMScanner(
            datFile: datFile,
            validator: validator,
            archiveHandlers: []
        )

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("scantest")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let results = try await scanner.scan(directory: tempDir)

        #expect(results.scannedPath == tempDir.path)
        #expect(results.foundGames.isEmpty)
        #expect(results.unknownFiles.isEmpty)
        #expect(results.errors.isEmpty)
        #expect(results.scanDate.timeIntervalSinceNow < 1)
    }

    @Test func testNoIntroROMScannerScanFiles() async throws {
        let metadata = NoIntroMetadata(name: "Test", description: "Test")
        let datFile = NoIntroDATFile(formatVersion: "1.0", games: [], metadata: metadata)
        let validator = NoIntroROMValidator()
        let scanner = NoIntroROMScanner(
            datFile: datFile,
            validator: validator,
            archiveHandlers: []
        )

        // Create test files
        let tempFile1 = FileManager.default.temporaryDirectory.appendingPathComponent("file1.rom")
        let tempFile2 = FileManager.default.temporaryDirectory.appendingPathComponent("file2.rom")

        try Data("data1".utf8).write(to: tempFile1)
        try Data("data2".utf8).write(to: tempFile2)
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

    @Test func testNoIntroScanResults() {
        let scanDate = Date()
        let results = NoIntroScanResults(
            scannedPath: "/test/path",
            foundGames: [],
            unknownFiles: [],
            scanDate: scanDate,
            errors: []
        )

        #expect(results.scannedPath == "/test/path")
        #expect(results.foundGames.isEmpty)
        #expect(results.unknownFiles.isEmpty)
        #expect(results.scanDate == scanDate)
        #expect(results.errors.isEmpty)
    }

    // MARK: - Rebuilder Tests

    @Test func testNoIntroROMRebuilder() async throws {
        let metadata = NoIntroMetadata(name: "Test", description: "Test")
        let datFile = NoIntroDATFile(formatVersion: "1.0", games: [], metadata: metadata)
        let archiveHandlers: [any ArchiveHandler] = [ZIPArchiveHandler()]

        let rebuilder = NoIntroROMRebuilder(
            datFile: datFile,
            archiveHandlers: archiveHandlers
        )

        #expect(rebuilder.datFile.metadata.name == "Test")
        #expect(rebuilder.archiveHandlers.count == 1)
    }

    @Test func testNoIntroROMRebuilderRebuild() async throws {
        let metadata = NoIntroMetadata(name: "Test", description: "Test")
        let datFile = NoIntroDATFile(formatVersion: "1.0", games: [], metadata: metadata)
        let rebuilder = NoIntroROMRebuilder(
            datFile: datFile,
            archiveHandlers: []
        )

        let sourceDir = FileManager.default.temporaryDirectory.appendingPathComponent("source")
        let destDir = FileManager.default.temporaryDirectory.appendingPathComponent("dest")

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
}
