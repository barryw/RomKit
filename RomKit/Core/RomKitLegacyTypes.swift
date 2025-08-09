//
//  RomKitLegacyTypes.swift
//  RomKit
//
//  Created by RomKit on 8/5/25.
//

import Foundation

// MARK: - Legacy Compatibility Types

/// Errors that can occur during RomKit operations
public enum RomKitError: Error, LocalizedError {
    /// No DAT file has been loaded
    case datFileNotLoaded
    /// The specified path is invalid or inaccessible
    case invalidPath(String)
    /// Scanning failed with the given reason
    case scanFailed(String)
    /// Rebuilding failed with the given reason
    case rebuildFailed(String)

    public var errorDescription: String? {
        switch self {
        case .datFileNotLoaded:
            return "DAT file must be loaded before performing operations"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .scanFailed(let reason):
            return "Scan failed: \(reason)"
        case .rebuildFailed(let reason):
            return "Rebuild failed: \(reason)"
        }
    }
}

/// Rebuild style options for organizing ROM sets
public enum RebuildStyle {
    /// Split sets: Each game in its own archive, clones only contain unique ROMs
    case split
    /// Merged sets: Clone ROMs are merged into parent archives
    case merged
    /// Non-merged sets: Each game archive is self-contained with all required ROMs
    case nonMerged

    func toGenericStyle() -> RebuildOptions.Style {
        switch self {
        case .split: return RebuildOptions.Style.split
        case .merged: return RebuildOptions.Style.merged
        case .nonMerged: return RebuildOptions.Style.nonMerged
        }
    }
}

// MARK: - Legacy Scan Result Adapter

struct LegacyScanResultAdapter: ScanResults {
    let scanResult: ScanResult

    var scannedPath: String { scanResult.scannedPath }
    var foundGames: [any ScannedGameEntry] { [] }
    var unknownFiles: [URL] { scanResult.unknownFiles.map { URL(fileURLWithPath: $0) } }
    var scanDate: Date { scanResult.scanDate }
    var errors: [ScanError] { [] }
}
