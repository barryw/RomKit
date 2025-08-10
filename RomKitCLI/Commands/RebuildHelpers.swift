//
//  RebuildHelpers.swift
//  RomKit CLI - Rebuild Command Helpers
//
//  Helper functions and extensions for the Rebuild command
//

import Foundation
import RomKit

// MARK: - Rebuild Extension for Helper Methods

extension Rebuild {
    func convertMAMEToGeneric(_ mameDAT: MAMEDATFile) -> DATFile {
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

            var cloneOf: String?
            var romOf: String?

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

    func printDryRunSummary(_ requirements: RebuildRequirements) {
        print("\n🎯 Sample games to rebuild:")
        let samplesToShow = min(5, requirements.gamesToRebuild.count)
        for req in requirements.gamesToRebuild.prefix(samplesToShow) {
            let status = req.missingROMs.isEmpty ? "✅" : "⚠️"
            print("   \(status) \(req.game.name)")
            if !req.missingROMs.isEmpty {
                print("      Missing \(req.missingROMs.count) of \(req.availableROMs.count + req.missingROMs.count) ROMs")
            }
        }

        if requirements.gamesToRebuild.count > samplesToShow {
            print("\n   ... and \(requirements.gamesToRebuild.count - samplesToShow) more games")
        }

        print("\n💡 Run without --dry-run to perform the rebuild")
    }

    func displayRebuildResults(_ results: RebuildResults) {
        RomKitCLI.printSection("Rebuild Complete")

        let total = results.successful + results.failed
        let successRate = total > 0 ? Int(Double(results.successful) / Double(total) * 100) : 0

        print("\n📊 Results:")
        print("   • Games processed: \(total.formatted())")
        print("     - ✅ Successful: \(results.successful.formatted()) (\(successRate)%)")
        if results.failed > 0 {
            print("     - ❌ Failed: \(results.failed.formatted())")
        }
        print("   • ROMs rebuilt: \(results.totalROMs.formatted())")

        if !results.errors.isEmpty {
            print("\n❌ Failed games (showing first 5):")
            for (game, error) in results.errors.prefix(5) {
                print("   • \(game): \(error)")
            }
            if results.errors.count > 5 {
                print("   ... and \(results.errors.count - 5) more")
            }
        }

        if results.successful > 0 {
            print("\n✅ Rebuild completed successfully!")
        }
    }

    func processGameResult(_ result: GameRebuildResult, results: inout RebuildResults) {
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

    func printProgress(_ current: Int, total: Int) {
        let percentage = Double(current) / Double(total) * 100
        print("\rProgress: \(current)/\(total) (\(String(format: "%.1f%%", percentage)))", terminator: "")
        fflush(stdout)
    }
}

// MARK: - Helper Functions

func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}
