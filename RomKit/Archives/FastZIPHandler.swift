//
//  FastZIPHandler.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation
import Compression
import zlib

// MARK: - Fast ZIP Archive Handler using native libraries

public class FastZIPArchiveHandler: ArchiveHandler {
    public let supportedExtensions = ["zip"]

    public init() {}

    public func canHandle(url: URL) -> Bool {
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    public func listContents(of url: URL) throws -> [ArchiveEntry] {
        // Use our direct ZIP reader for better performance and reliability
        return try ZIPReader.readEntries(from: url)
    }

    public func extract(entry: ArchiveEntry, from url: URL) throws -> Data {
        // Use unzip command as a temporary solution
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Extract specific file using unzip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", "-j", "-o", url.path, entry.path, "-d", tempDir.path]

        // Don't capture stderr unless we need it - this saves file descriptors
        process.standardError = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw ArchiveError.entryNotFound(entry.path)
        }

        // Read the extracted file
        let extractedFile = tempDir.appendingPathComponent(URL(fileURLWithPath: entry.path).lastPathComponent)
        guard FileManager.default.fileExists(atPath: extractedFile.path) else {
            throw ArchiveError.entryNotFound(entry.path)
        }

        return try Data(contentsOf: extractedFile)
    }

    public func extractAll(from url: URL, to destination: URL) throws {
        guard let fileHandle = FileHandle(forReadingAtPath: url.path) else {
            throw ArchiveError.cannotOpenArchive(url.path)
        }
        defer { fileHandle.closeFile() }

        let fileManager = FileManager.default

        while let (header, data) = try readNextZipEntryWithData(from: fileHandle) {
            let destinationFile = destination.appendingPathComponent(header.path)

            try fileManager.createDirectory(
                at: destinationFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let decompressed = try decompressData(data, method: header.compressionMethod)
            try decompressed.write(to: destinationFile)
        }
    }

    public func create(at url: URL, with entries: [(name: String, data: Data)]) throws {
        guard let fileHandle = FileHandle(forWritingAtPath: url.path) ?? createFile(at: url) else {
            throw ArchiveError.cannotCreateArchive(url.path)
        }
        defer { fileHandle.closeFile() }

        var centralDirectory: [CentralDirectoryRecord] = []

        for (name, data) in entries {
            let offset = fileHandle.offsetInFile
            let compressed = try compressData(data)
            let crc32 = computeCRC32(data: data)

            // Write local file header
            try writeLocalFileHeader(
                to: fileHandle,
                fileName: name,
                compressedSize: UInt32(compressed.count),
                uncompressedSize: UInt32(data.count),
                crc32: crc32
            )

            // Write compressed data
            fileHandle.write(compressed)

            // Store for central directory
            centralDirectory.append(CentralDirectoryRecord(
                fileName: name,
                offset: offset,
                compressedSize: UInt32(compressed.count),
                uncompressedSize: UInt32(data.count),
                crc32: crc32
            ))
        }

        // Write central directory
        let centralDirOffset = fileHandle.offsetInFile
        for record in centralDirectory {
            try writeCentralDirectoryRecord(to: fileHandle, record: record)
        }

        // Write end of central directory
        try writeEndOfCentralDirectory(
            to: fileHandle,
            numberOfEntries: UInt16(centralDirectory.count),
            centralDirectorySize: UInt32(fileHandle.offsetInFile - centralDirOffset),
            centralDirectoryOffset: UInt32(centralDirOffset)
        )
    }

    // MARK: - Helper Methods

    private func readNextZipEntry(from fileHandle: FileHandle) -> ArchiveEntry? {
        // Simplified - would need full ZIP parsing
        return nil
    }

    private func readNextZipEntryWithData(from fileHandle: FileHandle) -> (header: ZipLocalHeader, data: Data)? {
        // Simplified - would need full ZIP parsing
        return nil
    }

    private func decompressData(_ data: Data, method: UInt16) throws -> Data {
        switch method {
        case 0: // Stored (no compression)
            return data
        case 8: // Deflate
            return try inflateData(data)
        default:
            throw ArchiveError.unsupportedFormat("Unsupported compression method: \(method)")
        }
    }

    private func compressData(_ data: Data) throws -> Data {
        return try deflateData(data)
    }

    private func inflateData(_ data: Data) throws -> Data {
        return data.withUnsafeBytes { bytes in
            guard let pointer = bytes.bindMemory(to: UInt8.self).baseAddress else {
                return Data()
            }

            let bufferSize = data.count * 4 // Assume max 4x expansion
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }

            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer(mutating: pointer)
            stream.avail_in = uInt(data.count)
            stream.next_out = buffer
            stream.avail_out = uInt(bufferSize)

            inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            defer { inflateEnd(&stream) }

            let result = inflate(&stream, Z_FINISH)
            guard result == Z_STREAM_END else {
                return Data()
            }

            return Data(bytes: buffer, count: bufferSize - Int(stream.avail_out))
        }
    }

    private func deflateData(_ data: Data) throws -> Data {
        return data.withUnsafeBytes { bytes in
            guard let pointer = bytes.bindMemory(to: UInt8.self).baseAddress else {
                return Data()
            }

            let bufferSize = data.count + 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }

            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer(mutating: pointer)
            stream.avail_in = uInt(data.count)
            stream.next_out = buffer
            stream.avail_out = uInt(bufferSize)

            deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            defer { deflateEnd(&stream) }

            let result = deflate(&stream, Z_FINISH)
            guard result == Z_STREAM_END else {
                return Data()
            }

            return Data(bytes: buffer, count: bufferSize - Int(stream.avail_out))
        }
    }

    private func computeCRC32(data: Data) -> UInt32 {
        return data.withUnsafeBytes { bytes in
            return UInt32(crc32(0, bytes.bindMemory(to: UInt8.self).baseAddress, uInt(data.count)))
        }
    }

    private func createFile(at url: URL) -> FileHandle? {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return FileHandle(forWritingAtPath: url.path)
    }

    private func writeLocalFileHeader(to fileHandle: FileHandle, fileName: String, compressedSize: UInt32, uncompressedSize: UInt32, crc32: UInt32) throws {
        var header = Data()

        // Local file header signature = 0x04034b50
        header.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])

        // Version needed to extract (2.0)
        header.append(contentsOf: withUnsafeBytes(of: UInt16(20).littleEndian) { Array($0) })

        // General purpose bit flag
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })

        // Compression method (8 = deflate)
        header.append(contentsOf: withUnsafeBytes(of: UInt16(8).littleEndian) { Array($0) })

        // Last mod file time and date
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })

        // CRC-32
        header.append(contentsOf: withUnsafeBytes(of: crc32.littleEndian) { Array($0) })

        // Compressed size
        header.append(contentsOf: withUnsafeBytes(of: compressedSize.littleEndian) { Array($0) })

        // Uncompressed size
        header.append(contentsOf: withUnsafeBytes(of: uncompressedSize.littleEndian) { Array($0) })

        // File name length
        header.append(contentsOf: withUnsafeBytes(of: UInt16(fileName.count).littleEndian) { Array($0) })

        // Extra field length
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })

        // File name
        guard let fileNameData = fileName.data(using: .utf8) else {
            throw ArchiveError.invalidFileName("Unable to encode filename: \(fileName)")
        }
        header.append(fileNameData)

        fileHandle.write(header)
    }

    private func writeCentralDirectoryRecord(to fileHandle: FileHandle, record: CentralDirectoryRecord) throws {
        // Implementation would write central directory record
    }

    private func writeEndOfCentralDirectory(to fileHandle: FileHandle, numberOfEntries: UInt16, centralDirectorySize: UInt32, centralDirectoryOffset: UInt32) throws {
        // Implementation would write end of central directory record
    }
}

// MARK: - Helper Structures

private struct ZipLocalHeader {
    let path: String
    let compressionMethod: UInt16
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let crc32: UInt32
}

private struct CentralDirectoryRecord {
    let fileName: String
    let offset: UInt64
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let crc32: UInt32
}
