//
//  Analyze.swift
//  RomKit CLI - Analyze Command
//
//  Analyzes a directory of ROMs against a DAT file to determine completeness
//

import ArgumentParser
import Foundation
import RomKit

struct Analyze: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Analyze ROMs against a DAT file to check completeness",
        discussion: """
            This command scans a directory of ROM files and compares them against
            a MAME DAT file to determine which games are complete, incomplete, or broken.

            The analysis will report:
            - Complete games: All required ROM files present with correct CRC
            - Incomplete games: Some ROM files missing
            - Broken games: ROM files present but with incorrect CRC
            - Extra files: ROM files not recognized in the DAT
            """
    )

    @Argument(help: "Path to the ROM directory to analyze")
    var romPath: String

    @Argument(help: "Path to the MAME DAT file")
    var datPath: String

    @Flag(name: .shortAndLong, help: "Show detailed information for each game")
    var verbose = false

    @Flag(name: .shortAndLong, help: "Use GPU acceleration for hash computation")
    var gpu = false

    @Flag(name: .long, help: "Show progress during analysis")
    var showProgress = false

    @Option(name: .shortAndLong, help: "Export results to JSON file")
    var output: String?

    @Flag(name: .long, help: "Skip CRC verification (faster but less accurate)")
    var skipVerification = false

    @Flag(name: .long, help: "Use indexed ROMs if available (much faster)")
    var useIndex = false

    @Option(name: .shortAndLong, help: "Number of parallel workers")
    var parallel: Int = ProcessInfo.processInfo.processorCount

    mutating func run() async throws {
        RomKitCLI.printHeader("🎮 RomKit ROM Analysis")

        // Validate inputs
        let romURL = URL(fileURLWithPath: romPath)
        let datURL = URL(fileURLWithPath: datPath)

        guard FileManager.default.fileExists(atPath: romURL.path) else {
            throw ValidationError("ROM directory does not exist: \(romPath)")
        }

        guard FileManager.default.fileExists(atPath: datURL.path) else {
            throw ValidationError("DAT file does not exist: \(datPath)")
        }

        print("📁 ROM Directory: \(romURL.path)")
        print("📄 DAT File: \(datURL.lastPathComponent)")
        print("⚡ GPU Acceleration: \(gpu ? "Enabled" : "Disabled")")
        print("🔍 Verification: \(skipVerification ? "Skip (fast mode)" : "Full CRC check")")
        print("📊 Index: \(useIndex ? "Use existing index" : "Direct file scan")")
        print("🔄 Parallel: \(parallel) workers")

        // Load DAT file
        RomKitCLI.printSection("Loading DAT File")
        let datFile = try await loadDATFile(from: datURL)
        print("✅ Loaded \(datFile.games.count) games from DAT")

        // Fast path: use index if requested
        let results: AnalysisResults
        if useIndex {
            RomKitCLI.printSection("Analyzing ROMs using Index")
            results = try await analyzeWithIndex(
                romDirectory: romURL,
                datFile: datFile,
                showProgress: showProgress
            )
        } else {
            // Scan ROM directory
            RomKitCLI.printSection("Scanning ROM Directory")
            let romFiles = try await scanROMDirectory(at: romURL)
            print("✅ Found \(romFiles.count) ROM files")

            // Analyze ROMs
            RomKitCLI.printSection("Analyzing ROMs")
            results = try await analyzeROMs(
                romFiles: romFiles,
                datFile: datFile,
                useGPU: gpu,
                skipVerification: skipVerification,
                parallel: parallel,
                showProgress: showProgress
            )
        }

        // Display results
        displayResults(results)

        // Export if requested
        if let outputPath = output {
            try exportResults(results, to: outputPath)
            print("\n📊 Results exported to: \(outputPath)")
        }
    }

    private func loadDATFile(from url: URL) async throws -> DATFile {
        // Try to load as string first to handle encoding issues
        let fileContent = try String(contentsOf: url, encoding: .utf8)
        let data = Data(fileContent.utf8)

        // Parse using MAME parser
        let mameDatFile: MAMEDATFile

        do {
            // Try fast parser first
            let parser = MAMEFastParser()
            mameDatFile = try await parser.parseXMLParallel(data: data)
        } catch {
            print("⚠️ Fast parser failed: \(error.localizedDescription)")
            print("Attempting full parser...")
            // Try the full MAME parser as fallback
            let fullParser = MAMEDATParser()
            mameDatFile = try fullParser.parse(data: data)
        }

        // Convert MAMEDATFile to DATFile
        let games = mameDatFile.games.compactMap { gameEntry -> Game? in
            // Convert GameEntry to Game
            // Convert ROMItems to ROMs
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

            // Try to get cloneOf and romOf from metadata if it's MAMEGameMetadata
            var cloneOf: String?
            var romOf: String?

            if let mameGameMetadata = gameEntry.metadata as? MAMEGameMetadata {
                cloneOf = mameGameMetadata.cloneOf
                romOf = mameGameMetadata.romOf
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
            name: mameDatFile.metadata.name,
            description: mameDatFile.metadata.description,
            version: mameDatFile.formatVersion,
            author: nil,
            games: games
        )
    }

    private func scanROMDirectory(at url: URL) async throws -> [ROMFile] {
        let scanner = ConcurrentScanner()
        var romFiles: [ROMFile] = []

        let results = try await scanner.scanDirectory(
            at: url,
            computeHashes: false // We'll compute hashes during analysis
        )

        for result in results {
            if result.isArchive {
                // It's a ZIP file containing ROMs
                romFiles.append(ROMFile(
                    url: result.url,
                    size: result.size,
                    isArchive: true
                ))
            } else if ["rom", "bin", "chd"].contains(result.url.pathExtension.lowercased()) {
                // Individual ROM file
                romFiles.append(ROMFile(
                    url: result.url,
                    size: result.size,
                    isArchive: false
                ))
            }
        }

        return romFiles
    }

    private func analyzeROMs(
        romFiles: [ROMFile],
        datFile: DATFile,
        useGPU: Bool,
        skipVerification: Bool,
        parallel: Int,
        showProgress: Bool
    ) async throws -> AnalysisResults {
        var results = AnalysisResults()
        let totalFiles = romFiles.count
        var processedFiles = 0

        // Create a game lookup dictionary for faster matching
        let gamesByName = Dictionary(
            uniqueKeysWithValues: datFile.games.map { (cleanGameName($0.name), $0) }
        )

        // Analyze each ROM file in parallel
        let startTime = Date()

        // Use actor for thread-safe result collection
        let resultCollector = AnalysisResultCollector()

        await withTaskGroup(of: Void.self) { group in
            var activeJobs = 0
            var fileIterator = romFiles.makeIterator()

            while let romFile = fileIterator.next() {
                // Wait if we've hit the parallel limit
                if activeJobs >= parallel {
                    await group.next()
                    activeJobs -= 1

                    if showProgress {
                        processedFiles += 1
                        let elapsed = Date().timeIntervalSince(startTime)
                        let rate = Double(processedFiles) / elapsed
                        let remaining = Double(totalFiles - processedFiles) / rate
                        let percentage = Double(processedFiles) / Double(totalFiles) * 100

                        let timeStr = remaining > 60
                            ? String(format: "%.0f min", remaining / 60)
                            : String(format: "%.0f sec", remaining)

                        // Clear line and print progress
                        print("\u{1B}[2K\rProgress: \(processedFiles)/\(totalFiles) (\(String(format: "%.1f%%", percentage))) - ETA: \(timeStr)", terminator: "")
                        fflush(stdout)
                    }
                }

                // Start new analysis job
                activeJobs += 1
                group.addTask {
                    let gameName = self.cleanGameName(romFile.url.deletingPathExtension().lastPathComponent)

                    if romFile.isArchive {
                        // Analyze ZIP archive
                        if let result = try? await self.analyzeArchiveParallel(
                            romFile: romFile,
                            gameName: gameName,
                            gamesByName: gamesByName,
                            useGPU: useGPU,
                            skipVerification: skipVerification
                        ) {
                            await resultCollector.add(result)
                        }
                    } else {
                        // Analyze individual ROM
                        if let result = try? await self.analyzeIndividualROMParallel(
                            romFile: romFile,
                            gameName: gameName,
                            gamesByName: gamesByName,
                            useGPU: useGPU,
                            skipVerification: skipVerification
                        ) {
                            await resultCollector.add(result)
                        }
                    }
                }
            }

            // Process remaining results
            for await _ in group {
                if showProgress {
                    processedFiles += 1
                    let percentage = Double(processedFiles) / Double(totalFiles) * 100
                    print("\u{1B}[2K\rProgress: \(processedFiles)/\(totalFiles) (\(String(format: "%.1f%%", percentage)))", terminator: "")
                    fflush(stdout)
                }
            }
        }

        results = await resultCollector.getResults()

        if showProgress {
            print("") // New line after progress
        }

        // Find missing games (in DAT but not on disk)
        let foundGameNames = Set(results.complete.keys)
            .union(results.incomplete.keys)
            .union(results.broken.keys)

        for game in datFile.games {
            let gameName = cleanGameName(game.name)
            if !foundGameNames.contains(gameName) {
                results.missing[gameName] = game
            }
        }

        return results
    }

    private func analyzeArchive(
        romFile: ROMFile,
        gameName: String,
        gamesByName: [String: Game],
        results: inout AnalysisResults,
        useGPU: Bool
    ) async throws {
        guard let expectedGame = gamesByName[gameName] else {
            results.unrecognized.append(romFile)
            return
        }

        let handler = ParallelZIPArchiveHandler()
        let entries: [ArchiveEntry]

        do {
            entries = try handler.listContents(of: romFile.url)
        } catch {
            // If we can't list contents, mark as broken
            results.broken[gameName] = GameStatus(
                game: expectedGame,
                foundROMs: [],
                missingROMs: expectedGame.roms.map { $0.name },
                brokenROMs: ["Failed to read archive: \(error.localizedDescription)"]
            )
            return
        }

        var matchedROMs: Set<String> = []
        var brokenROMs: [String: String] = [:] // ROM name -> issue

        for entry in entries {
            let romName = entry.path.lowercased()

            // Find matching ROM in game
            if let expectedROM = expectedGame.roms.first(where: { $0.name.lowercased() == romName }) {
                do {
                    // Extract and verify CRC
                    let data = try handler.extract(entry: entry, from: romFile.url)
                    let actualCRC = useGPU
                        ? await ParallelHashUtilities.crc32GPU(data: data)
                        : HashUtilities.crc32(data: data)

                    if let expectedCRC = expectedROM.crc,
                       actualCRC.lowercased() == expectedCRC.lowercased() {
                        matchedROMs.insert(romName)
                    } else if let expectedCRC = expectedROM.crc {
                        brokenROMs[romName] = "CRC mismatch: expected \(expectedCRC), got \(actualCRC)"
                    } else {
                        // ROM has no CRC to verify
                        matchedROMs.insert(romName)
                    }
                } catch {
                    // If extraction fails, mark this ROM as broken
                    brokenROMs[romName] = "Extraction failed: \(error.localizedDescription)"
                }
            }
        }

        // Determine game status
        let requiredROMs = Set(expectedGame.roms.map { $0.name.lowercased() })
        let missingROMs = requiredROMs.subtracting(matchedROMs).subtracting(brokenROMs.keys)

        if !brokenROMs.isEmpty {
            results.broken[gameName] = GameStatus(
                game: expectedGame,
                foundROMs: Array(matchedROMs),
                missingROMs: Array(missingROMs),
                brokenROMs: Array(brokenROMs.keys)
            )
        } else if missingROMs.isEmpty {
            results.complete[gameName] = GameStatus(
                game: expectedGame,
                foundROMs: Array(matchedROMs),
                missingROMs: [],
                brokenROMs: []
            )
        } else {
            results.incomplete[gameName] = GameStatus(
                game: expectedGame,
                foundROMs: Array(matchedROMs),
                missingROMs: Array(missingROMs),
                brokenROMs: []
            )
        }
    }

    private func analyzeIndividualROM(
        romFile: ROMFile,
        gameName: String,
        gamesByName: [String: Game],
        results: inout AnalysisResults,
        useGPU: Bool
    ) async throws {
        // For individual ROM files, we'd need more complex logic
        // to group them by game. For now, mark as unrecognized
        results.unrecognized.append(romFile)
    }

    private func cleanGameName(_ name: String) -> String {
        // Remove common suffixes and clean up game names for matching
        return name
            .replacingOccurrences(of: ".zip", with: "")
            .replacingOccurrences(of: ".7z", with: "")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func displayResults(_ results: AnalysisResults) {
        RomKitCLI.printHeader("📊 Analysis Results")

        let total = results.complete.count + results.incomplete.count +
                   results.broken.count + results.missing.count

        print("\n📈 Summary:")
        print("  Total games in DAT: \(total)")
        print("  ✅ Complete: \(results.complete.count) (\(RomKitCLI.formatPercentage(Double(results.complete.count) / Double(max(total, 1)))))")
        print("  ⚠️  Incomplete: \(results.incomplete.count) (\(RomKitCLI.formatPercentage(Double(results.incomplete.count) / Double(max(total, 1)))))")
        print("  ❌ Broken: \(results.broken.count) (\(RomKitCLI.formatPercentage(Double(results.broken.count) / Double(max(total, 1)))))")
        print("  📭 Missing: \(results.missing.count) (\(RomKitCLI.formatPercentage(Double(results.missing.count) / Double(max(total, 1)))))")
        print("  ❓ Unrecognized files: \(results.unrecognized.count)")

        if verbose {
            if !results.broken.isEmpty {
                RomKitCLI.printSection("❌ Broken Games")
                for (name, status) in results.broken.sorted(by: { $0.key < $1.key }).prefix(10) {
                    print("\n  \(name):")
                    for issue in status.issues {
                        print("    - \(issue)")
                    }
                }
                if results.broken.count > 10 {
                    print("  ... and \(results.broken.count - 10) more")
                }
            }

            if !results.incomplete.isEmpty {
                RomKitCLI.printSection("⚠️  Incomplete Games")
                for (name, status) in results.incomplete.sorted(by: { $0.key < $1.key }).prefix(10) {
                    print("\n  \(name):")
                    for issue in status.issues.prefix(3) {
                        print("    - \(issue)")
                    }
                    if status.issues.count > 3 {
                        print("    ... and \(status.issues.count - 3) more issues")
                    }
                }
                if results.incomplete.count > 10 {
                    print("  ... and \(results.incomplete.count - 10) more")
                }
            }

            if !results.missing.isEmpty {
                RomKitCLI.printSection("📭 Missing Games (Top 10)")
                for (name, _) in results.missing.sorted(by: { $0.key < $1.key }).prefix(10) {
                    print("  - \(name)")
                }
                if results.missing.count > 10 {
                    print("  ... and \(results.missing.count - 10) more")
                }
            }
        }
    }

    private func exportResults(_ results: AnalysisResults, to path: String) throws {
        let export = AnalysisExport(
            timestamp: Date(),
            summary: AnalysisSummary(
                totalGames: results.complete.count + results.incomplete.count +
                           results.broken.count + results.missing.count,
                complete: results.complete.count,
                incomplete: results.incomplete.count,
                broken: results.broken.count,
                missing: results.missing.count,
                unrecognized: results.unrecognized.count
            ),
            completeGames: Array(results.complete.keys).sorted(),
            incompleteGames: results.incomplete.mapValues { $0.issues },
            brokenGames: results.broken.mapValues { $0.issues },
            missingGames: Array(results.missing.keys).sorted()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(export)
        try data.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - Data Structures

struct ROMFile {
    let url: URL
    let size: UInt64
    let isArchive: Bool
}

struct GameStatus {
    let game: Game
    let foundROMs: [String]
    let missingROMs: [String]
    let brokenROMs: [String]

    var issues: [String] {
        var issues: [String] = []
        for rom in missingROMs {
            issues.append("Missing: \(rom)")
        }
        for rom in brokenROMs {
            issues.append("Broken: \(rom)")
        }
        return issues
    }
}

struct AnalysisResults {
    var complete: [String: GameStatus] = [:]
    var incomplete: [String: GameStatus] = [:]
    var broken: [String: GameStatus] = [:]
    var missing: [String: Game] = [:]
    var unrecognized: [ROMFile] = []
}

struct AnalysisExport: Codable {
    let timestamp: Date
    let summary: AnalysisSummary
    let completeGames: [String]
    let incompleteGames: [String: [String]]
    let brokenGames: [String: [String]]
    let missingGames: [String]
}

struct AnalysisSummary: Codable {
    let totalGames: Int
    let complete: Int
    let incomplete: Int
    let broken: Int
    let missing: Int
    let unrecognized: Int
}

// MARK: - Parallel Analysis Support

/// Actor for thread-safe result collection
actor AnalysisResultCollector {
    private var results = AnalysisResults()

    func add(_ result: SingleGameResult) {
        switch result {
        case .complete(let name, let status):
            results.complete[name] = status
        case .incomplete(let name, let status):
            results.incomplete[name] = status
        case .broken(let name, let status):
            results.broken[name] = status
        case .unrecognized(let file):
            results.unrecognized.append(file)
        }
    }

    func getResults() -> AnalysisResults {
        return results
    }
}

enum SingleGameResult {
    case complete(String, GameStatus)
    case incomplete(String, GameStatus)
    case broken(String, GameStatus)
    case unrecognized(ROMFile)
}

// MARK: - Fast Analysis with Index

extension Analyze {
    private func analyzeWithIndex(
        romDirectory: URL,
        datFile: DATFile,
        showProgress: Bool
    ) async throws -> AnalysisResults {
        // Initialize index manager
        let indexManager = try await ROMIndexManager()

        // Check if this directory is indexed
        let sources = await indexManager.listSources()
        let isIndexed = sources.contains { source in
            URL(fileURLWithPath: source.path).standardized == romDirectory.standardized
        }

        if !isIndexed {
            print("⚠️  Directory not indexed. Indexing now...")
            try await indexManager.addSource(romDirectory, showProgress: showProgress)
        }

        print("✅ Using indexed ROMs for fast analysis")

        // Load entire index into memory for fast lookups
        print("Loading index into memory...")
        let memoryIndex = await indexManager.loadIndexIntoMemory()
        print("✅ Loaded \(memoryIndex.count) unique CRCs")

        var results = AnalysisResults()
        let totalGames = datFile.games.count
        var processedGames = 0

        // Analyze each game
        for game in datFile.games {
            if showProgress {
                processedGames += 1
                let percentage = Double(processedGames) / Double(totalGames) * 100
                print("\rAnalyzing: \(processedGames)/\(totalGames) (\(String(format: "%.1f%%", percentage)))", terminator: "")
                fflush(stdout)
            }

            let gameName = cleanGameName(game.name)
            var foundROMs: [String] = []
            var missingROMs: [String] = []

            // Check each ROM using in-memory index
            for rom in game.roms {
                if let crc = rom.crc?.lowercased() {
                    if memoryIndex[crc] != nil {
                        foundROMs.append(rom.name)
                    } else {
                        missingROMs.append(rom.name)
                    }
                }
            }

            // Determine game status
            if missingROMs.isEmpty && !foundROMs.isEmpty {
                results.complete[gameName] = GameStatus(
                    game: game,
                    foundROMs: foundROMs,
                    missingROMs: [],
                    brokenROMs: []
                )
            } else if !foundROMs.isEmpty {
                results.incomplete[gameName] = GameStatus(
                    game: game,
                    foundROMs: foundROMs,
                    missingROMs: missingROMs,
                    brokenROMs: []
                )
            } else {
                results.missing[gameName] = game
            }
        }

        if showProgress {
            print("") // New line after progress
        }

        return results
    }

    private func analyzeArchiveParallel(
        romFile: ROMFile,
        gameName: String,
        gamesByName: [String: Game],
        useGPU: Bool,
        skipVerification: Bool
    ) async throws -> SingleGameResult {
        guard let expectedGame = gamesByName[gameName] else {
            return .unrecognized(romFile)
        }

        let handler = ParallelZIPArchiveHandler()
        let entries = try handler.listContents(of: romFile.url)

        var foundROMs: [String] = []
        var missingROMs: [String] = []
        var brokenROMs: [String] = []

        for expectedROM in expectedGame.roms {
            if let entry = entries.first(where: { $0.path == expectedROM.name }) {
                foundROMs.append(expectedROM.name)

                // Skip verification if requested
                if !skipVerification {
                    if let expectedCRC = expectedROM.crc,
                       let actualCRC = entry.crc32,
                       actualCRC.lowercased() != expectedCRC.lowercased() {
                        brokenROMs.append(expectedROM.name)
                    }
                }
            } else {
                missingROMs.append(expectedROM.name)
            }
        }

        let status = GameStatus(
            game: expectedGame,
            foundROMs: foundROMs,
            missingROMs: missingROMs,
            brokenROMs: brokenROMs
        )

        if missingROMs.isEmpty && brokenROMs.isEmpty {
            return .complete(gameName, status)
        } else if !brokenROMs.isEmpty {
            return .broken(gameName, status)
        } else {
            return .incomplete(gameName, status)
        }
    }

    private func analyzeIndividualROMParallel(
        romFile: ROMFile,
        gameName: String,
        gamesByName: [String: Game],
        useGPU: Bool,
        skipVerification: Bool
    ) async throws -> SingleGameResult {
        guard let expectedGame = gamesByName[gameName] else {
            return .unrecognized(romFile)
        }

        // For individual ROM files, we need more complex logic
        // This is a simplified version
        let status = GameStatus(
            game: expectedGame,
            foundROMs: [romFile.url.lastPathComponent],
            missingROMs: [],
            brokenROMs: []
        )

        return .incomplete(gameName, status)
    }
}
