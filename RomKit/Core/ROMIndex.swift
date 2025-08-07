//
//  ROMIndex.swift
//  RomKit
//
//  Multi-source ROM indexing and cataloging system
//

import Foundation

/// Represents a single indexed ROM with its location and metadata
public struct IndexedROM {
    public let name: String
    public let size: UInt64
    public let crc32: String
    public let sha1: String?
    public let md5: String?
    public let location: ROMLocation
    public let lastModified: Date

    public init(
        name: String,
        size: UInt64,
        crc32: String,
        sha1: String? = nil,
        md5: String? = nil,
        location: ROMLocation,
        lastModified: Date = Date()
    ) {
        self.name = name
        self.size = size
        self.crc32 = crc32
        self.sha1 = sha1
        self.md5 = md5
        self.location = location
        self.lastModified = lastModified
    }
}

/// Describes where a ROM is located
public enum ROMLocation: Codable, Hashable {
    case archive(path: URL, entryPath: String) // ZIP/7z file with internal path
    case file(path: URL)                       // Loose file on disk
    case remote(url: URL, credentials: String?) // Network location (NAS/SMB/HTTP)

    public var displayPath: String {
        switch self {
        case .archive(let path, let entry):
            return "\(path.path)#\(entry)"
        case .file(let path):
            return path.path
        case .remote(let url, _):
            return url.absoluteString
        }
    }

    public var isLocal: Bool {
        switch self {
        case .archive, .file:
            return true
        case .remote:
            return false
        }
    }
}

/// Main ROM indexing system that catalogs ROMs from multiple sources
public actor ROMIndex {

    // MARK: - Properties

    /// All indexed ROMs by CRC32 for fast lookup
    private var romsByCRC: [String: [IndexedROM]] = [:]

    /// All indexed ROMs by name for name-based lookup
    private var romsByName: [String: [IndexedROM]] = [:]

    /// Source directories being indexed
    private var sourcePaths: Set<URL> = []

    /// Cache file for persistence
    private let cacheURL: URL?

    /// Statistics
    public private(set) var totalROMs: Int = 0
    public private(set) var totalSize: UInt64 = 0
    public private(set) var duplicates: Int = 0

    // MARK: - Initialization

    public init(cacheURL: URL? = nil) {
        self.cacheURL = cacheURL

        // Try to load cached index
        if let cacheURL = cacheURL {
            Task {
                try? await loadCache(from: cacheURL)
            }
        }
    }

    // MARK: - Indexing Operations

    /// Index ROMs from multiple source directories
    public func indexSources(_ sources: [URL], showProgress: Bool = false) async throws {
        for source in sources {
            if showProgress {
                print("📂 Indexing: \(source.path)")
            }

            try await indexDirectory(source, showProgress: showProgress)
            sourcePaths.insert(source)
        }

        // Save to cache after indexing
        if let cacheURL = cacheURL {
            try await saveCache(to: cacheURL)
        }

        if showProgress {
            printStatistics()
        }
    }

    /// Index a single directory recursively
    public func indexDirectory(_ directory: URL, showProgress: Bool = false) async throws {
        let scanner = ConcurrentScanner()
        let results = try await scanner.scanDirectory(
            at: directory,
            computeHashes: true
        )

        var processedCount = 0
        let totalCount = results.count

        for result in results {
            if showProgress && processedCount % 100 == 0 {
                print("  Processing: \(processedCount)/\(totalCount) files...")
            }

            if result.isArchive {
                // Index contents of archive
                try await indexArchive(at: result.url)
            } else if isROMFile(url: result.url) {
                // For loose ROM files, compute hash if available
                var crc32 = ""
                if let hash = result.hash {
                    crc32 = hash // Assuming hash is CRC32
                } else if result.size < 10_000_000 { // Compute for small files
                    let data = try Data(contentsOf: result.url)
                    crc32 = HashUtilities.crc32(data: data)
                }

                let rom = IndexedROM(
                    name: result.url.lastPathComponent,
                    size: result.size,
                    crc32: crc32,
                    sha1: nil,
                    md5: nil,
                    location: .file(path: result.url),
                    lastModified: result.modificationDate
                )
                addROM(rom)
            }

            processedCount += 1
        }
    }

    /// Index contents of an archive file
    private func indexArchive(at url: URL) async throws {
        let handler: ArchiveHandler

        switch url.pathExtension.lowercased() {
        case "zip":
            handler = ParallelZIPArchiveHandler()
        case "7z":
            handler = SevenZipArchiveHandler()
        default:
            return // Unsupported archive type
        }

        guard handler.canHandle(url: url) else { return }

        let entries = try handler.listContents(of: url)

        for entry in entries {
            // Skip non-ROM files in archives
            guard isROMFile(url: URL(fileURLWithPath: entry.path)) else { continue }

            // For performance, we'll compute hashes on-demand during rebuild/repair
            let rom = IndexedROM(
                name: URL(fileURLWithPath: entry.path).lastPathComponent,
                size: entry.uncompressedSize,
                crc32: entry.crc32 ?? "",
                sha1: nil, // Compute on-demand
                md5: nil,  // Compute on-demand
                location: .archive(path: url, entryPath: entry.path),
                lastModified: entry.modificationDate ?? Date()
            )
            addROM(rom)
        }
    }

    /// Add a ROM to the index
    private func addROM(_ rom: IndexedROM) {
        // Index by CRC32
        if !rom.crc32.isEmpty {
            if romsByCRC[rom.crc32] != nil {
                romsByCRC[rom.crc32]?.append(rom)
                duplicates += 1
            } else {
                romsByCRC[rom.crc32] = [rom]
            }
        }

        // Index by name
        let normalizedName = rom.name.lowercased()
        if romsByName[normalizedName] != nil {
            romsByName[normalizedName]?.append(rom)
        } else {
            romsByName[normalizedName] = [rom]
        }

        totalROMs += 1
        totalSize += rom.size
    }

    // MARK: - Search Operations

    /// Find ROMs by CRC32
    public func findByCRC(_ crc32: String) -> [IndexedROM] {
        return romsByCRC[crc32.lowercased()] ?? []
    }

    /// Find ROMs by name (case-insensitive)
    public func findByName(_ name: String) -> [IndexedROM] {
        return romsByName[name.lowercased()] ?? []
    }

    /// Find best match for a ROM requirement
    public func findBestMatch(for rom: ROM) -> IndexedROM? {
        // First try CRC32 match (most reliable)
        if let crc = rom.crc {
            let matches = findByCRC(crc)

            // Prefer local files over remote
            if let localMatch = matches.first(where: { $0.location.isLocal }) {
                return localMatch
            }

            return matches.first
        }

        // Fall back to name match
        let matches = findByName(rom.name)

        // Filter by size if available
        let sizeMatches = matches.filter { $0.size == rom.size }

        if !sizeMatches.isEmpty {
            // Prefer local files
            if let localMatch = sizeMatches.first(where: { $0.location.isLocal }) {
                return localMatch
            }
            return sizeMatches.first
        }

        // Return any name match as last resort
        return matches.first
    }

    /// Find all available sources for a ROM
    public func findAllSources(for rom: ROM) -> [IndexedROM] {
        var sources: [IndexedROM] = []

        // Add CRC matches
        if let crc = rom.crc {
            sources.append(contentsOf: findByCRC(crc))
        }

        // Add name+size matches if not already included
        let nameMatches = findByName(rom.name).filter { $0.size == rom.size }
        for match in nameMatches where !sources.contains(where: { $0.location == match.location }) {
            sources.append(match)
        }

        // Sort by preference: local files first, then archives, then remote
        return sources.sorted { lhs, rhs in
            switch (lhs.location, rhs.location) {
            case (.file, _):
                return true
            case (_, .file):
                return false
            case (.archive, .remote):
                return true
            case (.remote, .archive):
                return false
            default:
                return false
            }
        }
    }

    // MARK: - Cache Management

    /// Save index to cache file
    public func saveCache(to url: URL) async throws {
        let cache = IndexCache(
            romsByCRC: romsByCRC,
            romsByName: romsByName,
            sourcePaths: Array(sourcePaths),
            totalROMs: totalROMs,
            totalSize: totalSize,
            duplicates: duplicates,
            timestamp: Date()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(cache)
        try data.write(to: url)
    }

    /// Load index from cache file
    public func loadCache(from url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let cache = try decoder.decode(IndexCache.self, from: data)

        // Check if cache is recent (within 24 hours)
        let age = Date().timeIntervalSince(cache.timestamp)
        if age > 86400 { // 24 hours
            print("⚠️ Cache is \(Int(age/3600)) hours old, consider re-indexing")
        }

        self.romsByCRC = cache.romsByCRC
        self.romsByName = cache.romsByName
        self.sourcePaths = Set(cache.sourcePaths)
        self.totalROMs = cache.totalROMs
        self.totalSize = cache.totalSize
        self.duplicates = cache.duplicates
    }

    /// Clear the index
    public func clear() {
        romsByCRC.removeAll()
        romsByName.removeAll()
        sourcePaths.removeAll()
        totalROMs = 0
        totalSize = 0
        duplicates = 0
    }

    /// Refresh index for specific sources
    public func refresh(sources: [URL]? = nil) async throws {
        let sourcesToRefresh = sources ?? Array(sourcePaths)

        // Clear existing entries from these sources
        if sources != nil {
            // TODO: Implement selective clearing
        } else {
            clear()
        }

        // Re-index
        try await indexSources(sourcesToRefresh, showProgress: true)
    }

    // MARK: - Statistics

    public func printStatistics() {
        print("\n📊 Index Statistics:")
        print("  Total ROMs: \(totalROMs)")
        print("  Total Size: \(formatBytes(totalSize))")
        print("  Unique CRCs: \(romsByCRC.count)")
        print("  Duplicates: \(duplicates)")
        print("  Sources: \(sourcePaths.count)")
    }

    public func getStatistics() -> IndexStatistics {
        return IndexStatistics(
            totalROMs: totalROMs,
            totalSize: totalSize,
            uniqueCRCs: romsByCRC.count,
            duplicates: duplicates,
            sources: sourcePaths.count,
            newROMs: 0
        )
    }

    // MARK: - Helpers

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

// MARK: - Supporting Types

/// Cache structure for persisting index
struct IndexCache: Codable {
    let romsByCRC: [String: [IndexedROM]]
    let romsByName: [String: [IndexedROM]]
    let sourcePaths: [URL]
    let totalROMs: Int
    let totalSize: UInt64
    let duplicates: Int
    let timestamp: Date
}

// Make IndexedROM Codable for caching
extension IndexedROM: Codable {}

// SevenZipArchiveHandler is already defined in ArchiveHandlers.swift
