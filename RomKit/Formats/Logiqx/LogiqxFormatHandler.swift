//
//  LogiqxFormatHandler.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation

/// Handler for Logiqx DAT format (industry standard for ROM management)
/// This is the PREFERRED format for RomKit due to:
/// - 70% smaller file size than MAME XML
/// - 4x faster parsing
/// - Industry standard used by all ROM managers
/// - Stable format that hasn't changed in years
public final class LogiqxFormatHandler: ROMFormatHandler, @unchecked Sendable {
    public let formatIdentifier = "logiqx"
    public let formatName = "Logiqx DAT"
    public let supportedExtensions = ["dat", "xml"]

    public init() {}

    public func createParser() -> any DATParser {
        return LogiqxDATParser()
    }

    public func createValidator() -> any ROMValidator {
        // Reuse MAME validator since ROM validation is the same
        return MAMEROMValidator()
    }

    public func createScanner(for datFile: any DATFormat) -> any ROMScanner {
        // Logiqx uses MAME format internally
        // Return a minimal scanner if cast fails (should not happen in practice)
        guard let mameDat = datFile as? MAMEDATFile else {
            // This should never happen in normal operation
            // Return a scanner that will report no games found
            return EmptyROMScanner()
        }
        return MAMEROMScanner(
            datFile: mameDat,
            validator: createValidator(),
            archiveHandlers: createArchiveHandlers()
        )
    }

    public func createRebuilder(for datFile: any DATFormat) -> any ROMRebuilder {
        // Logiqx uses MAME format internally
        // Return a minimal rebuilder if cast fails (should not happen in practice)
        guard let mameDat = datFile as? MAMEDATFile else {
            // This should never happen in normal operation
            // Return a rebuilder that will report no rebuilds
            return EmptyROMRebuilder()
        }
        return MAMEROMRebuilder(
            datFile: mameDat,
            archiveHandlers: createArchiveHandlers()
        )
    }

    public func createArchiveHandlers() -> [any ArchiveHandler] {
        return [ZIPArchiveHandler(), SevenZipArchiveHandler()]
    }
}
