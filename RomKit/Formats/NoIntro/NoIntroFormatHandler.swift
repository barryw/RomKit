//
//  NoIntroFormatHandler.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation

// MARK: - No-Intro Format Handler

public final class NoIntroFormatHandler: ROMFormatHandler, @unchecked Sendable {
    public let formatIdentifier = "no-intro"
    public let formatName = "No-Intro"
    public let supportedExtensions = ["dat", "xml"]

    public init() {}

    public func createParser() -> any DATParser {
        return NoIntroDATParser()
    }

    public func createValidator() -> any ROMValidator {
        return NoIntroROMValidator()
    }

    public func createScanner(for datFile: any DATFormat) -> any ROMScanner {
        guard let noIntroDat = datFile as? NoIntroDATFile else {
            print("Warning: Invalid DAT file type for No-Intro scanner, expected MAMEDATFile")
            return NoOpROMScanner()
        }
        return NoIntroROMScanner(datFile: noIntroDat, validator: createValidator(), archiveHandlers: createArchiveHandlers())
    }

    public func createRebuilder(for datFile: any DATFormat) -> any ROMRebuilder {
        guard let noIntroDat = datFile as? NoIntroDATFile else {
            print("Warning: Invalid DAT file type for No-Intro rebuilder, expected MAMEDATFile")
            return NoOpROMRebuilder()
        }
        return NoIntroROMRebuilder(datFile: noIntroDat, archiveHandlers: createArchiveHandlers())
    }

    public func createArchiveHandlers() -> [any ArchiveHandler] {
        return [ZIPArchiveHandler(), SevenZipArchiveHandler()]
    }
}

// MARK: - No-Intro Models

public struct NoIntroDATFile: DATFormat {
    public let formatName = "No-Intro"
    public let formatVersion: String?
    public let games: [any GameEntry]
    public let metadata: any DATMetadata

    public init(formatVersion: String? = nil, games: [NoIntroGame], metadata: NoIntroMetadata) {
        self.formatVersion = formatVersion
        self.games = games
        self.metadata = metadata
    }
}

public struct NoIntroMetadata: DATMetadata {
    public let name: String
    public let description: String
    public let version: String?
    public let author: String?
    public let date: String?
    public let comment: String?
    public let url: String?
    public let category: String?

    public init(
        name: String,
        description: String,
        version: String? = nil,
        author: String? = nil,
        date: String? = nil,
        comment: String? = nil,
        url: String? = nil,
        category: String? = nil
    ) {
        self.name = name
        self.description = description
        self.version = version
        self.author = author
        self.date = date
        self.comment = comment
        self.url = url
        self.category = category
    }
}

public struct NoIntroGame: GameEntry {
    public let identifier: String
    public let name: String
    public let description: String
    public let items: [any ROMItem]
    public let metadata: any GameMetadata

    public init(name: String, description: String, roms: [NoIntroROM], metadata: NoIntroGameMetadata) {
        self.identifier = name
        self.name = name
        self.description = description
        self.items = roms
        self.metadata = metadata
    }
}

public struct NoIntroGameMetadata: GameMetadata {
    public let year: String?
    public let manufacturer: String?
    public let category: String?
    public let cloneOf: String?
    public let romOf: String?
    public let sampleOf: String?
    public let sourceFile: String?
    public let serial: String?
    public let revision: String?
    public let region: String?
    public let language: String?

    public init(
        year: String? = nil,
        manufacturer: String? = nil,
        category: String? = nil,
        serial: String? = nil,
        revision: String? = nil,
        region: String? = nil,
        language: String? = nil
    ) {
        self.year = year
        self.manufacturer = manufacturer
        self.category = category
        self.cloneOf = nil
        self.romOf = nil
        self.sampleOf = nil
        self.sourceFile = nil
        self.serial = serial
        self.revision = revision
        self.region = region
        self.language = language
    }
}

public struct NoIntroROM: ROMItem {
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

// MARK: - No-Intro Parser

public class NoIntroDATParser: NSObject, DATParser {
    public typealias DATType = NoIntroDATFile

    public func canParse(data: Data) -> Bool {
        guard let xmlString = String(data: data.prefix(1000), encoding: .utf8) else {
            return false
        }

        return xmlString.contains("<!DOCTYPE datafile") &&
               (xmlString.contains("No-Intro") || xmlString.contains("clrmamepro"))
    }

    public func parse(data: Data) throws -> NoIntroDATFile {
        // Simplified implementation - would need full XML parsing
        let metadata = NoIntroMetadata(
            name: "No-Intro Collection",
            description: "No-Intro DAT File"
        )

        return NoIntroDATFile(
            formatVersion: "1.0",
            games: [],
            metadata: metadata
        )
    }

    public func parse(url: URL) throws -> NoIntroDATFile {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }
}

// MARK: - No-Intro Validator

public class NoIntroROMValidator: ROMValidator {
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

// MARK: - No-Intro Scanner

public class NoIntroROMScanner: ROMScanner {
    public typealias DATType = NoIntroDATFile

    public let datFile: NoIntroDATFile
    public let validator: any ROMValidator
    public let archiveHandlers: [any ArchiveHandler]

    public init(datFile: NoIntroDATFile, validator: any ROMValidator, archiveHandlers: [any ArchiveHandler]) {
        self.datFile = datFile
        self.validator = validator
        self.archiveHandlers = archiveHandlers
    }

    public func scan(directory: URL) async throws -> any ScanResults {
        // Simplified implementation
        return NoIntroScanResults(
            scannedPath: directory.path,
            foundGames: [],
            unknownFiles: [],
            scanDate: Date(),
            errors: []
        )
    }

    public func scan(files: [URL]) async throws -> any ScanResults {
        return NoIntroScanResults(
            scannedPath: "",
            foundGames: [],
            unknownFiles: files,
            scanDate: Date(),
            errors: []
        )
    }
}

public struct NoIntroScanResults: ScanResults {
    public let scannedPath: String
    public let foundGames: [any ScannedGameEntry]
    public let unknownFiles: [URL]
    public let scanDate: Date
    public let errors: [ScanError]
}

// MARK: - No-Intro Rebuilder

public class NoIntroROMRebuilder: ROMRebuilder {
    public typealias DATType = NoIntroDATFile

    public let datFile: NoIntroDATFile
    public let archiveHandlers: [any ArchiveHandler]

    public init(datFile: NoIntroDATFile, archiveHandlers: [any ArchiveHandler]) {
        self.datFile = datFile
        self.archiveHandlers = archiveHandlers
    }

    public func rebuild(from source: URL, to destination: URL, options: RebuildOptions) async throws -> RebuildResults {
        return RebuildResults(rebuilt: 0, skipped: 0, failed: 0)
    }
}
