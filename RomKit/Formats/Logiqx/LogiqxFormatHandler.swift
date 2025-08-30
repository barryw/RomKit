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
        guard let mameDat = datFile as? MAMEDATFile else {
            print("Warning: Invalid DAT file type for Logiqx scanner, expected MAMEDATFile")
            return NoOpROMScanner()
        }
        return MAMEROMScanner(
            datFile: mameDat,
            validator: createValidator(),
            archiveHandlers: createArchiveHandlers()
        )
    }

    public func createRebuilder(for datFile: any DATFormat) -> any ROMRebuilder {
        guard let mameDat = datFile as? MAMEDATFile else {
            print("Warning: Invalid DAT file type for Logiqx rebuilder, expected MAMEDATFile")
            return NoOpROMRebuilder()
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
