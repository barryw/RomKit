//
//  RedumpFormatHandler.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation

// MARK: - Redump Format Handler

public final class RedumpFormatHandler: ROMFormatHandler, @unchecked Sendable {
    public let formatIdentifier = "redump"
    public let formatName = "Redump"
    public let supportedExtensions = ["dat", "xml"]

    public init() {}

    public func createParser() -> any DATParser {
        return RedumpDATParser()
    }

    public func createValidator() -> any ROMValidator {
        return RedumpROMValidator()
    }

    public func createScanner(for datFile: any DATFormat) -> any ROMScanner {
        guard let redumpDat = datFile as? RedumpDATFile else {
            fatalError("Invalid DAT file type for Redump scanner")
        }
        return RedumpROMScanner(datFile: redumpDat, validator: createValidator(), archiveHandlers: createArchiveHandlers())
    }

    public func createRebuilder(for datFile: any DATFormat) -> any ROMRebuilder {
        guard let redumpDat = datFile as? RedumpDATFile else {
            fatalError("Invalid DAT file type for Redump rebuilder")
        }
        return RedumpROMRebuilder(datFile: redumpDat, archiveHandlers: createArchiveHandlers())
    }

    public func createArchiveHandlers() -> [any ArchiveHandler] {
        // Redump primarily deals with disc images
        return [ZIPArchiveHandler(), CHDArchiveHandler(), CUEBINArchiveHandler()]
    }
}

// MARK: - Redump Models

public struct RedumpDATFile: DATFormat {
    public let formatName = "Redump"
    public let formatVersion: String?
    public let games: [any GameEntry]
    public let metadata: any DATMetadata

    public init(formatVersion: String? = nil, games: [RedumpGame], metadata: RedumpMetadata) {
        self.formatVersion = formatVersion
        self.games = games
        self.metadata = metadata
    }
}

public struct RedumpMetadata: DATMetadata {
    public let name: String
    public let description: String
    public let version: String?
    public let author: String?
    public let date: String?
    public let comment: String?
    public let url: String?
    public let system: String?

    public init(
        name: String,
        description: String,
        version: String? = nil,
        author: String? = nil,
        date: String? = nil,
        comment: String? = nil,
        url: String? = nil,
        system: String? = nil
    ) {
        self.name = name
        self.description = description
        self.version = version
        self.author = author
        self.date = date
        self.comment = comment
        self.url = url
        self.system = system
    }
}

public struct RedumpGame: GameEntry {
    public let identifier: String
    public let name: String
    public let description: String
    public let items: [any ROMItem]
    public let metadata: any GameMetadata
    public let tracks: [RedumpTrack]

    public init(name: String, description: String, roms: [RedumpROM], tracks: [RedumpTrack] = [], metadata: RedumpGameMetadata) {
        self.identifier = name
        self.name = name
        self.description = description
        self.items = roms
        self.tracks = tracks
        self.metadata = metadata
    }
}

public struct RedumpGameMetadata: GameMetadata {
    public let year: String?
    public let manufacturer: String?
    public let category: String?
    public let cloneOf: String?
    public let romOf: String?
    public let sampleOf: String?
    public let sourceFile: String?
    public let serial: String?
    public let version: String?
    public let region: String?
    public let languages: [String]
    public let discNumber: Int?
    public let discTotal: Int?

    public init(
        year: String? = nil,
        manufacturer: String? = nil,
        category: String? = nil,
        serial: String? = nil,
        version: String? = nil,
        region: String? = nil,
        languages: [String] = [],
        discNumber: Int? = nil,
        discTotal: Int? = nil
    ) {
        self.year = year
        self.manufacturer = manufacturer
        self.category = category
        self.cloneOf = nil
        self.romOf = nil
        self.sampleOf = nil
        self.sourceFile = nil
        self.serial = serial
        self.version = version
        self.region = region
        self.languages = languages
        self.discNumber = discNumber
        self.discTotal = discTotal
    }
}

public struct RedumpROM: ROMItem {
    public let name: String
    public let size: UInt64
    public let checksums: ROMChecksums
    public let status: ROMStatus
    public let attributes: ROMAttributes

    public init(
        name: String,
        size: UInt64,
        checksums: ROMChecksums,
        status: ROMStatus = .good,
        attributes: ROMAttributes = ROMAttributes()
    ) {
        self.name = name
        self.size = size
        self.checksums = checksums
        self.status = status
        self.attributes = attributes
    }
}

public struct RedumpTrack: Sendable {
    public let number: Int
    public let type: String
    public let name: String
    public let size: UInt64
    public let crc32: String?
    public let md5: String?
    public let sha1: String?

    public init(
        number: Int,
        type: String,
        name: String,
        size: UInt64,
        crc32: String? = nil,
        md5: String? = nil,
        sha1: String? = nil
    ) {
        self.number = number
        self.type = type
        self.name = name
        self.size = size
        self.crc32 = crc32
        self.md5 = md5
        self.sha1 = sha1
    }
}

// MARK: - CUE/BIN Archive Handler

public final class CUEBINArchiveHandler: ArchiveHandler, @unchecked Sendable {
    public let supportedExtensions = ["cue", "bin", "iso", "img"]

    public init() {}

    public func canHandle(url: URL) -> Bool {
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    public func listContents(of url: URL) throws -> [ArchiveEntry] {
        // CUE/BIN handling would require specialized parsing
        throw ArchiveError.unsupportedFormat("CUE/BIN support not yet implemented")
    }

    public func extract(entry: ArchiveEntry, from url: URL) throws -> Data {
        throw ArchiveError.unsupportedFormat("CUE/BIN support not yet implemented")
    }

    public func extractAll(from url: URL, to destination: URL) throws {
        throw ArchiveError.unsupportedFormat("CUE/BIN support not yet implemented")
    }

    public func create(at url: URL, with entries: [(name: String, data: Data)]) throws {
        throw ArchiveError.unsupportedFormat("CUE/BIN creation not supported")
    }
}

// MARK: - Redump Parser

public class RedumpDATParser: NSObject, DATParser {
    public typealias DATType = RedumpDATFile

    public func canParse(data: Data) -> Bool {
        guard let xmlString = String(data: data.prefix(1000), encoding: .utf8) else {
            return false
        }

        return xmlString.contains("<!DOCTYPE datafile") &&
               xmlString.contains("redump.org")
    }

    public func parse(data: Data) throws -> RedumpDATFile {
        // Simplified implementation - would need full XML parsing
        let metadata = RedumpMetadata(
            name: "Redump Collection",
            description: "Redump DAT File",
            url: "http://redump.org"
        )

        return RedumpDATFile(
            formatVersion: "1.0",
            games: [],
            metadata: metadata
        )
    }

    public func parse(url: URL) throws -> RedumpDATFile {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }
}

// MARK: - Redump Validator

public class RedumpROMValidator: ROMValidator {
    private let mameValidator = MAMEROMValidator()

    public func validate(item: any ROMItem, against data: Data) -> ValidationResult {
        return mameValidator.validate(item: item, against: data)
    }

    public func validate(item: any ROMItem, at url: URL) throws -> ValidationResult {
        return try mameValidator.validate(item: item, at: url)
    }

    public func computeChecksums(for data: Data) -> ROMChecksums {
        return mameValidator.computeChecksums(for: data)
    }
}

// MARK: - Redump Scanner

public class RedumpROMScanner: ROMScanner {
    public typealias DATType = RedumpDATFile

    public let datFile: RedumpDATFile
    public let validator: any ROMValidator
    public let archiveHandlers: [any ArchiveHandler]

    public init(datFile: RedumpDATFile, validator: any ROMValidator, archiveHandlers: [any ArchiveHandler]) {
        self.datFile = datFile
        self.validator = validator
        self.archiveHandlers = archiveHandlers
    }

    public func scan(directory: URL) async throws -> any ScanResults {
        return RedumpScanResults(
            scannedPath: directory.path,
            foundGames: [],
            unknownFiles: [],
            scanDate: Date(),
            errors: []
        )
    }

    public func scan(files: [URL]) async throws -> any ScanResults {
        return RedumpScanResults(
            scannedPath: "",
            foundGames: [],
            unknownFiles: files,
            scanDate: Date(),
            errors: []
        )
    }
}

public struct RedumpScanResults: ScanResults {
    public let scannedPath: String
    public let foundGames: [any ScannedGameEntry]
    public let unknownFiles: [URL]
    public let scanDate: Date
    public let errors: [ScanError]
}

// MARK: - Redump Rebuilder

public class RedumpROMRebuilder: ROMRebuilder {
    public typealias DATType = RedumpDATFile

    public let datFile: RedumpDATFile
    public let archiveHandlers: [any ArchiveHandler]

    public init(datFile: RedumpDATFile, archiveHandlers: [any ArchiveHandler]) {
        self.datFile = datFile
        self.archiveHandlers = archiveHandlers
    }

    public func rebuild(from source: URL, to destination: URL, options: RebuildOptions) async throws -> RebuildResults {
        return RebuildResults(rebuilt: 0, skipped: 0, failed: 0)
    }
}
