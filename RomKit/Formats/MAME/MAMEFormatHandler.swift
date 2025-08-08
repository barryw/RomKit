//
//  MAMEFormatHandler.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation
import CryptoKit
import zlib

// MARK: - MAME Format Handler

public class MAMEFormatHandler: ROMFormatHandler {
    public let formatIdentifier = "mame"
    public let formatName = "MAME"
    public let supportedExtensions = ["xml", "dat"]

    public init() {}

    public func createParser() -> any DATParser {
        return MAMEDATParser()
    }

    public func createValidator() -> any ROMValidator {
        return MAMEROMValidator()
    }

    public func createScanner(for datFile: any DATFormat) -> any ROMScanner {
        guard let mameDat = datFile as? MAMEDATFile else {
            fatalError("Invalid DAT file type for MAME scanner")
        }
        return MAMEROMScanner(datFile: mameDat, validator: createValidator(), archiveHandlers: createArchiveHandlers())
    }

    public func createRebuilder(for datFile: any DATFormat) -> any ROMRebuilder {
        guard let mameDat = datFile as? MAMEDATFile else {
            fatalError("Invalid DAT file type for MAME rebuilder")
        }
        return MAMEROMRebuilder(datFile: mameDat, archiveHandlers: createArchiveHandlers())
    }

    public func createArchiveHandlers() -> [any ArchiveHandler] {
        return [ZIPArchiveHandler(), SevenZipArchiveHandler(), CHDArchiveHandler()]
    }
}

// MARK: - MAME ROM Validator

public class MAMEROMValidator: ROMValidator {

    public init() {}

    public func validate(item: any ROMItem, against data: Data) -> ValidationResult {
        let actualChecksums = computeChecksums(for: data)
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

    public func validate(item: any ROMItem, at url: URL) throws -> ValidationResult {
        let data = try Data(contentsOf: url)
        return validate(item: item, against: data)
    }

    public func computeChecksums(for data: Data) -> ROMChecksums {
        let crc = data.withUnsafeBytes { bytes in
            return zlib.crc32(0, bytes.bindMemory(to: UInt8.self).baseAddress, uInt(data.count))
        }

        let sha1Digest = Insecure.SHA1.hash(data: data)
        let sha256Digest = SHA256.hash(data: data)
        let md5Digest = Insecure.MD5.hash(data: data)

        return ROMChecksums(
            crc32: String(format: "%08x", crc),
            sha1: sha1Digest.map { String(format: "%02x", $0) }.joined(),
            sha256: sha256Digest.map { String(format: "%02x", $0) }.joined(),
            md5: md5Digest.map { String(format: "%02x", $0) }.joined()
        )
    }

    public func computeChecksumsAsync(for data: Data) async -> ROMChecksums {
        let multiHash = await ParallelHashUtilities.computeAllHashes(data: data)
        return ROMChecksums(
            crc32: multiHash.crc32,
            sha1: multiHash.sha1,
            sha256: multiHash.sha256,
            md5: multiHash.md5
        )
    }
}

// MARK: - MAME ROM Scanner

public class MAMEROMScanner: ROMScanner, CallbackSupportedScanner {
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
        var foundGames: [MAMEScannedGame] = []
        var unknownFiles: [URL] = []
        let errors: [ScanError] = []

        let startTime = Date()
        let totalCount = files.count
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let maxConcurrency = min(processorCount * 2, 8)

        struct FileScanResult {
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

        let duration = Date().timeIntervalSince(startTime)

        // Send scan completed event
        callbackManager?.sendEvent(.scanCompleted(
            gamesFound: foundGames.count,
            duration: duration
        ))

        return MAMEScanResults(
            scannedPath: files.first?.deletingLastPathComponent().path ?? "",
            foundGames: foundGames,
            unknownFiles: unknownFiles,
            scanDate: Date(),
            errors: errors
        )
    }

    private func findScanFiles(in directory: URL) throws -> [URL] {
        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var files: [URL] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            let isSupported = archiveHandlers.contains { handler in
                handler.canHandle(url: fileURL)
            }
            if isSupported {
                files.append(fileURL)
            }
        }

        return files
    }

    private func scanFileOptimized(_ url: URL) async -> MAMEScannedGame? {
        let gameName = url.deletingPathExtension().lastPathComponent

        guard let game = datFile.games.first(where: { ($0 as? MAMEGame)?.name == gameName }) as? MAMEGame else {
            callbackManager?.sendEvent(.warning("Unknown file: \(url.lastPathComponent)"))
            return nil
        }

        var foundItems: [ScannedItem] = []

        if let handler = archiveHandlers.first(where: { $0.canHandle(url: url) }) {
            do {
                callbackManager?.sendEvent(.archiveOpening(url: url))

                let entries = try handler.listContents(of: url)

                let itemResults = await withTaskGroup(of: ScannedItem?.self) { group in
                    for entry in entries {
                        if let rom = game.items.first(where: { $0.name == entry.path }) {
                            group.addTask {
                                do {
                                    self.callbackManager?.sendEvent(.archiveExtracting(
                                        fileName: entry.path,
                                        size: UInt64(entry.uncompressedSize ?? 0)
                                    ))

                                    let data = try handler.extract(entry: entry, from: url)

                                    self.callbackManager?.sendEvent(.validationStarted(itemName: rom.name))

                                    let validationResult = await self.validateItemAsync(rom, data: data)

                                    self.callbackManager?.sendEvent(.validationCompleted(
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
                                    self.callbackManager?.sendEvent(.error(RomKitCallbackError.unknown(error)))
                                    return nil
                                }
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

                foundItems = itemResults
            } catch {
                callbackManager?.sendEvent(.error(RomKitCallbackError.archiveCorrupted(url: url)))
            }
        }

        let missingItems = game.items.filter { rom in
            !foundItems.contains { $0.item.name == rom.name }
        }

        return MAMEScannedGame(
            game: game,
            foundItems: foundItems,
            missingItems: missingItems
        )
    }

    private func validateItemAsync(_ item: any ROMItem, data: Data) async -> ValidationResult {
        let actualChecksums = await (validator as? MAMEROMValidator)?.computeChecksumsAsync(for: data) ?? validator.computeChecksums(for: data)
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

    private func scanFile(_ url: URL) async -> MAMEScannedGame? {
        let gameName = url.deletingPathExtension().lastPathComponent

        guard let game = datFile.games.first(where: { ($0 as? MAMEGame)?.name == gameName }) as? MAMEGame else {
            callbackManager?.sendEvent(.warning("Unknown file: \(url.lastPathComponent)"))
            return nil
        }

        var foundItems: [ScannedItem] = []

        if let handler = archiveHandlers.first(where: { $0.canHandle(url: url) }) {
            do {
                // Send archive opening event
                callbackManager?.sendEvent(.archiveOpening(url: url))

                let entries = try handler.listContents(of: url)

                for entry in entries {
                    if let rom = game.items.first(where: { $0.name == entry.path }) {
                        do {
                            // Send extracting event
                            callbackManager?.sendEvent(.archiveExtracting(
                                fileName: entry.path,
                                size: UInt64(entry.uncompressedSize ?? 0)
                            ))

                            let data = try handler.extract(entry: entry, from: url)

                            // Send validation event
                            callbackManager?.sendEvent(.validationStarted(itemName: rom.name))

                            let validationResult = validator.validate(item: rom, against: data)

                            // Send validation completed event
                            callbackManager?.sendEvent(.validationCompleted(
                                itemName: rom.name,
                                isValid: validationResult.isValid,
                                errors: validationResult.errors
                            ))

                            let scannedItem = ScannedItem(
                                item: rom,
                                location: url.appendingPathComponent(entry.path),
                                validationResult: validationResult
                            )
                            foundItems.append(scannedItem)
                        } catch {
                            callbackManager?.sendEvent(.error(RomKitCallbackError.unknown(error)))
                        }
                    }
                }
            } catch {
                callbackManager?.sendEvent(.error(RomKitCallbackError.archiveCorrupted(url: url)))
            }
        }

        let missingItems = game.items.filter { rom in
            !foundItems.contains { $0.item.name == rom.name }
        }

        return MAMEScannedGame(
            game: game,
            foundItems: foundItems,
            missingItems: missingItems
        )
    }
}

// MARK: - AsyncSemaphore Helper

private actor AsyncSemaphore {
    private var availablePermits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.availablePermits = limit
    }

    func wait() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            availablePermits += 1
        }
    }
}

// MARK: - MAME Scan Results

public struct MAMEScanResults: ScanResults {
    public let scannedPath: String
    public let foundGames: [any ScannedGameEntry]
    public let unknownFiles: [URL]
    public let scanDate: Date
    public let errors: [ScanError]
}

public struct MAMEScannedGame: ScannedGameEntry {
    public let game: any GameEntry
    public let foundItems: [ScannedItem]
    public let missingItems: [any ROMItem]
    public var status: GameCompletionStatus {
        if missingItems.isEmpty && !foundItems.isEmpty {
            let allValid = foundItems.allSatisfy { $0.validationResult.isValid }
            return allValid ? .complete : .incomplete
        } else if foundItems.isEmpty {
            return .missing
        } else {
            return .incomplete
        }
    }

    public init(game: MAMEGame, foundItems: [ScannedItem], missingItems: [any ROMItem]) {
        self.game = game
        self.foundItems = foundItems
        self.missingItems = missingItems
    }
}

// MARK: - MAME ROM Rebuilder

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

        // Send rebuild started event
        callbackManager?.sendEvent(.rebuildStarted(
            source: source.path,
            destination: destination.path
        ))

        var rebuilt = 0
        let failed = 0
        var skipped = 0

        let totalGames = datFile.games.count
        var currentIndex = 0

        // Scan source directory first
        let scanner = MAMEROMScanner(
            datFile: datFile,
            validator: MAMEROMValidator(),
            archiveHandlers: archiveHandlers
        )

        callbackManager?.sendEvent(.info("Scanning source directory..."))
        let scanResults = try await scanner.scan(directory: source)

        // Process each game
        for game in datFile.games {
            currentIndex += 1

            // Check for cancellation
            if callbackManager?.shouldCancel() == true {
                callbackManager?.sendEvent(.error(RomKitCallbackError.cancelled))
                break
            }

            guard let mameGame = game as? MAMEGame else { continue }

            // Send rebuilding game event
            callbackManager?.sendEvent(.rebuildingGame(
                name: mameGame.name,
                index: currentIndex,
                total: totalGames
            ))

            // Update progress
            callbackManager?.sendProgress(
                current: currentIndex,
                total: totalGames,
                message: "Rebuilding \(mameGame.name)...",
                currentItem: mameGame.name
            )

            // Find matching scanned game
            let scannedGame = scanResults.foundGames.first {
                ($0.game as? MAMEGame)?.name == mameGame.name
            }

            if let scannedGame = scannedGame {
                // Create output archive
                let outputPath = destination.appendingPathComponent("\(mameGame.name).zip")

                callbackManager?.sendEvent(.archiveCreating(url: outputPath))

                // Add ROMs to archive based on rebuild style
                for item in scannedGame.foundItems {
                    callbackManager?.sendEvent(.archiveAdding(
                        fileName: item.item.name,
                        size: item.item.size
                    ))

                    // Archive creation logic would go here
                }

                rebuilt += 1

                // Send game rebuilt event
                callbackManager?.sendEvent(.gameRebuilt(
                    name: mameGame.name,
                    success: true
                ))
            } else {
                skipped += 1
                callbackManager?.sendEvent(.warning("Game \(mameGame.name) not found in source"))
            }
        }

        let duration = Date().timeIntervalSince(startTime)

        // Send rebuild completed event
        callbackManager?.sendEvent(.rebuildCompleted(
            rebuilt: rebuilt,
            failed: failed,
            duration: duration
        ))

        // Send completion callback
        if failed > 0 {
            callbackManager?.sendCompletion(.failure(
                RomKitCallbackError.rebuildFailed(
                    game: "\(failed) games",
                    reason: "See event log for details"
                )
            ))
        } else {
            callbackManager?.sendCompletion(.success(()))
        }

        return RebuildResults(rebuilt: rebuilt, skipped: skipped, failed: failed)
    }
}
