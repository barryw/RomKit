//
//  AnalyzeJSON.swift
//  RomKit CLI - JSON Analysis Output
//
//  Structured analysis output for pipeline processing
//

import Foundation
import RomKit

// MARK: - JSON Output Structures

public struct AnalysisJSON: Codable {
    let metadata: AnalysisMetadata
    let complete: [String: GameAnalysis]
    let incomplete: [String: GameAnalysis]
    let broken: [String: GameAnalysis]
    let missing: [String]
    let unrecognized: [UnrecognizedFile]

    public struct AnalysisMetadata: Codable {
        let datFile: String
        let analyzedAt: Date
        let sourceDirectory: String
        let totalGames: Int
        let romCount: Int
    }

    public struct GameAnalysis: Codable {
        let status: GameStatus
        let foundROMs: [ROMAnalysis]?
        let missingROMs: [ROMReference]?
        let issues: [ROMIssue]?
    }

    public enum GameStatus: String, Codable {
        case complete
        case incomplete
        case broken
    }

    public struct ROMAnalysis: Codable {
        let name: String
        let crc32: String
        let size: UInt64
        let location: String // File or archive path
        let verified: Bool
    }

    public struct ROMReference: Codable {
        let name: String
        let crc32: String?
        let size: UInt64
    }

    public struct ROMIssue: Codable {
        let rom: String
        let issue: String
        let expectedCRC: String?
        let actualCRC: String?
    }

    public struct UnrecognizedFile: Codable {
        let path: String
        let size: UInt64
    }
}

// MARK: - Analyze Extension for JSON Output

extension Analyze {

    func outputJSON(_ results: AnalysisResults, to url: URL? = nil) throws {
        let json = convertToJSON(results)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(json)

        if let url = url {
            try data.write(to: url)
        } else {
            // Output to stdout for piping
            print(String(data: data, encoding: .utf8) ?? "{}")
        }
    }

    private func convertToJSON(_ results: AnalysisResults) -> AnalysisJSON {
        var completeGames: [String: AnalysisJSON.GameAnalysis] = [:]
        var incompleteGames: [String: AnalysisJSON.GameAnalysis] = [:]
        var brokenGames: [String: AnalysisJSON.GameAnalysis] = [:]

        // Convert complete games
        for (name, status) in results.complete {
            completeGames[name] = AnalysisJSON.GameAnalysis(
                status: AnalysisJSON.GameStatus.complete,
                foundROMs: status.game.roms.map { rom in
                    AnalysisJSON.ROMAnalysis(
                        name: rom.name,
                        crc32: rom.crc ?? "",
                        size: rom.size,
                        location: "\(name).zip",
                        verified: true
                    )
                },
                missingROMs: nil,
                issues: nil
            )
        }

        // Convert incomplete games
        for (name, status) in results.incomplete {
            incompleteGames[name] = AnalysisJSON.GameAnalysis(
                status: AnalysisJSON.GameStatus.incomplete,
                foundROMs: nil, // Would need to track this
                missingROMs: status.issues.compactMap { issue in
                    if issue.hasPrefix("Missing ROM:") {
                        let romName = String(issue.dropFirst("Missing ROM: ".count))
                        return AnalysisJSON.ROMReference(
                            name: romName,
                            crc32: nil,
                            size: 0
                        )
                    }
                    return nil
                },
                issues: nil
            )
        }

        // Convert broken games
        for (name, status) in results.broken {
            brokenGames[name] = AnalysisJSON.GameAnalysis(
                status: AnalysisJSON.GameStatus.broken,
                foundROMs: nil,
                missingROMs: nil,
                issues: status.issues.map { issue in
                    AnalysisJSON.ROMIssue(
                        rom: name,
                        issue: issue,
                        expectedCRC: nil,
                        actualCRC: nil
                    )
                }
            )
        }

        // Convert unrecognized files
        let unrecognized = results.unrecognized.map { file in
            AnalysisJSON.UnrecognizedFile(
                path: file.url.path,
                size: file.size
            )
        }

        return AnalysisJSON(
            metadata: AnalysisJSON.AnalysisMetadata(
                datFile: datPath,
                analyzedAt: Date(),
                sourceDirectory: romPath,
                totalGames: results.complete.count + results.incomplete.count +
                          results.broken.count + results.missing.count,
                romCount: results.complete.values.flatMap { $0.game.roms }.count
            ),
            complete: completeGames,
            incomplete: incompleteGames,
            broken: brokenGames,
            missing: results.missing.keys.map { $0 },
            unrecognized: unrecognized
        )
    }
}

// MARK: - Rebuild Extension to Consume JSON

extension Rebuild {

    func rebuildFromAnalysis(_ analysisPath: String) async throws {
        let data: Data

        if analysisPath == "-" {
            // Read from stdin
            data = FileHandle.standardInput.readDataToEndOfFile()
        } else {
            let url = URL(fileURLWithPath: analysisPath)
            data = try Data(contentsOf: url)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let analysis = try decoder.decode(AnalysisJSON.self, from: data)

        print("📊 Loaded analysis of \(analysis.metadata.totalGames) games")
        print("  ✅ Complete: \(analysis.complete.count) (skipping)")
        print("  ⚠️  Incomplete: \(analysis.incomplete.count) (will rebuild)")
        print("  ❌ Broken: \(analysis.broken.count) (will rebuild)")
        print("  📭 Missing: \(analysis.missing.count) (will attempt)")

        // Build list of games that need work
        var gamesToRebuild: Set<String> = []
        gamesToRebuild.formUnion(analysis.incomplete.keys)
        gamesToRebuild.formUnion(analysis.broken.keys)
        gamesToRebuild.formUnion(analysis.missing)

        // Now proceed with targeted rebuild
        await performTargetedRebuild(games: gamesToRebuild, analysis: analysis)
    }

    private func performTargetedRebuild(games: Set<String>, analysis: AnalysisJSON) async {
        // This is where we'd integrate with the existing rebuild logic
        // but only process the games identified by the analysis

        for gameName in games {
            // Check if we have any ROMs for this game
            if analysis.incomplete[gameName] != nil {
                print("🔄 Rebuilding incomplete game: \(gameName)")
                // Use incomplete.foundROMs to know what we already have
                // Use incomplete.missingROMs to know what to look for
            } else if analysis.broken[gameName] != nil {
                print("🔧 Fixing broken game: \(gameName)")
                // Need to replace broken ROMs
            } else if analysis.missing.contains(gameName) {
                print("🔍 Searching for missing game: \(gameName)")
                // Need to find all ROMs
            }
        }
    }
}
