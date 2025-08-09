//
//  ParallelZIPHandler.swift
//  RomKit
//
//  Optimized parallel ZIP archive processing
//

import Foundation
import Compression
import zlib

public final class ParallelZIPArchiveHandler: ArchiveHandler, @unchecked Sendable {
    public let supportedExtensions = ["zip"]

    private let maxConcurrentOperations = ProcessInfo.processInfo.activeProcessorCount

    public init() {}

    public func canHandle(url: URL) -> Bool {
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    public func listContents(of url: URL) throws -> [ArchiveEntry] {
        let handler = FastZIPArchiveHandler()
        return try handler.listContents(of: url)
    }

    public func extract(entry: ArchiveEntry, from url: URL) throws -> Data {
        let handler = FastZIPArchiveHandler()
        return try handler.extract(entry: entry, from: url)
    }

    public func extractAll(from url: URL, to destination: URL) throws {
        let entries = try listContents(of: url)

        for entry in entries {
            let data = try extract(entry: entry, from: url)
            let destinationFile = destination.appendingPathComponent(entry.path)

            try FileManager.default.createDirectory(
                at: destinationFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            try data.write(to: destinationFile)
        }
    }

    public func create(at url: URL, with entries: [(name: String, data: Data)]) throws {
        guard let fileHandle = FileHandle(forWritingAtPath: url.path) ?? createFile(at: url) else {
            throw ArchiveError.cannotCreateArchive(url.path)
        }
        defer { try? fileHandle.close() }

        var centralDirectory: [CentralDirectoryRecord] = []

        for (name, data) in entries {
            let offset = fileHandle.offsetInFile
            let compressed = deflateData(data)
            let crc32 = computeCRC32(data: data)

            try writeLocalFileHeader(
                to: fileHandle,
                fileName: name,
                compressedSize: UInt32(compressed.count),
                uncompressedSize: UInt32(data.count),
                crc32: crc32
            )

            fileHandle.write(compressed)

            centralDirectory.append(CentralDirectoryRecord(
                fileName: name,
                offset: offset,
                compressedSize: UInt32(compressed.count),
                uncompressedSize: UInt32(data.count),
                crc32: crc32
            ))
        }

        let centralDirOffset = fileHandle.offsetInFile
        for record in centralDirectory {
            try writeCentralDirectoryRecord(to: fileHandle, record: record)
        }

        try writeEndOfCentralDirectory(
            to: fileHandle,
            numberOfEntries: UInt16(centralDirectory.count),
            centralDirectorySize: UInt32(fileHandle.offsetInFile - centralDirOffset),
            centralDirectoryOffset: UInt32(centralDirOffset)
        )
    }

    // MARK: - Async versions for parallel processing

    public func extractAllAsync(from url: URL, to destination: URL) async throws {
        let entries = try listContents(of: url)

        try await withThrowingTaskGroup(of: Void.self) { group in
            let semaphore = AsyncSemaphore(limit: maxConcurrentOperations)

            for entry in entries {
                group.addTask {
                    await semaphore.wait()

                    let data = try self.extract(entry: entry, from: url)
                    let destinationFile = destination.appendingPathComponent(entry.path)

                    try FileManager.default.createDirectory(
                        at: destinationFile.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )

                    try data.write(to: destinationFile)
                    await semaphore.signal()
                }
            }

            try await group.waitForAll()
        }
    }

    public func createAsync(at url: URL, with entries: [(name: String, data: Data)]) async throws {
        let compressedEntries = try await withThrowingTaskGroup(of: CompressedEntry.self) { group in
            for (name, data) in entries {
                group.addTask {
                    async let compressed = self.deflateData(data)
                    async let crc = self.computeCRC32(data: data)

                    let compressedData = await compressed
                    let crc32Value = await crc

                    return CompressedEntry(
                        name: name,
                        originalData: data,
                        compressedData: compressedData,
                        crc32: crc32Value
                    )
                }
            }

            var results: [CompressedEntry] = []
            for try await entry in group {
                results.append(entry)
            }
            return results
        }

        try writeZipFile(at: url, with: compressedEntries)
    }

    // MARK: - Helper Methods

    private func computeCRC32(data: Data) -> UInt32 {
        return data.withUnsafeBytes { bytes in
            UInt32(crc32(0, bytes.bindMemory(to: UInt8.self).baseAddress, uInt(data.count)))
        }
    }

    private func writeZipFile(at url: URL, with entries: [CompressedEntry]) throws {
        guard let fileHandle = FileHandle(forWritingAtPath: url.path) ?? createFile(at: url) else {
            throw ArchiveError.cannotCreateArchive(url.path)
        }
        defer { try? fileHandle.close() }

        var centralDirectory: [CentralDirectoryRecord] = []

        for entry in entries {
            let offset = fileHandle.offsetInFile

            try writeLocalFileHeader(
                to: fileHandle,
                fileName: entry.name,
                compressedSize: UInt32(entry.compressedData.count),
                uncompressedSize: UInt32(entry.originalData.count),
                crc32: entry.crc32
            )

            fileHandle.write(entry.compressedData)

            centralDirectory.append(CentralDirectoryRecord(
                fileName: entry.name,
                offset: offset,
                compressedSize: UInt32(entry.compressedData.count),
                uncompressedSize: UInt32(entry.originalData.count),
                crc32: entry.crc32
            ))
        }

        let centralDirOffset = fileHandle.offsetInFile
        for record in centralDirectory {
            try writeCentralDirectoryRecord(to: fileHandle, record: record)
        }

        try writeEndOfCentralDirectory(
            to: fileHandle,
            numberOfEntries: UInt16(centralDirectory.count),
            centralDirectorySize: UInt32(fileHandle.offsetInFile - centralDirOffset),
            centralDirectoryOffset: UInt32(centralDirOffset)
        )
    }

    private struct CompressedEntry {
        let name: String
        let originalData: Data
        let compressedData: Data
        let crc32: UInt32
    }

    private func deflateData(_ data: Data) -> Data {
        // Use Foundation's built-in compression to avoid manual zlib management
        guard let compressed = try? (data as NSData).compressed(using: .zlib) else {
            print("Warning: Failed to compress data using Foundation compression")
            return data  // Return original data as fallback
        }
        return compressed as Data
    }

    private func createFile(at url: URL) -> FileHandle? {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return FileHandle(forWritingAtPath: url.path)
    }

    private func writeLocalFileHeader(to fileHandle: FileHandle, fileName: String, compressedSize: UInt32, uncompressedSize: UInt32, crc32: UInt32) throws {
        var header = Data()

        header.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])
        header.append(contentsOf: withUnsafeBytes(of: UInt16(20).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(8).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: crc32.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: compressedSize.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: uncompressedSize.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(fileName.count).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        guard let fileNameData = fileName.data(using: .utf8) else {
            throw ArchiveError.invalidFileName("Unable to encode filename: \(fileName)")
        }
        header.append(fileNameData)

        fileHandle.write(header)
    }

    private func writeCentralDirectoryRecord(to fileHandle: FileHandle, record: CentralDirectoryRecord) throws {
        var header = Data()

        header.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0x031E).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(20).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(8).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: record.crc32.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: record.compressedSize.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: record.uncompressedSize.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(record.fileName.count).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(record.offset).littleEndian) { Array($0) })
        guard let recordFileNameData = record.fileName.data(using: .utf8) else {
            throw ArchiveError.invalidFileName("Unable to encode filename: \(record.fileName)")
        }
        header.append(recordFileNameData)

        fileHandle.write(header)
    }

    private func writeEndOfCentralDirectory(to fileHandle: FileHandle, numberOfEntries: UInt16, centralDirectorySize: UInt32, centralDirectoryOffset: UInt32) throws {
        var header = Data()

        header.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: numberOfEntries.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: numberOfEntries.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: centralDirectorySize.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: centralDirectoryOffset.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })

        fileHandle.write(header)
    }
}

private struct CentralDirectoryRecord {
    let fileName: String
    let offset: UInt64
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let crc32: UInt32
}

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
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        } else {
            availablePermits += 1
        }
    }
}
