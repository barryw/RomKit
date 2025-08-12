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
/// - Index and manage ROM locations for fast lookups and deduplication
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
    private var indexManager: ROMIndexManager?

    // MARK: - Public API Properties

    /// Header information from the loaded DAT file
    public var datHeader: DATHeader? {
        guard let datFile = genericKit.datFile else { return nil }
        let metadata = datFile.metadata
        return DATHeader(
            name: metadata.name,
            description: metadata.description,
            version: metadata.version ?? "Unknown",
            author: metadata.author,
            homepage: nil,  // Will need to check if available in metadata extensions
            url: metadata.url,
            date: metadata.date,
            comment: metadata.comment
        )
    }

    /// All games/machines from the loaded DAT file
    public var games: [GameInfo] {
        guard let datFile = genericKit.datFile else { return [] }
        return datFile.games.map { gameEntry in
            convertGameEntryToGameInfo(gameEntry)
        }
    }

    /// Number of games in the loaded DAT file
    public var gameCount: Int {
        genericKit.datFile?.games.count ?? 0
    }

    /// Total number of ROMs across all games
    public var totalROMCount: Int {
        guard let datFile = genericKit.datFile else { return 0 }
        return datFile.games.reduce(0) { total, game in
            total + game.items.count
        }
    }

    /// The format of the loaded DAT file
    public var datFormat: DATFormatType {
        guard let format = genericKit.currentFormatIdentifier else { return .unknown }
        return DATFormatType(rawValue: format) ?? .unknown
    }

    /// Returns true if a DAT file is currently loaded
    public var isDATLoaded: Bool {
        return genericKit.isLoaded
    }

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
    public func loadDAT(from path: String) async throws {
        // Auto-detect format, but prefer Logiqx as it's the industry standard
        // The registry will check Logiqx first automatically
        try await genericKit.loadDAT(from: path, format: nil)
    }

    /// Explicitly load a DAT file as Logiqx format
    ///
    /// Use this method when you know the DAT file is in Logiqx XML format.
    /// Logiqx is the industry standard format supported by most ROM management tools.
    ///
    /// - Parameter path: Path to the Logiqx DAT file
    /// - Throws: ``RomKitError/invalidPath(_:)`` if the file cannot be read
    public func loadLogiqxDAT(from path: String) async throws {
        // Explicitly load as Logiqx format (industry standard)
        try await genericKit.loadDAT(from: path, format: "logiqx")
    }

    /// Explicitly load a DAT file as MAME XML format
    ///
    /// Use this method for native MAME XML files that include device and BIOS information.
    ///
    /// - Parameter path: Path to the MAME XML file
    /// - Throws: ``RomKitError/invalidPath(_:)`` if the file cannot be read
    public func loadMAMEDAT(from path: String) async throws {
        // Explicitly load as MAME XML format (legacy)
        try await genericKit.loadDAT(from: path, format: "mame")
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

    // MARK: - Extended Operations

    /// Generate a fixdat from scan results
    public func generateFixdat(from scanResult: ScanResult, to path: String, format: FixdatFormat) throws {
        guard let datFile = genericKit.datFile else {
            throw RomKitError.datFileNotLoaded
        }
        let fixdat = FixdatGenerator.generateFixdat(from: scanResult, originalDAT: datFile)
        try fixdat.save(to: path, format: format)
    }

    /// Generate missing report from scan results
    public func generateMissingReport(from scanResult: ScanResult, options: MissingReportOptions? = nil) throws -> MissingReport {
        guard let datFile = genericKit.datFile else {
            throw RomKitError.datFileNotLoaded
        }
        return MissingReportGenerator.generate(from: scanResult, datFile: datFile, options: options ?? MissingReportOptions())
    }

    /// Generate collection statistics from scan results
    public func generateStatistics(from scanResult: ScanResult) throws -> CollectionStatistics {
        guard let datFile = genericKit.datFile else {
            throw RomKitError.datFileNotLoaded
        }
        return StatisticsGenerator.generate(from: scanResult, datFile: datFile)
    }

    /// Rename ROMs according to DAT file
    public func renameROMs(in directory: String, dryRun: Bool = false) async throws -> RenameResult {
        guard let datFile = genericKit.datFile else {
            throw RomKitError.datFileNotLoaded
        }
        let organizer = ROMOrganizer(datFile: datFile)
        return try await organizer.renameROMs(in: URL(fileURLWithPath: directory), dryRun: dryRun)
    }

    /// Organize ROM collection
    public func organizeCollection(from source: String, to destination: String, style: OrganizationStyle) async throws -> OrganizeResult {
        guard let datFile = genericKit.datFile else {
            throw RomKitError.datFileNotLoaded
        }
        let organizer = ROMOrganizer(datFile: datFile)
        return try await organizer.organizeCollection(
            from: URL(fileURLWithPath: source),
            to: URL(fileURLWithPath: destination),
            style: style
        )
    }

    // MARK: - Search/Query Methods

    /// Find a game by its exact name
    /// - Parameter name: The exact name of the game to find
    /// - Returns: The game information if found, nil otherwise
    public func findGame(name: String) -> GameInfo? {
        return games.first { $0.name == name }
    }

    /// Find games that contain ROMs with the specified CRC
    /// - Parameter crc: The CRC32 checksum to search for
    /// - Returns: Array of games containing ROMs with the specified CRC
    public func findGamesByCRC(_ crc: String) -> [GameInfo] {
        let normalizedCRC = crc.lowercased()
        return games.filter { game in
            game.roms.contains { rom in
                rom.crc.lowercased() == normalizedCRC
            }
        }
    }

    /// Get all game names from the loaded DAT
    /// - Returns: Array of all game names
    public func getAllGameNames() -> [String] {
        return games.map { $0.name }
    }

    /// Search for games by description (case-insensitive partial match)
    /// - Parameter searchText: Text to search for in game descriptions
    /// - Returns: Array of games with matching descriptions
    public func searchGamesByDescription(_ searchText: String) -> [GameInfo] {
        let lowercaseSearch = searchText.lowercased()
        return games.filter { game in
            game.description?.lowercased().contains(lowercaseSearch) ?? false
        }
    }

    /// Get all parent games (non-clones)
    /// - Returns: Array of parent games
    public func getParentGames() -> [GameInfo] {
        return games.filter { $0.isParent }
    }

    /// Get all clone games
    /// - Returns: Array of clone games
    public func getCloneGames() -> [GameInfo] {
        return games.filter { $0.isClone }
    }

    /// Get clones of a specific parent game
    /// - Parameter parentName: Name of the parent game
    /// - Returns: Array of clone games
    public func getClones(of parentName: String) -> [GameInfo] {
        return games.filter { $0.cloneOf == parentName }
    }

    // MARK: - Index Management APIs

    /// Initialize or get the index manager
    private func ensureIndexManager() async throws -> ROMIndexManager {
        if indexManager == nil {
            indexManager = try await ROMIndexManager()
        }
        guard let manager = indexManager else {
            throw RomKitError.scanFailed("Failed to initialize index manager")
        }
        return manager
    }

    /// Get all directories that have been indexed
    /// - Returns: Array of indexed source URLs
    public func getSources() async throws -> [URL] {
        let manager = try await ensureIndexManager()
        let sources = await manager.listSources()
        return sources.map { URL(fileURLWithPath: $0.path) }
    }

    /// Get all indexed directories with details
    /// - Returns: Array of IndexedSource with path and statistics
    public func getIndexedDirectories() async throws -> [IndexedSource] {
        let manager = try await ensureIndexManager()
        let sources = await manager.listSources()
        return sources.map { source in
            IndexedSource(
                path: URL(fileURLWithPath: source.path),
                totalROMs: source.romCount,
                totalSize: Int64(source.totalSize),
                lastIndexed: source.lastScan
            )
        }
    }

    /// Get detailed statistics for an indexed directory
    /// - Parameter source: The directory URL to get statistics for
    /// - Returns: Statistics for the specified directory, or nil if not indexed
    public func getStatistics(for source: URL) async throws -> IndexStatistics? {
        let manager = try await ensureIndexManager()
        let sources = await manager.listSources()

        // Find the source matching the requested path
        guard let sourceInfo = sources.first(where: {
            URL(fileURLWithPath: $0.path).standardized.path == source.standardized.path
        }) else {
            return nil
        }

        // Get duplicate info for this source
        let duplicates = await manager.findDuplicates(minCopies: 2)
        let sourceDuplicates = duplicates.filter { dup in
            dup.locations.contains { loc in
                loc.hasPrefix(source.path)
            }
        }

        // Count unique games (simplified - in real implementation would need DAT info)
        let uniqueGames = sourceInfo.romCount

        // Count archives and CHDs
        let fileManager = FileManager.default
        var archives = 0
        var chds = 0

        if let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey]) {
            while let element = enumerator.nextObject() {
                if let fileURL = element as? URL {
                    let pathExtension = fileURL.pathExtension.lowercased()
                    if pathExtension == "zip" || pathExtension == "7z" {
                        archives += 1
                    } else if pathExtension == "chd" {
                        chds += 1
                    }
                }
            }
        }

        return IndexStatistics(
            path: source,
            totalROMs: sourceInfo.romCount,
            uniqueGames: uniqueGames,
            duplicates: sourceDuplicates.count,
            archives: archives,
            chds: chds,
            totalSize: Int64(sourceInfo.totalSize),
            lastIndexed: sourceInfo.lastScan
        )
    }

    /// Remove a directory from the index
    /// - Parameter url: The directory URL to remove
    public func removeSource(_ url: URL) async throws {
        let manager = try await ensureIndexManager()
        try await manager.removeSource(url, showProgress: false)
    }

    /// Re-scan a directory and update the index
    /// - Parameter url: The directory URL to refresh
    public func refreshSource(_ url: URL) async throws {
        let manager = try await ensureIndexManager()
        try await manager.refreshSources([url], showProgress: false)
    }

    /// Add a new directory to the index
    /// - Parameter url: The directory URL to add
    public func addSource(_ url: URL) async throws {
        let manager = try await ensureIndexManager()
        try await manager.addSource(url, showProgress: false)
    }

    // MARK: - Conversion Helpers

    private func convertGameEntryToGameInfo(_ gameEntry: any GameEntry) -> GameInfo {
        // Extract metadata
        var year: String?
        var manufacturer: String?
        var cloneOf: String?
        var romOf: String?
        var isBios = false
        var isDevice = false

        if let mameMetadata = gameEntry.metadata as? MAMEGameMetadata {
            year = mameMetadata.year
            manufacturer = mameMetadata.manufacturer
            cloneOf = mameMetadata.cloneOf
            romOf = mameMetadata.romOf
            isBios = mameMetadata.isBios
            isDevice = mameMetadata.isDevice
        } else {
            // Generic metadata
            year = gameEntry.metadata.year
            manufacturer = gameEntry.metadata.manufacturer
            cloneOf = gameEntry.metadata.cloneOf
            romOf = gameEntry.metadata.romOf
        }

        // Convert ROMs
        let roms = gameEntry.items.map { item in
            ROMEntry(
                name: item.name,
                size: Int(item.size),
                crc: item.checksums.crc32 ?? "",
                md5: item.checksums.md5,
                sha1: item.checksums.sha1,
                status: item.status.rawValue,
                merge: item.attributes.merge
            )
        }

        // Extract disks if this is a MAME game
        var disks: [DiskInfo] = []
        if let mameGame = gameEntry as? MAMEGame {
            disks = mameGame.disks.map { disk in
                DiskInfo(
                    name: disk.name,
                    sha1: disk.checksums.sha1 ?? "",
                    md5: disk.checksums.md5,
                    status: disk.status.rawValue,
                    merge: disk.attributes.merge
                )
            }
        }

        return GameInfo(
            name: gameEntry.name,
            description: gameEntry.description,
            year: year,
            manufacturer: manufacturer,
            cloneOf: cloneOf,
            romOf: romOf,
            isBios: isBios,
            isDevice: isDevice,
            roms: roms,
            disks: disks
        )
    }

    private func convertToLegacyScanResult(_ results: any ScanResults) -> ScanResult {
        let foundGames = results.foundGames.compactMap { game in
            convertGameEntryToScannedGame(game)
        }

        return ScanResult(
            scannedPath: results.scannedPath,
            foundGames: foundGames,
            unknownFiles: results.unknownFiles.map { $0.path }
        )
    }

    private func convertGameEntryToScannedGame(_ game: any ScannedGameEntry) -> ScannedGame? {
        guard let mameGame = game.game as? MAMEGame else { return nil }

        let legacyGame = createLegacyGame(from: mameGame)
        let foundRoms = convertFoundItems(game.foundItems)
        let missingRoms = convertMissingItems(game.missingItems)

        return ScannedGame(
            game: legacyGame,
            foundRoms: foundRoms,
            missingRoms: missingRoms
        )
    }

    private func createLegacyGame(from mameGame: MAMEGame) -> Game {
        Game(
            name: mameGame.name,
            description: mameGame.description,
            cloneOf: (mameGame.metadata as? MAMEGameMetadata)?.cloneOf,
            romOf: (mameGame.metadata as? MAMEGameMetadata)?.romOf,
            year: mameGame.metadata.year,
            manufacturer: mameGame.metadata.manufacturer,
            roms: mameGame.items.compactMap(convertROMItemToLegacyROM)
        )
    }

    private func convertROMItemToLegacyROM(_ item: any ROMItem) -> ROM? {
        guard let mameRom = item as? MAMEROM else { return nil }
        return ROM(
            name: mameRom.name,
            size: mameRom.size,
            crc: mameRom.checksums.crc32,
            sha1: mameRom.checksums.sha1,
            status: mameRom.status
        )
    }

    private func convertFoundItems(_ items: [ScannedItem]) -> [ScannedROM] {
        items.compactMap(convertFoundItemToScannedROM)
    }

    private func convertFoundItemToScannedROM(_ item: ScannedItem) -> ScannedROM? {
        guard let mameRom = item.item as? MAMEROM else { return nil }

        let rom = createLegacyROMFromMAME(mameRom)
        let hash = createFileHash(from: item, size: mameRom.size)
        let status: ROMValidationStatus = item.validationResult.isValid ? .good : .bad

        return ScannedROM(
            rom: rom,
            filePath: item.location.path,
            hash: hash,
            status: status
        )
    }

    private func createLegacyROMFromMAME(_ mameRom: MAMEROM) -> ROM {
        ROM(
            name: mameRom.name,
            size: mameRom.size,
            crc: mameRom.checksums.crc32,
            sha1: mameRom.checksums.sha1,
            status: mameRom.status
        )
    }

    private func createFileHash(from item: ScannedItem, size: UInt64) -> FileHash {
        FileHash(
            crc32: item.validationResult.actualChecksums.crc32 ?? "",
            sha1: item.validationResult.actualChecksums.sha1 ?? "",
            md5: item.validationResult.actualChecksums.md5 ?? "",
            size: size
        )
    }

    private func convertMissingItems(_ items: [any ROMItem]) -> [ROM] {
        items.compactMap(convertROMItemToLegacyROM)
    }

    private func convertToGenericScanResult(_ scanResult: ScanResult) -> any ScanResults {
        return LegacyScanResultAdapter(scanResult: scanResult)
    }

    private func convertToLegacyAuditReport(_ genericReport: GenericAuditReport, scanResult: ScanResult) -> AuditReport {
        // Extract detailed information from scan result
        var completeGames: [String] = []
        var incompleteGames: [IncompleteGame] = []
        var missingGames: [String] = []
        let badRoms: [BadROM] = []

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
