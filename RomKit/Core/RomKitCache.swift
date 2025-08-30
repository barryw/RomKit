//
//  RomKitCache.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation

/// Caches parsed DAT files to avoid re-parsing
public class RomKitCache {

    private let cacheDirectory: URL
    private let queue = DispatchQueue(label: "com.romkit.cache", attributes: .concurrent)

    public init() {
        // Use app support directory for cache, or temp directory as fallback
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first {
            self.cacheDirectory = appSupport.appendingPathComponent("RomKit/Cache")
        } else {
            // Fallback to temp directory (for CI or restricted environments)
            self.cacheDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("RomKit/Cache")
        }

        // Create cache directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory,
                                                withIntermediateDirectories: true)
    }

    /// Get cache key for a DAT file
    private func cacheKey(for url: URL) -> String {
        // Use file path and modification date as key
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modDate = attributes?[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        let timestamp = Int(modDate.timeIntervalSince1970)

        // Sanitize path for use as filename
        let path = url.path
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        // Ensure reasonable filename length
        let truncatedPath = String(path.prefix(200))
        return "\(truncatedPath)_\(timestamp).cache"
    }

    /// Check if cached version exists and is valid
    public func hasCached(for datURL: URL) -> Bool {
        let key = cacheKey(for: datURL)
        let cacheFile = cacheDirectory.appendingPathComponent(key)
        return FileManager.default.fileExists(atPath: cacheFile.path)
    }

    /// Save parsed DAT to cache (synchronous for testing)
    public func save(_ datFile: MAMEDATFile, for datURL: URL) {
        queue.sync(flags: .barrier) {
            let key = self.cacheKey(for: datURL)
            let cacheFile = self.cacheDirectory.appendingPathComponent(key)

            let cached = CachedDAT(
                version: 1,
                sourceURL: datURL.path,
                parseDate: Date(),
                datFile: datFile
            )

            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                let data = try encoder.encode(cached)
                try data.write(to: cacheFile)

                // Clean old cache files
                self.cleanOldCaches(except: key)
            } catch {
                // Silently fail - caching is optional
                print("Cache save failed: \(error)")
            }
        }
    }

    /// Load cached DAT
    public func load(for datURL: URL) -> MAMEDATFile? {
        var result: MAMEDATFile?

        queue.sync {
            let key = cacheKey(for: datURL)
            let cacheFile = cacheDirectory.appendingPathComponent(key)

            guard FileManager.default.fileExists(atPath: cacheFile.path) else {
                return
            }

            do {
                let data = try Data(contentsOf: cacheFile)
                let decoder = JSONDecoder()
                let cached = try decoder.decode(CachedDAT.self, from: data)
                result = cached.datFile
            } catch {
                // Cache load failed - delete corrupt cache
                try? FileManager.default.removeItem(at: cacheFile)
                print("Cache load failed: \(error)")
            }
        }

        return result
    }

    /// Clean old cache files for the same source
    private func cleanOldCaches(except currentKey: String) {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory,
                                                                   includingPropertiesForKeys: nil)

            // Extract base name from current key (without timestamp)
            let baseName = currentKey.replacingOccurrences(of: "_\\d+\\.cache$",
                                                          with: "",
                                                          options: .regularExpression)

            for file in files {
                let filename = file.lastPathComponent
                if filename != currentKey && filename.hasPrefix(baseName) {
                    try? FileManager.default.removeItem(at: file)
                    print("Removed old cache: \(filename)")
                }
            }
        } catch {
            // Ignore cleanup errors
        }
    }

    /// Clear all cache
    public func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory,
                                                withIntermediateDirectories: true)
        print("Cache cleared")
    }

    /// Get cache size
    public func getCacheSize() -> Int64 {
        var size: Int64 = 0

        if let enumerator = FileManager.default.enumerator(at: cacheDirectory,
                                                           includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in enumerator {
                if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    size += Int64(fileSize)
                }
            }
        }

        return size
    }
}

// MARK: - Cached DAT Structure

struct CachedDAT: Codable {
    let version: Int
    let sourceURL: String
    let parseDate: Date
    let datFile: MAMEDATFile
}

// Make MAME models Codable for caching
extension MAMEDATFile: Codable {
    enum CodingKeys: String, CodingKey {
        case formatVersion, games, metadata
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.formatVersion = try container.decode(String.self, forKey: .formatVersion)
        self.games = try container.decode([MAMEGame].self, forKey: .games)
        self.metadata = try container.decode(MAMEMetadata.self, forKey: .metadata)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(games as? [MAMEGame] ?? [], forKey: .games)
        try container.encode(metadata as? MAMEMetadata, forKey: .metadata)
    }
}

extension MAMEGame: Codable {
    enum CodingKeys: String, CodingKey {
        case identifier, name, description, items, metadata, disks, samples
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try container.decodeIfPresent(String.self, forKey: .identifier) ?? ""
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decode(String.self, forKey: .description)

        // Decode ROMs safely
        let roms = try container.decode([MAMEROM].self, forKey: .items)
        self.items = roms

        // Decode metadata safely
        let gameMetadata = try container.decode(MAMEGameMetadata.self, forKey: .metadata)
        self.metadata = gameMetadata

        self.disks = try container.decodeIfPresent([MAMEDisk].self, forKey: .disks) ?? []
        self.samples = try container.decodeIfPresent([MAMESample].self, forKey: .samples) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)

        // Only encode MAMEROM items, skip others
        let mameROMs = items.compactMap { $0 as? MAMEROM }
        try container.encode(mameROMs, forKey: .items)

        // Only encode MAMEGameMetadata, throw error for others
        guard let mameMetadata = metadata as? MAMEGameMetadata else {
            throw EncodingError.invalidValue(
                metadata,
                EncodingError.Context(
                    codingPath: encoder.codingPath + [CodingKeys.metadata],
                    debugDescription: "Expected MAMEGameMetadata but got \(type(of: metadata))"
                )
            )
        }
        try container.encode(mameMetadata, forKey: .metadata)

        try container.encode(disks, forKey: .disks)
        try container.encode(samples, forKey: .samples)
    }
}
