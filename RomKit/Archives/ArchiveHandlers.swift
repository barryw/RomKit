//
//  ArchiveHandlers.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation
import zlib

// MARK: - ZIP Archive Handler (using fast native implementation)

public typealias ZIPArchiveHandler = FastZIPArchiveHandler

// MARK: - 7-Zip Archive Handler (Stub)

public class SevenZipArchiveHandler: ArchiveHandler {
    public let supportedExtensions = ["7z"]
    
    public init() {}
    
    public func canHandle(url: URL) -> Bool {
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }
    
    public func listContents(of url: URL) throws -> [ArchiveEntry] {
        // Would require external 7z library
        throw ArchiveError.unsupportedFormat("7z support not yet implemented")
    }
    
    public func extract(entry: ArchiveEntry, from url: URL) throws -> Data {
        throw ArchiveError.unsupportedFormat("7z support not yet implemented")
    }
    
    public func extractAll(from url: URL, to destination: URL) throws {
        throw ArchiveError.unsupportedFormat("7z support not yet implemented")
    }
    
    public func create(at url: URL, with entries: [(name: String, data: Data)]) throws {
        throw ArchiveError.unsupportedFormat("7z support not yet implemented")
    }
}

// MARK: - CHD Archive Handler (Stub)

public class CHDArchiveHandler: ArchiveHandler {
    public let supportedExtensions = ["chd"]
    
    public init() {}
    
    public func canHandle(url: URL) -> Bool {
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }
    
    public func listContents(of url: URL) throws -> [ArchiveEntry] {
        // CHD files are single files, not archives
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = fileAttributes[.size] as? UInt64 ?? 0
        
        return [ArchiveEntry(
            path: url.lastPathComponent,
            compressedSize: size,
            uncompressedSize: size,
            modificationDate: fileAttributes[.modificationDate] as? Date
        )]
    }
    
    public func extract(entry: ArchiveEntry, from url: URL) throws -> Data {
        // CHD validation would require specialized handling
        throw ArchiveError.unsupportedFormat("CHD validation not yet implemented")
    }
    
    public func extractAll(from url: URL, to destination: URL) throws {
        // CHD files would just be copied
        let fileManager = FileManager.default
        let destinationFile = destination.appendingPathComponent(url.lastPathComponent)
        try fileManager.copyItem(at: url, to: destinationFile)
    }
    
    public func create(at url: URL, with entries: [(name: String, data: Data)]) throws {
        throw ArchiveError.unsupportedFormat("CHD creation not supported")
    }
}

// MARK: - Archive Errors

public enum ArchiveError: Error, LocalizedError {
    case cannotOpenArchive(String)
    case cannotCreateArchive(String)
    case entryNotFound(String)
    case unsupportedFormat(String)
    case extractionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .cannotOpenArchive(let path):
            return "Cannot open archive: \(path)"
        case .cannotCreateArchive(let path):
            return "Cannot create archive: \(path)"
        case .entryNotFound(let entry):
            return "Entry not found: \(entry)"
        case .unsupportedFormat(let message):
            return "Unsupported format: \(message)"
        case .extractionFailed(let message):
            return "Extraction failed: \(message)"
        }
    }
}