//
//  MAMEScanResults.swift
//  RomKit
//
//  MAME scan result types
//

import Foundation

/// MAME scan results
public struct MAMEScanResults: ScanResults {
    public let scannedPath: String
    public let foundGames: [any ScannedGameEntry]
    public let unknownFiles: [URL]
    public let scanDate: Date
    public let errors: [ScanError]
    public let scanDuration: TimeInterval

    public init(
        scannedPath: String = "",
        foundGames: [any ScannedGameEntry] = [],
        unknownFiles: [URL] = [],
        scanDate: Date = Date(),
        errors: [ScanError] = [],
        scanDuration: TimeInterval = 0
    ) {
        self.scannedPath = scannedPath
        self.foundGames = foundGames
        self.unknownFiles = unknownFiles
        self.scanDate = scanDate
        self.errors = errors
        self.scanDuration = scanDuration
    }
}

/// MAME scanned game entry
public struct MAMEScannedGame: ScannedGameEntry {
    public let game: any GameEntry
    public let foundItems: [ScannedItem]
    public let missingItems: [any ROMItem]

    public var status: GameCompletionStatus {
        if missingItems.isEmpty {
            return .complete
        } else if foundItems.isEmpty {
            return .missing
        } else {
            return .incomplete
        }
    }

    public var completionPercentage: Double {
        let total = foundItems.count + missingItems.count
        guard total > 0 else { return 0 }
        return Double(foundItems.count) / Double(total) * 100
    }
}
