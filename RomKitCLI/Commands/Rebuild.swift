//
//  Rebuild.swift
//  RomKit CLI - Rebuild Command
//
//  Rebuilds ROM sets from multiple source directories
//

import ArgumentParser
import Foundation
import RomKit

struct Rebuild: AsyncParsableCommand {
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

    @Flag(name: .shortAndLong, help: "Only rebuild missing or incomplete sets")
    var missing = false

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
    var parallel: Int = 4

    mutating func run() async throws {
        RomKitCLI.printHeader("🔨 RomKit ROM Rebuild")

        // Validate inputs
        let datURL = URL(fileURLWithPath: datPath)
        let outputURL = URL(fileURLWithPath: outputPath)

        guard FileManager.default.fileExists(atPath: datURL.path) else {
            throw ValidationError("DAT file does not exist: \(datPath)")
        }

        if sources.isEmpty {
            throw ValidationError("At least one source directory must be specified with -s/--source")
        }

        let sourceURLs = sources.map { URL(fileURLWithPath: $0) }
        for sourceURL in sourceURLs {
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw ValidationError("Source directory does not exist: \(sourceURL.path)")
            }
        }

        // Create output directory if needed
        if !dryRun {
            try FileManager.default.createDirectory(
                at: outputURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        print("📄 DAT File: \(datURL.lastPathComponent)")
        print("📂 Output: \(outputURL.path)")
        print("🗂️ Sources: \(sources.count) directories")
        print("🎯 Style: \(style)")
        print("✅ Verify: \(verify)")
        print("⚡ GPU: \(gpu)")
        if dryRun {
            print("🚫 DRY RUN MODE - No files will be modified")
        }

        // Load DAT file
        RomKitCLI.printSection("Loading DAT File")
        let datFile = try await loadDATFile(from: datURL)
        print("✅ Loaded \(datFile.games.count) games from DAT")

        // Create and populate ROM index using the manager
        RomKitCLI.printSection("Indexing Source Directories")
        let cacheURL = cacheFile.map { URL(fileURLWithPath: $0) }
        let indexManager = try await ROMIndexManager(databasePath: cacheURL)

        // Add sources
        for source in sourceURLs {
            try await indexManager.addSource(source, showProgress: showProgress)
        }

        // Get analysis
        let analysis = await indexManager.analyzeIndex()

        print("✅ Indexed \(analysis.totalROMs) ROMs from \(analysis.sources.count) sources")
        print("   Unique CRCs: \(analysis.uniqueROMs)")
        print("   Duplicates: \(analysis.totalDuplicates)")

        if !analysis.recommendations.isEmpty {
            print("\n💡 Recommendations:")
            for recommendation in analysis.recommendations {
                print("   • \(recommendation)")
            }
        }

        // Analyze what needs to be rebuilt
        RomKitCLI.printSection("Analyzing Rebuild Requirements")
        let requirements = try await analyzeRebuildRequirements(
            datFile: datFile,
            outputDirectory: outputURL,
            indexManager: indexManager,
            onlyMissing: missing
        )

        print("📊 Rebuild Requirements:")
        print("   Games to rebuild: \(requirements.gamesToRebuild.count)")
        print("   ROMs needed: \(requirements.totalROMs)")
        print("   ROMs available: \(requirements.availableROMs)")
        print("   ROMs missing: \(requirements.missingROMs)")

        if requirements.missingROMs > 0 {
            print("\n⚠️ Warning: \(requirements.missingROMs) ROMs are not available in source directories")
        }

        if dryRun {
            RomKitCLI.printSection("Dry Run Results")
            printDryRunSummary(requirements)
            return
        }

        // Perform the rebuild
        RomKitCLI.printSection("Rebuilding ROM Sets")
        let results = try await performRebuild(
            requirements: requirements,
            indexManager: indexManager,
            outputDirectory: outputURL,
            style: style,
            verify: verify,
            useGPU: gpu,
            parallel: parallel,
            showProgress: showProgress
        )

        // Display results
        displayRebuildResults(results)
    }

    private func loadDATFile(from url: URL) async throws -> DATFile {
        let fileContent = try String(contentsOf: url, encoding: .utf8)
        let data = fileContent.data(using: .utf8)!

        // Try MAME parser first
        let parser = MAMEFastParser()
        if let mameDatFile = try? await parser.parseXMLParallel(data: data) {
            return convertMAMEToGeneric(mameDatFile)
        }

        // Fall back to Logiqx
        let logiqxParser = LogiqxDATParser()
        let mameDatFile = try logiqxParser.parse(data: data)
        return convertMAMEToGeneric(mameDatFile)
    }

    private func convertMAMEToGeneric(_ mameDAT: MAMEDATFile) -> DATFile {
        let games = mameDAT.games.compactMap { gameEntry -> Game? in
            let roms = gameEntry.items.map { item in
                ROM(
                    name: item.name,
                    size: item.size,
                    crc: item.checksums.crc32,
                    sha1: item.checksums.sha1,
                    md5: item.checksums.md5,
                    status: item.status,
                    merge: item.attributes.merge
                )
            }

            var cloneOf: String? = nil
            var romOf: String? = nil

            if let mameMetadata = gameEntry.metadata as? MAMEGameMetadata {
                cloneOf = mameMetadata.cloneOf
                romOf = mameMetadata.romOf
            }

            return Game(
                name: gameEntry.name,
                description: gameEntry.description,
                cloneOf: cloneOf,
                romOf: romOf,
                sampleOf: nil,
                year: gameEntry.metadata.year,
                manufacturer: gameEntry.metadata.manufacturer,
                roms: roms,
                disks: []
            )
        }

        return DATFile(
            name: mameDAT.metadata.name,
            description: mameDAT.metadata.description,
            version: mameDAT.formatVersion,
            author: nil,
            games: games
        )
    }

    private func analyzeRebuildRequirements(
        datFile: DATFile,
        outputDirectory: URL,
        indexManager: ROMIndexManager,
        onlyMissing: Bool
    ) async throws -> RebuildRequirements {
        var requirements = RebuildRequirements()

        for game in datFile.games {
            let gameOutputPath = outputDirectory.appendingPathComponent("\(game.name).zip")

            // Check if we need to rebuild this game
            if onlyMissing && FileManager.default.fileExists(atPath: gameOutputPath.path) {
                // TODO: Could verify the existing ZIP is complete
                continue
            }

            var gameRequirement = GameRebuildRequirement(game: game)

            for rom in game.roms {
                requirements.totalROMs += 1

                if let source = await indexManager.findBestSource(for: rom) {
                    gameRequirement.availableROMs.append((rom, source))
                    requirements.availableROMs += 1
                } else {
                    gameRequirement.missingROMs.append(rom)
                    requirements.missingROMs += 1
                }
            }

            // Only add games that can be at least partially rebuilt
            if !gameRequirement.availableROMs.isEmpty {
                requirements.gamesToRebuild.append(gameRequirement)
            }
        }

        return requirements
    }

    private func performRebuild(
        requirements: RebuildRequirements,
        indexManager: ROMIndexManager,
        outputDirectory: URL,
        style: RebuildStyle,
        verify: Bool,
        useGPU: Bool,
        parallel: Int,
        showProgress: Bool
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
                if activeJobs >= parallel {
                    if let result = await group.next() {
                        processGameResult(result, results: &results)
                        activeJobs -= 1
                        processedGames += 1

                        if showProgress {
                            printProgress(processedGames, total: totalGames)
                        }
                    }
                }

                // Start new rebuild job
                activeJobs += 1
                group.addTask {
                    return await self.rebuildGame(
                        requirement: gameReq,
                        indexManager: indexManager,
                        outputDirectory: outputDirectory,
                        style: style,
                        verify: verify,
                        useGPU: useGPU
                    )
                }
            }

            // Process remaining results
            for await result in group {
                processGameResult(result, results: &results)
                processedGames += 1

                if showProgress {
                    printProgress(processedGames, total: totalGames)
                }
            }
        }

        if showProgress {
            print("") // New line after progress
        }

        return results
    }

    private func rebuildGame(
        requirement: GameRebuildRequirement,
        indexManager: ROMIndexManager,
        outputDirectory: URL,
        style: RebuildStyle,
        verify: Bool,
        useGPU: Bool
    ) async -> GameRebuildResult {
        let outputPath = outputDirectory.appendingPathComponent("\(requirement.game.name).zip")
        var result = GameRebuildResult(gameName: requirement.game.name)

        do {
            var rebuiltROMs: [(name: String, data: Data)] = []

            // Extract/copy each available ROM
            for (rom, source) in requirement.availableROMs {
                let data = try await extractROM(from: source, verify: verify, useGPU: useGPU)

                if verify {
                    // Verify CRC if requested
                    let actualCRC = useGPU
                        ? await ParallelHashUtilities.crc32(data: data)
                        : HashUtilities.crc32(data: data)

                    if let expectedCRC = rom.crc,
                       actualCRC.lowercased() != expectedCRC.lowercased() {
                        result.warnings.append("CRC mismatch for \(rom.name)")
                    }
                }

                rebuiltROMs.append((rom.name, data))
                result.romsRebuilt += 1
            }

            // Create output ZIP
            if !rebuiltROMs.isEmpty {
                let handler = ParallelZIPArchiveHandler()
                try await handler.createAsync(at: outputPath, with: rebuiltROMs)
                result.success = true
            }

            // Note missing ROMs
            for rom in requirement.missingROMs {
                result.warnings.append("Missing ROM: \(rom.name)")
            }

        } catch {
            result.success = false
            result.error = error.localizedDescription
        }

        return result
    }

    private func extractROM(from source: IndexedROM, verify: Bool, useGPU: Bool) async throws -> Data {
        switch source.location {
        case .file(let path):
            return try Data(contentsOf: path)

        case .archive(let archivePath, let entryPath):
            let handler: ArchiveHandler
            switch archivePath.pathExtension.lowercased() {
            case "zip":
                handler = FastZIPArchiveHandler()
            case "7z":
                handler = SevenZipArchiveHandler()
            default:
                throw ArchiveError.unsupportedFormat("Unknown archive type")
            }

            let entries = try handler.listContents(of: archivePath)
            guard let entry = entries.first(where: { $0.path == entryPath }) else {
                throw ArchiveError.entryNotFound(entryPath)
            }

            return try handler.extract(entry: entry, from: archivePath)

        case .remote(_, _):
            // TODO: Implement network fetching
            throw ArchiveError.unsupportedFormat("Remote sources not yet implemented")
        }
    }

    private func processGameResult(_ result: GameRebuildResult, results: inout RebuildResults) {
        if result.success {
            results.successful += 1
        } else {
            results.failed += 1
        }

        results.totalROMs += result.romsRebuilt

        if !result.warnings.isEmpty {
            results.warnings[result.gameName] = result.warnings
        }

        if let error = result.error {
            results.errors[result.gameName] = error
        }
    }

    private func printProgress(_ current: Int, total: Int) {
        let percentage = Double(current) / Double(total) * 100
        print("\rProgress: \(current)/\(total) (\(String(format: "%.1f%%", percentage)))", terminator: "")
        fflush(stdout)
    }

    private func printDryRunSummary(_ requirements: RebuildRequirements) {
        print("\n🎯 Games that would be rebuilt:")
        for (index, req) in requirements.gamesToRebuild.prefix(10).enumerated() {
            print("  \(index + 1). \(req.game.name)")
            print("     - Available: \(req.availableROMs.count) ROMs")
            if !req.missingROMs.isEmpty {
                print("     - Missing: \(req.missingROMs.count) ROMs")
            }
        }

        if requirements.gamesToRebuild.count > 10 {
            print("  ... and \(requirements.gamesToRebuild.count - 10) more")
        }
    }

    private func displayRebuildResults(_ results: RebuildResults) {
        RomKitCLI.printHeader("📊 Rebuild Results")

        print("\n✅ Successful: \(results.successful) games")
        print("❌ Failed: \(results.failed) games")
        print("📦 Total ROMs: \(results.totalROMs)")

        if !results.warnings.isEmpty {
            print("\n⚠️ Warnings:")
            for (game, warnings) in results.warnings.prefix(5) {
                print("  \(game):")
                for warning in warnings.prefix(3) {
                    print("    - \(warning)")
                }
            }
        }

        if !results.errors.isEmpty {
            print("\n❌ Errors:")
            for (game, error) in results.errors.prefix(5) {
                print("  \(game): \(error)")
            }
        }
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
    let game: Game
    var availableROMs: [(ROM, IndexedROM)] = []
    var missingROMs: [ROM] = []
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