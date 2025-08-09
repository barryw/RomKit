//
//  AnalyzeWithIndex.swift
//  RomKit CLI - Index-Aware Analyze Command
//
//  Example of how analyze could use the index system
//

import ArgumentParser
import Foundation
import RomKit

private enum IndexError: Error {
    case noIndex
}

struct AnalyzeWithIndex: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze-indexed",
        abstract: "Analyze ROMs using the index system for better performance"
    )

    @Argument(help: "Path to the ROM directory to analyze")
    var romPath: String

    @Argument(help: "Path to the MAME DAT file")
    var datPath: String

    @Flag(name: .long, help: "Force re-scan even if index exists")
    var forceScan = false

    @Flag(name: .long, help: "Auto-create index if missing")
    var autoIndex = false

    @Option(name: .long, help: "Path to index database")
    var indexPath: String?

    private func handleIndexing(indexManager: ROMIndexManager, romURL: URL) async throws {
        let sources = await indexManager.listSources()
        let isIndexed = sources.contains { $0.path == romURL.path }

        if isIndexed && !forceScan {
            handleExistingIndex(sources: sources, romURL: romURL)
        } else if !isIndexed {
            try await handleMissingIndex(indexManager: indexManager, romURL: romURL)
        } else if forceScan {
            print("🔄 Force re-scanning directory...")
            try await indexManager.refreshSources([romURL], showProgress: true)
        }
    }

    private func handleExistingIndex(sources: [SourceInfo], romURL: URL) {
        print("✅ Using existing index for fast analysis")
        if let source = sources.first(where: { $0.path == romURL.path }) {
            let age = Date().timeIntervalSince(source.lastScan)
            if age > 86400 { // 24 hours
                print("⚠️  Index is \(Int(age/3600)) hours old")
                print("   Consider refreshing with --force-scan")
            }
        }
    }

    private func handleMissingIndex(indexManager: ROMIndexManager, romURL: URL) async throws {
        if autoIndex {
            print("📂 Creating index for faster future analysis...")
            try await indexManager.addSource(romURL, showProgress: true)
        } else {
            print("ℹ️  No index found for this directory")
            print("   Create one with --auto-index for faster analysis")
            print("   Falling back to direct scan...")
            let scanner = ConcurrentScanner()
            _ = try await scanner.scanDirectory(at: romURL, computeHashes: true)
            throw IndexError.noIndex
        }
    }

    mutating func run() async throws {
        let romURL = URL(fileURLWithPath: romPath)
        let datURL = URL(fileURLWithPath: datPath)

        // Initialize index manager
        let dbPath = indexPath.map { URL(fileURLWithPath: $0) }
        let indexManager = try await ROMIndexManager(databasePath: dbPath)

        // Handle indexing
        try await handleIndexing(indexManager: indexManager, romURL: romURL)

        // Now perform analysis using the index
        print("\n📊 Analyzing using index...")

        // Load DAT file
        let datFile = try await loadDATFile(from: datURL)

        // Analyze each game using the index
        var complete = 0
        var incomplete = 0
        var missing = 0

        for game in datFile.games {
            var foundROMs = 0
            let requiredROMs = game.roms.count

            for rom in game.roms where await indexManager.findBestSource(for: rom) != nil {
                foundROMs += 1
            }

            if foundROMs == requiredROMs && requiredROMs > 0 {
                complete += 1
            } else if foundROMs > 0 {
                incomplete += 1
            } else {
                missing += 1
            }
        }

        print("\n📈 Results:")
        print("  ✅ Complete: \(complete) games")
        print("  ⚠️  Incomplete: \(incomplete) games")
        print("  ❌ Missing: \(missing) games")

        // Show index statistics
        let analysis = await indexManager.analyzeIndex()
        print("\n💾 Index Statistics:")
        print("  Total ROMs: \(analysis.totalROMs)")
        print("  Unique CRCs: \(analysis.uniqueROMs)")
        print("  Duplicates: \(analysis.totalDuplicates)")
        if !analysis.recommendations.isEmpty {
            print("\n💡 Recommendations:")
            for rec in analysis.recommendations {
                print("  • \(rec)")
            }
        }
    }

    private func loadDATFile(from url: URL) async throws -> DATFile {
        // Implementation from Rebuild.swift
        let fileContent = try String(contentsOf: url, encoding: .utf8)
        let data = Data(fileContent.utf8)

        let parser = MAMEFastParser()
        if let mameDatFile = try? await parser.parseXMLParallel(data: data) {
            return convertMAMEToGeneric(mameDatFile)
        }

        let logiqxParser = LogiqxDATParser()
        let mameDatFile = try logiqxParser.parse(data: data)
        return convertMAMEToGeneric(mameDatFile)
    }

    private func convertMAMEToGeneric(_ mameDAT: MAMEDATFile) -> DATFile {
        // Implementation from Rebuild.swift
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

            return Game(
                name: gameEntry.name,
                description: gameEntry.description,
                cloneOf: (gameEntry.metadata as? MAMEGameMetadata)?.cloneOf,
                romOf: (gameEntry.metadata as? MAMEGameMetadata)?.romOf,
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
}
