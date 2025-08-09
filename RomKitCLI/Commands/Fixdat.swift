//
//  Fixdat.swift
//  RomKitCLI
//
//  Generate fixdat files containing only missing ROMs
//

import ArgumentParser
import Foundation
import RomKit

struct Fixdat: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate a fixdat file containing only missing ROMs",
        discussion: """
            Creates a DAT file containing only the ROMs that are missing from your collection.
            This is useful for sharing with other collectors or tracking acquisition progress.
            
            Supports both Logiqx XML (industry standard) and ClrMamePro formats.
            """
    )
    
    @Argument(help: "Directory containing ROM files to analyze")
    var romDirectory: String
    
    @Argument(help: "DAT file to compare against")
    var datFile: String
    
    @Argument(help: "Output path for the generated fixdat")
    var outputPath: String
    
    @Option(name: .shortAndLong, help: "Output format: logiqx or clrmamepro (default: logiqx)")
    var format: String = "logiqx"
    
    @Flag(name: .long, help: "Include device ROMs in fixdat")
    var includeDevices = false
    
    @Flag(name: .long, help: "Include BIOS ROMs in fixdat")
    var includeBios = false
    
    @Flag(name: .long, help: "Include clone games in fixdat")
    var includeClones = false
    
    @Flag(name: .long, help: "Show progress during analysis")
    var showProgress = false
    
    @Flag(name: .shortAndLong, help: "Verbose output showing details")
    var verbose = false
    
    func run() async throws {
        let startTime = Date()
        
        print("🔧 Generating Fixdat")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Initialize RomKit
        let romkit = RomKit()
        
        // Load DAT file
        if verbose {
            print("📋 Loading DAT file: \(datFile)")
        }
        let datURL = URL(fileURLWithPath: datFile)
        try await romkit.loadDAT(from: datURL.path)
        
        // Scan ROM directory
        if verbose {
            print("🔍 Scanning ROM directory: \(romDirectory)")
        }
        
        let scanResult: ScanResult
        if showProgress {
            print("Scanning ROMs...")
            scanResult = try await romkit.scanDirectory(romDirectory)
        } else {
            scanResult = try await romkit.scanDirectory(romDirectory)
        }
        
        // Apply filters based on options
        let filteredScanResult = filterScanResult(scanResult)
        
        // Count missing ROMs
        let missingCount = filteredScanResult.foundGames.reduce(0) { count, game in
            count + game.missingRoms.count
        }
        
        if missingCount == 0 {
            print("✅ No missing ROMs found! Your collection is complete.")
            return
        }
        
        print("\n📊 Analysis Results:")
        print("   Total games scanned: \(scanResult.foundGames.count)")
        print("   Games with missing ROMs: \(filteredScanResult.foundGames.filter { !$0.missingRoms.isEmpty }.count)")
        print("   Total missing ROMs: \(missingCount)")
        
        // Determine output format
        let outputFormat: FixdatFormat = format.lowercased() == "clrmamepro" ? .clrmamepro : .logiqxXML
        
        // Generate fixdat
        if verbose {
            print("\n🔧 Generating fixdat in \(outputFormat == .logiqxXML ? "Logiqx XML" : "ClrMamePro") format...")
        }
        
        try romkit.generateFixdat(
            from: filteredScanResult,
            to: outputPath,
            format: outputFormat
        )
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        print("\n✅ Fixdat generated successfully!")
        print("   Output file: \(outputPath)")
        print("   Format: \(outputFormat == .logiqxXML ? "Logiqx XML" : "ClrMamePro")")
        print("   Missing ROMs documented: \(missingCount)")
        print("   Time elapsed: \(String(format: "%.2f", elapsedTime)) seconds")
        
        if verbose {
            print("\n💡 Tip: Share this fixdat with other collectors to find missing ROMs")
        }
    }
    
    private func filterScanResult(_ scanResult: ScanResult) -> ScanResult {
        var filteredGames = scanResult.foundGames
        
        // Filter based on options
        if !includeClones {
            filteredGames = filteredGames.filter { game in
                game.game.cloneOf == nil
            }
        }
        
        if !includeBios {
            filteredGames = filteredGames.filter { game in
                !game.game.name.lowercased().contains("bios")
            }
        }
        
        if !includeDevices {
            filteredGames = filteredGames.filter { game in
                // Simple heuristic for device ROMs
                !game.game.name.hasPrefix("device_")
            }
        }
        
        return ScanResult(
            scannedPath: scanResult.scannedPath,
            foundGames: filteredGames,
            unknownFiles: scanResult.unknownFiles
        )
    }
}