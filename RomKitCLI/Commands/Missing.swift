//
//  Missing.swift
//  RomKitCLI
//
//  Generate missing ROM reports
//

import ArgumentParser
import Foundation
import RomKit

struct Missing: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate a missing ROM report",
        discussion: """
            Creates detailed reports showing which ROMs are missing from your collection.
            Supports both HTML (for web viewing) and text (for console/sharing) formats.
            """
    )
    
    @Argument(help: "Directory containing ROM files to analyze")
    var romDirectory: String
    
    @Argument(help: "DAT file to compare against")
    var datFile: String
    
    @Option(name: .shortAndLong, help: "Output file path (without extension)")
    var output: String?
    
    @Option(name: .shortAndLong, help: "Report format: html, text, or both (default: both)")
    var format: String = "both"
    
    @Flag(name: .long, help: "Group clone games with their parents")
    var groupByParent = false
    
    @Flag(name: .long, help: "Include device ROMs in report")
    var includeDevices = false
    
    @Flag(name: .long, help: "Include BIOS ROMs in report")
    var includeBios = false
    
    @Flag(name: .long, help: "Include clone games in report")
    var includeClones = false
    
    @Flag(name: .long, help: "Show alternative ROM sources")
    var showAlternatives = false
    
    @Option(name: .long, help: "Sort by: name, missing, manufacturer, year (default: missing)")
    var sortBy: String = "missing"
    
    @Flag(name: .long, help: "Show progress during analysis")
    var showProgress = false
    
    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose = false
    
    func run() async throws {
        let startTime = Date()
        
        print("📋 Generating Missing ROM Report")
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
        
        // Configure report options
        let sortByOption: MissingReportSort = switch sortBy.lowercased() {
        case "name": .name
        case "manufacturer": .manufacturer
        case "year": .year
        default: .missingCount
        }
        
        let options = MissingReportOptions(
            groupByParent: groupByParent,
            includeDevices: includeDevices,
            includeBIOS: includeBios,
            includeClones: includeClones,
            showAlternatives: showAlternatives,
            sortBy: sortByOption
        )
        
        // Generate report
        if verbose {
            print("\n📊 Generating report...")
        }
        
        let report = try romkit.generateMissingReport(
            from: scanResult,
            options: options
        )
        
        // Print summary
        print("\n📊 Collection Summary:")
        print("   Total games: \(report.totalGames)")
        print("   Complete games: \(report.completeGames)")
        print("   Partial games: \(report.partialGames)")
        print("   Missing games: \(report.missingGames)")
        print("   Total ROMs: \(report.totalROMs)")
        print("   Missing ROMs: \(report.missingROMs)")
        
        if report.totalSize > 0 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            print("   Missing size: \(formatter.string(fromByteCount: Int64(report.missingSize)))")
        }
        
        // Save reports
        let baseOutput = output ?? "missing_report"
        var savedFiles: [String] = []
        
        if format == "html" || format == "both" {
            let htmlPath = baseOutput + ".html"
            let htmlContent = report.generateHTML()
            try htmlContent.write(toFile: htmlPath, atomically: true, encoding: String.Encoding.utf8)
            savedFiles.append(htmlPath)
            if verbose {
                print("\n✅ HTML report saved: \(htmlPath)")
            }
        }
        
        if format == "text" || format == "both" {
            let textPath = baseOutput + ".txt"
            let textContent = report.generateText()
            try textContent.write(toFile: textPath, atomically: true, encoding: String.Encoding.utf8)
            savedFiles.append(textPath)
            if verbose {
                print("✅ Text report saved: \(textPath)")
            }
        }
        
        // Print top missing if verbose
        if verbose && !report.missingByCategory.isEmpty {
            print("\n🎮 Top Missing Categories:")
            for (category, games) in report.missingByCategory.prefix(5) {
                print("   \(category): \(games.count) games")
            }
        }
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        print("\n✅ Report generation complete!")
        for file in savedFiles {
            print("   📄 \(file)")
        }
        print("   Time elapsed: \(String(format: "%.2f", elapsedTime)) seconds")
        
        if verbose && format.contains("html") {
            print("\n💡 Tip: Open the HTML report in a web browser for an interactive view")
        }
    }
}