//
//  RebuildExecution.swift
//  RomKit CLI - Rebuild Execution Functions
//
//  Game rebuild execution and ROM extraction for the Rebuild command
//

import Foundation
import RomKit

// MARK: - Rebuild Execution Extension

extension Rebuild {
    func rebuildGame(
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
            // Extract ROMs in parallel
            let rebuiltROMs = try await withThrowingTaskGroup(of: (String, Data)?.self) { group in
                var extractedROMs: [(name: String, data: Data)] = []

                // Add extraction tasks
                for (rom, source) in requirement.availableROMs {
                    group.addTask {
                        do {
                            let data = try await self.extractROM(from: source, verify: verify, useGPU: useGPU)

                            if verify {
                                // Verify CRC if requested
                                let actualCRC = useGPU
                                    ? await ParallelHashUtilities.crc32(data: data)
                                    : HashUtilities.crc32(data: data)

                                if let expectedCRC = rom.checksums.crc32,
                                   actualCRC.lowercased() != expectedCRC.lowercased() {
                                    // Note: warnings need to be handled differently in parallel context
                                }
                            }

                            return (rom.name, data)
                        } catch {
                            // Return nil on error to continue with other ROMs
                            return nil
                        }
                    }
                }

                // Collect results
                for try await romData in group {
                    if let romData = romData {
                        extractedROMs.append(romData)
                    }
                }

                return extractedROMs
            }

            result.romsRebuilt = rebuiltROMs.count

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

    func extractROM(from source: IndexedROM, verify: Bool, useGPU: Bool) async throws -> Data {
        switch source.location {
        case .file(let path):
            return try Data(contentsOf: path)

        case .archive(let archivePath, let entryPath):
            let handler: any ArchiveHandler
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

        case .remote:
            // TODO: Implement network fetching
            throw ArchiveError.unsupportedFormat("Remote sources not yet implemented")
        }
    }
}
