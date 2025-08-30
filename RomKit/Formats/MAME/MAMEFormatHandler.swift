//
//  MAMEFormatHandler.swift
//  RomKit
//
//  MAME format handler
//

import Foundation

/// MAME Format Handler
public final class MAMEFormatHandler: ROMFormatHandler, @unchecked Sendable {
    public let formatIdentifier = "mame"
    public let formatName = "MAME"
    public let supportedExtensions = ["xml", "dat"]

    public init() {}

    public func createParser() -> any DATParser {
        return MAMEDATParser()
    }

    public func createValidator() -> any ROMValidator {
        return MAMEROMValidator()
    }

    public func createScanner(for datFile: any DATFormat) -> any ROMScanner {
        guard let mameDat = datFile as? MAMEDATFile else {
            // Return a minimal scanner if cast fails (should not happen in practice)
            return EmptyROMScanner()
        }
        return MAMEROMScanner(datFile: mameDat, validator: createValidator(), archiveHandlers: createArchiveHandlers())
    }

    public func createRebuilder(for datFile: any DATFormat) -> any ROMRebuilder {
        guard let mameDat = datFile as? MAMEDATFile else {
            // Return a minimal rebuilder if cast fails (should not happen in practice)
            return EmptyROMRebuilder()
        }
        return MAMEROMRebuilder(datFile: mameDat, archiveHandlers: createArchiveHandlers())
    }

    public func createArchiveHandlers() -> [any ArchiveHandler] {
        return [ZIPArchiveHandler(), SevenZipArchiveHandler()]
    }
}
