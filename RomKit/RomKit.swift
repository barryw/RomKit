//
//  RomKit.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation

/// RomKit is a powerful Swift framework for managing, validating, and rebuilding ROM collections
/// using DAT files from various cataloging projects like No-Intro, Redump, and MAME.
///
/// ## Overview
///
/// RomKit provides comprehensive tools for ROM collectors and preservation enthusiasts to:
/// - Parse DAT files from multiple formats (Logiqx XML, MAME XML, No-Intro, Redump)
/// - Scan directories to identify and validate ROM files
/// - Generate detailed audit reports showing collection completeness
/// - Rebuild ROM sets in various formats (split, merged, non-merged)
/// - Handle archive formats (ZIP, 7z) transparently
/// - Detect and manage duplicate ROMs across multiple sources
///
/// ## Quick Start
///
/// ```swift
/// import RomKit
///
/// // Initialize RomKit
/// let romkit = RomKit()
///
/// // Load a DAT file (auto-detects format)
/// try romkit.loadDAT(from: "/path/to/mame.dat")
///
/// // Scan your ROM directory
/// let scanResult = try await romkit.scanDirectory("/path/to/roms")
///
/// // Generate an audit report
/// let report = romkit.generateAuditReport(from: scanResult)
/// print("Complete games: \(report.completeGames.count)")
/// print("Missing games: \(report.missingGames.count)")
///
/// // Rebuild ROM sets
/// try await romkit.rebuild(
///     from: "/path/to/source",
///     to: "/path/to/destination",
///     style: .split
/// )
/// ```
///
/// ## Features
///
/// ### DAT File Support
/// - **Logiqx XML**: Industry standard format (preferred)
/// - **MAME XML**: Native MAME format with full device/BIOS support
/// - **No-Intro**: Cartridge-based system DATs
/// - **Redump**: Disc-based system DATs with CUE/BIN support
///
/// ### Scanning Capabilities
/// - Recursive directory scanning
/// - Archive content inspection (ZIP files)
/// - CRC32, SHA1, MD5 checksum validation
/// - Duplicate detection across sources
/// - Parent/clone relationship handling
///
/// ### Rebuild Styles
/// - **Split**: Separate archives for each game, clones only contain unique ROMs
/// - **Merged**: Clones merged into parent archives
/// - **Non-Merged**: Each game is self-contained with all required ROMs
///
/// ### Performance Optimizations
/// - Concurrent file scanning
/// - Parallel checksum computation
/// - Metal GPU acceleration for hash calculations (when available)
/// - Efficient caching of parsed DAT files
/// - Async/await support throughout
///
/// ## Advanced Usage
///
/// ### Format-Specific Loading
///
/// ```swift
/// // Explicitly load as Logiqx format
/// try romkit.loadLogiqxDAT(from: "/path/to/logiqx.dat")
///
/// // Load MAME format
/// try romkit.loadMAMEDAT(from: "/path/to/mame.xml")
/// ```
///
/// ### Custom Concurrency
///
/// ```swift
/// // Initialize with custom concurrency level
/// let romkit = RomKit(concurrencyLevel: 8)
/// ```
///
/// ### Working with Scan Results
///
/// ```swift
/// let scanResult = try await romkit.scanDirectory("/roms")
///
/// // Check individual games
/// for game in scanResult.foundGames {
///     switch game.status {
///     case .complete:
///         print("\(game.game.name): Complete!")
///     case .incomplete:
///         print("\(game.game.name): Missing \(game.missingRoms.count) ROMs")
///     case .missing:
///         print("\(game.game.name): Not found")
///     }
/// }
///
/// // Identify unknown files
/// for unknownFile in scanResult.unknownFiles {
///     print("Unknown file: \(unknownFile)")
/// }
/// ```
///
/// ## Topics
///
/// ### Essentials
/// - ``RomKit``
/// - ``loadDAT(from:)``
/// - ``scanDirectory(_:)``
/// - ``generateAuditReport(from:)``
///
/// ### Rebuilding
/// - ``rebuild(from:to:style:)``
/// - ``RebuildStyle``
///
/// ### Errors
/// - ``RomKitError``
public class RomKit {
    private let genericKit = RomKitGeneric()

    /// Initialize a new RomKit instance
    /// - Parameter concurrencyLevel: Maximum number of concurrent operations (defaults to processor count)
    public init(concurrencyLevel: Int = ProcessInfo.processInfo.processorCount) {
        // Concurrency level is now handled internally by each scanner
    }

    /// Load a DAT file from the specified path
    ///
    /// This method auto-detects the DAT format and prefers Logiqx as the industry standard.
    /// Supported formats include:
    /// - Logiqx XML (preferred)
    /// - MAME XML
    /// - No-Intro
    /// - Redump
    ///
    /// - Parameter path: Path to the DAT file
    /// - Throws: ``RomKitError/invalidPath(_:)`` if the file cannot be read
    ///
    /// ## Example
    /// ```swift
    /// let romkit = RomKit()
    /// try romkit.loadDAT(from: "/path/to/mame.dat")
    /// ```
    public func loadDAT(from path: String) throws {
        // Auto-detect format, but prefer Logiqx as it's the industry standard
        // The registry will check Logiqx first automatically
        try genericKit.loadDAT(from: path, format: nil)
    }

    /// Explicitly load a DAT file as Logiqx format
    ///
    /// Use this method when you know the DAT file is in Logiqx XML format.
    /// Logiqx is the industry standard format supported by most ROM management tools.
    ///
    /// - Parameter path: Path to the Logiqx DAT file
    /// - Throws: ``RomKitError/invalidPath(_:)`` if the file cannot be read
    public func loadLogiqxDAT(from path: String) throws {
        // Explicitly load as Logiqx format (industry standard)
        try genericKit.loadDAT(from: path, format: "logiqx")
    }

    /// Explicitly load a DAT file as MAME XML format
    ///
    /// Use this method for native MAME XML files that include device and BIOS information.
    ///
    /// - Parameter path: Path to the MAME XML file
    /// - Throws: ``RomKitError/invalidPath(_:)`` if the file cannot be read
    public func loadMAMEDAT(from path: String) throws {
        // Explicitly load as MAME XML format (legacy)
        try genericKit.loadDAT(from: path, format: "mame")
    }

    /// Scan a directory for ROM files and validate against loaded DAT
    ///
    /// This method recursively scans the specified directory, identifying ROM files
    /// and validating them against the loaded DAT file. It handles both loose files
    /// and ZIP archives.
    ///
    /// - Parameter path: Directory path to scan
    /// - Returns: A ``ScanResult`` containing found games, missing ROMs, and unknown files
    /// - Throws: ``RomKitError/datFileNotLoaded`` if no DAT file is loaded
    /// - Throws: ``RomKitError/scanFailed(_:)`` if the scan encounters an error
    ///
    /// ## Example
    /// ```swift
    /// let result = try await romkit.scanDirectory("/path/to/roms")
    /// print("Found \(result.foundGames.count) games")
    /// ```
    public func scanDirectory(_ path: String) async throws -> ScanResult {
        guard let results = try await genericKit.scan(directory: path) else {
            throw RomKitError.scanFailed("No results returned")
        }

        // Convert generic results to legacy format
        return convertToLegacyScanResult(results)
    }

    /// Generate an audit report from scan results
    ///
    /// Creates a detailed report showing the completeness of your ROM collection,
    /// including statistics on complete, incomplete, and missing games.
    ///
    /// - Parameter scanResult: The result from ``scanDirectory(_:)``
    /// - Returns: An ``AuditReport`` with detailed statistics
    ///
    /// ## Example
    /// ```swift
    /// let report = romkit.generateAuditReport(from: scanResult)
    /// print("Collection completeness: \(report.statistics.completeGames)/\(report.statistics.totalGames)")
    /// ```
    public func generateAuditReport(from scanResult: ScanResult) -> AuditReport {
        // Convert legacy scan result to generic and generate report
        let genericReport = genericKit.generateAuditReport(from: convertToGenericScanResult(scanResult))
        return convertToLegacyAuditReport(genericReport, scanResult: scanResult)
    }

    /// Rebuild ROM sets from source to destination using specified style
    ///
    /// This method rebuilds your ROM collection according to the specified style,
    /// organizing games into the appropriate archive structure.
    ///
    /// - Parameters:
    ///   - source: Source directory containing ROM files
    ///   - destination: Destination directory for rebuilt sets
    ///   - style: The rebuild style to use (split, merged, or non-merged)
    /// - Throws: ``RomKitError/rebuildFailed(_:)`` if rebuild encounters an error
    ///
    /// ## Rebuild Styles
    /// - **Split**: Each game in its own archive, clones reference parent ROMs
    /// - **Merged**: Clone ROMs are merged into parent archives
    /// - **Non-Merged**: Each game archive contains all required ROMs
    ///
    /// ## Example
    /// ```swift
    /// try await romkit.rebuild(
    ///     from: "/path/to/source",
    ///     to: "/path/to/rebuilt",
    ///     style: .split
    /// )
    /// ```
    public func rebuild(from source: String, to destination: String, style: RebuildStyle) async throws {
        let options = RebuildOptions(style: style.toGenericStyle())
        _ = try await genericKit.rebuild(from: source, to: destination, options: options)
    }

    // MARK: - Missing ROMs & Fixdat

    /// Generate a Fixdat file for missing ROMs
    ///
    /// Creates a DAT file containing only the ROMs you're missing from your collection.
    /// This is useful for sharing want lists or focusing collection efforts.
    ///
    /// - Parameters:
    ///   - scanResult: The scan result containing missing ROM information
    ///   - path: Path where to save the Fixdat file
    ///   - format: Format for the Fixdat (Logiqx XML or ClrMamePro)
    /// - Throws: ``RomKitError/writeFailed(_:)`` if the file cannot be written
    ///
    /// ## Example
    /// ```swift
    /// let scanResult = try await romkit.scanDirectory("/path/to/roms")
    /// try romkit.generateFixdat(from: scanResult, to: "/path/to/missing.dat")
    /// ```
    public func generateFixdat(
        from scanResult: ScanResult,
        to path: String,
        format: FixdatFormat = .logiqxXML
    ) throws {
        guard let datFile = genericKit.currentDATFile else {
            throw RomKitError.datFileNotLoaded
        }

        let fixdat = FixdatGenerator.generateFixdat(
            from: scanResult,
            originalDAT: datFile
        )

        try fixdat.save(to: path, format: format)
    }

    /// Generate a detailed missing ROMs report
    ///
    /// Creates a comprehensive report of missing ROMs with statistics and grouping options.
    ///
    /// - Parameters:
    ///   - scanResult: The scan result to analyze
    ///   - options: Report generation options
    /// - Returns: A ``MissingReport`` with detailed information
    /// - Throws: ``RomKitError/datFileNotLoaded`` if no DAT file is loaded
    ///
    /// ## Example
    /// ```swift
    /// let report = try romkit.generateMissingReport(
    ///     from: scanResult,
    ///     options: MissingReportOptions(
    ///         groupByParent: true,
    ///         includeClones: false
    ///     )
    /// )
    /// print(report.generateText())
    /// ```
    public func generateMissingReport(
        from scanResult: ScanResult,
        options: MissingReportOptions = MissingReportOptions()
    ) throws -> MissingReport {
        guard let datFile = genericKit.currentDATFile else {
            throw RomKitError.datFileNotLoaded
        }

        return MissingReportGenerator.generate(
            from: scanResult,
            datFile: datFile,
            options: options
        )
    }

    // MARK: - TorrentZip Support

    /// Convert a ZIP file to TorrentZip format
    ///
    /// TorrentZip creates reproducible ZIP files with consistent CRCs for easier sharing.
    ///
    /// - Parameters:
    ///   - path: Path to the ZIP file to convert
    ///   - outputPath: Optional output path (if nil, replaces original)
    /// - Throws: ``RomKitError/invalidPath(_:)`` if the file doesn't exist
    ///
    /// ## Example
    /// ```swift
    /// try romkit.torrentZip("/path/to/game.zip")
    /// ```
    public func torrentZip(_ path: String, outputPath: String? = nil) throws {
        let url = URL(fileURLWithPath: path)
        let output = outputPath.map { URL(fileURLWithPath: $0) }
        try TorrentZip.convertToTorrentZip(at: url, outputURL: output)
    }

    /// Verify if a ZIP is TorrentZip compliant
    ///
    /// - Parameter path: Path to the ZIP file
    /// - Returns: true if the ZIP is TorrentZip compliant
    /// - Throws: ``RomKitError/invalidPath(_:)`` if the file doesn't exist
    public func isTorrentZip(_ path: String) throws -> Bool {
        let url = URL(fileURLWithPath: path)
        return try TorrentZip.isTorrentZip(at: url)
    }

    /// Convert all ZIPs in a directory to TorrentZip format
    ///
    /// - Parameters:
    ///   - directory: Directory containing ZIP files
    ///   - recursive: Whether to process subdirectories
    /// - Throws: ``RomKitError/invalidPath(_:)`` if the directory doesn't exist
    ///
    /// ## Example
    /// ```swift
    /// try await romkit.torrentZipDirectory("/path/to/roms")
    /// ```
    public func torrentZipDirectory(_ directory: String, recursive: Bool = true) async throws {
        let url = URL(fileURLWithPath: directory)
        try await TorrentZip.convertDirectory(at: url, recursive: recursive)
    }

    // MARK: - Collection Statistics

    /// Generate comprehensive collection statistics
    ///
    /// Analyzes your collection and provides detailed statistics including completion rates,
    /// storage usage, and breakdowns by year, manufacturer, and category.
    ///
    /// - Parameter scanResult: The scan result to analyze
    /// - Returns: ``CollectionStatistics`` with detailed metrics
    /// - Throws: ``RomKitError/datFileNotLoaded`` if no DAT file is loaded
    ///
    /// ## Example
    /// ```swift
    /// let stats = try romkit.generateStatistics(from: scanResult)
    /// print(stats.generateTextReport())
    /// // Save HTML report
    /// try stats.generateHTMLReport().write(to: "report.html")
    /// ```
    public func generateStatistics(from scanResult: ScanResult) throws -> CollectionStatistics {
        guard let datFile = genericKit.currentDATFile else {
            throw RomKitError.datFileNotLoaded
        }

        return StatisticsGenerator.generate(from: scanResult, datFile: datFile)
    }

    // MARK: - ROM Organization

    /// Rename ROMs to match DAT file names
    ///
    /// Ensures your ROM files are named exactly as specified in the DAT file.
    ///
    /// - Parameters:
    ///   - directory: Directory containing ROMs to rename
    ///   - dryRun: If true, only shows what would be renamed without making changes
    ///   - preserveOriginals: If true, copies files instead of moving them
    /// - Returns: ``RenameResult`` with details of the operation
    /// - Throws: ``RomKitError/invalidPath(_:)`` if the directory doesn't exist
    ///
    /// ## Example
    /// ```swift
    /// let result = try romkit.renameROMs(
    ///     in: "/path/to/roms",
    ///     dryRun: false
    /// )
    /// print(result.summary)
    /// ```
    public func renameROMs(
        in directory: String,
        dryRun: Bool = true,
        preserveOriginals: Bool = false
    ) async throws -> RenameResult {
        guard let datFile = genericKit.currentDATFile else {
            throw RomKitError.datFileNotLoaded
        }

        let organizer = ROMOrganizer(datFile: datFile)
        return try await organizer.renameROMs(
            in: URL(fileURLWithPath: directory),
            dryRun: dryRun,
            preserveOriginals: preserveOriginals
        )
    }

    /// Organize ROM collection into folders
    ///
    /// Organizes your ROMs into a folder structure based on various criteria.
    ///
    /// - Parameters:
    ///   - source: Source directory containing ROMs
    ///   - destination: Destination directory for organized ROMs
    ///   - style: Organization style (by manufacturer, year, genre, etc.)
    ///   - moveFiles: If true, moves files; if false, copies them
    /// - Returns: ``OrganizeResult`` with details of the operation
    /// - Throws: ``RomKitError/invalidPath(_:)`` if directories don't exist
    ///
    /// ## Example
    /// ```swift
    /// let result = try romkit.organizeCollection(
    ///     from: "/path/to/roms",
    ///     to: "/path/to/organized",
    ///     style: .byManufacturer
    /// )
    /// ```
    public func organizeCollection(
        from source: String,
        to destination: String,
        style: OrganizationStyle,
        moveFiles: Bool = false
    ) async throws -> OrganizeResult {
        guard let datFile = genericKit.currentDATFile else {
            throw RomKitError.datFileNotLoaded
        }

        let organizer = ROMOrganizer(datFile: datFile)
        return try await organizer.organizeCollection(
            from: URL(fileURLWithPath: source),
            to: URL(fileURLWithPath: destination),
            style: style,
            moveFiles: moveFiles
        )
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
