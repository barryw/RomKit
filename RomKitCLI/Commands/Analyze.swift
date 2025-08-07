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
        
        // Load DAT file
        RomKitCLI.printSection("Loading DAT File")
        let datFile = try await loadDATFile(from: datURL)
        print("✅ Loaded \(datFile.games.count) games from DAT")
        
        // Scan ROM directory
        RomKitCLI.printSection("Scanning ROM Directory")
        let romFiles = try await scanROMDirectory(at: romURL)
        print("✅ Found \(romFiles.count) ROM files")
        
        // Analyze ROMs
        RomKitCLI.printSection("Analyzing ROMs")
        let results = try await analyzeROMs(
            romFiles: romFiles,
            datFile: datFile,
            useGPU: gpu,
            showProgress: showProgress
        )
        
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
        let data = fileContent.data(using: .utf8)!
        
        // Parse using MAME parser
        let parser = MAMEFastParser()
        let mameDatFile: MAMEDATFile
        
        do {
            mameDatFile = try await parser.parseXMLParallel(data: data)
        } catch {
            print("⚠️ XML parsing failed: \(error.localizedDescription)")
            print("Attempting fallback parser...")
            // Try the regular parser as fallback
            mameDatFile = try parser.parseXMLStreaming(data: data)
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
            var cloneOf: String? = nil
            var romOf: String? = nil
            
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
        showProgress: Bool
    ) async throws -> AnalysisResults {
        var results = AnalysisResults()
        let totalFiles = romFiles.count
        var processedFiles = 0
        
        // Create a game lookup dictionary for faster matching
        let gamesByName = Dictionary(
            uniqueKeysWithValues: datFile.games.map { (cleanGameName($0.name), $0) }
        )
        
        // Analyze each ROM file
        let startTime = Date()
        for romFile in romFiles {
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
            
            let gameName = cleanGameName(romFile.url.deletingPathExtension().lastPathComponent)
            
            if romFile.isArchive {
                // Analyze ZIP archive
                try await analyzeArchive(
                    romFile: romFile,
                    gameName: gameName,
                    gamesByName: gamesByName,
                    results: &results,
                    useGPU: useGPU
                )
            } else {
                // Analyze individual ROM
                try await analyzeIndividualROM(
                    romFile: romFile,
                    gameName: gameName,
                    gamesByName: gamesByName,
                    results: &results,
                    useGPU: useGPU
                )
            }
        }
        
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
                issues: ["Failed to read archive: \(error.localizedDescription)"]
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
                issues: Array(brokenROMs.values)
            )
        } else if missingROMs.isEmpty {
            results.complete[gameName] = expectedGame
        } else {
            results.incomplete[gameName] = GameStatus(
                game: expectedGame,
                issues: missingROMs.map { "Missing ROM: \($0)" }
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
    let issues: [String]
}

struct AnalysisResults {
    var complete: [String: Game] = [:]
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