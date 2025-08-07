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
    internal let queue = DispatchQueue(label: "romkit.index.sqlite", attributes: .concurrent)

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
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    private func openDatabase() async throws {
        if sqlite3_open_v2(dbPath.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            throw IndexError.databaseError(lastErrorMessage())
        }

        // Enable WAL mode for better concurrency
        try await execute("PRAGMA journal_mode = WAL")

        // Optimize for our use case
        try await execute("PRAGMA synchronous = NORMAL")
        try await execute("PRAGMA cache_size = 10000")
        try await execute("PRAGMA temp_store = MEMORY")
    }

    private func createTables() async throws {
        // Main ROM table
        let createROMTable = """
            CREATE TABLE IF NOT EXISTS roms (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                size INTEGER NOT NULL,
                crc32 TEXT,
                sha1 TEXT,
                md5 TEXT,
                location_type TEXT NOT NULL,
                location_path TEXT NOT NULL,
                location_entry TEXT,
                last_modified INTEGER NOT NULL,
                last_verified INTEGER,
                UNIQUE(location_path, location_entry)
            )
            """
        try await execute(createROMTable)

        // Create indexes for fast lookups
        try await execute("CREATE INDEX IF NOT EXISTS idx_crc32 ON roms(crc32)")
        try await execute("CREATE INDEX IF NOT EXISTS idx_name ON roms(name COLLATE NOCASE)")
        try await execute("CREATE INDEX IF NOT EXISTS idx_size ON roms(size)")
        try await execute("CREATE INDEX IF NOT EXISTS idx_location ON roms(location_path)")

        // Source directories table
        let createSourcesTable = """
            CREATE TABLE IF NOT EXISTS sources (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                path TEXT UNIQUE NOT NULL,
                last_scan INTEGER NOT NULL,
                rom_count INTEGER DEFAULT 0,
                total_size INTEGER DEFAULT 0
            )
            """
        try await execute(createSourcesTable)

        // Duplicate tracking table
        let createDuplicatesTable = """
            CREATE TABLE IF NOT EXISTS duplicates (
                crc32 TEXT NOT NULL,
                rom_id INTEGER NOT NULL,
                FOREIGN KEY(rom_id) REFERENCES roms(id) ON DELETE CASCADE
            )
            """
        try await execute(createDuplicatesTable)
        try await execute("CREATE INDEX IF NOT EXISTS idx_dup_crc32 ON duplicates(crc32)")
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
        var crc32 = ""
        if let hash = scanResult.hash {
            crc32 = hash
        } else if scanResult.size < 10_000_000 { // Compute for small files
            let data = try Data(contentsOf: scanResult.url)
            crc32 = HashUtilities.crc32(data: data)
        }

        let query = """
            INSERT OR REPLACE INTO roms
            (name, size, crc32, sha1, md5, location_type, location_path, location_entry, last_modified)
            VALUES (?, ?, ?, NULL, NULL, 'file', ?, NULL, ?)
            """

        try await execute(query, parameters: [
            scanResult.url.lastPathComponent,
            Int(scanResult.size),
            crc32.isEmpty ? nil : crc32,
            scanResult.url.path,
            Int(scanResult.modificationDate.timeIntervalSince1970)
        ])
    }

    private func indexArchive(at url: URL) async throws {
        let handler: ArchiveHandler

        switch url.pathExtension.lowercased() {
        case "zip":
            handler = ParallelZIPArchiveHandler()
        case "7z":
            handler = SevenZipArchiveHandler()
        default:
            return
        }

        guard handler.canHandle(url: url) else { return }

        let entries = try handler.listContents(of: url)

        for entry in entries {
            // Index ALL files inside archives (they're all assumed to be ROMs)
            // Skip only directories and obviously non-ROM files
            let filename = URL(fileURLWithPath: entry.path).lastPathComponent
            if filename.hasPrefix(".") || filename.lowercased() == "readme.txt" {
                continue
            }

            let query = """
                INSERT OR REPLACE INTO roms
                (name, size, crc32, sha1, md5, location_type, location_path, location_entry, last_modified)
                VALUES (?, ?, ?, NULL, NULL, 'archive', ?, ?, ?)
                """

            try await execute(query, parameters: [
                filename,
                Int(entry.uncompressedSize),
                entry.crc32 ?? "",
                url.path,
                entry.path,
                Int((entry.modificationDate ?? Date()).timeIntervalSince1970)
            ])
        }
    }

    // MARK: - Search Operations

    /// Find ROMs by CRC32 (very fast with index)
    public func findByCRC(_ crc32: String) async -> [IndexedROM] {
        let query = """
            SELECT name, size, crc32, sha1, md5, location_type, location_path, location_entry, last_modified
            FROM roms
            WHERE crc32 = ? COLLATE NOCASE
            ORDER BY location_type ASC, last_modified DESC
            """

        return await executeQuery(query, parameters: [crc32.lowercased()])
    }

    /// Find ROMs by name pattern (supports wildcards)
    public func findByName(_ pattern: String) async -> [IndexedROM] {
        let query = """
            SELECT name, size, crc32, sha1, md5, location_type, location_path, location_entry, last_modified
            FROM roms
            WHERE name LIKE ? COLLATE NOCASE
            ORDER BY name, location_type ASC
            """

        return await executeQuery(query, parameters: [pattern])
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
        let query = """
            SELECT crc32, COUNT(*) as count, GROUP_CONCAT(location_path || COALESCE('::' || location_entry, ''), '|||') as locations
            FROM roms
            WHERE crc32 IS NOT NULL AND crc32 != ''
            GROUP BY crc32
            HAVING count > 1
            ORDER BY count DESC
            """

        var results: [DuplicateEntry] = []

        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                var statement: OpaquePointer?

                guard sqlite3_prepare_v2(self.db, query, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume()
                    return
                }

                defer { sqlite3_finalize(statement) }

                while sqlite3_step(statement) == SQLITE_ROW {
                    let crc32 = String(cString: sqlite3_column_text(statement, 0))
                    let count = Int(sqlite3_column_int(statement, 1))
                    let locationsStr = String(cString: sqlite3_column_text(statement, 2))
                    let locations = locationsStr.split(separator: "|||").map(String.init)

                    results.append(DuplicateEntry(crc32: crc32, count: count, locations: locations))
                }

                continuation.resume()
            }
        }

        return results
    }

    // MARK: - Statistics

    internal func updateStatistics() async {
        let stats = await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
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
            queue.async {
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

    /// Remove entries for a specific source (duplicate method - remove this one)
    // This method is redundant as it's already defined in the extension below

    /// Verify indexed files still exist
    public func verify(removeStale: Bool = false) async throws -> (valid: Int, stale: Int) {
        let query = "SELECT id, location_type, location_path, location_entry FROM roms"
        var staleIDs: [Int] = []
        var validCount = 0

        await withCheckedContinuation { continuation in
            queue.async {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(self.db, query, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume()
                    return
                }
                defer { sqlite3_finalize(statement) }

                while sqlite3_step(statement) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(statement, 0))
                    let locationType = String(cString: sqlite3_column_text(statement, 1))
                    let locationPath = String(cString: sqlite3_column_text(statement, 2))

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
            queue.async(flags: .barrier) {
                var statement: OpaquePointer?

                guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: IndexError.databaseError(self.lastErrorMessage()))
                    return
                }

                defer { sqlite3_finalize(statement) }

                // Bind parameters
                for (index, param) in parameters.enumerated() {
                    let idx = Int32(index + 1)

                    if let intParam = param as? Int {
                        sqlite3_bind_int64(statement, idx, Int64(intParam))
                    } else if let stringParam = param as? String {
                        sqlite3_bind_text(statement, idx, stringParam, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                    } else if param is NSNull {
                        sqlite3_bind_null(statement, idx)
                    }
                }

                let result = sqlite3_step(statement)
                if result != SQLITE_DONE && result != SQLITE_ROW {
                    continuation.resume(throwing: IndexError.databaseError(self.lastErrorMessage()))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func executeQuery(_ sql: String, parameters: [Any] = []) async -> [IndexedROM] {
        await withCheckedContinuation { continuation in
            queue.async {
                var statement: OpaquePointer?
                var results: [IndexedROM] = []

                guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(returning: results)
                    return
                }

                defer { sqlite3_finalize(statement) }

                // Bind parameters
                for (index, param) in parameters.enumerated() {
                    let idx = Int32(index + 1)

                    if let intParam = param as? Int {
                        sqlite3_bind_int64(statement, idx, Int64(intParam))
                    } else if let stringParam = param as? String {
                        sqlite3_bind_text(statement, idx, stringParam, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                    }
                }

                while sqlite3_step(statement) == SQLITE_ROW {
                    let name = String(cString: sqlite3_column_text(statement, 0))
                    let size = UInt64(sqlite3_column_int64(statement, 1))
                    let crc32 = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
                    let sha1 = sqlite3_column_text(statement, 3).map { String(cString: $0) }
                    let md5 = sqlite3_column_text(statement, 4).map { String(cString: $0) }
                    let locationType = String(cString: sqlite3_column_text(statement, 5))
                    let locationPath = String(cString: sqlite3_column_text(statement, 6))
                    let locationEntry = sqlite3_column_text(statement, 7).map { String(cString: $0) }
                    let lastModified = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 8)))

                    let location: ROMLocation
                    switch locationType {
                    case "file":
                        location = .file(path: URL(fileURLWithPath: locationPath))
                    case "archive":
                        location = .archive(path: URL(fileURLWithPath: locationPath), entryPath: locationEntry ?? "")
                    default:
                        continue
                    }

                    let rom = IndexedROM(
                        name: name,
                        size: size,
                        crc32: crc32,
                        sha1: sha1,
                        md5: md5,
                        location: location,
                        lastModified: lastModified
                    )

                    results.append(rom)
                }

                continuation.resume(returning: results)
            }
        }
    }

    private func lastErrorMessage() -> String {
        if let errorMessage = sqlite3_errmsg(db) {
            return String(cString: errorMessage)
        }
        return "Unknown database error"
    }

    private func isROMFile(url: URL) -> Bool {
        let romExtensions = ["rom", "bin", "chd", "neo", "a78", "col", "int", "vec", "ws", "wsc"]
        return romExtensions.contains(url.pathExtension.lowercased())
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unitIndex = 0

        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }

        return String(format: "%.2f %@", size, units[unitIndex])
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
