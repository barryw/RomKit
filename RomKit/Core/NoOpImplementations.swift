//
//  NoOpImplementations.swift
//  RomKit
//
//  No-op implementations for error handling
//

import Foundation

/// No-op ROM scanner that does nothing
public struct NoOpROMScanner: ROMScanner {
    public func scan(at paths: [URL], outputDirectory: URL?, 
                     fixMode: FixMode, showProgress: Bool) async throws -> ScanResult {
        print("Warning: NoOpROMScanner called - this should not happen in normal operation")
        return ScanResult(
            foundGames: [],
            missingGames: [],
            unknownFiles: [],
            errors: []
        )
    }
}

/// No-op ROM rebuilder that does nothing
public struct NoOpROMRebuilder: ROMRebuilder {
    public func rebuild(from sourceDirectory: URL, to outputDirectory: URL,
                       mergeMode: MergeMode, showProgress: Bool) async throws -> RebuildResult {
        print("Warning: NoOpROMRebuilder called - this should not happen in normal operation")
        return RebuildResult(
            rebuiltGames: [],
            missingROMs: [],
            errors: []
        )
    }
}