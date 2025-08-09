//
//  RedumpArchiveTests.swift
//  RomKitTests
//
//  Split from RedumpHandlerTests to avoid type body length violation
//

import Testing
import Foundation
@testable import RomKit

struct RedumpArchiveTests {

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
        let validXML = Data("""
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
        """.utf8)

        #expect(parser.canParse(data: validXML) == true)
    }

    @Test func testRedumpDATParserInvalidData() {
        let parser = RedumpDATParser()

        // Test with non-XML data
        let invalidData = Data("This is not XML".utf8)
        #expect(parser.canParse(data: invalidData) == false)

        // Test with empty data
        let emptyData = Data()
        #expect(parser.canParse(data: emptyData) == false)

        // Test with XML but no redump.org reference
        let wrongXML = Data("""
        <?xml version="1.0"?>
        <!DOCTYPE datafile>
        <datafile>
            <header>
                <name>Other Collection</name>
            </header>
        </datafile>
        """.utf8)
        #expect(parser.canParse(data: wrongXML) == false)
    }

    @Test func testRedumpDATParserParse() throws {
        let parser = RedumpDATParser()

        let xmlData = Data("""
        <?xml version="1.0"?>
        <!DOCTYPE datafile>
        <datafile>
            <header>
                <name>Test</name>
                <url>http://redump.org</url>
            </header>
        </datafile>
        """.utf8)

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
        let xmlData = Data("""
        <?xml version="1.0"?>
        <!DOCTYPE datafile>
        <datafile>
            <header>
                <name>Redump Test</name>
                <url>http://redump.org</url>
            </header>
        </datafile>
        """.utf8)

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
        let testData = Data("PlayStation Game Data".utf8)
        let checksums = validator.computeChecksums(for: testData)

        #expect(checksums.crc32 != nil)
        #expect(checksums.md5 != nil)
        #expect(checksums.sha1 != nil)
    }

    @Test func testRedumpROMValidatorValidateData() {
        let validator = RedumpROMValidator()

        let testData = Data("Test Disc Image Data".utf8)
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

        let testData = Data("Correct Data".utf8)
        let wrongData = Data("Wrong Data".utf8)

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
        let testData = Data("PlayStation Disc Image".utf8)
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
}
