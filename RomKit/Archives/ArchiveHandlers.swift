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

// MARK: - Archive Errors

public enum ArchiveError: Error, LocalizedError {
    case cannotOpenArchive(String)
    case cannotCreateArchive(String)
    case entryNotFound(String)
    case unsupportedFormat(String)
    case extractionFailed(String)
    case invalidFileName(String)

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
        case .invalidFileName(let name):
            return "Invalid file name: \(name)"
        }
    }
}
