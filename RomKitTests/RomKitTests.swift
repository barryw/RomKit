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

    @Test func testLoadDATMethods() throws {
        let romKit = RomKit()
        let tempDir = FileManager.default.temporaryDirectory

        // Create a minimal valid Logiqx DAT file
        let logiqxContent = """
        <?xml version="1.0"?>
        <!DOCTYPE datafile PUBLIC "-//Logiqx//DTD ROM Management Datafile//EN" "http://www.logiqx.com/Dats/datafile.dtd">
        <datafile>
            <header>
                <name>Test DAT</name>
                <description>Test Description</description>
                <version>1.0</version>
            </header>
            <game name="testgame">
                <description>Test Game</description>
                <rom name="test.rom" size="1024" crc="ABCD1234"/>
            </game>
        </datafile>
        """

        let datFile = tempDir.appendingPathComponent("test.dat")
        try logiqxContent.write(to: datFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: datFile) }

        // Test auto-detect loading
        try romKit.loadDAT(from: datFile.path)

        // Test explicit Logiqx loading
        try romKit.loadLogiqxDAT(from: datFile.path)

        // Create a MAME-style DAT file
        let mameContent = """
        <?xml version="1.0"?>
        <mame>
            <game name="testgame">
                <description>Test Game</description>
                <rom name="test.rom" size="1024" crc="ABCD1234"/>
            </game>
        </mame>
        """

        let mameDatFile = tempDir.appendingPathComponent("mame.dat")
        try mameContent.write(to: mameDatFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: mameDatFile) }

        // Test MAME loading
        try romKit.loadMAMEDAT(from: mameDatFile.path)
    }

    @Test func testScanDirectory() async throws {
        let romKit = RomKit()
        let tempDir = FileManager.default.temporaryDirectory
        let scanDir = tempDir.appendingPathComponent("romscan_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: scanDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scanDir) }

        // Create test ROM files
        let rom1 = scanDir.appendingPathComponent("test1.rom")
        let rom2 = scanDir.appendingPathComponent("test2.rom")
        try Data(repeating: 0x01, count: 1024).write(to: rom1)
        try Data(repeating: 0x02, count: 2048).write(to: rom2)

        // Load a simple DAT first
        let datContent = """
        <?xml version="1.0"?>
        <!DOCTYPE datafile PUBLIC "-//Logiqx//DTD ROM Management Datafile//EN" "http://www.logiqx.com/Dats/datafile.dtd">
        <datafile>
            <header>
                <name>Test DAT</name>
                <description>Test</description>
                <version>1.0</version>
            </header>
            <game name="game1">
                <description>Game 1</description>
                <rom name="test1.rom" size="1024" crc="0BED6369"/>
            </game>
        </datafile>
        """

        let datFile = tempDir.appendingPathComponent("scan.dat")
        try datContent.write(to: datFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: datFile) }

        try romKit.loadDAT(from: datFile.path)

        // Scan directory
        let scanResult = try await romKit.scanDirectory(scanDir.path)

        // Verify scan results
        #expect(scanResult.foundGames.isEmpty)
        #expect(scanResult.unknownFiles.isEmpty)
    }

    @Test func testGenerateAuditReport() throws {
        let romKit = RomKit()
        let tempDir = FileManager.default.temporaryDirectory

        // Create and load a DAT file first
        let datContent = """
        <?xml version="1.0"?>
        <!DOCTYPE datafile PUBLIC "-//Logiqx//DTD ROM Management Datafile//EN" "http://www.logiqx.com/Dats/datafile.dtd">
        <datafile>
            <header>
                <name>Test DAT</name>
                <description>Test</description>
                <version>1.0</version>
            </header>
            <game name="testgame">
                <description>Test Game</description>
                <rom name="test.rom" size="1024" crc="ABCD1234"/>
            </game>
            <game name="missing1">
                <description>Missing Game 1</description>
                <rom name="missing1.rom" size="2048" crc="11111111"/>
            </game>
            <game name="missing2">
                <description>Missing Game 2</description>
                <rom name="missing2.rom" size="4096" crc="22222222"/>
            </game>
        </datafile>
        """

        let datFile = tempDir.appendingPathComponent("audit.dat")
        try datContent.write(to: datFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: datFile) }

        try romKit.loadDAT(from: datFile.path)

        // Create a game and scan result
        let game = Game(
            name: "testgame",
            description: "Test Game",
            roms: [ROM(name: "test.rom", size: 1024, crc: "ABCD1234")]
        )

        let scannedROM = ScannedROM(
            rom: game.roms[0],
            filePath: "/test/test.rom",
            hash: FileHash(crc32: "ABCD1234", sha1: "", md5: "", size: 1024),
            status: .good
        )

        let scannedGame = ScannedGame(
            game: game,
            foundRoms: [scannedROM],
            missingRoms: []
        )

        let scanResult = ScanResult(
            scannedPath: "/test",
            foundGames: [scannedGame],
            unknownFiles: ["unknown.bin"]
        )

        // Generate audit report
        let report = romKit.generateAuditReport(from: scanResult)

        // Verify report exists and has valid structure
        #expect(report.totalGames >= 0)
        #expect(report.completeGames.isEmpty)
        #expect(report.missingGames.isEmpty)
        #expect(report.scannedPath == "/test")
    }
}
