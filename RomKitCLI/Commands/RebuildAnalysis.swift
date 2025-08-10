//
//  RebuildAnalysis.swift
//  RomKit CLI - Rebuild Analysis Functions
//
//  Analysis and requirement checking for the Rebuild command
//

import Foundation
import RomKit

// MARK: - Analysis Structures

struct SkippedCounts {
    var complete = 0
    var incomplete = 0
    var nonWorking = 0
    var badDumps = 0
}

struct GameAnalysis {
    let requirement: GameRebuildRequirement
    let shouldRebuild: Bool
}

struct GameAnalysisContext {
    let indexManager: ROMIndexManager
    let memoryIndex: [String: [IndexedROM]]
    let outputDirectory: URL
    let updateMode: Bool
    let allowIncomplete: Bool
}

// MARK: - Analysis Functions

extension Rebuild {
    func analyzeRebuildRequirements(
        datFile: any DATFormat,
        outputDirectory: URL,
        indexManager: ROMIndexManager,
        updateMode: Bool,
        allowIncomplete: Bool,
        includeNonWorking: Bool,
        includeBadDumps: Bool,
        showProgress: Bool
    ) async throws -> RebuildRequirements {
        RomKitCLI.printSection("Analyzing Requirements")

        // Load entire index into memory for fast lookups
        let allMemoryIndex = await indexManager.loadIndexIntoMemory()

        // Filter out ROMs from the output directory to prevent circular dependency
        let outputPathStandardized = outputDirectory.standardizedFileURL.path
        var memoryIndex: [String: [IndexedROM]] = [:]
        var excludedCount = 0

        for (crc, roms) in allMemoryIndex {
            let filteredROMs = roms.filter { rom in
                switch rom.location {
                case .file(let path):
                    let romPath = path.standardizedFileURL.path
                    // Check if this ROM is in the output directory
                    if romPath.hasPrefix(outputPathStandardized) {
                        excludedCount += 1
                        return false
                    }
                    return true
                case .archive(let archivePath, _):
                    let archivePathStandardized = archivePath.standardizedFileURL.path
                    // Check if this archive is in the output directory
                    if archivePathStandardized.hasPrefix(outputPathStandardized) {
                        excludedCount += 1
                        return false
                    }
                    return true
                case .remote:
                    return true // Remote sources are always allowed
                }
            }

            if !filteredROMs.isEmpty {
                memoryIndex[crc] = filteredROMs
            }
        }

        let games = datFile.games
        print("📊 Analyzing \(games.count.formatted()) games...")
        var requirements = RebuildRequirements()
        var skippedCounts = SkippedCounts()
        var processedCount = 0

        // Process all games to determine what needs rebuilding
        for game in games {
            if showProgress && processedCount % 500 == 0 {
                let percentage = Int(Double(processedCount) / Double(games.count) * 100)
                print("\r   Processing: \(percentage)%", terminator: "")
                fflush(stdout)
            }
            processedCount += 1

            // Skip non-working games if filtered
            if shouldSkipNonWorking(game, includeNonWorking: includeNonWorking) {
                skippedCounts.nonWorking += 1
                continue
            }

            // Get game ROMs
            let gameRoms = getGameROMs(from: game)

            // Skip games with bad dumps if filtered
            if shouldSkipBadDumps(gameRoms, includeBadDumps: includeBadDumps) {
                skippedCounts.badDumps += 1
                continue
            }

            // Analyze game requirements
            let context = GameAnalysisContext(
                indexManager: indexManager,
                memoryIndex: memoryIndex,
                outputDirectory: outputDirectory,
                updateMode: updateMode,
                allowIncomplete: allowIncomplete
            )
            let gameAnalysis = analyzeGameRequirements(
                game: game,
                gameRoms: gameRoms,
                context: context,
                requirements: &requirements,
                skippedCounts: &skippedCounts
            )

            if gameAnalysis.shouldRebuild {
                requirements.gamesToRebuild.append(gameAnalysis.requirement)
            }
        }

        if showProgress {
            print("\r   Processing: Complete                       ")
        }

        printSkippedSummary(skippedCounts, updateMode: updateMode)

        return requirements
    }

    func shouldSkipNonWorking(_ game: any GameEntry, includeNonWorking: Bool) -> Bool {
        guard !includeNonWorking else { return false }

        if let mameGame = game as? MAMEGame,
           let metadata = mameGame.metadata as? MAMEGameMetadata {
            return metadata.runnable == false
        }
        return false
    }

    func shouldSkipBadDumps(_ gameRoms: [any ROMItem], includeBadDumps: Bool) -> Bool {
        guard !includeBadDumps else { return false }

        for rom in gameRoms {
            if rom.status == .baddump || rom.status == .nodump {
                return true
            }
        }
        return false
    }

    func getGameROMs(from game: any GameEntry) -> [any ROMItem] {
        if let mameGame = game as? MAMEGame {
            return mameGame.items
        }
        return []
    }

    func analyzeGameRequirements(
        game: any GameEntry,
        gameRoms: [any ROMItem],
        context: GameAnalysisContext,
        requirements: inout RebuildRequirements,
        skippedCounts: inout SkippedCounts
    ) -> GameAnalysis {
        var gameRequirement = GameRebuildRequirement(game: game)

        // Find sources for all ROMs
        let legacyROMs = convertToLegacyROMs(gameRoms)
        let sources = context.indexManager.findBestSourcesBatch(for: legacyROMs, using: context.memoryIndex)

        // Categorize ROMs
        for (index, rom) in gameRoms.enumerated() {
            if let source = sources[index] {
                gameRequirement.availableROMs.append((rom, source))
                requirements.availableROMs += 1
            } else {
                gameRequirement.missingROMs.append(rom)
                requirements.missingROMs += 1
            }
            requirements.totalROMs += 1
        }

        // Determine rebuild decision
        let shouldRebuild = determineRebuildDecision(
            game: game,
            gameRequirement: &gameRequirement,
            outputDirectory: context.outputDirectory,
            updateMode: context.updateMode,
            allowIncomplete: context.allowIncomplete,
            skippedCounts: &skippedCounts,
            gameRoms: gameRoms
        )

        return GameAnalysis(requirement: gameRequirement, shouldRebuild: shouldRebuild)
    }

    func convertToLegacyROMs(_ gameRoms: [any ROMItem]) -> [ROM] {
        return gameRoms.map { rom in
            ROM(
                name: rom.name,
                size: rom.size,
                crc: rom.checksums.crc32,
                sha1: rom.checksums.sha1,
                md5: rom.checksums.md5,
                status: rom.status,
                merge: rom.attributes.merge
            )
        }
    }

    func determineRebuildDecision(
        game: any GameEntry,
        gameRequirement: inout GameRebuildRequirement,
        outputDirectory: URL,
        updateMode: Bool,
        allowIncomplete: Bool,
        skippedCounts: inout SkippedCounts,
        gameRoms: [any ROMItem]
    ) -> Bool {
        let isComplete = gameRequirement.missingROMs.isEmpty
        let hasAvailableROMs = !gameRequirement.availableROMs.isEmpty
        let gameOutputPath = outputDirectory.appendingPathComponent("\(game.name).zip")
        let fileExists = FileManager.default.fileExists(atPath: gameOutputPath.path)

        if updateMode {
            return handleUpdateMode(
                fileExists: fileExists,
                isComplete: isComplete,
                hasAvailableROMs: hasAvailableROMs,
                allowIncomplete: allowIncomplete,
                gameOutputPath: gameOutputPath,
                gameRoms: gameRoms,
                skippedCounts: &skippedCounts
            )
        } else {
            return handleFullRebuildMode(
                isComplete: isComplete,
                hasAvailableROMs: hasAvailableROMs,
                allowIncomplete: allowIncomplete,
                skippedCounts: &skippedCounts
            )
        }
    }

    func handleUpdateMode(
        fileExists: Bool,
        isComplete: Bool,
        hasAvailableROMs: Bool,
        allowIncomplete: Bool,
        gameOutputPath: URL,
        gameRoms: [any ROMItem],
        skippedCounts: inout SkippedCounts
    ) -> Bool {
        if !fileExists {
            if isComplete || (allowIncomplete && hasAvailableROMs) {
                return true
            }
            skippedCounts.incomplete += 1
            return false
        }

        // File exists - check if it needs updating
        let isExistingComplete = verifyExistingZIP(gameOutputPath, requiredROMs: gameRoms)
        if isExistingComplete {
            skippedCounts.complete += 1
            return false
        }

        // File is incomplete - rebuild if we can improve it
        if isComplete || (allowIncomplete && hasAvailableROMs) {
            return true
        }
        return false
    }

    func handleFullRebuildMode(
        isComplete: Bool,
        hasAvailableROMs: Bool,
        allowIncomplete: Bool,
        skippedCounts: inout SkippedCounts
    ) -> Bool {
        if isComplete || (allowIncomplete && hasAvailableROMs) {
            return true
        }
        skippedCounts.incomplete += 1
        return false
    }

    func printSkippedSummary(_ counts: SkippedCounts, updateMode: Bool) {
        if counts.incomplete > 0 || counts.nonWorking > 0 || counts.badDumps > 0 || (counts.complete > 0 && updateMode) {
            print("\n📋 Skipped Games:")

            if counts.complete > 0 && updateMode {
                print("   • \(counts.complete.formatted()) already complete")
            }

            if counts.incomplete > 0 {
                print("   • \(counts.incomplete.formatted()) incomplete (--allow-incomplete to include)")
            }

            if counts.nonWorking > 0 {
                print("   • \(counts.nonWorking.formatted()) non-working (--include-non-working to include)")
            }

            if counts.badDumps > 0 {
                print("   • \(counts.badDumps.formatted()) with bad dumps (--include-bad-dumps to include)")
            }
        }
    }

    /// Check if an existing ZIP file has all required ROMs
    func verifyExistingZIP(_ zipPath: URL, requiredROMs: [any ROMItem]) -> Bool {
        do {
            let handler = FastZIPArchiveHandler()
            let entries = try handler.listContents(of: zipPath)

            // Build a set of existing ROM names in the ZIP
            let existingNames = Set(entries.map { $0.path })

            // Check if all required ROMs are present
            for rom in requiredROMs where !existingNames.contains(rom.name) {
                return false // Missing ROM
            }

            return true // All ROMs present
        } catch {
            // Error reading ZIP, consider it incomplete
            return false
        }
    }
}
