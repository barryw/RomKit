//
//  MAMEROMRebuilder.swift
//  RomKit
//
//  MAME ROM rebuilding functionality
//

import Foundation

/// MAME ROM Rebuilder
public class MAMEROMRebuilder: ROMRebuilder, CallbackSupportedRebuilder {
    public typealias DATType = MAMEDATFile

    public let datFile: MAMEDATFile
    public let archiveHandlers: [any ArchiveHandler]

    /// Callback manager for progress and event reporting
    public var callbackManager: CallbackManager?

    public init(datFile: MAMEDATFile, archiveHandlers: [any ArchiveHandler]) {
        self.datFile = datFile
        self.archiveHandlers = archiveHandlers
    }

    /// Convenience initializer with callback support
    public convenience init(datFile: MAMEDATFile,
                            archiveHandlers: [any ArchiveHandler],
                            delegate: RomKitDelegate? = nil,
                            callbacks: RomKitCallbacks? = nil,
                            eventStream: RomKitEventStream? = nil) {
        self.init(datFile: datFile, archiveHandlers: archiveHandlers)
        self.callbackManager = CallbackManager(
            delegate: delegate,
            callbacks: callbacks,
            eventStream: eventStream
        )
    }

    public func rebuild(from source: URL, to destination: URL, options: RebuildOptions) async throws -> RebuildResults {
        let startTime = Date()

        sendRebuildStartedEvent(source: source, destination: destination)

        let scanResults = try await performSourceScan(source: source)
        let rebuildStats = await processGamesForRebuild(
            scanResults: scanResults,
            destination: destination,
            options: options
        )

        let duration = Date().timeIntervalSince(startTime)

        sendRebuildCompletedEvent(stats: rebuildStats, duration: duration)
        sendCompletionCallback(stats: rebuildStats)

        return RebuildResults(
            rebuilt: rebuildStats.rebuilt,
            skipped: rebuildStats.skipped,
            failed: rebuildStats.failed
        )
    }

    // MARK: - Private Methods

    private struct RebuildStats {
        var rebuilt: Int = 0
        var failed: Int = 0
        var skipped: Int = 0
    }

    private func sendRebuildStartedEvent(source: URL, destination: URL) {
        callbackManager?.sendEvent(.rebuildStarted(
            source: source.path,
            destination: destination.path
        ))
    }

    private func sendRebuildCompletedEvent(stats: RebuildStats, duration: TimeInterval) {
        callbackManager?.sendEvent(.rebuildCompleted(
            rebuilt: stats.rebuilt,
            failed: stats.failed,
            duration: duration
        ))
    }

    private func sendCompletionCallback(stats: RebuildStats) {
        if stats.failed > 0 {
            callbackManager?.sendCompletion(.failure(
                RomKitCallbackError.rebuildFailed(
                    game: "\(stats.failed) games",
                    reason: "See event log for details"
                )
            ))
        } else {
            callbackManager?.sendCompletion(.success(()))
        }
    }

    private func performSourceScan(source: URL) async throws -> ScanResults {
        let scanner = MAMEROMScanner(
            datFile: datFile,
            validator: MAMEROMValidator(),
            archiveHandlers: archiveHandlers
        )

        callbackManager?.sendEvent(.info("Scanning source directory..."))
        return try await scanner.scan(directory: source)
    }

    private func processGamesForRebuild(scanResults: ScanResults,
                                         destination: URL,
                                         options: RebuildOptions) async -> RebuildStats {
        var stats = RebuildStats()
        let totalGames = datFile.games.count
        var currentIndex = 0

        for game in datFile.games {
            currentIndex += 1

            if callbackManager?.shouldCancel() == true {
                callbackManager?.sendEvent(.error(RomKitCallbackError.cancelled))
                break
            }

            guard let mameGame = game as? MAMEGame else { continue }

            sendRebuildingGameEvent(game: mameGame, index: currentIndex, total: totalGames)

            let result = await rebuildSingleGame(
                game: mameGame,
                scanResults: scanResults,
                destination: destination,
                options: options
            )

            switch result {
            case .rebuilt:
                stats.rebuilt += 1
            case .skipped:
                stats.skipped += 1
            case .failed:
                stats.failed += 1
            }
        }

        return stats
    }

    private enum RebuildResult {
        case rebuilt
        case skipped
        case failed
    }

    private func rebuildSingleGame(game: MAMEGame,
                                    scanResults: ScanResults,
                                    destination: URL,
                                    options: RebuildOptions) async -> RebuildResult {
        guard let scannedGame = findScannedGame(for: game, in: scanResults) else {
            callbackManager?.sendEvent(.warning("Game \(game.name) not found in source"))
            return .skipped
        }

        let outputPath = destination.appendingPathComponent("\(game.name).zip")

        do {
            try await createRebuildArchive(
                game: game,
                scannedGame: scannedGame,
                outputPath: outputPath,
                options: options
            )

            callbackManager?.sendEvent(.gameRebuilt(name: game.name, success: true))
            return .rebuilt
        } catch {
            callbackManager?.sendEvent(.gameRebuilt(name: game.name, success: false))
            callbackManager?.sendEvent(.error(RomKitCallbackError.unknown(error)))
            return .failed
        }
    }

    private func findScannedGame(for game: MAMEGame, in scanResults: ScanResults) -> (any ScannedGameEntry)? {
        scanResults.foundGames.first {
            ($0.game as? MAMEGame)?.name == game.name
        }
    }

    private func sendRebuildingGameEvent(game: MAMEGame, index: Int, total: Int) {
        callbackManager?.sendEvent(.rebuildingGame(
            name: game.name,
            index: index,
            total: total
        ))

        callbackManager?.sendProgress(
            current: index,
            total: total,
            message: "Rebuilding \(game.name)...",
            currentItem: game.name
        )
    }

    private func createRebuildArchive(game: MAMEGame,
                                       scannedGame: any ScannedGameEntry,
                                       outputPath: URL,
                                       options: RebuildOptions) async throws {
        callbackManager?.sendEvent(.archiveCreating(url: outputPath))

        // Archive creation implementation would go here
        // This is a placeholder for the actual archive creation logic

        for item in scannedGame.foundItems {
            callbackManager?.sendEvent(.archiveAdding(
                fileName: item.item.name,
                size: item.item.size
            ))

            // Add item to archive
            // Implementation depends on the archive handler
        }
    }
}
