//
//  RomKitProtocols.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation

// MARK: - Core Data Protocols

public protocol DATFormat: Sendable {
    var formatName: String { get }
    var formatVersion: String? { get }
    var games: [any GameEntry] { get }
    var metadata: any DATMetadata { get }
}

public protocol DATMetadata: Sendable {
    var name: String { get }
    var description: String { get }
    var version: String? { get }
    var author: String? { get }
    var date: String? { get }
    var comment: String? { get }
    var url: String? { get }
}

public protocol GameEntry: Sendable {
    var identifier: String { get }
    var name: String { get }
    var description: String { get }
    var items: [any ROMItem] { get }
    var metadata: any GameMetadata { get }
}

public protocol GameMetadata: Sendable {
    var year: String? { get }
    var manufacturer: String? { get }
    var category: String? { get }
    var cloneOf: String? { get }
    var romOf: String? { get }
    var sampleOf: String? { get }
    var sourceFile: String? { get }
}

public protocol ROMItem: Sendable {
    var name: String { get }
    var size: UInt64 { get }
    var checksums: ROMChecksums { get }
    var status: ROMStatus { get }
    var attributes: ROMAttributes { get }
}

public enum ROMStatus: String, Codable, Sendable {
    case good
    case baddump
    case nodump
    case verified
}

public struct ROMChecksums: Codable, Sendable {
    public var crc32: String?
    public var sha1: String?
    public var sha256: String?
    public var md5: String?

    public init(crc32: String? = nil, sha1: String? = nil, sha256: String? = nil, md5: String? = nil) {
        self.crc32 = crc32
        self.sha1 = sha1
        self.sha256 = sha256
        self.md5 = md5
    }
}

public struct ROMAttributes: Codable, Sendable {
    public var merge: String?
    public var date: String?
    public var optional: Bool

    public init(merge: String? = nil, date: String? = nil, optional: Bool = false) {
        self.merge = merge
        self.date = date
        self.optional = optional
    }
}

// MARK: - Parser Protocol

public protocol DATParser {
    associatedtype DATType: DATFormat

    func canParse(data: Data) -> Bool
    func parse(data: Data) throws -> DATType
    func parse(url: URL) throws -> DATType
}

// MARK: - Validator Protocol

public protocol ROMValidator {
    func validate(item: any ROMItem, against data: Data) -> ValidationResult
    func validate(item: any ROMItem, at url: URL) throws -> ValidationResult
    func computeChecksums(for data: Data) -> ROMChecksums
}

public struct ValidationResult: Sendable {
    public let isValid: Bool
    public let actualChecksums: ROMChecksums
    public let expectedChecksums: ROMChecksums
    public let sizeMismatch: Bool
    public let errors: [String]

    public init(
        isValid: Bool,
        actualChecksums: ROMChecksums,
        expectedChecksums: ROMChecksums,
        sizeMismatch: Bool = false,
        errors: [String] = []
    ) {
        self.isValid = isValid
        self.actualChecksums = actualChecksums
        self.expectedChecksums = expectedChecksums
        self.sizeMismatch = sizeMismatch
        self.errors = errors
    }
}

// MARK: - Archive Handler Protocol

public protocol ArchiveHandler: Sendable {
    var supportedExtensions: [String] { get }

    func canHandle(url: URL) -> Bool
    func listContents(of url: URL) throws -> [ArchiveEntry]
    func extract(entry: ArchiveEntry, from url: URL) throws -> Data
    func extractAll(from url: URL, to destination: URL) throws
    func create(at url: URL, with entries: [(name: String, data: Data)]) throws
}

public struct ArchiveEntry: Sendable {
    public let path: String
    public let compressedSize: UInt64
    public let uncompressedSize: UInt64
    public let modificationDate: Date?
    public let crc32: String?

    public init(
        path: String,
        compressedSize: UInt64,
        uncompressedSize: UInt64,
        modificationDate: Date? = nil,
        crc32: String? = nil
    ) {
        self.path = path
        self.compressedSize = compressedSize
        self.uncompressedSize = uncompressedSize
        self.modificationDate = modificationDate
        self.crc32 = crc32
    }
}

// MARK: - Scanner Protocol

public protocol ROMScanner {
    associatedtype DATType: DATFormat

    var datFile: DATType { get }
    var validator: any ROMValidator { get }
    var archiveHandlers: [any ArchiveHandler] { get }

    func scan(directory: URL) async throws -> any ScanResults
    func scan(files: [URL]) async throws -> any ScanResults
}

public protocol ScanResults: Sendable {
    var scannedPath: String { get }
    var foundGames: [any ScannedGameEntry] { get }
    var unknownFiles: [URL] { get }
    var scanDate: Date { get }
    var errors: [ScanError] { get }
}

public protocol ScannedGameEntry: Sendable {
    var game: any GameEntry { get }
    var foundItems: [ScannedItem] { get }
    var missingItems: [any ROMItem] { get }
    var status: GameCompletionStatus { get }
}

public struct ScannedItem: Sendable {
    public let item: any ROMItem
    public let location: URL
    public let validationResult: ValidationResult

    public init(item: any ROMItem, location: URL, validationResult: ValidationResult) {
        self.item = item
        self.location = location
        self.validationResult = validationResult
    }
}

public enum GameCompletionStatus: Sendable {
    case complete
    case incomplete
    case missing
    case unknown
}

public struct ScanError: Error, Sendable {
    public let file: URL
    public let message: String

    public init(file: URL, message: String) {
        self.file = file
        self.message = message
    }
}

// MARK: - Rebuilder Protocol

public protocol ROMRebuilder {
    associatedtype DATType: DATFormat

    var datFile: DATType { get }
    var archiveHandlers: [any ArchiveHandler] { get }

    func rebuild(from source: URL, to destination: URL, options: RebuildOptions) async throws -> RebuildResults
}

public struct RebuildOptions: Sendable {
    public enum Style: Sendable {
        case split
        case merged
        case nonMerged
        case raw
    }

    public let style: Style
    public let deleteSource: Bool
    public let skipExisting: Bool
    public let verifyAfterBuild: Bool

    public init(
        style: Style = .split,
        deleteSource: Bool = false,
        skipExisting: Bool = true,
        verifyAfterBuild: Bool = false
    ) {
        self.style = style
        self.deleteSource = deleteSource
        self.skipExisting = skipExisting
        self.verifyAfterBuild = verifyAfterBuild
    }
}

public struct RebuildResults {
    public let rebuilt: Int
    public let skipped: Int
    public let failed: Int
    public let errors: [String]

    public init(rebuilt: Int, skipped: Int, failed: Int, errors: [String] = []) {
        self.rebuilt = rebuilt
        self.skipped = skipped
        self.failed = failed
        self.errors = errors
    }
}

// MARK: - Format Handler Protocol

public protocol ROMFormatHandler: Sendable {
    var formatIdentifier: String { get }
    var formatName: String { get }
    var supportedExtensions: [String] { get }

    func createParser() -> any DATParser
    func createValidator() -> any ROMValidator
    func createScanner(for datFile: any DATFormat) -> any ROMScanner
    func createRebuilder(for datFile: any DATFormat) -> any ROMRebuilder
    func createArchiveHandlers() -> [any ArchiveHandler]
}
