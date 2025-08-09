//
//  SQLiteROMIndex.swift
//  RomKit
//
//  SQLite-based ROM indexing for better performance and scalability
//

import Foundation
import SQLite3

/// SQLite-based ROM index for efficient storage and querying
public actor SQLiteROMIndex {

    // MARK: - Properties

    internal var db: OpaquePointer?
    internal let dbPath: URL
    // Remove DispatchQueue to prevent mixing with Swift Concurrency
    // All database operations will be properly serialized through the actor

    /// Statistics
    public private(set) var totalROMs: Int = 0
    public private(set) var totalSize: UInt64 = 0
    public private(set) var duplicates: Int = 0

    // MARK: - Initialization

    public init(databasePath: URL? = nil) async throws {
        // Use provided path or default to user's cache directory
        if let path = databasePath {
            self.dbPath = path
        } else {
            guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                throw ConfigurationError.missingCacheDirectory
            }
            let romkitDir = cacheDir.appendingPathComponent("RomKit", isDirectory: true)
            try FileManager.default.createDirectory(at: romkitDir, withIntermediateDirectories: true)
            self.dbPath = romkitDir.appendingPathComponent("rom_index.db")
        }

        try await openDatabase()
        try await createTables()
        await updateStatistics()
    }

    deinit {
        if let db = db {
            sqlite3_close_v2(db)  // Use v2 for better cleanup
        }
    }

    // MARK: - Database Setup

    private func openDatabase() async throws {
        if sqlite3_open_v2(dbPath.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil) != SQLITE_OK {
            throw IndexError.databaseError(lastErrorMessage())
        }

        // Use safer settings for testing
        try await execute("PRAGMA journal_mode = WAL")
        try await execute("PRAGMA synchronous = NORMAL")
        try await execute("PRAGMA cache_size = 1000")  // Reduced cache size
        try await execute("PRAGMA temp_store = MEMORY")
        try await execute("PRAGMA busy_timeout = 5000")  // 5 second timeout
    }

    private func createTables() async throws {
        // Main ROM table
        try await execute(Queries.createROMTable)

        // Create indexes for fast lookups
        try await createIndexes()

        // Source directories table
        try await execute(Queries.createSourcesTable)

        // Duplicate tracking table
        try await execute(Queries.createDuplicatesTable)
        try await execute("CREATE INDEX IF NOT EXISTS idx_dup_crc32 ON duplicates(crc32)")
    }

    private func createIndexes() async throws {
        try await execute("CREATE INDEX IF NOT EXISTS idx_crc32 ON roms(crc32)")
        try await execute("CREATE INDEX IF NOT EXISTS idx_name ON roms(name COLLATE NOCASE)")
        try await execute("CREATE INDEX IF NOT EXISTS idx_size ON roms(size)")
        try await execute("CREATE INDEX IF NOT EXISTS idx_location ON roms(location_path)")
    }

    // MARK: - Indexing Operations

    /// Index ROMs from multiple source directories
    public func indexSources(_ sources: [URL], showProgress: Bool = false) async throws {
        for source in sources {
            if showProgress {
                print("📂 Indexing: \(source.path)")
            }

            try await indexDirectory(source, showProgress: showProgress)

            // Record source
            let query = """
                INSERT OR REPLACE INTO sources (path, last_scan, rom_count, total_size)
                VALUES (?, ?,
                    (SELECT COUNT(*) FROM roms WHERE location_path LIKE ? || '%'),
                    (SELECT COALESCE(SUM(size), 0) FROM roms WHERE location_path LIKE ? || '%')
                )
                """
            try await execute(query, parameters: [
                source.path,
                Int(Date().timeIntervalSince1970),
                source.path,
                source.path
            ])
        }

        await updateStatistics()

        if showProgress {
            await printStatistics()
        }
    }

    /// Index a single directory
    public func indexDirectory(_ directory: URL, showProgress: Bool = false) async throws {
        let scanner = ConcurrentScanner()
        let results = try await scanner.scanDirectory(
            at: directory,
            computeHashes: true
        )

        // Begin transaction for batch insert
        try await execute("BEGIN TRANSACTION")

        do {
            var processedCount = 0
            let totalCount = results.count

            for result in results {
                if showProgress && processedCount % 100 == 0 {
                    print("  Processing: \(processedCount)/\(totalCount) files...")
                }

                // Index archives (ZIP/7z) by extracting and indexing contents
                if result.isArchive || result.url.pathExtension.lowercased() == "zip" {
                    try await indexArchive(at: result.url)
                } else {
                    // Index any other file as a potential ROM
                    // (loose ROM files don't always have standard extensions)
                    try await indexFile(result)
                }

                processedCount += 1
            }

            try await execute("COMMIT")
        } catch {
            try await execute("ROLLBACK")
            throw error
        }
    }

    private func indexFile(_ scanResult: ConcurrentScanner.ScanResult) async throws {
        let crc32 = await computeCRC32(for: scanResult)

        try await execute(Queries.insertROM, parameters: [
            scanResult.url.lastPathComponent,
            Int(scanResult.size),
            crc32.isEmpty ? NSNull() : crc32,
            "file",
            scanResult.url.path,
            NSNull(),
            Int(scanResult.modificationDate.timeIntervalSince1970)
        ])
    }

    private func computeCRC32(for scanResult: ConcurrentScanner.ScanResult) async -> String {
        if let hash = scanResult.hash {
            return hash
        } else if scanResult.size < 10_000_000 { // Compute for small files
            if let data = try? Data(contentsOf: scanResult.url) {
                return HashUtilities.crc32(data: data)
            }
        }
        return ""
    }

    private func indexArchive(at url: URL) async throws {
        guard let handler = getArchiveHandler(for: url) else { return }
        guard handler.canHandle(url: url) else { return }

        let entries = try handler.listContents(of: url)

        for entry in entries where shouldIndexEntry(entry) {
            try await indexArchiveEntry(entry, archiveURL: url)
        }
    }

    private func getArchiveHandler(for url: URL) -> ArchiveHandler? {
        switch url.pathExtension.lowercased() {
        case "zip":
            return ParallelZIPArchiveHandler()
        case "7z":
            return SevenZipArchiveHandler()
        default:
            return nil
        }
    }

    private func shouldIndexEntry(_ entry: ArchiveEntry) -> Bool {
        let filename = URL(fileURLWithPath: entry.path).lastPathComponent
        return !filename.hasPrefix(".") && filename.lowercased() != "readme.txt"
    }

    private func indexArchiveEntry(_ entry: ArchiveEntry, archiveURL: URL) async throws {
        let filename = URL(fileURLWithPath: entry.path).lastPathComponent

        try await execute(Queries.insertROM, parameters: [
            filename,
            Int(entry.uncompressedSize),
            entry.crc32 ?? "",
            "archive",
            archiveURL.path,
            entry.path,
            Int((entry.modificationDate ?? Date()).timeIntervalSince1970)
        ])
    }

    // MARK: - Search Operations

    /// Find ROMs by CRC32 (very fast with index)
    public func findByCRC(_ crc32: String) async -> [IndexedROM] {
        return await executeQuery(Queries.findByCRC, parameters: [crc32.lowercased()])
    }

    /// Find ROMs by name pattern (supports wildcards)
    public func findByName(_ pattern: String) async -> [IndexedROM] {
        return await executeQuery(Queries.findByName, parameters: [pattern])
    }

    /// Find ROMs by size range
    public func findBySize(min: UInt64? = nil, max: UInt64? = nil) async -> [IndexedROM] {
        var query = "SELECT name, size, crc32, sha1, md5, location_type, location_path, location_entry, last_modified FROM roms WHERE 1=1"
        var params: [Any] = []

        if let min = min {
            query += " AND size >= ?"
            params.append(Int(min))
        }

        if let max = max {
            query += " AND size <= ?"
            params.append(Int(max))
        }

        query += " ORDER BY size"

        return await executeQuery(query, parameters: params)
    }

    /// Find best match for a ROM requirement
    public func findBestMatch(for rom: ROM) async -> IndexedROM? {
        // First try CRC32 match
        if let crc = rom.crc {
            let matches = await findByCRC(crc)
            if let match = matches.first {
                return match
            }
        }

        // Fall back to name + size match
        let nameMatches = await findByName(rom.name)
        return nameMatches.first { $0.size == rom.size }
    }

    /// Find duplicate ROMs
    public func findDuplicates() async -> [DuplicateEntry] {
        return await executeDuplicateQuery()
    }

    private func executeDuplicateQuery() async -> [DuplicateEntry] {
        var results: [DuplicateEntry] = []

        await withCheckedContinuation { continuation in
            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(self.db, Queries.findDuplicates, -1, &statement, nil) == SQLITE_OK else {
                continuation.resume()
                return
            }

            defer { sqlite3_finalize(statement) }

            while sqlite3_step(statement) == SQLITE_ROW {
                if let entry = extractDuplicateEntry(from: statement) {
                    results.append(entry)
                }
            }

            continuation.resume()
        }

        return results
    }

    private func extractDuplicateEntry(from statement: OpaquePointer?) -> DuplicateEntry? {
        guard let crc32Ptr = sqlite3_column_text(statement, 0),
              let locationsPtr = sqlite3_column_text(statement, 2) else {
            return nil
        }

        let crc32 = String(cString: crc32Ptr)
        let count = Int(sqlite3_column_int(statement, 1))
        let locationsStr = String(cString: locationsPtr)
        let locations = locationsStr.split(separator: "|||").map(String.init)

        return DuplicateEntry(crc32: crc32, count: count, locations: locations)
    }

    // MARK: - Statistics

    internal func updateStatistics() async {
        let stats = await withCheckedContinuation { continuation in
            var statement: OpaquePointer?

            // Get total ROMs and size
            let query = "SELECT COUNT(*), COALESCE(SUM(size), 0) FROM roms"
            guard sqlite3_prepare_v2(self.db, query, -1, &statement, nil) == SQLITE_OK else {
                continuation.resume(returning: (0, UInt64(0), 0))
                return
            }

            var totalROMs = 0
            var totalSize: UInt64 = 0

            if sqlite3_step(statement) == SQLITE_ROW {
                totalROMs = Int(sqlite3_column_int(statement, 0))
                totalSize = UInt64(sqlite3_column_int64(statement, 1))
            }
            sqlite3_finalize(statement)

            // Get duplicate count
            let dupQuery = """
                SELECT COUNT(*) FROM (
                    SELECT crc32 FROM roms
                    WHERE crc32 IS NOT NULL AND crc32 != ''
                    GROUP BY crc32 HAVING COUNT(*) > 1
                )
                """
            guard sqlite3_prepare_v2(self.db, dupQuery, -1, &statement, nil) == SQLITE_OK else {
                continuation.resume(returning: (totalROMs, totalSize, 0))
                return
            }

            var duplicates = 0
            if sqlite3_step(statement) == SQLITE_ROW {
                duplicates = Int(sqlite3_column_int(statement, 0))
            }
            sqlite3_finalize(statement)

            continuation.resume(returning: (totalROMs, totalSize, duplicates))
        }

        self.totalROMs = stats.0
        self.totalSize = stats.1
        self.duplicates = stats.2
    }

    public func printStatistics() async {
        await updateStatistics()

        print("\n📊 Index Statistics:")
        print("  Total ROMs: \(totalROMs)")
        print("  Total Size: \(formatBytes(totalSize))")
        print("  Duplicates: \(duplicates)")

        // Get source count
        let sourceCount = await countSources()
        print("  Sources: \(sourceCount)")

        // Database size
        if let dbSize = try? FileManager.default.attributesOfItem(atPath: dbPath.path)[.size] as? Int {
            print("  Index Size: \(formatBytes(UInt64(dbSize)))")
        }
    }

    private func countSources() async -> Int {
        let query = "SELECT COUNT(*) FROM sources"
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

    // MARK: - Maintenance

    /// Vacuum database to reclaim space
    public func vacuum() async throws {
        try await execute("VACUUM")
    }

    /// Clear all indexed data
    public func clear() async throws {
        try await execute("DELETE FROM roms")
        try await execute("DELETE FROM sources")
        try await execute("DELETE FROM duplicates")
        await updateStatistics()
    }

    /// Verify indexed files still exist
    public func verify(removeStale: Bool = false) async throws -> (valid: Int, stale: Int) {
        let query = "SELECT id, location_type, location_path, location_entry FROM roms"
        var staleIDs: [Int] = []
        var validCount = 0

        await withCheckedContinuation { continuation in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, query, -1, &statement, nil) == SQLITE_OK else {
                continuation.resume()
                return
            }
            defer { sqlite3_finalize(statement) }

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))

                guard let locationTypePtr = sqlite3_column_text(statement, 1),
                      let locationPathPtr = sqlite3_column_text(statement, 2) else {
                    continue
                }

                let locationType = String(cString: locationTypePtr)
                let locationPath = String(cString: locationPathPtr)

                let exists: Bool
                if locationType == "file" {
                    exists = FileManager.default.fileExists(atPath: locationPath)
                } else {
                    // For archives, just check if archive exists
                    exists = FileManager.default.fileExists(atPath: locationPath)
                }

                if exists {
                    validCount += 1
                } else {
                    staleIDs.append(id)
                }
            }

            continuation.resume()
        }

        if removeStale && !staleIDs.isEmpty {
            let placeholders = staleIDs.map { _ in "?" }.joined(separator: ",")
            let deleteQuery = "DELETE FROM roms WHERE id IN (\(placeholders))"
            try await execute(deleteQuery, parameters: staleIDs)
            await updateStatistics()
        }

        return (validCount, staleIDs.count)
    }

    // MARK: - Helper Methods

    internal func execute(_ sql: String, parameters: [Any] = []) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                continuation.resume(throwing: IndexError.databaseError(self.lastErrorMessage()))
                return
            }

            defer { sqlite3_finalize(statement) }

            bindParameters(to: statement, parameters: parameters)

            let result = sqlite3_step(statement)
            if result != SQLITE_DONE && result != SQLITE_ROW {
                continuation.resume(throwing: IndexError.databaseError(self.lastErrorMessage()))
            } else {
                continuation.resume()
            }
        }
    }

    private func executeQuery(_ sql: String, parameters: [Any] = []) async -> [IndexedROM] {
        await withCheckedContinuation { continuation in
            var statement: OpaquePointer?
            var results: [IndexedROM] = []

            guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                continuation.resume(returning: results)
                return
            }

            defer { sqlite3_finalize(statement) }

            bindParameters(to: statement, parameters: parameters)

            while sqlite3_step(statement) == SQLITE_ROW {
                if let rom = extractROM(from: statement) {
                    results.append(rom)
                }
            }

            continuation.resume(returning: results)
        }
    }

    private func bindParameters(to statement: OpaquePointer?, parameters: [Any]) {
        for (index, param) in parameters.enumerated() {
            let idx = Int32(index + 1)

            if let intParam = param as? Int {
                sqlite3_bind_int64(statement, idx, Int64(intParam))
            } else if let stringParam = param as? String {
                sqlite3_bind_text(statement, idx, stringParam, -1, nil)
            } else if param is NSNull {
                sqlite3_bind_null(statement, idx)
            }
        }
    }

    private func extractROM(from statement: OpaquePointer?) -> IndexedROM? {
        guard let namePtr = sqlite3_column_text(statement, 0),
              let locationTypePtr = sqlite3_column_text(statement, 5),
              let locationPathPtr = sqlite3_column_text(statement, 6) else {
            return nil
        }

        let name = String(cString: namePtr)
        let size = UInt64(sqlite3_column_int64(statement, 1))
        let crc32 = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
        let sha1 = sqlite3_column_text(statement, 3).map { String(cString: $0) }
        let md5 = sqlite3_column_text(statement, 4).map { String(cString: $0) }
        let locationType = String(cString: locationTypePtr)
        let locationPath = String(cString: locationPathPtr)
        let locationEntry = sqlite3_column_text(statement, 7).map { String(cString: $0) }
        let lastModified = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 8)))

        let location: ROMLocation
        switch locationType {
        case "file":
            location = .file(path: URL(fileURLWithPath: locationPath))
        case "archive":
            location = .archive(path: URL(fileURLWithPath: locationPath), entryPath: locationEntry ?? "")
        default:
            return nil
        }

        return IndexedROM(
            name: name,
            size: size,
            crc32: crc32,
            sha1: sha1,
            md5: md5,
            location: location,
            lastModified: lastModified
        )
    }

    private func lastErrorMessage() -> String {
        if let errorMessage = sqlite3_errmsg(db) {
            return String(cString: errorMessage)
        }
        return "Unknown database error"
    }

}

// MARK: - Error Types

enum IndexError: LocalizedError {
    case databaseError(String)
    case invalidPath(String)

    var errorDescription: String? {
        switch self {
        case .databaseError(let message):
            return "Database error: \(message)"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        }
    }
}
