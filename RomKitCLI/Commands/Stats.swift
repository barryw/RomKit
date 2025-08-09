//
//  Stats.swift
//  RomKitCLI
//
//  Generate collection statistics and health reports
//

import ArgumentParser
import Foundation
import RomKit

struct Stats: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate collection statistics and health report",
        discussion: """
            Analyzes your ROM collection and generates comprehensive statistics including:
            - Collection completion percentage
            - Health score
            - Breakdown by year and manufacturer
            - Storage usage analysis
            - Issue detection
            """
    )

    @Argument(help: "Directory containing ROM files to analyze")
    var romDirectory: String

    @Argument(help: "DAT file to compare against")
    var datFile: String

    @Option(name: .shortAndLong, help: "Output file path (without extension)")
    var output: String?

    @Option(name: .shortAndLong, help: "Report format: html, text, console, or all (default: console)")
    var format: String = "console"

    @Flag(name: .long, help: "Show detailed breakdown by year")
    var byYear = false

    @Flag(name: .long, help: "Show detailed breakdown by manufacturer")
    var byManufacturer = false

    @Flag(name: .long, help: "Show CHD statistics if applicable")
    var showChd = false

    @Flag(name: .long, help: "Show detected issues")
    var showIssues = false

    @Flag(name: .long, help: "Show progress during analysis")
    var showProgress = false

    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose = false

    func run() async throws {
        let startTime = Date()

        print("📊 Generating Collection Statistics")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Initialize RomKit
        let romkit = RomKit()

        // Load DAT file
        if verbose {
            print("📋 Loading DAT file: \(datFile)")
        }
        let datURL = URL(fileURLWithPath: datFile)
        try romkit.loadDAT(from: datURL.path)

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

        // Generate statistics
        if verbose {
            print("\n📊 Calculating statistics...")
        }

        let stats = try romkit.generateStatistics(from: scanResult)

        // Display console output if requested
        if format == "console" || format == "all" {
            displayConsoleStats(stats)
        }

        // Save reports if output path specified
        if let baseOutput = output {
            var savedFiles: [String] = []

            if format == "html" || format == "all" {
                let htmlPath = baseOutput + "_stats.html"
                let htmlContent = stats.generateHTMLReport()
                try htmlContent.write(toFile: htmlPath, atomically: true, encoding: String.Encoding.utf8)
                savedFiles.append(htmlPath)
                if verbose {
                    print("\n✅ HTML report saved: \(htmlPath)")
                }
            }

            if format == "text" || format == "all" {
                let textPath = baseOutput + "_stats.txt"
                let textContent = stats.generateTextReport()
                try textContent.write(toFile: textPath, atomically: true, encoding: String.Encoding.utf8)
                savedFiles.append(textPath)
                if verbose {
                    print("✅ Text report saved: \(textPath)")
                }
            }

            if !savedFiles.isEmpty {
                print("\n✅ Reports saved:")
                for file in savedFiles {
                    print("   📄 \(file)")
                }
            }
        }

        let elapsedTime = Date().timeIntervalSince(startTime)
        print("\n⏱️  Time elapsed: \(String(format: "%.2f", elapsedTime)) seconds")
    }

    private func displayConsoleStats(_ stats: CollectionStatistics) {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        print("\n📊 COLLECTION OVERVIEW")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Health Score with color indicator
        let healthIndicator = switch stats.healthScore {
        case 90...100: "🟢"
        case 70..<90: "🟡"
        case 50..<70: "🟠"
        default: "🔴"
        }
        print("\nHealth Score: \(healthIndicator) \(String(format: "%.0f", stats.healthScore))%")

        // Games
        print("\n🎮 GAMES")
        print("   Total:     \(String(format: "%6d", stats.totalGames))")
        print("   Complete:  \(String(format: "%6d", stats.completeGames)) (\(String(format: "%.1f", stats.completionPercentage))%)")
        print("   Partial:   \(String(format: "%6d", stats.partialGames))")
        print("   Missing:   \(String(format: "%6d", stats.missingGames))")

        // ROMs
        print("\n💾 ROMS")
        print("   Total:     \(String(format: "%6d", stats.totalROMs))")
        print("   Found:     \(String(format: "%6d", stats.foundROMs)) (\(String(format: "%.1f", stats.romCompletionPercentage))%)")
        print("   Missing:   \(String(format: "%6d", stats.missingROMs))")

        // Storage
        print("\n💿 STORAGE")
        print("   Total Size:      \(formatter.string(fromByteCount: Int64(stats.totalSize)))")
        print("   Collection:      \(formatter.string(fromByteCount: Int64(stats.collectionSize)))")
        print("   Missing:         \(formatter.string(fromByteCount: Int64(stats.missingSize)))")

        // Special Categories
        print("\n🎯 SPECIAL CATEGORIES")
        print("   Parent Games:    \(String(format: "%6d", stats.parentStats.total)) (\(stats.parentStats.complete) complete)")
        print("   Clone Games:     \(String(format: "%6d", stats.cloneStats.total)) (\(stats.cloneStats.complete) complete)")
        print("   BIOS Sets:       \(String(format: "%6d", stats.biosStats.total)) (\(stats.biosStats.complete) complete)")
        print("   Device ROMs:     \(String(format: "%6d", stats.deviceStats.total)) (\(stats.deviceStats.complete) complete)")

        // CHD Statistics if requested
        if showChd && stats.chdStats != nil, let chd = stats.chdStats {
            print("\n💿 CHD FILES")
            print("   Total CHDs:      \(String(format: "%6d", chd.totalCHDs))")
            print("   Found:           \(String(format: "%6d", chd.foundCHDs))")
            print("   Missing:         \(String(format: "%6d", chd.missingCHDs))")
            print("   Total Size:      \(formatter.string(fromByteCount: Int64(chd.totalSize)))")
        }

        // By Year breakdown
        if byYear && !stats.byYear.isEmpty {
            print("\n📅 BY YEAR (Top 10)")
            let sortedYears = stats.byYear.sorted { $0.key < $1.key }.suffix(10)
            for (year, yearStats) in sortedYears {
                let percentage = Double(yearStats.complete) / Double(yearStats.total) * 100
                print("   \(year): \(yearStats.complete)/\(yearStats.total) (\(String(format: "%.1f", percentage))%)")
            }
        }

        // By Manufacturer breakdown
        if byManufacturer && !stats.byManufacturer.isEmpty {
            print("\n🏭 BY MANUFACTURER (Top 10)")
            let sortedMfg = stats.byManufacturer.sorted { $0.value.total > $1.value.total }.prefix(10)
            for (manufacturer, mfgStats) in sortedMfg {
                let percentage = Double(mfgStats.complete) / Double(mfgStats.total) * 100
                let mfgName = String(manufacturer.prefix(30))
                print("   \(String(format: "%-30s", mfgName)): \(mfgStats.complete)/\(mfgStats.total) (\(String(format: "%.1f", percentage))%)")
            }
        }

        // Issues
        if showIssues && !stats.issues.isEmpty {
            print("\n⚠️  DETECTED ISSUES")
            for issue in stats.issues.prefix(10) {
                let icon = switch issue.severity {
                case .critical: "🔴"
                case .warning: "🟡"
                case .info: "🔵"
                }
                print("   \(icon) \(issue.description)")
            }
            if stats.issues.count > 10 {
                print("   ... and \(stats.issues.count - 10) more issues")
            }
        }

        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}