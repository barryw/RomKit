//
//  RomKitErrors.swift
//  RomKit
//
//  Comprehensive error handling for RomKit
//

import Foundation

// MARK: - Base Error Protocol

public protocol RomKitErrorProtocol: LocalizedError {
    var category: ErrorCategory { get }
    var severity: ErrorSeverity { get }
    var suggestedRecovery: String? { get }
}

public enum ErrorCategory {
    case configuration
    case fileSystem
    case parsing
    case validation
    case scanning
    case rebuilding
    case database
    case network
    case archive
}

public enum ErrorSeverity {
    case critical   // Operation cannot continue
    case error      // Operation failed but app can continue
    case warning    // Operation succeeded with issues
    case info       // Informational only
}

// MARK: - Configuration Errors

public enum ConfigurationError: RomKitErrorProtocol {
    case missingCacheDirectory
    case invalidPath(String)
    case missingConfiguration(String)
    case invalidConfiguration(key: String, value: String)

    public var category: ErrorCategory { .configuration }

    public var severity: ErrorSeverity {
        switch self {
        case .missingCacheDirectory:
            return .critical
        case .invalidPath:
            return .error
        case .missingConfiguration:
            return .error
        case .invalidConfiguration:
            return .warning
        }
    }

    public var errorDescription: String? {
        switch self {
        case .missingCacheDirectory:
            return "Unable to locate cache directory"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .missingConfiguration(let key):
            return "Missing required configuration: \(key)"
        case .invalidConfiguration(let key, let value):
            return "Invalid configuration for \(key): \(value)"
        }
    }

    public var suggestedRecovery: String? {
        switch self {
        case .missingCacheDirectory:
            return "Ensure the application has proper permissions to access the cache directory"
        case .invalidPath:
            return "Verify the path exists and is accessible"
        case .missingConfiguration(let key):
            return "Add the required configuration key: \(key)"
        case .invalidConfiguration:
            return "Check the configuration value format and try again"
        }
    }
}

// MARK: - File System Errors

public enum FileSystemError: RomKitErrorProtocol {
    case fileNotFound(URL)
    case directoryNotFound(URL)
    case insufficientPermissions(URL)
    case diskFull
    case fileCorrupted(URL, reason: String?)
    case writeFailed(URL, underlyingError: Error?)

    public var category: ErrorCategory { .fileSystem }

    public var severity: ErrorSeverity {
        switch self {
        case .diskFull:
            return .critical
        case .fileCorrupted:
            return .error
        default:
            return .error
        }
    }

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .directoryNotFound(let url):
            return "Directory not found: \(url.path)"
        case .insufficientPermissions(let url):
            return "Insufficient permissions to access: \(url.path)"
        case .diskFull:
            return "Insufficient disk space available"
        case .fileCorrupted(let url, let reason):
            return "File corrupted: \(url.lastPathComponent)\(reason.map { " - \($0)" } ?? "")"
        case .writeFailed(let url, let error):
            return "Failed to write to: \(url.path)\(error.map { " - \($0.localizedDescription)" } ?? "")"
        }
    }

    public var suggestedRecovery: String? {
        switch self {
        case .fileNotFound, .directoryNotFound:
            return "Verify the path exists and try again"
        case .insufficientPermissions:
            return "Check file permissions and ensure the app has access"
        case .diskFull:
            return "Free up disk space and try again"
        case .fileCorrupted:
            return "Try re-downloading or restoring the file from backup"
        case .writeFailed:
            return "Check disk space and permissions, then try again"
        }
    }
}

// MARK: - Parsing Errors

public enum ParsingError: RomKitErrorProtocol {
    case invalidFormat(String)
    case unsupportedVersion(String)
    case malformedXML(line: Int?, column: Int?, reason: String)
    case missingRequiredField(String)
    case invalidDataType(field: String, expected: String, got: String)

    public var category: ErrorCategory { .parsing }

    public var severity: ErrorSeverity {
        switch self {
        case .missingRequiredField:
            return .warning
        default:
            return .error
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let format):
            return "Invalid or unrecognized format: \(format)"
        case .unsupportedVersion(let version):
            return "Unsupported format version: \(version)"
        case .malformedXML(let line, let column, let reason):
            let location = [line.map { "line \($0)" }, column.map { "column \($0)" }]
                .compactMap { $0 }
                .joined(separator: ", ")
            return "Malformed XML\(location.isEmpty ? "" : " at \(location)"): \(reason)"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidDataType(let field, let expected, let got):
            return "Invalid data type for \(field): expected \(expected), got \(got)"
        }
    }

    public var suggestedRecovery: String? {
        switch self {
        case .invalidFormat:
            return "Ensure the file is in a supported DAT format (MAME, Logiqx, NoIntro, Redump)"
        case .unsupportedVersion:
            return "Try updating RomKit or converting the file to a supported version"
        case .malformedXML:
            return "Validate the XML file and fix any syntax errors"
        case .missingRequiredField:
            return "Add the missing field to the DAT file"
        case .invalidDataType:
            return "Correct the data type in the source file"
        }
    }
}

// MARK: - Scanning Errors

public enum ScanningError: RomKitErrorProtocol {
    case noResultsFound
    case scanCancelled
    case invalidROMStructure(URL, reason: String)
    case duplicateROM(name: String, locations: [URL])
    case missingDependency(String)

    public var category: ErrorCategory { .scanning }

    public var severity: ErrorSeverity {
        switch self {
        case .scanCancelled:
            return .info
        case .duplicateROM:
            return .warning
        default:
            return .error
        }
    }

    public var errorDescription: String? {
        switch self {
        case .noResultsFound:
            return "No ROMs found during scan"
        case .scanCancelled:
            return "Scan was cancelled by user"
        case .invalidROMStructure(let url, let reason):
            return "Invalid ROM structure in \(url.lastPathComponent): \(reason)"
        case .duplicateROM(let name, let locations):
            return "Duplicate ROM '\(name)' found in \(locations.count) locations"
        case .missingDependency(let dependency):
            return "Missing required dependency: \(dependency)"
        }
    }

    public var suggestedRecovery: String? {
        switch self {
        case .noResultsFound:
            return "Verify the scan directory contains ROM files"
        case .scanCancelled:
            return nil
        case .invalidROMStructure:
            return "Check the ROM file structure and repair if necessary"
        case .duplicateROM:
            return "Consider removing duplicate files to save space"
        case .missingDependency:
            return "Install or locate the missing dependency"
        }
    }
}

// MARK: - Archive Errors

public enum ArchiveHandlingError: RomKitErrorProtocol {
    case unsupportedFormat(String)
    case corruptedArchive(URL, details: String?)
    case extractionFailed(URL, reason: String)
    case compressionFailed(reason: String)
    case invalidFileName(String)
    case passwordProtected(URL)

    public var category: ErrorCategory { .archive }

    public var severity: ErrorSeverity {
        switch self {
        case .passwordProtected:
            return .warning
        default:
            return .error
        }
    }

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "Unsupported archive format: \(format)"
        case .corruptedArchive(let url, let details):
            return "Corrupted archive: \(url.lastPathComponent)\(details.map { " - \($0)" } ?? "")"
        case .extractionFailed(let url, let reason):
            return "Failed to extract \(url.lastPathComponent): \(reason)"
        case .compressionFailed(let reason):
            return "Compression failed: \(reason)"
        case .invalidFileName(let name):
            return "Invalid file name in archive: \(name)"
        case .passwordProtected(let url):
            return "Archive is password protected: \(url.lastPathComponent)"
        }
    }

    public var suggestedRecovery: String? {
        switch self {
        case .unsupportedFormat:
            return "Convert the archive to ZIP format"
        case .corruptedArchive:
            return "Re-download or repair the archive"
        case .extractionFailed:
            return "Check disk space and permissions"
        case .compressionFailed:
            return "Check disk space and try again"
        case .invalidFileName:
            return "Rename the file to use valid characters"
        case .passwordProtected:
            return "Provide the password or use an unprotected archive"
        }
    }
}

// MARK: - Database Errors

public enum DatabaseError: RomKitErrorProtocol {
    case connectionFailed(String)
    case queryFailed(String, underlyingError: Error?)
    case corruptedDatabase
    case migrationFailed(from: Int, to: Int, reason: String)
    case transactionFailed(String)
    case databaseLocked
    case databaseError(String)
    case invalidPath(String)

    public var category: ErrorCategory { .database }

    public var severity: ErrorSeverity {
        switch self {
        case .corruptedDatabase:
            return .critical
        case .databaseLocked:
            return .warning
        default:
            return .error
        }
    }

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "Database connection failed: \(reason)"
        case .queryFailed(let query, let error):
            return "Query failed: \(query)\(error.map { " - \($0.localizedDescription)" } ?? "")"
        case .corruptedDatabase:
            return "Database is corrupted and cannot be read"
        case .migrationFailed(let from, let to, let reason):
            return "Migration failed from version \(from) to \(to): \(reason)"
        case .transactionFailed(let reason):
            return "Transaction failed: \(reason)"
        case .databaseLocked:
            return "Database is locked by another process"
        case .databaseError(let message):
            return "Database error: \(message)"
        case .invalidPath(let path):
            return "Invalid database path: \(path)"
        }
    }

    public var suggestedRecovery: String? {
        switch self {
        case .connectionFailed:
            return "Check database path and permissions"
        case .queryFailed:
            return "Review the query syntax and try again"
        case .corruptedDatabase:
            return "Restore from backup or rebuild the database"
        case .migrationFailed:
            return "Restore from backup and try updating again"
        case .transactionFailed:
            return "Retry the operation"
        case .databaseLocked:
            return "Close other applications using the database"
        case .databaseError, .invalidPath:
            return "Check the database configuration"
        }
    }
}

// MARK: - Validation Errors

public enum ValidationError: RomKitErrorProtocol {
    case checksumMismatch(expected: String, got: String)
    case sizeMismatch(expected: UInt64, got: UInt64)
    case missingRequiredROM(String)
    case invalidROMContent(String)
    case validationSkipped(reason: String)

    public var category: ErrorCategory { .validation }

    public var severity: ErrorSeverity {
        switch self {
        case .validationSkipped:
            return .info
        case .checksumMismatch, .sizeMismatch:
            return .error
        default:
            return .warning
        }
    }

    public var errorDescription: String? {
        switch self {
        case .checksumMismatch(let expected, let got):
            return "Checksum mismatch: expected \(expected), got \(got)"
        case .sizeMismatch(let expected, let got):
            return "Size mismatch: expected \(expected) bytes, got \(got) bytes"
        case .missingRequiredROM(let name):
            return "Missing required ROM: \(name)"
        case .invalidROMContent(let reason):
            return "Invalid ROM content: \(reason)"
        case .validationSkipped(let reason):
            return "Validation skipped: \(reason)"
        }
    }

    public var suggestedRecovery: String? {
        switch self {
        case .checksumMismatch, .sizeMismatch:
            return "Re-download the ROM or verify the source"
        case .missingRequiredROM:
            return "Locate and add the missing ROM file"
        case .invalidROMContent:
            return "Verify the ROM file integrity"
        case .validationSkipped:
            return nil
        }
    }
}

// MARK: - Error Collection

public struct ErrorCollection {
    private var errors: [RomKitErrorProtocol] = []

    public var count: Int { errors.count }
    public var isEmpty: Bool { errors.isEmpty }

    public var criticalErrors: [RomKitErrorProtocol] {
        errors.filter { $0.severity == .critical }
    }

    public var hasCriticalErrors: Bool {
        !criticalErrors.isEmpty
    }

    public mutating func append(_ error: RomKitErrorProtocol) {
        errors.append(error)
    }

    public mutating func append(contentsOf newErrors: [RomKitErrorProtocol]) {
        errors.append(contentsOf: newErrors)
    }

    public func grouped(by category: ErrorCategory) -> [RomKitErrorProtocol] {
        errors.filter { $0.category == category }
    }

    public func formatted() -> String {
        errors.map { error in
            let severity = switch error.severity {
            case .critical: "❌ CRITICAL"
            case .error: "⛔ ERROR"
            case .warning: "⚠️ WARNING"
            case .info: "ℹ️ INFO"
            }

            var message = "\(severity): \(error.localizedDescription)"
            if let recovery = error.suggestedRecovery {
                message += "\n  💡 \(recovery)"
            }
            return message
        }.joined(separator: "\n")
    }
}
