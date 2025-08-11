//
//  Consolidate.swift
//  RomKit CLI - Consolidate Command
//
//  Consolidates ROMs from all indexed directories into a single complete collection
//

import ArgumentParser
import Foundation
import RomKit

struct Consolidate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Consolidate ROMs from all indexed directories into a single collection",
        discussion: """
            This command creates a complete ROM collection by copying unique ROMs from all
            indexed directories to a new output directory. It does not modify or delete
            files from source directories.
            
            The consolidation process:
            1. Scans all indexed directories for unique ROMs
            2. Copies the best version of each ROM to the output directory
            3. Optionally adds the output as a new indexed directory
            4. Can replace all existing indexes with just the consolidated one
            """
    )
    
    @Argument(help: "Output directory for consolidated ROM collection")
    var outputPath: String
    
    @Flag(name: .long, help: "Add output directory to index after consolidation")
    var addToIndex = false
    
    @Flag(name: .long, help: "Replace all existing indexed directories with the consolidated one")
    var replaceIndexes = false
    
    @Flag(name: .long, help: "Verify ROM integrity during copy (slower but safer)")
    var verify = false
    
    @Flag(name: .long, help: "Show progress during consolidation")
    var showProgress = false
    
    @Flag(name: .shortAndLong, help: "Verbose output showing each file copied")
    var verbose = false
    
    @Flag(name: .long, help: "Dry run - show what would be done without copying files")
    var dryRun = false
    
    @Option(name: .long, help: "Preferred source priority (comma-separated source paths)")
    var preferredSources: String?
    
    @Option(name: .shortAndLong, help: "Number of parallel copy operations (0 = auto-detect)")
    var parallel: Int = 0
    
    mutating func run() async throws {
        RomKitCLI.printHeader("🔄 ROM Collection Consolidation")
        
        let outputURL = URL(fileURLWithPath: outputPath)
        
        if dryRun {
            print("🔍 DRY RUN MODE - No files will be copied")
        }
        
        // Create output directory if needed
        if !dryRun {
            try FileManager.default.createDirectory(
                at: outputURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        // Initialize index manager
        let indexManager = try await ROMIndexManager()
        
        // Get all indexed sources
        let sources = await indexManager.listSources()
        
        guard !sources.isEmpty else {
            throw ValidationError("No indexed directories found. Use 'romkit index add' to index directories first.")
        }
        
        RomKitCLI.printSection("Indexed Sources")
        print("📂 Found \(sources.count) indexed source\(sources.count == 1 ? "" : "s"):")
        for source in sources {
            print("   • \(source.path) (\(source.romCount.formatted()) ROMs)")
        }
        
        // Load all ROMs into memory for analysis
        RomKitCLI.printSection("Analyzing ROM Collection")
        let allROMs = await indexManager.loadIndexIntoMemory()
        
        // Track consolidation stats
        var stats = ConsolidationStats()
        stats.totalSources = sources.count
        stats.totalUniqueROMs = allROMs.count
        
        // Calculate total ROMs across all sources
        for (_, romList) in allROMs {
            stats.totalROMs += romList.count
        }
        
        print("📊 Collection Statistics:")
        print("   • Total ROMs: \(stats.totalROMs.formatted())")
        print("   • Unique ROMs: \(stats.totalUniqueROMs.formatted())")
        print("   • Duplicates: \((stats.totalROMs - stats.totalUniqueROMs).formatted())")
        
        if dryRun {
            performDryRun(allROMs: allROMs, outputURL: outputURL, stats: &stats)
        } else {
            try await performConsolidation(
                allROMs: allROMs,
                outputURL: outputURL,
                indexManager: indexManager,
                stats: &stats
            )
        }
        
        // Display results
        displayResults(stats: stats)
    }
    
    private func performDryRun(
        allROMs: [String: [IndexedROM]],
        outputURL: URL,
        stats: inout ConsolidationStats
    ) {
        RomKitCLI.printSection("Dry Run Analysis")
        
        var sampleROMs: [(crc: String, rom: IndexedROM)] = []
        
        for (crc, romList) in allROMs.prefix(10) {
            // Pick the best version (prefer archives over loose files)
            let bestROM = selectBestROM(from: romList)
            sampleROMs.append((crc, bestROM))
            stats.romsToConsolidate += 1
        }
        
        if allROMs.count > 10 {
            stats.romsToConsolidate = allROMs.count
        }
        
        print("\n📋 Sample ROMs to consolidate:")
        for (index, (crc, rom)) in sampleROMs.enumerated() {
            print("   \(index + 1). CRC: \(crc)")
            if verbose {
                switch rom.location {
                case .file(let url):
                    print("      From: \(url.path)")
                case .archive(let archiveURL, let entry):
                    print("      From: \(archiveURL.path) → \(entry)")
                case .remote(let url, _):
                    print("      From: \(url)")
                }
                print("      To: \(outputURL.appendingPathComponent(rom.name).path)")
            } else {
                print("      Name: \(rom.name)")
            }
        }
        
        if allROMs.count > 10 {
            print("\n   ... and \((allROMs.count - 10).formatted()) more ROMs")
        }
        
        // Estimate size
        var estimatedSize: Int64 = 0
        for (_, romList) in allROMs {
            let bestROM = selectBestROM(from: romList)
            estimatedSize += Int64(bestROM.size)
        }
        
        print("\n💾 Estimated output size: \(RomKitCLI.formatFileSize(estimatedSize))")
        print("\n💡 Run without --dry-run to perform the consolidation")
    }
    
    private func performConsolidation(
        allROMs: [String: [IndexedROM]],
        outputURL: URL,
        indexManager: ROMIndexManager,
        stats: inout ConsolidationStats
    ) async throws {
        RomKitCLI.printSection("Consolidating ROMs")
        
        let totalROMs = allROMs.count
        var processedROMs = 0
        
        // Determine optimal parallelism
        let maxParallel = parallel > 0 ? parallel : ProcessInfo.processInfo.activeProcessorCount * 2
        
        print("⚡ Using \(maxParallel) parallel workers")
        
        // Convert dictionary to array for better parallel processing
        let romPairs = Array(allROMs)
        
        // Use actor for thread-safe stats updates
        let statsActor = StatsActor()
        
        // Process ROMs with maximum parallelism
        await withTaskGroup(of: ConsolidationResult.self) { group in
            // Launch initial batch of tasks
            for index in 0..<min(maxParallel, romPairs.count) {
                let (crc, romList) = romPairs[index]
                let bestROM = selectBestROM(from: romList)
                
                group.addTask {
                    return await self.consolidateROM(
                        rom: bestROM,
                        crc: crc,
                        outputURL: outputURL,
                        verify: self.verify
                    )
                }
            }
            
            var nextIndex = min(maxParallel, romPairs.count)
            
            // Process results and launch new tasks
            for await result in group {
                await statsActor.processResult(result)
                processedROMs += 1
                
                if showProgress {
                    let currentStats = await statsActor.getStats()
                    printProgressWithStats(processedROMs, total: totalROMs, stats: currentStats)
                }
                
                // Launch next task if available
                if nextIndex < romPairs.count {
                    let (crc, romList) = romPairs[nextIndex]
                    let bestROM = selectBestROM(from: romList)
                    nextIndex += 1
                    
                    group.addTask {
                        return await self.consolidateROM(
                            rom: bestROM,
                            crc: crc,
                            outputURL: outputURL,
                            verify: self.verify
                        )
                    }
                }
            }
        }
        
        // Update stats from actor
        let finalStats = await statsActor.getStats()
        stats.copied = finalStats.copied
        stats.skipped = finalStats.skipped
        stats.failed = finalStats.failed
        stats.errors = finalStats.errors
        
        if showProgress {
            print("") // New line after progress
        }
        
        // Handle index updates
        if addToIndex || replaceIndexes {
            try await updateIndexes(
                outputURL: outputURL,
                indexManager: indexManager,
                replaceAll: replaceIndexes
            )
        }
    }
    
    private func consolidateROM(
        rom: IndexedROM,
        crc: String,
        outputURL: URL,
        verify: Bool
    ) async -> ConsolidationResult {
        let outputFile = outputURL.appendingPathComponent(rom.name)
        
        // Skip if file already exists - use async check for better performance
        let fileExists = await Task.detached(priority: .userInitiated) {
            FileManager.default.fileExists(atPath: outputFile.path)
        }.value
        
        if fileExists {
            return ConsolidationResult(
                crc: crc,
                success: true,
                skipped: true,
                error: nil
            )
        }
        
        do {
            // Extract or copy the ROM using async I/O
            let data: Data
            
            switch rom.location {
            case .file(let sourceURL):
                // Use async file I/O for better performance
                data = try await Task.detached(priority: .userInitiated) {
                    try Data(contentsOf: sourceURL)
                }.value
                
            case .archive(let archiveURL, let entryPath):
                // Use appropriate archive handler
                let handler: any ArchiveHandler
                switch archiveURL.pathExtension.lowercased() {
                case "zip":
                    handler = FastZIPArchiveHandler()
                case "7z":
                    handler = SevenZipArchiveHandler()
                default:
                    throw ArchiveError.unsupportedFormat("Unknown archive format: \(archiveURL.pathExtension)")
                }
                
                let entry = ArchiveEntry(
                    path: entryPath,
                    compressedSize: UInt64(rom.size),
                    uncompressedSize: UInt64(rom.size),
                    crc32: crc
                )
                
                // Extract in background thread
                data = try await Task.detached(priority: .userInitiated) {
                    try handler.extract(entry: entry, from: archiveURL)
                }.value
                
            case .remote:
                // Skip remote ROMs for now
                return ConsolidationResult(
                    crc: crc,
                    success: false,
                    skipped: true,
                    error: "Remote ROM sources not yet supported"
                )
            }
            
            // Verify if requested - use parallel hashing for large files
            if verify {
                let actualCRC: String
                if data.count > 10_485_760 { // 10MB threshold
                    actualCRC = await ParallelHashUtilities.crc32(data: data)
                } else {
                    actualCRC = HashUtilities.crc32(data: data)
                }
                
                if actualCRC.lowercased() != crc.lowercased() {
                    throw ValidationError("CRC mismatch: expected \(crc), got \(actualCRC)")
                }
            }
            
            // Write to output using async I/O
            try await Task.detached(priority: .userInitiated) {
                try data.write(to: outputFile, options: .atomic)
            }.value
            
            if verbose {
                print("\n✅ Copied: \(rom.name)")
            }
            
            return ConsolidationResult(
                crc: crc,
                success: true,
                skipped: false,
                error: nil
            )
            
        } catch {
            if verbose {
                print("\n❌ Failed: \(rom.name) - \(error.localizedDescription)")
            }
            
            return ConsolidationResult(
                crc: crc,
                success: false,
                skipped: false,
                error: error.localizedDescription
            )
        }
    }
    
    private func selectBestROM(from romList: [IndexedROM]) -> IndexedROM {
        // Prioritization logic:
        // 1. Prefer ROMs from preferred sources (if specified)
        // 2. Prefer archived ROMs over loose files (better organization)
        // 3. Pick the first available otherwise
        
        if let preferredPaths = preferredSources?.split(separator: ",").map(String.init) {
            for path in preferredPaths {
                for rom in romList {
                    switch rom.location {
                    case .file(let url):
                        if url.path.contains(path) {
                            return rom
                        }
                    case .archive(let url, _):
                        if url.path.contains(path) {
                            return rom
                        }
                    default:
                        continue
                    }
                }
            }
        }
        
        // Prefer archives
        for rom in romList {
            if case .archive = rom.location {
                return rom
            }
        }
        
        // Return first available
        return romList[0]
    }
    
    private func updateIndexes(
        outputURL: URL,
        indexManager: ROMIndexManager,
        replaceAll: Bool
    ) async throws {
        RomKitCLI.printSection("Updating Index")
        
        if replaceAll {
            // Remove all existing sources
            let existingSources = await indexManager.listSources()
            for source in existingSources {
                print("🗑️  Removing source: \(source.path)")
                try await indexManager.removeSource(URL(fileURLWithPath: source.path))
            }
        }
        
        // Add the consolidated directory
        print("➕ Adding consolidated directory to index...")
        try await indexManager.addSource(outputURL, showProgress: showProgress)
        
        let analysis = await indexManager.analyzeIndex()
        print("✅ Index updated:")
        print("   • Total ROMs: \(analysis.totalROMs.formatted())")
        print("   • Unique ROMs: \(analysis.uniqueROMs.formatted())")
    }
    
    
    private func printProgress(_ current: Int, total: Int) {
        let percentage = Double(current) / Double(total) * 100
        print("\rProgress: \(current)/\(total) (\(String(format: "%.1f%%", percentage)))", terminator: "")
        fflush(stdout)
    }
    
    private func printProgressWithStats(_ current: Int, total: Int, stats: ConsolidationStats) {
        let percentage = Double(current) / Double(total) * 100
        print("\r⚡ Progress: \(current)/\(total) (\(String(format: "%.1f%%", percentage))) | ✅ \(stats.copied) | ⏭️ \(stats.skipped) | ❌ \(stats.failed)", terminator: "")
        fflush(stdout)
    }
    
    private func displayResults(stats: ConsolidationStats) {
        RomKitCLI.printSection("Consolidation Complete")
        
        print("\n📊 Results:")
        print("   • Sources processed: \(stats.totalSources)")
        print("   • Unique ROMs found: \(stats.totalUniqueROMs.formatted())")
        
        if !dryRun {
            print("   • ROMs copied: \(stats.copied.formatted())")
            if stats.skipped > 0 {
                print("   • ROMs skipped (already exist): \(stats.skipped.formatted())")
            }
            if stats.failed > 0 {
                print("   • ROMs failed: \(stats.failed.formatted())")
            }
            
            if !stats.errors.isEmpty && verbose {
                print("\n❌ Errors (first 5):")
                for error in stats.errors.prefix(5) {
                    print("   • \(error)")
                }
            }
            
            let successRate = Double(stats.copied) / Double(stats.copied + stats.failed) * 100
            print("\n✅ Success rate: \(String(format: "%.1f%%", successRate))")
        }
    }
}

// MARK: - Supporting Types

private struct ConsolidationStats {
    var totalSources = 0
    var totalROMs = 0
    var totalUniqueROMs = 0
    var romsToConsolidate = 0
    var copied = 0
    var skipped = 0
    var failed = 0
    var errors: [String] = []
}

private struct ConsolidationResult {
    let crc: String
    let success: Bool
    let skipped: Bool
    let error: String?
}

// Actor for thread-safe statistics updates
private actor StatsActor {
    private var stats = ConsolidationStats()
    
    func processResult(_ result: ConsolidationResult) {
        if result.success {
            if result.skipped {
                stats.skipped += 1
            } else {
                stats.copied += 1
            }
        } else {
            stats.failed += 1
            if let error = result.error {
                stats.errors.append(error)
            }
        }
    }
    
    func getStats() -> ConsolidationStats {
        return stats
    }
}