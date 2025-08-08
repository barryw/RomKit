//
//  GenericUsage.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation
import RomKit

// MARK: - Example Usage of Generic RomKit

func demonstrateGenericRomKit() async throws {
    
    // 1. Basic usage with auto-detection
    let romKit = RomKitGeneric()
    
    // Load a DAT file - format will be auto-detected
    try romKit.loadDAT(from: "mame.xml")
    print("Loaded format: \(romKit.currentFormat ?? "Unknown")")
    
    // Scan a directory
    if let results = try await romKit.scan(directory: "/path/to/roms") {
        print("Found \(results.foundGames.count) games")
        
        // Generate audit report
        let report = romKit.generateAuditReport(from: results)
        print("Complete: \(report.completeGames) games")
        print("Incomplete: \(report.incompleteGames) games")
        print("Missing: \(report.missingGames) games")
        print("Completion: \(report.completionPercentage)%")
    }
    
    // 2. Explicit format specification
    let noIntroKit = RomKitGeneric()
    try noIntroKit.loadDAT(from: "nintendo.dat", format: "no-intro")
    
    // 3. Using different formats
    let formats = ["mame", "no-intro", "redump"]
    
    for format in formats {
        let kit = RomKitGeneric()
        
        // Each format has its own parser, validator, scanner, etc.
        if let handler = RomKitFormatRegistry.shared.handler(for: format) {
            print("\nFormat: \(handler.formatName)")
            print("Extensions: \(handler.supportedExtensions)")
            
            // Each format can have different archive handlers
            let archiveHandlers = handler.createArchiveHandlers()
            print("Supported archives: \(archiveHandlers.map { type(of: $0) })")
        }
    }
    
    // 4. Legacy compatibility
    let legacyKit = RomKit()
    try legacyKit.loadDAT(from: "mame.xml") // Defaults to MAME
    let scanResult = try await legacyKit.scanDirectory("/path/to/roms")
    let auditReport = legacyKit.generateAuditReport(from: scanResult)
    print("Legacy audit complete: \(auditReport.completeGames.count) complete games")
}

// MARK: - Custom Format Implementation Example

// To add a new format (e.g., TOSEC), implement these protocols:

struct TOSECFormatHandler: ROMFormatHandler {
    let formatIdentifier = "tosec"
    let formatName = "TOSEC"
    let supportedExtensions = ["dat", "xml"]
    
    func createParser() -> any DATParser {
        return TOSECParser()
    }
    
    func createValidator() -> any ROMValidator {
        // Reuse MAME validator or create custom
        return MAMEROMValidator()
    }
    
    func createScanner(for datFile: any DATFormat) -> any ROMScanner {
        // Implementation would go here
        // In a real implementation, you would return a proper scanner
        // For this example, we'll throw an error instead of using fatalError
        struct NotImplementedScanner: ROMScanner {
            typealias DATType = TOSECDATFile
            let datFile: any DATFormat
            let validator: any ROMValidator
            let archiveHandlers: [any ArchiveHandler]
            
            func scan(directory: URL) async throws -> any ScanResults {
                throw NSError(domain: "TOSEC", code: -1, userInfo: [NSLocalizedDescriptionKey: "TOSEC scanner not yet implemented"])
            }
            
            func scan(files: [URL]) async throws -> any ScanResults {
                throw NSError(domain: "TOSEC", code: -1, userInfo: [NSLocalizedDescriptionKey: "TOSEC scanner not yet implemented"])
            }
        }
        return NotImplementedScanner(datFile: datFile, validator: createValidator(), archiveHandlers: createArchiveHandlers())
    }
    
    func createRebuilder(for datFile: any DATFormat) -> any ROMRebuilder {
        // Implementation would go here
        // In a real implementation, you would return a proper rebuilder
        // For this example, we'll throw an error instead of using fatalError
        struct NotImplementedRebuilder: ROMRebuilder {
            typealias DATType = TOSECDATFile
            let datFile: any DATFormat
            let archiveHandlers: [any ArchiveHandler]
            
            func rebuild(from source: URL, to destination: URL, options: RebuildOptions) async throws -> any RebuildResults {
                throw NSError(domain: "TOSEC", code: -1, userInfo: [NSLocalizedDescriptionKey: "TOSEC rebuilder not yet implemented"])
            }
        }
        return NotImplementedRebuilder(datFile: datFile, archiveHandlers: createArchiveHandlers())
    }
    
    func createArchiveHandlers() -> [any ArchiveHandler] {
        return [ZIPArchiveHandler(), SevenZipArchiveHandler()]
    }
}

class TOSECParser: DATParser {
    typealias DATType = TOSECDATFile
    
    func canParse(data: Data) -> Bool {
        // Check if this is a TOSEC DAT
        return false
    }
    
    func parse(data: Data) throws -> TOSECDATFile {
        // Parse TOSEC format
        throw NSError(domain: "TOSEC", code: 0)
    }
    
    func parse(url: URL) throws -> TOSECDATFile {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }
}

struct TOSECDATFile: DATFormat {
    let formatName = "TOSEC"
    let formatVersion: String?
    let games: [any GameEntry]
    let metadata: DATMetadata
}

// Register the custom format
func registerCustomFormat() {
    let tosecHandler = TOSECFormatHandler()
    RomKitFormatRegistry.shared.register(tosecHandler)
    
    // Now TOSEC format is available
    let kit = RomKitGeneric()
    // try kit.loadDAT(from: "tosec.dat", format: "tosec")
}