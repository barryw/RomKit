//
//  Index.swift
//  RomKit CLI - Index Management Command
//
//  Manages the SQLite ROM index for fast lookups across multiple directories
//

import ArgumentParser
import Foundation
import RomKit

struct Index: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage the ROM index for fast lookups",
        discussion: """
            The index command manages a SQLite database that catalogs ROMs across
            multiple directories for fast searching and deduplication detection.
            
            The index is used by the rebuild and repair commands to quickly find
            ROMs across multiple source directories without repeated scanning.
            """,
        subcommands: [
            Add.self,
            Remove.self,
            Refresh.self,
            List.self,
            Stats.self,
            Verify.self,
            Clear.self,
            Find.self
        ]
    )
}

// MARK: - Add Subcommand

extension Index {
    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add a directory to the index"
        )
        
        @Argument(help: "Directory path to add to the index")
        var directory: String
        
        @Flag(name: .long, help: "Show progress during indexing")
        var showProgress = false
        
        @Option(name: .long, help: "Path to index database file")
        var indexPath: String?
        
        mutating func run() async throws {
            RomKitCLI.printHeader("📂 Adding Directory to Index")
            
            let dirURL = URL(fileURLWithPath: directory)
            guard FileManager.default.fileExists(atPath: dirURL.path) else {
                throw ValidationError("Directory does not exist: \(directory)")
            }
            
            let dbPath = indexPath.map { URL(fileURLWithPath: $0) }
            let manager = try await ROMIndexManager(databasePath: dbPath)
            
            print("Adding: \(dirURL.path)")
            
            let startTime = Date()
            try await manager.addSource(dirURL, showProgress: showProgress)
            let elapsed = Date().timeIntervalSince(startTime)
            
            // Get statistics
            let sources = await manager.listSources()
            if let source = sources.first(where: { $0.path == dirURL.path }) {
                print("\n✅ Successfully indexed:")
                print("  ROMs: \(source.romCount)")
                print("  Size: \(formatBytes(source.totalSize))")
                print("  Time: \(String(format: "%.1f", elapsed)) seconds")
            }
        }
    }
}

// MARK: - Remove Subcommand

extension Index {
    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove a directory from the index"
        )
        
        @Argument(help: "Directory path to remove from the index")
        var directory: String
        
        @Option(name: .long, help: "Path to index database file")
        var indexPath: String?
        
        mutating func run() async throws {
            RomKitCLI.printHeader("➖ Removing Directory from Index")
            
            let dirURL = URL(fileURLWithPath: directory)
            let dbPath = indexPath.map { URL(fileURLWithPath: $0) }
            let manager = try await ROMIndexManager(databasePath: dbPath)
            
            print("Removing: \(dirURL.path)")
            
            try await manager.removeSource(dirURL, showProgress: true)
            
            print("✅ Directory removed from index")
        }
    }
}

// MARK: - Refresh Subcommand

extension Index {
    struct Refresh: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Refresh indexed directories"
        )
        
        @Argument(
            help: "Directory paths to refresh (refreshes all if none specified)",
            completion: .directory
        )
        var directories: [String] = []
        
        @Flag(name: .long, help: "Show progress during refresh")
        var showProgress = false
        
        @Option(name: .long, help: "Path to index database file")
        var indexPath: String?
        
        mutating func run() async throws {
            RomKitCLI.printHeader("🔄 Refreshing Index")
            
            let dbPath = indexPath.map { URL(fileURLWithPath: $0) }
            let manager = try await ROMIndexManager(databasePath: dbPath)
            
            let sources = directories.isEmpty 
                ? nil 
                : directories.map { URL(fileURLWithPath: $0) }
            
            if directories.isEmpty {
                print("Refreshing all indexed directories...")
            } else {
                print("Refreshing \(directories.count) director\(directories.count == 1 ? "y" : "ies")...")
            }
            
            let startTime = Date()
            try await manager.refreshSources(sources, showProgress: showProgress)
            let elapsed = Date().timeIntervalSince(startTime)
            
            print("\n✅ Refresh complete in \(String(format: "%.1f", elapsed)) seconds")
            
            // Show updated statistics
            let analysis = await manager.analyzeIndex()
            print("\nUpdated statistics:")
            print("  Total ROMs: \(analysis.totalROMs)")
            print("  Unique CRCs: \(analysis.uniqueROMs)")
            print("  Duplicates: \(analysis.totalDuplicates)")
        }
    }
}

// MARK: - List Subcommand

extension Index {
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all indexed directories"
        )
        
        @Option(name: .long, help: "Path to index database file")
        var indexPath: String?
        
        @Flag(name: .shortAndLong, help: "Show detailed information")
        var verbose = false
        
        mutating func run() async throws {
            let dbPath = indexPath.map { URL(fileURLWithPath: $0) }
            let manager = try await ROMIndexManager(databasePath: dbPath)
            
            let sources = await manager.listSources()
            
            if sources.isEmpty {
                print("No directories indexed")
                print("\nUse 'romkit index add <directory>' to add directories")
                return
            }
            
            RomKitCLI.printHeader("📚 Indexed Directories")
            
            for (index, source) in sources.enumerated() {
                print("\n\(index + 1). \(source.path)")
                
                if verbose {
                    print("   Last scan: \(formatDate(source.lastScan))")
                    print("   ROM count: \(source.romCount)")
                    print("   Total size: \(formatBytes(source.totalSize))")
                    
                    let age = Date().timeIntervalSince(source.lastScan)
                    if age > 86400 { // 24 hours
                        let days = Int(age / 86400)
                        print("   ⚠️  Index is \(days) day\(days == 1 ? "" : "s") old")
                    }
                }
            }
            
            if !verbose {
                print("\nUse --verbose for detailed information")
            }
        }
    }
}

// MARK: - Stats Subcommand

extension Index {
    struct Stats: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Display index statistics and analysis"
        )
        
        @Option(name: .long, help: "Path to index database file")
        var indexPath: String?
        
        @Option(name: .long, help: "Export statistics to JSON file")
        var export: String?
        
        @Flag(name: .long, help: "Show top duplicates")
        var showDuplicates = false
        
        mutating func run() async throws {
            let dbPath = indexPath.map { URL(fileURLWithPath: $0) }
            let manager = try await ROMIndexManager(databasePath: dbPath)
            
            RomKitCLI.printHeader("📊 Index Statistics")
            
            let analysis = await manager.analyzeIndex()
            
            print("\n📈 Overview:")
            print("  Total ROMs: \(analysis.totalROMs)")
            print("  Unique ROMs: \(analysis.uniqueROMs)")
            print("  Total Size: \(formatBytes(analysis.totalSize))")
            print("  Sources: \(analysis.sources.count)")
            
            if analysis.totalDuplicates > 0 {
                print("\n🔁 Duplication:")
                print("  Duplicate groups: \(analysis.duplicateGroups)")
                print("  Total duplicates: \(analysis.totalDuplicates)")
                print("  Duplication rate: \(String(format: "%.1f%%", analysis.duplicatePercentage))")
                print("  Space wasted: \(formatBytes(analysis.spaceWasted))")
                
                if showDuplicates {
                    print("\n📋 Top Duplicates:")
                    let duplicates = await manager.findDuplicates(minCopies: 3)
                    for (index, dup) in duplicates.prefix(10).enumerated() {
                        print("  \(index + 1). CRC \(dup.crc32): \(dup.count) copies")
                        if dup.locations.count <= 3 {
                            for location in dup.locations {
                                print("      - \(location)")
                            }
                        } else {
                            for location in dup.locations.prefix(2) {
                                print("      - \(location)")
                            }
                            print("      ... and \(dup.locations.count - 2) more")
                        }
                    }
                }
            }
            
            if !analysis.recommendations.isEmpty {
                print("\n💡 Recommendations:")
                for recommendation in analysis.recommendations {
                    print("  • \(recommendation)")
                }
            }
            
            // Export if requested
            if let exportPath = export {
                let url = URL(fileURLWithPath: exportPath)
                try await manager.exportStatistics(to: url)
                print("\n✅ Statistics exported to: \(exportPath)")
            }
        }
    }
}

// MARK: - Verify Subcommand

extension Index {
    struct Verify: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Verify indexed files still exist"
        )
        
        @Flag(name: .long, help: "Remove stale entries from index")
        var removeStale = false
        
        @Option(name: .long, help: "Path to index database file")
        var indexPath: String?
        
        mutating func run() async throws {
            RomKitCLI.printHeader("🔍 Verifying Index")
            
            let dbPath = indexPath.map { URL(fileURLWithPath: $0) }
            let manager = try await ROMIndexManager(databasePath: dbPath)
            
            print("Checking indexed files...")
            
            let result = try await manager.verify(
                removeStale: removeStale,
                showProgress: true
            )
            
            print("\n📊 Verification Results:")
            print("  ✅ Valid: \(result.valid) files")
            
            if result.stale > 0 {
                print("  ⚠️  Stale: \(result.stale) files")
                
                if removeStale {
                    print("  🗑️  Removed: \(result.removed) entries")
                } else {
                    print("\n  Use --remove-stale to clean up stale entries")
                }
            }
            
            if result.stale == 0 {
                print("\n✅ All indexed files are valid")
            }
        }
    }
}

// MARK: - Clear Subcommand

extension Index {
    struct Clear: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Clear the entire index"
        )
        
        @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
        var force = false
        
        @Option(name: .long, help: "Path to index database file")
        var indexPath: String?
        
        mutating func run() async throws {
            let dbPath = indexPath.map { URL(fileURLWithPath: $0) }
            let manager = try await ROMIndexManager(databasePath: dbPath)
            
            if !force {
                print("⚠️  This will delete all indexed data.")
                print("Are you sure? (y/N): ", terminator: "")
                
                let response = readLine()?.lowercased()
                if response != "y" && response != "yes" {
                    print("Cancelled")
                    return
                }
            }
            
            RomKitCLI.printHeader("🗑️ Clearing Index")
            
            try await manager.clearAll()
            
            print("✅ Index cleared successfully")
        }
    }
}

// MARK: - Find Subcommand

extension Index {
    struct Find: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Find ROMs in the index by name or CRC32"
        )
        
        @Argument(help: "Search query (CRC32 checksum or ROM name)")
        var query: String
        
        @Option(name: .long, help: "Path to index database file")
        var indexPath: String?
        
        @Flag(name: .shortAndLong, help: "Show all results/locations")
        var all = false
        
        @Flag(name: .shortAndLong, help: "Use fuzzy matching for names")
        var fuzzy = false
        
        @Option(name: .shortAndLong, help: "Maximum number of results to show")
        var limit: Int = 10
        
        @Flag(name: .long, help: "Search by name only")
        var nameOnly = false
        
        @Flag(name: .long, help: "Search by CRC32 only")
        var crcOnly = false
        
        mutating func run() async throws {
            let dbPath = indexPath.map { URL(fileURLWithPath: $0) }
            let manager = try await ROMIndexManager(databasePath: dbPath)
            
            RomKitCLI.printHeader("🔍 Finding ROMs")
            
            // Determine search type
            let isCRC32 = query.count == 8 && query.allSatisfy { $0.isHexDigit }
            
            if crcOnly || (!nameOnly && isCRC32) {
                // Search by CRC32
                await searchByCRC32(query, manager: manager)
            } else {
                // Search by name
                await searchByName(query, manager: manager)
            }
        }
        
        private func searchByCRC32(_ crc: String, manager: ROMIndexManager) async {
            print("Searching for CRC32: \(crc)")
            
            if let romInfo = await manager.findROM(crc32: crc) {
                print("\n✅ Found ROM:")
                print("  Name: \(romInfo.name)")
                print("  Size: \(formatBytes(romInfo.size))")
                print("  CRC32: \(romInfo.crc32)")
                print("  Copies: \(romInfo.copyCount)")
                
                if all || romInfo.locations.count <= 3 {
                    print("\n📍 Locations:")
                    for (index, location) in romInfo.locations.enumerated() {
                        print("  \(index + 1). \(location.path)")
                        print("     Type: \(location.type)")
                        print("     Verified: \(formatDate(location.lastVerified))")
                    }
                } else {
                    print("\n📍 Locations (showing first 3 of \(romInfo.locations.count)):")
                    for (index, location) in romInfo.locations.prefix(3).enumerated() {
                        print("  \(index + 1). \(location.path)")
                    }
                    print("\nUse --all to see all locations")
                }
            } else {
                print("\n❌ ROM not found with CRC32: \(crc)")
                suggestSimilarCRCs(crc, manager: manager)
            }
        }
        
        private func searchByName(_ name: String, manager: ROMIndexManager) async {
            let searchPattern = fuzzy ? "%\(name)%" : name
            print("Searching for name: \(name)\(fuzzy ? " (fuzzy)" : " (exact)")")
            
            let results = await manager.findByName(pattern: searchPattern, limit: all ? nil : limit)
            
            if results.isEmpty {
                print("\n❌ No ROMs found matching: \(name)")
                if !fuzzy {
                    print("\n💡 Tip: Try --fuzzy for partial matches")
                }
                return
            }
            
            print("\n✅ Found \(results.count) ROM\(results.count == 1 ? "" : "s"):")
            
            // Group by CRC32 to show duplicates together
            var romsByCRC: [String: [ROMSearchResult]] = [:]
            for result in results {
                let crc = result.crc32 ?? "unknown"
                if romsByCRC[crc] == nil {
                    romsByCRC[crc] = []
                }
                romsByCRC[crc]?.append(result)
            }
            
            var displayedCount = 0
            for (crc, roms) in romsByCRC.sorted(by: { $0.value[0].name < $1.value[0].name }) {
                if !all && displayedCount >= limit {
                    let remaining = romsByCRC.count - displayedCount
                    print("\n... and \(remaining) more group\(remaining == 1 ? "" : "s")")
                    print("Use --all to see all results")
                    break
                }
                
                let firstROM = roms[0]
                print("\n📦 \(firstROM.name)")
                print("  Size: \(formatBytes(firstROM.size))")
                print("  CRC32: \(crc)")
                
                if roms.count > 1 {
                    print("  📍 \(roms.count) locations:")
                    for (idx, rom) in roms.enumerated() {
                        if !all && idx >= 3 {
                            print("      ... and \(roms.count - 3) more")
                            break
                        }
                        print("      • \(rom.location)")
                    }
                } else {
                    print("  📍 Location: \(firstROM.location)")
                }
                
                displayedCount += 1
            }
        }
        
        private func suggestSimilarCRCs(_ crc: String, manager: ROMIndexManager) {
            print("\n💡 Did you mean one of these?")
            print("  (Similar CRC32 suggestions would require fuzzy CRC search)")
        }
    }
}

// MARK: - Helper Functions

private func formatBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var size = Double(bytes)
    var unitIndex = 0
    
    while size >= 1024 && unitIndex < units.count - 1 {
        size /= 1024
        unitIndex += 1
    }
    
    return String(format: "%.2f %@", size, units[unitIndex])
}

private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}