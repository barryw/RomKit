//
//  Lib7zArchiveHandler.swift
//  RomKit
//
//  7-Zip archive handler using lib7z
//

import Foundation
import Lib7z

public final class SevenZipArchiveHandler: ArchiveHandler, @unchecked Sendable {
    public let supportedExtensions = ["7z"]
    
    static let shared = SevenZipArchiveHandler()
    
    public init() {
        // Initialize lib7z once
        _ = Lib7zInitializer.shared
    }
    
    public func canHandle(url: URL) -> Bool {
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
            return false
        }
        
        // If file doesn't exist, return false
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        
        // Check if it's a valid 7z file
        return url.withUnsafeFileSystemRepresentation { path in
            guard let path = path else { return false }
            return lib7z_is_valid_archive(path) != 0
        }
    }
    
    public func listContents(of url: URL) throws -> [ArchiveEntry] {
        return try url.withUnsafeFileSystemRepresentation { path in
            guard let path = path else {
                throw ArchiveError.cannotOpenArchive(url.path)
            }
            
            
            guard let archive = lib7z_open_archive(path) else {
                throw ArchiveError.cannotOpenArchive("Failed to open 7z archive")
            }
            defer { lib7z_close_archive(archive) }
            
            let numEntries = lib7z_get_num_entries(archive)
            var entries: [ArchiveEntry] = []
            
            for index in 0..<numEntries {
                var entry = lib7z_entry_t()
                guard lib7z_get_entry_info(archive, index, &entry) != 0 else {
                    continue
                }
                
                // Skip directories
                if entry.is_directory != 0 {
                    continue
                }
                
                let path = withUnsafeBytes(of: entry.path) { bytes in
                    guard let ptr = bytes.bindMemory(to: CChar.self).baseAddress else {
                        return ""
                    }
                    return String(cString: ptr)
                }
                
                entries.append(ArchiveEntry(
                    path: path,
                    compressedSize: entry.size, // 7z doesn't expose per-file compressed size
                    uncompressedSize: entry.size,
                    modificationDate: entry.has_mtime != 0 ? Date(timeIntervalSince1970: TimeInterval(entry.mtime)) : nil,
                    crc32: entry.has_crc32 != 0 ? String(format: "%08x", entry.crc32) : nil
                ))
            }
            
            return entries
        }
    }
    
    public func extract(entry: ArchiveEntry, from url: URL) throws -> Data {
        return try url.withUnsafeFileSystemRepresentation { archivePath in
            guard let archivePath = archivePath else {
                throw ArchiveError.cannotOpenArchive(url.path)
            }
            
            guard let archive = lib7z_open_archive(archivePath) else {
                throw ArchiveError.cannotOpenArchive("Failed to open 7z archive")
            }
            defer { lib7z_close_archive(archive) }
            
            // Find entry by path
            let numEntries = lib7z_get_num_entries(archive)
            var targetIndex: Int? = nil
            
            for index in 0..<numEntries {
                var entryInfo = lib7z_entry_t()
                guard lib7z_get_entry_info(archive, index, &entryInfo) != 0 else {
                    continue
                }
                
                let entryPath = withUnsafeBytes(of: entryInfo.path) { bytes in
                    guard let ptr = bytes.bindMemory(to: CChar.self).baseAddress else {
                        return ""
                    }
                    return String(cString: ptr)
                }
                if entryPath == entry.path {
                    targetIndex = index
                    break
                }
            }
            
            guard let index = targetIndex else {
                throw ArchiveError.entryNotFound(entry.path)
            }
            
            // Extract to memory
            var result = lib7z_extract_to_memory(archive, index)
            defer { lib7z_free_extract_result(&result) }
            
            guard result.success != 0, let data = result.data else {
                throw ArchiveError.extractionFailed("Failed to extract file from 7z")
            }
            
            return Data(bytes: data, count: result.size)
        }
    }
    
    public func extractAll(from url: URL, to destination: URL) throws {
        let entries = try listContents(of: url)
        
        // Create destination directory if needed
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        
        for entry in entries {
            let data = try extract(entry: entry, from: url)
            let outputPath = destination.appendingPathComponent(entry.path)
            
            // Create parent directories if needed
            let parentDir = outputPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            
            // Write file
            try data.write(to: outputPath)
            
            // Set modification date if available
            if let modDate = entry.modificationDate {
                try FileManager.default.setAttributes([.modificationDate: modDate], ofItemAtPath: outputPath.path)
            }
        }
    }
    
    public func create(at url: URL, with entries: [(name: String, data: Data)]) throws {
        // 7z creation is complex and not needed for ROM management
        throw ArchiveError.unsupportedFormat("7z creation not implemented - use ZIP for creating archives")
    }
    
    // Batch extraction for performance
    public func extractMultiple(entries: [ArchiveEntry], from url: URL) async throws -> [String: Data] {
        var results: [String: Data] = [:]
        
        // Extract each file
        for entry in entries {
            let data = try extract(entry: entry, from: url)
            results[entry.path] = data
        }
        
        return results
    }
}

// MARK: - Lib7z Initializer

private final class Lib7zInitializer: @unchecked Sendable {
    static let shared = Lib7zInitializer()
    
    private init() {
        lib7z_init()
    }
    
    deinit {
        lib7z_cleanup()
    }
}

// MARK: - Data CRC32 Extension (if not already defined)

extension Data {
    func crc32() -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        
        for byte in self {
            crc = crc ^ UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (0xEDB88320 & (0 - (crc & 1)))
            }
        }
        
        return crc ^ 0xFFFFFFFF
    }
}