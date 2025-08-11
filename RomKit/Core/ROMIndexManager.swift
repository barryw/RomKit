//
//  ROMIndexManager.swift
//  RomKit
//
//  High-level ROM index management with deduplication and source tracking
//

import Foundation
import SQLite3

/// Main ROM index manager that handles deduplication and source management
public actor ROMIndexManager {

    // MARK: - Properties

    private let index: SQLiteROMIndex
    private let dbPath: URL

    // MARK: - Initialization

    public init(databasePath: URL? = nil) async throws {
        if let path = databasePath {
            self.dbPath = path
        } else {
            guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                throw ConfigurationError.missingCacheDirectory
            }
            let romkitDir = cacheDir.appendingPathComponent("RomKit", isDirectory: true)
            try FileManager.default.createDirectory(at: romkitDir, withIntermediateDirectories: true)
            self.dbPath = romkitDir.appendingPathComponent("romkit_index.db")
        }

        self.index = try await SQLiteROMIndex(databasePath: dbPath)
    }

    // MARK: - Source Management

    /// Add a new source directory to the index
    public func addSource(_ source: URL, showProgress: Bool = true) async throws {
        if showProgress {
            print("➕ Adding source: \(source.path)")
        }

        // Check if source already exists
        let existing = await index.getSources()
        if existing.contains(where: { $0.path == source.path }) {
            if showProgress {
                print("⚠️  Source already indexed. Use refresh to update.")
            }
            return
        }

        // Index the new source
        try await index.indexSources([source], showProgress: showProgress)

        if showProgress {
            let stats = await index.getStatistics()
            print("✅ Added source with \(stats.newROMs) new ROMs, \(stats.duplicates) duplicates")
        }
    }

    /// Remove a source directory from the index
    public func removeSource(_ source: URL, showProgress: Bool = true) async throws {
        if showProgress {
            print("➖ Removing source: \(source.path)")
        }

        let removed = try await index.removeSource(source)

        if showProgress {
            print("✅ Removed \(removed) ROM entries")
        }
    }

    /// Refresh sources (re-scan for changes)
    public func refreshSources(_ sources: [URL]? = nil, showProgress: Bool = true) async throws {
        let sourcesToRefresh: [URL]
        if let sources = sources {
            sourcesToRefresh = sources
        } else {
            let sourceInfos = await index.getSources()
            sourcesToRefresh = sourceInfos.map { URL(fileURLWithPath: $0.path) }
        }

        if showProgress {
            print("🔄 Refreshing \(sourcesToRefresh.count) source(s)")
        }

        for source in sourcesToRefresh {
            if showProgress {
                print("  Scanning: \(source.lastPathComponent)")
            }

            // Remove old entries
            _ = try await index.removeSource(source)

            // Re-index
            try await index.indexSources([source], showProgress: false)
        }

        if showProgress {
            await index.printStatistics()
        }
    }

    /// List all indexed sources
    public func listSources() async -> [SourceInfo] {
        return await index.getSources()
    }

    // MARK: - ROM Lookup

    /// Find ROM by CRC32 - returns all locations where this ROM exists
    public func findROM(crc32: String) async throws -> ROMInfo? {
        let locations = await index.findByCRC(crc32)
        guard !locations.isEmpty else { return nil }

        // Group by actual ROM (same CRC = same ROM)
        guard let first = locations.first else {
            return nil
        }
        return ROMInfo(
            crc32: crc32,
            name: first.name, // Use most common name
            size: first.size,
            locations: locations.map { loc in
                ROMLocationInfo(
                    path: loc.location.displayPath,
                    type: loc.location.isLocal ? .local : .remote,
                    lastVerified: loc.lastModified
                )
            }
        )
    }

    /// Find ROMs by name pattern - supports SQL wildcards (% and _)
    public func findByName(pattern: String, limit: Int? = nil) async -> [ROMSearchResult] {
        let matches = await index.findByName(pattern)

        // Convert to search results
        var results: [ROMSearchResult] = []
        for match in matches {
            results.append(ROMSearchResult(
                name: match.name,
                crc32: match.crc32,
                size: match.size,
                location: match.location.displayPath
            ))
        }

        // Apply limit if specified
        if let limit = limit, results.count > limit {
            return Array(results.prefix(limit))
        }

        return results
    }

    /// Find best source for a ROM (prefers local, then newest)
    public func findBestSource(for rom: ROM) async -> IndexedROM? {
        guard let crc = rom.crc else {
            // Fall back to name matching if no CRC
            let matches = await index.findByName(rom.name)
            return matches.first { $0.size == rom.size }
        }

        let locations = await index.findByCRC(crc)

        // Sort by preference: local files > local archives > remote
        let sorted = locations.sorted { lhs, rhs in
            switch (lhs.location, rhs.location) {
            case (.file, _): return true
            case (_, .file): return false
            case (.archive, .remote): return true
            case (.remote, .archive): return false
            default:
                // Same type, prefer newer
                return lhs.lastModified > rhs.lastModified
            }
        }

        return sorted.first
    }
    
    /// Load all indexed ROMs into memory for fast batch lookups
    public func loadIndexIntoMemory() async -> [String: [IndexedROM]] {
        // Get all ROMs from the index
        let allROMs = await index.getAllROMs()
        
        // Group by CRC32 for fast lookups
        var romsByCRC: [String: [IndexedROM]] = [:]
        for rom in allROMs {
            let crc = rom.crc32.lowercased()
            if romsByCRC[crc] == nil {
                romsByCRC[crc] = []
            }
            romsByCRC[crc]?.append(rom)
        }
        
        return romsByCRC
    }
    
    /// Load all ROMs into memory grouped by CRC32+size composite key for proper deduplication
    public func loadIndexIntoMemoryWithCompositeKey() async -> [String: [IndexedROM]] {
        // Get all ROMs from the index
        let allROMs = await index.getAllROMs()
        
        // Group by CRC32+size composite key to handle CRC collisions
        var romsByKey: [String: [IndexedROM]] = [:]
        for rom in allROMs {
            // Create composite key: CRC32_SIZE
            let key = "\(rom.crc32.lowercased())_\(rom.size)"
            if romsByKey[key] == nil {
                romsByKey[key] = []
            }
            romsByKey[key]?.append(rom)
        }
        
        return romsByKey
    }
    
    /// Find best sources for multiple ROMs using in-memory index
    public nonisolated func findBestSourcesBatch(for roms: [ROM], using memoryIndex: [String: [IndexedROM]]) -> [IndexedROM?] {
        var results: [IndexedROM?] = []
        
        for rom in roms {
            if let crc = rom.crc?.lowercased(),
               let locations = memoryIndex[crc] {
                // Sort by preference: local files > local archives > remote
                let sorted = locations.sorted { lhs, rhs in
                    switch (lhs.location, rhs.location) {
                    case (.file, _): return true
                    case (_, .file): return false
                    case (.archive, .remote): return true
                    case (.remote, .archive): return false
                    default:
                        // Same type, prefer newer
                        return lhs.lastModified > rhs.lastModified
                    }
                }
                results.append(sorted.first)
            } else {
                results.append(nil)
            }
        }
        
        return results
    }

    /// Find all duplicate ROMs across sources
    public func findDuplicates(minCopies: Int = 2) async -> [DuplicateInfo] {
        let duplicates = await index.findDuplicates()

        return duplicates
            .filter { $0.count >= minCopies }
            .map { dup in
                DuplicateInfo(
                    crc32: dup.crc32,
                    count: dup.count,
                    locations: dup.locations,
                    potentialSpaceSaved: 0 // Would need to calculate
                )
            }
    }

    // MARK: - Analysis

    /// Analyze index for optimization opportunities
    public func analyzeIndex() async -> IndexAnalysis {
        let stats = await index.getStatistics()
        let sources = await index.getSources()
        let duplicates = await index.findDuplicates()

        // Calculate space that could be saved by deduplication
        var spaceSaveable: UInt64 = 0
        for dup in duplicates where dup.count > 1 {
            // Each duplicate beyond the first is saveable space
            if let romInfo = try? await findROM(crc32: dup.crc32) {
                spaceSaveable += romInfo.size * UInt64(dup.count - 1)
            }
        }

        return IndexAnalysis(
            totalROMs: stats.totalROMs,
            uniqueROMs: stats.uniqueCRCs,
            totalSize: stats.totalSize,
            duplicateGroups: duplicates.count,
            totalDuplicates: duplicates.reduce(0) { $0 + $1.count } - duplicates.count,
            spaceWasted: spaceSaveable,
            sources: sources,
            recommendations: generateRecommendations(stats: stats, duplicates: duplicates)
        )
    }

    private func generateRecommendations(stats: IndexStatistics, duplicates: [DuplicateEntry]) -> [String] {
        var recommendations: [String] = []

        // Check for excessive duplication
        let dupRatio = Double(stats.duplicates) / Double(max(stats.totalROMs, 1))
        if dupRatio > 0.3 {
            recommendations.append("High duplication rate (\(Int(dupRatio * 100))%). Consider consolidating sources.")
        }

        // Check for very common duplicates
        let veryDuplicated = duplicates.filter { $0.count > 5 }
        if !veryDuplicated.isEmpty {
            recommendations.append("\(veryDuplicated.count) ROMs exist in 5+ locations. Review source organization.")
        }

        // Index size check
        if stats.totalROMs > 100000 {
            recommendations.append("Large index (\(stats.totalROMs) ROMs). Consider running vacuum() to optimize.")
        }

        return recommendations
    }

    // MARK: - Maintenance

    /// Verify all indexed files still exist
    public func verify(removeStale: Bool = false, showProgress: Bool = true) async throws -> VerificationResult {
        if showProgress {
            print("🔍 Verifying indexed files...")
        }

        let (valid, stale) = try await index.verify(removeStale: removeStale)

        if showProgress {
            print("✅ Valid: \(valid)")
            if stale > 0 {
                print("⚠️  Stale: \(stale) \(removeStale ? "(removed)" : "(not removed)")")
            }
        }

        return VerificationResult(valid: valid, stale: stale, removed: removeStale ? stale : 0)
    }

    /// Optimize database
    public func optimize() async throws {
        try await index.vacuum()
    }

    /// Clear entire index
    public func clearAll() async throws {
        try await index.clear()
    }

    /// Export index statistics
    public func exportStatistics(to url: URL) async throws {
        let analysis = await analyzeIndex()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(analysis)
        try data.write(to: url)
    }
}

// MARK: - Data Types

/// Information about a ROM and all its locations
public struct ROMInfo: Sendable {
    public let crc32: String
    public let name: String
    public let size: UInt64
    public let locations: [ROMLocationInfo]

    public var copyCount: Int { locations.count }
    public var hasDuplicates: Bool { locations.count > 1 }
}

/// Search result for ROM queries
public struct ROMSearchResult: Sendable {
    public let name: String
    public let crc32: String?
    public let size: UInt64
    public let location: String
}

/// Information about a ROM location
public struct ROMLocationInfo: Sendable {
    public let path: String
    public let type: LocationType
    public let lastVerified: Date

    public enum LocationType: Sendable {
        case local
        case remote
    }
}

/// Information about duplicate ROMs
public struct DuplicateInfo: Sendable {
    public let crc32: String
    public let count: Int
    public let locations: [String]
    public let potentialSpaceSaved: UInt64
}

/// Source directory information
public struct SourceInfo: Sendable {
    public let path: String
    public let lastScan: Date
    public let romCount: Int
    public let totalSize: UInt64
}

/// Index analysis results
public struct IndexAnalysis: Codable, Sendable {
    public let totalROMs: Int
    public let uniqueROMs: Int
    public let totalSize: UInt64
    public let duplicateGroups: Int
    public let totalDuplicates: Int
    public let spaceWasted: UInt64
    public let sources: [SourceInfo]
    public let recommendations: [String]

    public var duplicatePercentage: Double {
        Double(totalDuplicates) / Double(max(totalROMs, 1)) * 100
    }

    public var averageDuplicationFactor: Double {
        Double(totalROMs) / Double(max(uniqueROMs, 1))
    }
}

/// Verification results
public struct VerificationResult: Sendable {
    public let valid: Int
    public let stale: Int
    public let removed: Int
}

/// Entry representing duplicate ROM information
public struct DuplicateEntry: Sendable {
    public let crc32: String
    public let count: Int
    public let locations: [String]
}

// MARK: - Extensions

extension SourceInfo: Codable {}

// MARK: - Updated SQLiteROMIndex

extension SQLiteROMIndex {

    /// Get all indexed sources
    public func getSources() async -> [SourceInfo] {
        let query = "SELECT path, last_scan, rom_count, total_size FROM sources ORDER BY path"

        return await withCheckedContinuation { continuation in
            var statement: OpaquePointer?
            var sources: [SourceInfo] = []

            guard sqlite3_prepare_v2(self.db, query, -1, &statement, nil) == SQLITE_OK else {
                continuation.resume(returning: sources)
                return
            }

            defer { sqlite3_finalize(statement) }

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let pathPtr = sqlite3_column_text(statement, 0) else {
                    continue
                }

                let path = String(cString: pathPtr)
                let lastScan = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 1)))
                let romCount = Int(sqlite3_column_int(statement, 2))
                let totalSize = UInt64(sqlite3_column_int64(statement, 3))

                sources.append(SourceInfo(
                    path: path,
                    lastScan: lastScan,
                    romCount: romCount,
                    totalSize: totalSize
                ))
            }

            continuation.resume(returning: sources)
        }
    }

    /// Remove a source and return count of removed entries
    public func removeSource(_ source: URL) async throws -> Int {
        // Resolve symlinks to get the actual path
        let resolvedPath = source.resolvingSymlinksInPath().path
        let originalPath = source.path

        // On macOS, /var is symlinked to /private/var
        // We need to check for both variations
        var pathsToCheck = [originalPath, resolvedPath]

        // Add /private prefix variant if path starts with /var
        if originalPath.hasPrefix("/var/") {
            pathsToCheck.append("/private" + originalPath)
        }
        if resolvedPath.hasPrefix("/var/") {
            pathsToCheck.append("/private" + resolvedPath)
        }

        // Remove /private prefix variant if path starts with /private/var
        if originalPath.hasPrefix("/private/var/") {
            pathsToCheck.append(String(originalPath.dropFirst(8))) // Remove "/private"
        }
        if resolvedPath.hasPrefix("/private/var/") {
            pathsToCheck.append(String(resolvedPath.dropFirst(8))) // Remove "/private"
        }

        // Remove duplicates
        pathsToCheck = Array(Set(pathsToCheck))

        // Build WHERE clause for all path variants
        let whereConditions = pathsToCheck.map { _ in "location_path LIKE ? || '%'" }.joined(separator: " OR ")
        let countQuery = "SELECT COUNT(*) FROM roms WHERE " + whereConditions

        let count = await withCheckedContinuation { continuation in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, countQuery, -1, &statement, nil) == SQLITE_OK else {
                continuation.resume(returning: 0)
                return
            }
            defer { sqlite3_finalize(statement) }

            // Bind all path variants
            for (index, path) in pathsToCheck.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 1), path, -1, nil)
            }

            if sqlite3_step(statement) == SQLITE_ROW {
                continuation.resume(returning: Int(sqlite3_column_int(statement, 0)))
            } else {
                continuation.resume(returning: 0)
            }
        }

        // Delete entries - check all path variants
        let deleteRomsQuery = "DELETE FROM roms WHERE " + whereConditions
        try await execute(deleteRomsQuery, parameters: pathsToCheck)

        let sourceConditions = pathsToCheck.map { _ in "path = ?" }.joined(separator: " OR ")
        let deleteSourcesQuery = "DELETE FROM sources WHERE " + sourceConditions
        try await execute(deleteSourcesQuery, parameters: pathsToCheck)
        await updateStatistics()

        return count
    }

    /// Get statistics with additional details
    public func getStatistics() async -> IndexStatistics {
        await updateStatistics()

        let sources = await getSources()
        let newROMs = 0 // Would need to track this during indexing

        return IndexStatistics(
            totalROMs: totalROMs,
            totalSize: totalSize,
            uniqueCRCs: await getUniqueCRCCount(),
            duplicates: duplicates,
            sources: sources.count,
            newROMs: newROMs
        )
    }

    private func getUniqueCRCCount() async -> Int {
        let query = "SELECT COUNT(DISTINCT crc32) FROM roms WHERE crc32 IS NOT NULL AND crc32 != ''"

        return await withCheckedContinuation { continuation in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, query, -1, &statement, nil) == SQLITE_OK else {
                continuation.resume(returning: 0)
                return
            }
            defer { sqlite3_finalize(statement) }

            if sqlite3_step(statement) == SQLITE_ROW {
                continuation.resume(returning: Int(sqlite3_column_int(statement, 0)))
            } else {
                continuation.resume(returning: 0)
            }
        }
    }
}

// IndexStatistics structure for tracking index metrics
public struct IndexStatistics: Sendable {
    public let totalROMs: Int
    public let totalSize: UInt64
    public let uniqueCRCs: Int
    public let duplicates: Int
    public let sources: Int
    public let newROMs: Int

    public init(totalROMs: Int, totalSize: UInt64, uniqueCRCs: Int, duplicates: Int, sources: Int, newROMs: Int = 0) {
        self.totalROMs = totalROMs
        self.totalSize = totalSize
        self.uniqueCRCs = uniqueCRCs
        self.duplicates = duplicates
        self.sources = sources
        self.newROMs = newROMs
    }
}
