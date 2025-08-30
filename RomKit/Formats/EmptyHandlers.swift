//
//  EmptyHandlers.swift
//  RomKit
//
//  Safe fallback handlers for format mismatches (CI compatibility)
//

import Foundation

// MARK: - Empty ROM Scanner

/// A scanner that returns no results - used as a safe fallback when DAT format casting fails
public final class EmptyROMScanner: ROMScanner {
    public typealias DATType = EmptyDATFile
    
    public let datFile = EmptyDATFile()
    public let validator: any ROMValidator = EmptyROMValidator()
    public let archiveHandlers: [any ArchiveHandler] = []
    
    public init() {}
    
    public func scan(directory: URL) async throws -> any ScanResults {
        return EmptyScanResults()
    }
    
    public func scan(files: [URL]) async throws -> any ScanResults {
        return EmptyScanResults()
    }
}

// MARK: - Empty ROM Rebuilder

/// A rebuilder that rebuilds nothing - used as a safe fallback when DAT format casting fails
public final class EmptyROMRebuilder: ROMRebuilder {
    public typealias DATType = EmptyDATFile
    
    public let datFile = EmptyDATFile()
    public let archiveHandlers: [any ArchiveHandler] = []
    
    public init() {}
    
    public func rebuild(from source: URL, to destination: URL, options: RebuildOptions) async throws -> RebuildResults {
        return RebuildResults(rebuilt: 0, skipped: 0, failed: 0)
    }
}

// MARK: - Supporting Types

public struct EmptyDATFile: DATFormat {
    public let formatName = "Empty"
    public let formatVersion: String? = nil
    public let games: [any GameEntry] = []
    public let metadata: any DATMetadata = EmptyDATMetadata()
}

public struct EmptyDATMetadata: DATMetadata {
    public let name = "Empty"
    public let description = "Empty DAT file"
    public let version: String? = nil
    public let author: String? = nil
    public let date: String? = nil
    public let comment: String? = nil
    public let url: String? = nil
}

public struct EmptyScanResults: ScanResults {
    public let scannedPath = ""
    public let foundGames: [any ScannedGameEntry] = []
    public let unknownFiles: [URL] = []
    public let scanDate = Date()
    public let errors: [ScanError] = []
}

public final class EmptyROMValidator: ROMValidator {
    public func validate(item: any ROMItem, against data: Data) -> ValidationResult {
        return ValidationResult(
            isValid: false,
            actualChecksums: ROMChecksums(),
            expectedChecksums: item.checksums,
            errors: ["Empty validator - no validation performed"]
        )
    }
    
    public func validate(item: any ROMItem, at url: URL) throws -> ValidationResult {
        return ValidationResult(
            isValid: false,
            actualChecksums: ROMChecksums(),
            expectedChecksums: item.checksums,
            errors: ["Empty validator - no validation performed"]
        )
    }
    
    public func computeChecksums(for data: Data) -> ROMChecksums {
        return ROMChecksums()
    }
}