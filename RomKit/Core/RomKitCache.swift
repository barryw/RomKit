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
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {
        // Use app support directory for cache
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        self.cacheDirectory = appSupport.appendingPathComponent("RomKit/Cache")

        // Create cache directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory,
                                                withIntermediateDirectories: true)
    }

    /// Get cache key for a DAT file
    private func cacheKey(for url: URL) -> String {
        // Use file path and modification date as key
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modDate = attributes?[.modificationDate] as? Date ?? Date()
        let timestamp = Int(modDate.timeIntervalSince1970)

        let path = url.path.replacingOccurrences(of: "/", with: "_")
        return "\(path)_\(timestamp).cache"
    }

    /// Check if cached version exists and is valid
    public func hasCached(for datURL: URL) -> Bool {
        let key = cacheKey(for: datURL)
        let cachePath = cacheDirectory.appendingPathComponent(key)
        return FileManager.default.fileExists(atPath: cachePath.path)
    }

    /// Save parsed DAT to cache
    public func save(_ datFile: MAMEDATFile, for datURL: URL) {
        let key = cacheKey(for: datURL)
        let cachePath = cacheDirectory.appendingPathComponent(key)

        // Convert to cacheable format
        let cacheData = CachedDAT(
            version: 1,
            sourceURL: datURL.path,
            parseDate: Date(),
            datFile: datFile
        )

        do {
            // For now, use JSON (could use binary later)
            let data = try encoder.encode(cacheData)
            try data.write(to: cachePath)

            print("Cached DAT file: \(cachePath.lastPathComponent)")
            print("  Size: \(data.count / 1024 / 1024) MB")

            // Clean old cache files
            cleanOldCaches(except: key)
        } catch {
            print("Failed to cache DAT: \(error)")
        }
    }

    /// Load cached DAT
    public func load(for datURL: URL) -> MAMEDATFile? {
        let key = cacheKey(for: datURL)
        let cachePath = cacheDirectory.appendingPathComponent(key)

        do {
            let data = try Data(contentsOf: cachePath)
            let cacheData = try decoder.decode(CachedDAT.self, from: data)

            print("Loaded cached DAT from: \(cachePath.lastPathComponent)")
            return cacheData.datFile
        } catch {
            print("Failed to load cache: \(error)")
            return nil
        }
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.formatVersion = try container.decode(String.self, forKey: .formatVersion)
        self.games = try container.decode([MAMEGame].self, forKey: .games)
        self.metadata = try container.decode(MAMEMetadata.self, forKey: .metadata)
    }

    public func encode(to encoder: Encoder) throws {
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try container.decodeIfPresent(String.self, forKey: .identifier) ?? ""
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decode(String.self, forKey: .description)
        self.items = try container.decode([MAMEROM].self, forKey: .items)
        self.metadata = try container.decode(MAMEGameMetadata.self, forKey: .metadata)
        self.disks = try container.decodeIfPresent([MAMEDisk].self, forKey: .disks) ?? []
        self.samples = try container.decodeIfPresent([MAMESample].self, forKey: .samples) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(items as? [MAMEROM] ?? [], forKey: .items)
        try container.encode(metadata as? MAMEGameMetadata, forKey: .metadata)
        try container.encode(disks, forKey: .disks)
        try container.encode(samples, forKey: .samples)
    }
}
