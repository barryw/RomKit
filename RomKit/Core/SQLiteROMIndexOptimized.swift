//
//  SQLiteROMIndexOptimized.swift
//  RomKit
//
//  Performance optimizations for SQLite ROM indexing
//

import Foundation
import SQLite3

extension SQLiteROMIndex {

    /// Optimized indexing with batch operations and parallel processing
    public func indexDirectoryOptimized(_ directory: URL, showProgress: Bool = false) async throws {
        let scanner = ConcurrentScanner()
        let results = try await scanner.scanDirectory(
            at: directory,
            computeHashes: false  // Don't compute hashes during scan
        )

        if showProgress {
            print("📊 Found \(results.count) files to process")
        }

        // Separate archives from regular files
        let archives = results.filter { $0.isArchive || $0.url.pathExtension.lowercased() == "zip" }
        let regularFiles = results.filter { !($0.isArchive || $0.url.pathExtension.lowercased() == "zip") }

        // Begin transaction
        try await execute("BEGIN TRANSACTION")

        do {
            // Process regular files in batches
            if !regularFiles.isEmpty {
                if showProgress {
                    print("📄 Processing \(regularFiles.count) regular files...")
                }
                try await batchInsertFiles(regularFiles)
            }

            // Process archives in parallel with batched inserts
            if !archives.isEmpty {
                if showProgress {
                    print("📦 Processing \(archives.count) archives...")
                }
                try await processArchivesInParallel(archives, showProgress: showProgress)
            }

            try await execute("COMMIT")
        } catch {
            try await execute("ROLLBACK")
            throw error
        }
    }

    /// Batch insert regular files
    private func batchInsertFiles(_ files: [ConcurrentScanner.ScanResult]) async throws {
        let batchSize = 1000

        for batch in files.chunked(into: batchSize) {
            var insertValues: [String] = []
            var parameters: [Any] = []

            for file in batch {
                // Use hash from scanner if available, otherwise compute for small files
                let crc32: Any
                if let hash = file.hash, !hash.isEmpty {
                    crc32 = hash
                } else if file.size < 10_000_000, let data = try? Data(contentsOf: file.url) {
                    crc32 = HashUtilities.crc32(data: data)
                } else {
                    crc32 = NSNull()
                }

                insertValues.append("(?, ?, ?, NULL, NULL, 'file', ?, NULL, ?)")
                parameters.append(contentsOf: [
                    file.url.lastPathComponent,
                    Int(file.size),
                    crc32,
                    file.url.path,
                    Int(file.modificationDate.timeIntervalSince1970)
                ])
            }

            let batchInsertSQL = """
                INSERT OR REPLACE INTO roms
                (name, size, crc32, sha1, md5, location_type, location_path, location_entry, last_modified)
                VALUES \(insertValues.joined(separator: ", "))
                """

            // Execute with proper parameter binding
            try await executeBatch(batchInsertSQL, parameters: parameters)
        }
    }

    /// Process archives in parallel
    private func processArchivesInParallel(_ archives: [ConcurrentScanner.ScanResult],
                                          showProgress: Bool) async throws {
        // Create a task group for parallel processing
        let maxConcurrency = ProcessInfo.processInfo.processorCount  // Use all available cores

        // Collect all entries first
        var allEntries: [(archive: URL, entries: [ArchiveEntry])] = []

        await withTaskGroup(of: (URL, [ArchiveEntry])?.self) { group in
            // Limit concurrent tasks
            var activeCount = 0
            var archiveIndex = 0

            while archiveIndex < archives.count || activeCount > 0 {
                // Add new tasks if under limit
                while activeCount < maxConcurrency && archiveIndex < archives.count {
                    let archive = archives[archiveIndex]
                    archiveIndex += 1
                    activeCount += 1

                    group.addTask {
                        guard let handler = self.getArchiveHandler(for: archive.url) else {
                            return nil
                        }

                        guard handler.canHandle(url: archive.url) else {
                            return nil
                        }

                        do {
                            let entries = try handler.listContents(of: archive.url)
                            return (archive.url, entries)
                        } catch {
                            if showProgress {
                                print("⚠️ Failed to read \(archive.url.lastPathComponent): \(error)")
                            }
                            return nil
                        }
                    }
                }

                // Collect results
                if let result = await group.next() {
                    activeCount -= 1
                    if let result = result {
                        allEntries.append(result)
                        if showProgress && allEntries.count % 100 == 0 {
                            print("  Processed \(allEntries.count)/\(archives.count) archives...")
                        }
                    }
                }
            }
        }

        // Now batch insert all entries
        try await batchInsertArchiveEntries(allEntries)
    }

    /// Batch insert archive entries
    private func batchInsertArchiveEntries(_ archives: [(archive: URL, entries: [ArchiveEntry])]) async throws {
        let batchSize = 5000
        var allParameters: [Any] = []
        var allValues: [String] = []

        for (archiveURL, entries) in archives {
            for entry in entries where shouldIndexEntry(entry) {
                let filename = URL(fileURLWithPath: entry.path).lastPathComponent

                allValues.append("(?, ?, ?, NULL, NULL, 'archive', ?, ?, ?)")
                allParameters.append(contentsOf: [
                    filename,
                    Int(entry.uncompressedSize),
                    entry.crc32 ?? "",
                    archiveURL.path,
                    entry.path,
                    Int((entry.modificationDate ?? Date()).timeIntervalSince1970)
                ])

                // Execute batch when we reach the limit
                if allValues.count >= batchSize {
                    let batchInsertSQL = """
                        INSERT OR REPLACE INTO roms
                        (name, size, crc32, sha1, md5, location_type, location_path, location_entry, last_modified)
                        VALUES \(allValues.joined(separator: ", "))
                        """

                    try await executeBatch(batchInsertSQL, parameters: allParameters)
                    allValues.removeAll()
                    allParameters.removeAll()
                }
            }
        }

        // Insert remaining entries
        if !allValues.isEmpty {
            let batchInsertSQL = """
                INSERT OR REPLACE INTO roms
                (name, size, crc32, sha1, md5, location_type, location_path, location_entry, last_modified)
                VALUES \(allValues.joined(separator: ", "))
                """

            try await executeBatch(batchInsertSQL, parameters: allParameters)
        }
    }

    /// Execute batch insert with proper parameter binding
    private func executeBatch(_ sql: String, parameters: [Any]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                continuation.resume(throwing: IndexError.databaseError(self.lastErrorMessage()))
                return
            }

            defer { sqlite3_finalize(statement) }

            // Bind all parameters
            for (index, param) in parameters.enumerated() {
                let idx = Int32(index + 1)
                if let intParam = param as? Int {
                    sqlite3_bind_int64(statement, idx, Int64(intParam))
                } else if let stringParam = param as? String {
                    let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                    sqlite3_bind_text(statement, idx, stringParam, -1, sqliteTransient)
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

// Helper to chunk arrays
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
