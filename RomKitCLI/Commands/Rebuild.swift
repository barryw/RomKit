//
//  Rebuild.swift
//  RomKit CLI - Rebuild Command
//
//  Rebuilds ROM sets from multiple source directories
//

import ArgumentParser
import Foundation
import RomKit

private struct RebuildOptions {
    let style: RebuildStyle
    let verify: Bool
    let useGPU: Bool
    let parallel: Int
    let showProgress: Bool
}

struct Rebuild: AsyncParsableCommand, Sendable {
    static let configuration = CommandConfiguration(
        abstract: "Rebuild ROM sets from multiple source directories",
        discussion: """
            This command rebuilds complete ROM sets by searching for required ROMs
            across multiple source directories and archives. It can handle:

            - Multiple source directories (local and network)
            - ZIP and 7z archives
            - Loose ROM files
            - Parent/Clone relationships
            - BIOS dependencies

            The rebuild process will:
            1. Index all source directories
            2. Match ROMs against the DAT file
            3. Copy/extract required ROMs to the output directory
            4. Create properly structured ZIP files
            """
    )

    @Argument(help: "Path to the MAME DAT file")
    var datPath: String

    @Argument(help: "Output directory for rebuilt ROM sets")
    var outputPath: String

    @Option(
        name: .customLong("source"),
        parsing: .upToNextOption,
        help: "Source directories to search for ROMs (can specify multiple)"
    )
    var sources: [String] = []

    @Option(name: [.customShort("s"), .customLong("style")], help: "Rebuild style: split, merged, or non-merged")
    var style: RebuildStyle = .split

    @Flag(name: .shortAndLong, help: "Update mode: Only rebuild missing or incomplete sets")
    var update = false

    @Flag(name: .long, help: "Allow building incomplete ROM sets (default: complete sets only)")
    var allowIncomplete = false

    @Flag(name: .long, help: "Include non-working games (default: working games only)")
    var includeNonWorking = false

    @Flag(name: .long, help: "Include games with bad dumps (default: good dumps only)")
    var includeBadDumps = false

    @Flag(name: .shortAndLong, inversion: .prefixedNo, help: "Verify CRC32 checksums during rebuild")
    var verify = true

    @Flag(name: .long, help: "Use GPU acceleration for hash computation")
    var gpu = false

    @Flag(name: .long, help: "Show progress during rebuild")
    var showProgress = false

    @Option(name: .long, help: "Cache file for ROM index")
    var cacheFile: String?

    @Flag(name: .shortAndLong, help: "Perform a dry run without copying files")
    var dryRun = false

    @Option(name: .shortAndLong, help: "Number of parallel operations")
    var parallel: Int = 10

    mutating func run() async throws {
        RomKitCLI.printHeader("🔨 RomKit ROM Rebuild")

        // Validate and prepare
        let inputs = try validateAndPrepareInputs()
        printConfiguration(datURL: inputs.datURL, outputURL: inputs.outputURL)

        // Load DAT and create index
        let datFile = try await loadDATFile(from: inputs.datURL)
        let indexManager = try await setupIndexManager(sourceURLs: inputs.sourceURLs, outputURL: inputs.outputURL)

        // Analyze requirements
        let requirements = try await analyzeRequirements(
            datFile: datFile,
            outputURL: inputs.outputURL,
            indexManager: indexManager
        )

        // Perform rebuild
        try await performRebuild(
            requirements: requirements,
            datFile: datFile,
            outputURL: inputs.outputURL,
            indexManager: indexManager
        )
    }

    private struct ValidatedInputs {
        let datURL: URL
        let outputURL: URL
        let sourceURLs: [URL]
    }

    private func validateAndPrepareInputs() throws -> ValidatedInputs {
        let datURL = URL(fileURLWithPath: datPath)
        let outputURL = URL(fileURLWithPath: outputPath)

        guard FileManager.default.fileExists(atPath: datURL.path) else {
            throw ValidationError("DAT file does not exist: \(datPath)")
        }

        var sourceURLs: [URL] = []

        if sources.isEmpty {
            // No sources specified, try to use indexed directories
            // Don't print here - it will be printed after the header

            // Check if the default index database exists
            // ROMIndexManager uses ~/Library/Caches/RomKit/romkit_index.db by default
            if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                let romkitDir = cacheDir.appendingPathComponent("RomKit", isDirectory: true)
                let indexPath = romkitDir.appendingPathComponent("romkit_index.db")

                if FileManager.default.fileExists(atPath: indexPath.path) {
                    // We'll get the sources from the index manager later
                    // For now, just use an empty array and handle it in setupIndexManager
                    sourceURLs = []
                } else {
                    throw ValidationError("No source directories specified and no indexed sources found.\nUse -s/--source to specify directories or 'romkit index add' to index directories first.")
                }
            } else {
                throw ValidationError("No source directories specified and no indexed sources found.\nUse -s/--source to specify directories or 'romkit index add' to index directories first.")
            }
        } else {
            sourceURLs = sources.map { URL(fileURLWithPath: $0) }
            for sourceURL in sourceURLs {
                guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                    throw ValidationError("Source directory does not exist: \(sourceURL.path)")
                }
            }
        }

        if !dryRun {
            try FileManager.default.createDirectory(
                at: outputURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        return ValidatedInputs(datURL: datURL, outputURL: outputURL, sourceURLs: sourceURLs)
    }

    private func printConfiguration(datURL: URL, outputURL: URL) {
        print("📄 DAT File: \(datURL.lastPathComponent)")
        print("📂 Output: \(outputURL.path)")
        if sources.isEmpty {
            print("🗂️ Sources: Using all indexed ROM sources")
        } else {
            print("🗂️ Sources: \(sources.count) new director\(sources.count == 1 ? "y" : "ies") to index")
        }
        print("🎯 Style: \(style)")
        print("🔄 Mode: \(update ? "Update existing sets" : "Full rebuild")")
        print("📦 Sets: \(allowIncomplete ? "Allow incomplete" : "Complete only")")
        print("🎮 Games: \(includeNonWorking ? "All" : "Working only")")
        print("💾 ROMs: \(includeBadDumps ? "All dumps" : "Good dumps only")")
        print("✅ Verify: \(verify)")
        print("⚡ GPU: \(gpu)")
        print("🔄 Parallel: \(parallel) workers")
        if dryRun {
            print("🚫 DRY RUN MODE - No files will be modified")
        }
    }

    private func setupIndexManager(sourceURLs: [URL], outputURL: URL) async throws -> ROMIndexManager {
        // Use cache file if specified, otherwise let ROMIndexManager use its default
        let indexPath: URL?
        if let cacheFile = cacheFile {
            indexPath = URL(fileURLWithPath: cacheFile)
        } else {
            // Let ROMIndexManager use its default (~/Library/Caches/RomKit/romkit_index.db)
            indexPath = nil
        }

        let indexManager = try await ROMIndexManager(databasePath: indexPath)

        if sourceURLs.isEmpty {
            // No sources specified, use ALL existing indexed sources
            RomKitCLI.printSection("ROM Sources")

            let existingSources = await indexManager.listSources()
            if existingSources.isEmpty {
                throw ValidationError("No indexed sources found. Use 'romkit index add' to index directories first.")
            }

            // Filter out the output directory from sources to avoid circular dependency
            let outputPathStandardized = outputURL.standardizedFileURL.path
            let filteredSources = existingSources.filter { source in
                let sourcePath = URL(fileURLWithPath: source.path).standardizedFileURL.path
                return sourcePath != outputPathStandardized
            }

            if filteredSources.isEmpty {
                throw ValidationError("No valid source directories found. The output directory cannot be used as a source.")
            }

            // Check if output directory is indexed
            let outputIsIndexed = existingSources.contains { source in
                let sourcePath = URL(fileURLWithPath: source.path).standardizedFileURL.path
                return sourcePath == outputPathStandardized
            }

            print("📂 Using \(filteredSources.count) indexed source\(filteredSources.count == 1 ? "" : "s")")
            for source in filteredSources {
                print("   • \(source.path) (\(source.romCount.formatted()) ROMs)")
            }

            if outputIsIndexed {
                print("   ⚠️ Excluding output directory from sources")
            }
        } else {
            // Add specified sources to the index
            RomKitCLI.printSection("Indexing New Source Directories")

            // Check if any source matches the output directory
            let outputPathStandardized = outputURL.standardizedFileURL.path
            let filteredNewSources = sourceURLs.filter { sourceURL in
                let sourcePath = sourceURL.standardizedFileURL.path
                if sourcePath == outputPathStandardized {
                    print("⚠️  Skipping source \(sourceURL.path) - matches output directory")
                    return false
                }
                return true
            }

            if filteredNewSources.isEmpty {
                throw ValidationError("No valid source directories. The output directory cannot be used as a source.")
            }

            print("📦 Adding \(filteredNewSources.count) source\(filteredNewSources.count == 1 ? "" : "s") to index...")
            for source in filteredNewSources {
                try await indexManager.addSource(source, showProgress: showProgress)
            }
        }

        let analysis = await indexManager.analyzeIndex()
        printIndexAnalysis(analysis)

        return indexManager
    }

    private func printIndexAnalysis(_ analysis: IndexAnalysis) {
        print("\n📊 Index Summary:")
        print("   • Total ROMs: \(analysis.totalROMs.formatted())")
        print("   • Unique CRCs: \(analysis.uniqueROMs.formatted())")
        if analysis.totalDuplicates > 0 {
            print("   • Duplicates: \(analysis.totalDuplicates.formatted())")
        }
    }

    private func analyzeRequirements(
        datFile: any DATFormat,
        outputURL: URL,
        indexManager: ROMIndexManager
    ) async throws -> RebuildRequirements {
        let requirements = try await analyzeRebuildRequirements(
            datFile: datFile,
            outputDirectory: outputURL,
            indexManager: indexManager,
            updateMode: update,
            allowIncomplete: allowIncomplete,
            includeNonWorking: includeNonWorking,
            includeBadDumps: includeBadDumps,
            showProgress: showProgress
        )

        print("\n📊 Build Summary:")
        print("   • Games to rebuild: \(requirements.gamesToRebuild.count.formatted())")
        if !requirements.gamesToRebuild.isEmpty {
            let completeGames = requirements.gamesToRebuild.filter { $0.missingROMs.isEmpty }.count
            let incompleteGames = requirements.gamesToRebuild.count - completeGames
            if completeGames > 0 {
                print("     - Complete: \(completeGames.formatted())")
            }
            if incompleteGames > 0 {
                print("     - Partial: \(incompleteGames.formatted())")
            }
        }
        print("   • Total ROMs: \(requirements.totalROMs.formatted())")
        print("     - Available: \(requirements.availableROMs.formatted())")
        if requirements.missingROMs > 0 {
            print("     - Missing: \(requirements.missingROMs.formatted())")
        }

        return requirements
    }

    private func performRebuild(
        requirements: RebuildRequirements,
        datFile: any DATFormat,
        outputURL: URL,
        indexManager: ROMIndexManager
    ) async throws {

        if requirements.missingROMs > 0 {
            print("\n⚠️  Some ROMs are not available in source directories")
        }

        if dryRun {
            RomKitCLI.printSection("Dry Run Results")
            printDryRunSummary(requirements)
            return
        }

        // Perform the rebuild
        RomKitCLI.printSection("Rebuilding ROM Sets")
        let options = RebuildOptions(
            style: style,
            verify: verify,
            useGPU: gpu,
            parallel: parallel,
            showProgress: showProgress
        )
        let results = try await performRebuild(
            requirements: requirements,
            indexManager: indexManager,
            outputDirectory: outputURL,
            options: options
        )

        // Display results
        displayRebuildResults(results)
    }

    private func loadDATFile(from url: URL) async throws -> any DATFormat {
        RomKitCLI.printSection("Loading DAT File")

        let data = try Data(contentsOf: url)
        let sizeInMB = Double(data.count) / 1_048_576
        print("📄 File size: \(String(format: "%.1f", sizeInMB)) MB")

        let logiqxParser = LogiqxDATParser()
        let datFile = try logiqxParser.parse(data: data)
        print("✅ Loaded \(datFile.games.count) games")

        return datFile
    }

    private func performRebuild(
        requirements: RebuildRequirements,
        indexManager: ROMIndexManager,
        outputDirectory: URL,
        options: RebuildOptions
    ) async throws -> RebuildResults {
        var results = RebuildResults()
        let totalGames = requirements.gamesToRebuild.count
        var processedGames = 0

        // Process games with limited parallelism
        await withTaskGroup(of: GameRebuildResult.self) { group in
            var activeJobs = 0
            var gameIterator = requirements.gamesToRebuild.makeIterator()

            while let gameReq = gameIterator.next() {
                // Wait if we've hit the parallel limit
                if activeJobs >= options.parallel {
                    if let result = await group.next() {
                        processGameResult(result, results: &results)
                        activeJobs -= 1
                        processedGames += 1

                        if options.showProgress {
                            printProgress(processedGames, total: totalGames)
                        }
                    }
                }

                // Start new rebuild job
                activeJobs += 1
                let req = gameReq
                let manager = indexManager
                let output = outputDirectory
                let style = options.style
                let verify = options.verify
                let gpu = options.useGPU
                group.addTask { [self] in
                    return await self.rebuildGame(
                        requirement: req,
                        indexManager: manager,
                        outputDirectory: output,
                        style: style,
                        verify: verify,
                        useGPU: gpu
                    )
                }
            }

            // Process remaining results
            for await result in group {
                processGameResult(result, results: &results)
                processedGames += 1

                if options.showProgress {
                    printProgress(processedGames, total: totalGames)
                }
            }
        }

        if options.showProgress {
            print("") // New line after progress
        }

        return results
    }

}

// MARK: - Supporting Types

enum RebuildStyle: String, ExpressibleByArgument {
    case split
    case merged
    case nonMerged = "non-merged"
}

struct RebuildRequirements {
    var gamesToRebuild: [GameRebuildRequirement] = []
    var totalROMs = 0
    var availableROMs = 0
    var missingROMs = 0
}

struct GameRebuildRequirement {
    let game: any GameEntry
    var availableROMs: [(any ROMItem, IndexedROM)] = []
    var missingROMs: [any ROMItem] = []
}

struct GameRebuildResult {
    let gameName: String
    var success = false
    var romsRebuilt = 0
    var warnings: [String] = []
    var error: String?
}

struct RebuildResults {
    var successful = 0
    var failed = 0
    var totalROMs = 0
    var warnings: [String: [String]] = [:]
    var errors: [String: String] = [:]
}
