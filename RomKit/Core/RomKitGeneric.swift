//
//  RomKitGeneric.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation

// MARK: - Generic RomKit Implementation

public class RomKitGeneric {
    internal var datFile: (any DATFormat)?
    private var formatHandler: (any ROMFormatHandler)?
    private var scanner: (any ROMScanner)?
    private var rebuilder: (any ROMRebuilder)?
    private let registry = RomKitFormatRegistry.shared

    public init() {}

    // MARK: - DAT Loading

    public func loadDAT(from path: String, format: String? = nil) throws {
        let url = URL(fileURLWithPath: path)
        try loadDAT(from: url, format: format)
    }

    public func loadDAT(from url: URL, format: String? = nil) throws {
        let handler: any ROMFormatHandler

        if let formatId = format {
            guard let hdlr = registry.handler(for: formatId) else {
                throw RomKitGenericError.unsupportedFormat(formatId)
            }
            handler = hdlr
        } else {
            guard let hdlr = try registry.detectFormat(from: url) else {
                throw RomKitGenericError.formatDetectionFailed
            }
            handler = hdlr
        }

        let parser = handler.createParser()
        let dat = try parser.parse(url: url)

        self.datFile = dat
        self.formatHandler = handler
        self.scanner = handler.createScanner(for: dat)
        self.rebuilder = handler.createRebuilder(for: dat)
    }

    public func loadDAT(data: Data, format: String? = nil) throws {
        let handler: any ROMFormatHandler

        if let formatId = format {
            guard let hdlr = registry.handler(for: formatId) else {
                throw RomKitGenericError.unsupportedFormat(formatId)
            }
            handler = hdlr
        } else {
            guard let hdlr = registry.detectFormat(from: data) else {
                throw RomKitGenericError.formatDetectionFailed
            }
            handler = hdlr
        }

        let parser = handler.createParser()
        let dat = try parser.parse(data: data)

        self.datFile = dat
        self.formatHandler = handler
        self.scanner = handler.createScanner(for: dat)
        self.rebuilder = handler.createRebuilder(for: dat)
    }

    // MARK: - Scanning

    public func scan(directory: String) async throws -> (any ScanResults)? {
        guard let scanner = scanner else {
            throw RomKitGenericError.datNotLoaded
        }

        let url = URL(fileURLWithPath: directory)
        return try await scanner.scan(directory: url)
    }

    public func scan(files: [URL]) async throws -> (any ScanResults)? {
        guard let scanner = scanner else {
            throw RomKitGenericError.datNotLoaded
        }

        return try await scanner.scan(files: files)
    }

    // MARK: - Rebuilding

    public func rebuild(
        from source: String,
        to destination: String,
        options: RebuildOptions = RebuildOptions()
    ) async throws -> RebuildResults? {
        guard let rebuilder = rebuilder else {
            throw RomKitGenericError.datNotLoaded
        }

        let sourceURL = URL(fileURLWithPath: source)
        let destinationURL = URL(fileURLWithPath: destination)

        return try await rebuilder.rebuild(
            from: sourceURL,
            to: destinationURL,
            options: options
        )
    }

    // MARK: - Auditing

    public func generateAuditReport(from scanResults: any ScanResults) -> GenericAuditReport {
        var completeGames = 0
        var incompleteGames = 0
        var missingGames = 0
        var totalItems = 0
        var foundItems = 0
        var missingItems = 0

        for game in scanResults.foundGames {
            switch game.status {
            case .complete:
                completeGames += 1
            case .incomplete:
                incompleteGames += 1
            case .missing:
                missingGames += 1
            case .unknown:
                break
            }

            totalItems += game.foundItems.count + game.missingItems.count
            foundItems += game.foundItems.count
            missingItems += game.missingItems.count
        }

        return GenericAuditReport(
            scanDate: scanResults.scanDate,
            scannedPath: scanResults.scannedPath,
            totalGames: scanResults.foundGames.count,
            completeGames: completeGames,
            incompleteGames: incompleteGames,
            missingGames: missingGames,
            totalItems: totalItems,
            foundItems: foundItems,
            missingItems: missingItems,
            unknownFiles: scanResults.unknownFiles.count,
            errors: scanResults.errors.count
        )
    }

    // MARK: - Properties

    public var currentFormat: String? {
        return formatHandler?.formatName
    }

    public var currentDATFile: (any DATFormat)? {
        return datFile
    }

    public var isLoaded: Bool {
        return datFile != nil
    }

    public var availableFormats: [String] {
        return registry.availableFormats
    }
}

// MARK: - Generic Audit Report

public struct GenericAuditReport: Codable {
    public let scanDate: Date
    public let scannedPath: String
    public let totalGames: Int
    public let completeGames: Int
    public let incompleteGames: Int
    public let missingGames: Int
    public let totalItems: Int
    public let foundItems: Int
    public let missingItems: Int
    public let unknownFiles: Int
    public let errors: Int

    public var completionPercentage: Double {
        guard totalGames > 0 else { return 0 }
        return (Double(completeGames) / Double(totalGames)) * 100.0
    }

    public var itemCompletionPercentage: Double {
        guard totalItems > 0 else { return 0 }
        return (Double(foundItems) / Double(totalItems)) * 100.0
    }
}

// MARK: - Errors

public enum RomKitGenericError: Error, LocalizedError {
    case datNotLoaded
    case unsupportedFormat(String)
    case formatDetectionFailed
    case scanFailed(String)
    case rebuildFailed(String)

    public var errorDescription: String? {
        switch self {
        case .datNotLoaded:
            return "No DAT file loaded. Please load a DAT file first."
        case .unsupportedFormat(let format):
            return "Unsupported format: \(format)"
        case .formatDetectionFailed:
            return "Could not detect DAT file format"
        case .scanFailed(let reason):
            return "Scan failed: \(reason)"
        case .rebuildFailed(let reason):
            return "Rebuild failed: \(reason)"
        }
    }
}
