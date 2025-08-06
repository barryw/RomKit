//
//  RomKit.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation

// MARK: - Main RomKit Class (Legacy compatibility wrapper)

public class RomKit {
    private let genericKit = RomKitGeneric()
    
    public init(concurrencyLevel: Int = ProcessInfo.processInfo.processorCount) {
        // Concurrency level is now handled internally by each scanner
    }
    
    public func loadDAT(from path: String) throws {
        // Auto-detect format, but prefer Logiqx as it's the industry standard
        // The registry will check Logiqx first automatically
        try genericKit.loadDAT(from: path, format: nil)
    }
    
    public func loadLogiqxDAT(from path: String) throws {
        // Explicitly load as Logiqx format (industry standard)
        try genericKit.loadDAT(from: path, format: "logiqx")
    }
    
    public func loadMAMEDAT(from path: String) throws {
        // Explicitly load as MAME XML format (legacy)
        try genericKit.loadDAT(from: path, format: "mame")
    }
    
    public func scanDirectory(_ path: String) async throws -> ScanResult {
        guard let results = try await genericKit.scan(directory: path) else {
            throw RomKitError.scanFailed("No results returned")
        }
        
        // Convert generic results to legacy format
        return convertToLegacyScanResult(results)
    }
    
    public func generateAuditReport(from scanResult: ScanResult) -> AuditReport {
        // Convert legacy scan result to generic and generate report
        let genericReport = genericKit.generateAuditReport(from: convertToGenericScanResult(scanResult))
        return convertToLegacyAuditReport(genericReport, scanResult: scanResult)
    }
    
    public func rebuild(from source: String, to destination: String, style: RebuildStyle) async throws {
        let options = RebuildOptions(style: style.toGenericStyle())
        _ = try await genericKit.rebuild(from: source, to: destination, options: options)
    }
    
    // MARK: - Conversion Helpers
    
    private func convertToLegacyScanResult(_ results: any ScanResults) -> ScanResult {
        var foundGames: [ScannedGame] = []
        
        for game in results.foundGames {
            if let mameGame = game.game as? MAMEGame {
                let legacyGame = Game(
                    name: mameGame.name,
                    description: mameGame.description,
                    cloneOf: (mameGame.metadata as? MAMEGameMetadata)?.cloneOf,
                    romOf: (mameGame.metadata as? MAMEGameMetadata)?.romOf,
                    year: mameGame.metadata.year,
                    manufacturer: mameGame.metadata.manufacturer,
                    roms: mameGame.items.compactMap { item in
                        guard let mameRom = item as? MAMEROM else { return nil }
                        return ROM(
                            name: mameRom.name,
                            size: mameRom.size,
                            crc: mameRom.checksums.crc32,
                            sha1: mameRom.checksums.sha1,
                            status: mameRom.status
                        )
                    }
                )
                
                let foundRoms = game.foundItems.compactMap { item -> ScannedROM? in
                    guard let mameRom = item.item as? MAMEROM else { return nil }
                    let rom = ROM(
                        name: mameRom.name,
                        size: mameRom.size,
                        crc: mameRom.checksums.crc32,
                        sha1: mameRom.checksums.sha1,
                        status: mameRom.status
                    )
                    
                    let hash = FileHash(
                        crc32: item.validationResult.actualChecksums.crc32 ?? "",
                        sha1: item.validationResult.actualChecksums.sha1 ?? "",
                        md5: item.validationResult.actualChecksums.md5 ?? "",
                        size: mameRom.size
                    )
                    
                    let status: ROMValidationStatus = item.validationResult.isValid ? .good : .bad
                    
                    return ScannedROM(
                        rom: rom,
                        filePath: item.location.path,
                        hash: hash,
                        status: status
                    )
                }
                
                let missingRoms = game.missingItems.compactMap { item -> ROM? in
                    guard let mameRom = item as? MAMEROM else { return nil }
                    return ROM(
                        name: mameRom.name,
                        size: mameRom.size,
                        crc: mameRom.checksums.crc32,
                        sha1: mameRom.checksums.sha1,
                        status: mameRom.status
                    )
                }
                
                let scannedGame = ScannedGame(
                    game: legacyGame,
                    foundRoms: foundRoms,
                    missingRoms: missingRoms
                )
                foundGames.append(scannedGame)
            }
        }
        
        return ScanResult(
            scannedPath: results.scannedPath,
            foundGames: foundGames,
            unknownFiles: results.unknownFiles.map { $0.path }
        )
    }
    
    private func convertToGenericScanResult(_ scanResult: ScanResult) -> any ScanResults {
        return LegacyScanResultAdapter(scanResult: scanResult)
    }
    
    private func convertToLegacyAuditReport(_ genericReport: GenericAuditReport, scanResult: ScanResult) -> AuditReport {
        // Extract detailed information from scan result
        var completeGames: [String] = []
        var incompleteGames: [IncompleteGame] = []
        var missingGames: [String] = []
        var badRoms: [BadROM] = []
        
        for scannedGame in scanResult.foundGames {
            switch scannedGame.status {
            case .complete:
                completeGames.append(scannedGame.game.name)
            case .incomplete:
                let missingRomNames = scannedGame.missingRoms.map { $0.name }
                let badRomNames = scannedGame.foundRoms.filter { $0.status == .bad }.map { $0.rom.name }
                incompleteGames.append(IncompleteGame(
                    gameName: scannedGame.game.name,
                    missingRoms: missingRomNames,
                    badRoms: badRomNames
                ))
            case .missing:
                missingGames.append(scannedGame.game.name)
            }
        }
        
        let statistics = AuditStatistics(
            totalGames: genericReport.totalGames,
            completeGames: genericReport.completeGames,
            incompleteGames: genericReport.incompleteGames,
            missingGames: genericReport.missingGames,
            totalRoms: genericReport.totalItems,
            goodRoms: genericReport.foundItems,
            badRoms: 0,
            missingRoms: genericReport.missingItems
        )
        
        return AuditReport(
            scanDate: genericReport.scanDate,
            scannedPath: genericReport.scannedPath,
            totalGames: genericReport.totalGames,
            completeGames: completeGames,
            incompleteGames: incompleteGames,
            missingGames: missingGames,
            badRoms: badRoms,
            unknownFiles: scanResult.unknownFiles,
            statistics: statistics
        )
    }
}

// MARK: - Legacy Compatibility Types

public enum RomKitError: Error, LocalizedError {
    case datFileNotLoaded
    case invalidPath(String)
    case scanFailed(String)
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

public enum RebuildStyle {
    case split
    case merged
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
