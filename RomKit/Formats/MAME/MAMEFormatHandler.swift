//
//  MAMEFormatHandler.swift
//  RomKit
//
//  MAME format handler
//

import Foundation

/// MAME Format Handler
public class MAMEFormatHandler: ROMFormatHandler {
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
            fatalError("Invalid DAT file type for MAME scanner")
        }
        return MAMEROMScanner(datFile: mameDat, validator: createValidator(), archiveHandlers: createArchiveHandlers())
    }

    public func createRebuilder(for datFile: any DATFormat) -> any ROMRebuilder {
        guard let mameDat = datFile as? MAMEDATFile else {
            fatalError("Invalid DAT file type for MAME rebuilder")
        }
        return MAMEROMRebuilder(datFile: mameDat, archiveHandlers: createArchiveHandlers())
    }

    public func createArchiveHandlers() -> [any ArchiveHandler] {
        return [ZIPArchiveHandler(), SevenZipArchiveHandler(), CHDArchiveHandler()]
    }
}
