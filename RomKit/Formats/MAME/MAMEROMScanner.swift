//
//  MAMEROMScanner.swift
//  RomKit
//
//  MAME ROM scanning functionality
//

import Foundation

/// MAME ROM Scanner
public final class MAMEROMScanner: ROMScanner, CallbackSupportedScanner, @unchecked Sendable {
    public typealias DATType = MAMEDATFile

    public let datFile: MAMEDATFile
    public let validator: any ROMValidator
    public let archiveHandlers: [any ArchiveHandler]

    private let fileManager = FileManager.default
    private let biosManager: MAMEBIOSManager

    /// Callback manager for progress and event reporting
    public var callbackManager: CallbackManager?

    public init(datFile: MAMEDATFile, validator: any ROMValidator, archiveHandlers: [any ArchiveHandler]) {
        self.datFile = datFile
        self.validator = validator
        self.archiveHandlers = archiveHandlers
        self.biosManager = MAMEBIOSManager(datFile: datFile)
    }

    /// Convenience initializer with callback support
    public convenience init(datFile: MAMEDATFile,
                            validator: any ROMValidator,
                            archiveHandlers: [any ArchiveHandler],
                            delegate: RomKitDelegate? = nil,
                            callbacks: RomKitCallbacks? = nil,
                            eventStream: RomKitEventStream? = nil) {
        self.init(datFile: datFile, validator: validator, archiveHandlers: archiveHandlers)
        self.callbackManager = CallbackManager(
            delegate: delegate,
            callbacks: callbacks,
            eventStream: eventStream
        )
    }

    public func scan(directory: URL) async throws -> ScanResults {
        let files = try findScanFiles(in: directory)

        // Send scan started event
        callbackManager?.sendEvent(.scanStarted(path: directory.path, fileCount: files.count))

        return try await scan(files: files)
    }

    public func scan(files: [URL]) async throws -> ScanResults {
        let startTime = Date()
        let results = try await performParallelScan(files: files)
        let duration = Date().timeIntervalSince(startTime)

        // Send scan completed event
        callbackManager?.sendEvent(.scanCompleted(
            gamesFound: results.foundGames.count,
            duration: duration
        ))

        return MAMEScanResults(
            foundGames: results.foundGames,
            unknownFiles: results.unknownFiles,
            errors: results.errors,
            scanDuration: duration
        )
    }

    // MARK: - Private Methods

    private struct ScanBatchResult: Sendable {
        let foundGames: [MAMEScannedGame]
        let unknownFiles: [URL]
        let errors: [ScanError]
    }

    private func performParallelScan(files: [URL]) async throws -> ScanBatchResult {
        var foundGames: [MAMEScannedGame] = []
        var unknownFiles: [URL] = []
        let errors: [ScanError] = []

        let totalCount = files.count
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let maxConcurrency = min(processorCount * 2, 8)

        struct FileScanResult: Sendable {
            let game: MAMEScannedGame?
            let url: URL
            let index: Int
        }

        _ = try await withThrowingTaskGroup(of: FileScanResult.self) { group in
            let semaphore = AsyncSemaphore(limit: maxConcurrency)

            for (index, file) in files.enumerated() {
                if callbackManager?.shouldCancel() == true {
                    callbackManager?.sendEvent(.error(RomKitCallbackError.cancelled))
                    break
                }

                group.addTask {
                    await semaphore.wait()

                    self.callbackManager?.sendEvent(.scanningFile(url: file, index: index + 1, total: totalCount))

                    let result = await self.scanFileOptimized(file)
                    await semaphore.signal()
                    return FileScanResult(game: result, url: file, index: index)
                }
            }

            var results: [FileScanResult] = []
            for try await result in group {
                results.append(result)

                let processedCount = results.count
                callbackManager?.sendProgress(
                    current: processedCount,
                    total: totalCount,
                    message: "Scanning files...",
                    currentItem: result.url.lastPathComponent
                )

                if let scannedGame = result.game {
                    foundGames.append(scannedGame)
                    callbackManager?.sendEvent(.gameFound(
                        name: scannedGame.game.name,
                        status: scannedGame.status
                    ))
                } else {
                    unknownFiles.append(result.url)
                }
            }

            return results
        }

        return ScanBatchResult(foundGames: foundGames, unknownFiles: unknownFiles, errors: errors)
    }

    private func findScanFiles(in directory: URL) throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return contents.filter { url in
            archiveHandlers.contains { $0.canHandle(url: url) }
        }
    }

    private func scanFileOptimized(_ url: URL) async -> MAMEScannedGame? {
        let gameName = url.deletingPathExtension().lastPathComponent

        guard let game = findGame(named: gameName) else {
            callbackManager?.sendEvent(.warning("Unknown file: \(url.lastPathComponent)"))
            return nil
        }

        let foundItems = await scanArchiveContents(url: url, game: game)
        let missingItems = findMissingItems(game: game, foundItems: foundItems)

        return MAMEScannedGame(
            game: game,
            foundItems: foundItems,
            missingItems: missingItems
        )
    }

    private func findGame(named name: String) -> MAMEGame? {
        datFile.games.first(where: { ($0 as? MAMEGame)?.name == name }) as? MAMEGame
    }

    private func findMissingItems(game: MAMEGame, foundItems: [ScannedItem]) -> [any ROMItem] {
        game.items.filter { rom in
            !foundItems.contains { $0.item.name == rom.name }
        }
    }

    private func scanArchiveContents(url: URL, game: MAMEGame) async -> [ScannedItem] {
        guard let handler = archiveHandlers.first(where: { $0.canHandle(url: url) }) else {
            return []
        }

        do {
            callbackManager?.sendEvent(.archiveOpening(url: url))
            let entries = try handler.listContents(of: url)

            return await scanArchiveEntries(entries: entries, url: url, game: game, handler: handler)
        } catch {
            callbackManager?.sendEvent(.error(RomKitCallbackError.archiveCorrupted(url: url)))
            return []
        }
    }

    private func scanArchiveEntries(entries: [ArchiveEntry],
                                    url: URL,
                                    game: MAMEGame,
                                    handler: any ArchiveHandler) async -> [ScannedItem] {
        await withTaskGroup(of: ScannedItem?.self) { group in
            for entry in entries {
                if let rom = game.items.first(where: { $0.name == entry.path }) {
                    group.addTask {
                        await self.scanSingleEntry(entry: entry, rom: rom, url: url, handler: handler)
                    }
                }
            }

            var results: [ScannedItem] = []
            for await item in group {
                if let item = item {
                    results.append(item)
                }
            }
            return results
        }
    }

    private func scanSingleEntry(entry: ArchiveEntry,
                                 rom: any ROMItem,
                                 url: URL,
                                 handler: any ArchiveHandler) async -> ScannedItem? {
        do {
            callbackManager?.sendEvent(.archiveExtracting(
                fileName: entry.path,
                size: entry.uncompressedSize
            ))

            let data = try handler.extract(entry: entry, from: url)

            callbackManager?.sendEvent(.validationStarted(itemName: rom.name))

            let validationResult = await validateItemAsync(rom, data: data)

            callbackManager?.sendEvent(.validationCompleted(
                itemName: rom.name,
                isValid: validationResult.isValid,
                errors: validationResult.errors
            ))

            return ScannedItem(
                item: rom,
                location: url.appendingPathComponent(entry.path),
                validationResult: validationResult
            )
        } catch {
            callbackManager?.sendEvent(.error(RomKitCallbackError.unknown(error)))
            return nil
        }
    }

    private func validateItemAsync(_ item: any ROMItem, data: Data) async -> ValidationResult {
        let actualChecksums = await computeChecksumsAsync(for: data)
        let expectedChecksums = item.checksums

        var errors: [String] = []
        var isValid = true

        if UInt64(data.count) != item.size {
            errors.append("Size mismatch: expected \(item.size), got \(data.count)")
            isValid = false
        }

        if let expectedCRC = expectedChecksums.crc32,
           let actualCRC = actualChecksums.crc32,
           expectedCRC.lowercased() != actualCRC.lowercased() {
            errors.append("CRC32 mismatch")
            isValid = false
        }

        if let expectedSHA1 = expectedChecksums.sha1,
           let actualSHA1 = actualChecksums.sha1,
           expectedSHA1.lowercased() != actualSHA1.lowercased() {
            errors.append("SHA1 mismatch")
            isValid = false
        }

        return ValidationResult(
            isValid: isValid,
            actualChecksums: actualChecksums,
            expectedChecksums: expectedChecksums,
            sizeMismatch: UInt64(data.count) != item.size,
            errors: errors
        )
    }

    private func computeChecksumsAsync(for data: Data) async -> ROMChecksums {
        // Use async computation if available
        return ROMChecksums(
            crc32: HashUtilities.crc32(data: data),
            sha1: HashUtilities.sha1(data: data),
            md5: HashUtilities.md5(data: data)
        )
    }
}

// MARK: - Async Semaphore

private actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.count = limit
    }

    func wait() async {
        count -= 1
        if count < 0 { // swiftlint:disable:this empty_count
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    func signal() {
        count += 1
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }
}
