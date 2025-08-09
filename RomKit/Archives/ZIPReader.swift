//
//  ZIPReader.swift
//  RomKit
//
//  Direct ZIP file reading without external dependencies
//

import Foundation
import zlib

/// Direct ZIP file reader that extracts CRC32 and file information from ZIP archives
public struct ZIPReader {

    // ZIP file signatures
    private static let localFileHeaderSignature: UInt32 = 0x04034b50
    private static let centralDirectorySignature: UInt32 = 0x02014b50
    private static let endOfCentralDirectorySignature: UInt32 = 0x06054b50

    /// Read ZIP file entries with CRC32 information
    public static func readEntries(from url: URL) throws -> [ArchiveEntry] {
        guard let data = try? Data(contentsOf: url) else {
            throw ArchiveError.cannotOpenArchive(url.path)
        }

        // Find end of central directory record
        guard let eocdOffset = findEndOfCentralDirectory(in: data) else {
            throw ArchiveError.cannotOpenArchive("Not a valid ZIP file")
        }

        // Read EOCD
        let eocd = try readEndOfCentralDirectory(data: data, offset: eocdOffset)

        // Read central directory entries
        var entries: [ArchiveEntry] = []
        var offset = Int(eocd.centralDirectoryOffset)

        for _ in 0..<eocd.totalEntries {
            let entry = try readCentralDirectoryEntry(data: data, offset: &offset)

            // Skip directories
            if !entry.fileName.hasSuffix("/") {
                entries.append(ArchiveEntry(
                    path: entry.fileName,
                    compressedSize: UInt64(entry.compressedSize),
                    uncompressedSize: UInt64(entry.uncompressedSize),
                    modificationDate: dosDateToDate(entry.lastModDate, entry.lastModTime),
                    crc32: String(format: "%08x", entry.crc32)
                ))
            }
        }

        return entries
    }

    // MARK: - End of Central Directory

    private struct EndOfCentralDirectory {
        let signature: UInt32
        let diskNumber: UInt16
        let centralDirectoryDisk: UInt16
        let entriesOnDisk: UInt16
        let totalEntries: UInt16
        let centralDirectorySize: UInt32
        let centralDirectoryOffset: UInt32
        let commentLength: UInt16
    }

    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        // EOCD is at the end of the file, search backwards
        // Minimum EOCD size is 22 bytes
        guard data.count >= 22 else { return nil }

        // Search for EOCD signature (limiting search to last 65KB + 22 bytes)
        let searchStart = max(0, data.count - 65557)

        for offset in stride(from: data.count - 22, through: searchStart, by: -1) {
            let signature = data.withUnsafeBytes { bytes in
                bytes.loadLittleEndian(fromByteOffset: offset, as: UInt32.self)
            }

            if signature == endOfCentralDirectorySignature {
                return offset
            }
        }

        return nil
    }

    private static func readEndOfCentralDirectory(data: Data, offset: Int) throws -> EndOfCentralDirectory {
        guard offset + 22 <= data.count else {
            throw ArchiveError.cannotOpenArchive("Invalid EOCD offset")
        }

        return data.withUnsafeBytes { bytes in
            EndOfCentralDirectory(
                signature: bytes.loadLittleEndian(fromByteOffset: offset, as: UInt32.self),
                diskNumber: bytes.loadLittleEndian(fromByteOffset: offset + 4, as: UInt16.self),
                centralDirectoryDisk: bytes.loadLittleEndian(fromByteOffset: offset + 6, as: UInt16.self),
                entriesOnDisk: bytes.loadLittleEndian(fromByteOffset: offset + 8, as: UInt16.self),
                totalEntries: bytes.loadLittleEndian(fromByteOffset: offset + 10, as: UInt16.self),
                centralDirectorySize: bytes.loadLittleEndian(fromByteOffset: offset + 12, as: UInt32.self),
                centralDirectoryOffset: bytes.loadLittleEndian(fromByteOffset: offset + 16, as: UInt32.self),
                commentLength: bytes.loadLittleEndian(fromByteOffset: offset + 20, as: UInt16.self)
            )
        }
    }

    // MARK: - Central Directory Entry

    private struct CentralDirectoryEntry {
        let signature: UInt32
        let versionMadeBy: UInt16
        let versionNeeded: UInt16
        let flags: UInt16
        let compressionMethod: UInt16
        let lastModTime: UInt16
        let lastModDate: UInt16
        let crc32: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let fileNameLength: UInt16
        let extraFieldLength: UInt16
        let commentLength: UInt16
        let diskStart: UInt16
        let internalAttributes: UInt16
        let externalAttributes: UInt32
        let localHeaderOffset: UInt32
        var fileName: String
    }

    private static func readCentralDirectoryEntry(data: Data, offset: inout Int) throws -> CentralDirectoryEntry {
        guard offset + 46 <= data.count else {
            throw ArchiveError.cannotOpenArchive("Invalid central directory entry")
        }

        // Read fields separately to avoid compiler complexity
        let signature = data.withUnsafeBytes { $0.loadLittleEndian(fromByteOffset: offset, as: UInt32.self) }
        let versionMadeBy = data.withUnsafeBytes { $0.loadLittleEndian(fromByteOffset: offset + 4, as: UInt16.self) }
        let versionNeeded = data.withUnsafeBytes { $0.loadLittleEndian(fromByteOffset: offset + 6, as: UInt16.self) }
        let flags = data.withUnsafeBytes { $0.loadLittleEndian(fromByteOffset: offset + 8, as: UInt16.self) }
        let compressionMethod = data.withUnsafeBytes { $0.loadLittleEndian(fromByteOffset: offset + 10, as: UInt16.self) }
        let lastModTime = data.withUnsafeBytes { $0.loadLittleEndian(fromByteOffset: offset + 12, as: UInt16.self) }
        let lastModDate = data.withUnsafeBytes { $0.loadLittleEndian(fromByteOffset: offset + 14, as: UInt16.self) }
        let crc32 = data.withUnsafeBytes { $0.loadLittleEndian(fromByteOffset: offset + 16, as: UInt32.self) }
        let compressedSize = data.withUnsafeBytes { $0.loadLittleEndian(fromByteOffset: offset + 20, as: UInt32.self) }
        let uncompressedSize = data.withUnsafeBytes { $0.loadLittleEndian(fromByteOffset: offset + 24, as: UInt32.self) }
        let fileNameLength = data.withUnsafeBytes { $0.loadLittleEndian(fromByteOffset: offset + 28, as: UInt16.self) }
        let extraFieldLength = data.withUnsafeBytes { $0.loadLittleEndian(fromByteOffset: offset + 30, as: UInt16.self) }
        let commentLength = data.withUnsafeBytes { $0.loadLittleEndian(fromByteOffset: offset + 32, as: UInt16.self) }
        let diskStart = data.withUnsafeBytes { $0.loadLittleEndian(fromByteOffset: offset + 34, as: UInt16.self) }
        let internalAttributes = data.withUnsafeBytes { $0.loadLittleEndian(fromByteOffset: offset + 36, as: UInt16.self) }
        let externalAttributes = data.withUnsafeBytes { $0.loadLittleEndian(fromByteOffset: offset + 38, as: UInt32.self) }
        let localHeaderOffset = data.withUnsafeBytes { $0.loadLittleEndian(fromByteOffset: offset + 42, as: UInt32.self) }

        let entry = CentralDirectoryEntry(
            signature: signature,
            versionMadeBy: versionMadeBy,
            versionNeeded: versionNeeded,
            flags: flags,
            compressionMethod: compressionMethod,
            lastModTime: lastModTime,
            lastModDate: lastModDate,
            crc32: crc32,
            compressedSize: compressedSize,
            uncompressedSize: uncompressedSize,
            fileNameLength: fileNameLength,
            extraFieldLength: extraFieldLength,
            commentLength: commentLength,
            diskStart: diskStart,
            internalAttributes: internalAttributes,
            externalAttributes: externalAttributes,
            localHeaderOffset: localHeaderOffset,
            fileName: ""
        )

        guard entry.signature == centralDirectorySignature else {
            throw ArchiveError.cannotOpenArchive("Invalid central directory signature")
        }

        // Read file name
        let fileNameStart = offset + 46
        let fileNameEnd = fileNameStart + Int(entry.fileNameLength)
        guard fileNameEnd <= data.count else {
            throw ArchiveError.cannotOpenArchive("Invalid file name length")
        }

        let fileNameData = data[fileNameStart..<fileNameEnd]
        let fileName = String(data: fileNameData, encoding: .utf8) ?? ""

        // Update offset
        offset = fileNameEnd + Int(entry.extraFieldLength) + Int(entry.commentLength)

        var mutableEntry = entry
        mutableEntry.fileName = fileName
        return mutableEntry
    }

    // MARK: - Data Extraction
    
    /// Extract data for a specific file from the ZIP archive
    public static func extractData(from url: URL, fileName: String) throws -> Data {
        guard let data = try? Data(contentsOf: url) else {
            throw ArchiveError.cannotOpenArchive(url.path)
        }
        
        // Find end of central directory record
        guard let eocdOffset = findEndOfCentralDirectory(in: data) else {
            throw ArchiveError.cannotOpenArchive("Not a valid ZIP file")
        }
        
        // Read EOCD
        let eocd = try readEndOfCentralDirectory(data: data, offset: eocdOffset)
        
        // Search central directory for the file
        var offset = Int(eocd.centralDirectoryOffset)
        
        for _ in 0..<eocd.totalEntries {
            let entry = try readCentralDirectoryEntry(data: data, offset: &offset)
            
            if entry.fileName == fileName {
                // Found the file, now read from local file header
                return try extractFileData(from: data, centralEntry: entry)
            }
        }
        
        throw ArchiveError.entryNotFound(fileName)
    }
    
    private static func extractFileData(from data: Data, centralEntry: CentralDirectoryEntry) throws -> Data {
        let localHeaderOffset = Int(centralEntry.localHeaderOffset)
        
        // Read local file header
        guard localHeaderOffset + 30 <= data.count else {
            throw ArchiveError.cannotOpenArchive("Invalid local header offset")
        }
        
        // Verify local file header signature
        let signature = data.withUnsafeBytes { bytes in
            bytes.loadLittleEndian(fromByteOffset: localHeaderOffset, as: UInt32.self)
        }
        
        guard signature == localFileHeaderSignature else {
            throw ArchiveError.cannotOpenArchive("Invalid local file header signature")
        }
        
        // Read local header fields
        let compressionMethod = data.withUnsafeBytes { bytes in
            bytes.loadLittleEndian(fromByteOffset: localHeaderOffset + 8, as: UInt16.self)
        }
        
        let fileNameLength = data.withUnsafeBytes { bytes in
            bytes.loadLittleEndian(fromByteOffset: localHeaderOffset + 26, as: UInt16.self)
        }
        
        let extraFieldLength = data.withUnsafeBytes { bytes in
            bytes.loadLittleEndian(fromByteOffset: localHeaderOffset + 28, as: UInt16.self)
        }
        
        // Calculate data offset
        let dataOffset = localHeaderOffset + 30 + Int(fileNameLength) + Int(extraFieldLength)
        let dataEnd = dataOffset + Int(centralEntry.compressedSize)
        
        guard dataEnd <= data.count else {
            throw ArchiveError.cannotOpenArchive("Invalid data range")
        }
        
        let compressedData = data[dataOffset..<dataEnd]
        
        // Decompress if needed
        switch compressionMethod {
        case 0: // Stored (no compression)
            return compressedData
        case 8: // Deflate
            return try inflateData(compressedData)
        default:
            throw ArchiveError.unsupportedFormat("Unsupported compression method: \(compressionMethod)")
        }
    }
    
    private static func inflateData(_ compressedData: Data) throws -> Data {
        guard !compressedData.isEmpty else {
            return Data()
        }
        
        return try compressedData.withUnsafeBytes { bytes in
            guard let pointer = bytes.bindMemory(to: UInt8.self).baseAddress else {
                throw ArchiveError.extractionFailed("Failed to access compressed data")
            }
            
            // Initialize zlib stream
            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer(mutating: pointer)
            stream.avail_in = uInt(compressedData.count)
            stream.zalloc = nil
            stream.zfree = nil
            stream.opaque = nil
            
            // Use -MAX_WBITS for raw deflate data (no zlib header)
            let initResult = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            guard initResult == Z_OK else {
                throw ArchiveError.extractionFailed("Failed to initialize inflate: \(initResult)")
            }
            defer { inflateEnd(&stream) }
            
            // Start with a reasonable buffer size, will grow if needed
            var outputData = Data()
            let chunkSize = 16384 // 16KB chunks
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
            defer { buffer.deallocate() }
            
            // Decompress in chunks
            repeat {
                stream.next_out = buffer
                stream.avail_out = uInt(chunkSize)
                
                let result = inflate(&stream, Z_NO_FLUSH)
                
                if result == Z_STREAM_ERROR {
                    throw ArchiveError.extractionFailed("Stream error during decompression")
                }
                
                if result == Z_NEED_DICT || result == Z_DATA_ERROR || result == Z_MEM_ERROR {
                    throw ArchiveError.extractionFailed("Decompression failed with error: \(result)")
                }
                
                let outputSize = chunkSize - Int(stream.avail_out)
                if outputSize > 0 {
                    outputData.append(buffer, count: outputSize)
                }
                
                if result == Z_STREAM_END {
                    break
                }
            } while stream.avail_out == 0
            
            return outputData
        }
    }

    // MARK: - Helpers

    private static func dosDateToDate(_ date: UInt16, _ time: UInt16) -> Date {
        let year = 1980 + Int((date >> 9) & 0x7F)
        let month = Int((date >> 5) & 0x0F)
        let day = Int(date & 0x1F)
        let hour = Int((time >> 11) & 0x1F)
        let minute = Int((time >> 5) & 0x3F)
        let second = Int((time & 0x1F) * 2)

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second

        return Calendar.current.date(from: components) ?? Date()
    }
}

// Extension to make it work with unsafe bytes
extension UnsafeRawBufferPointer {
    func loadLittleEndian<T>(fromByteOffset offset: Int, as type: T.Type) -> T where T: FixedWidthInteger {
        var value: T = 0
        withUnsafeMutableBytes(of: &value) { dest in
            guard let baseAddress = self.baseAddress else {
                return
            }
            let source = baseAddress.advanced(by: offset)
            dest.copyMemory(from: UnsafeRawBufferPointer(start: source, count: MemoryLayout<T>.size))
        }
        return value.littleEndian
    }
}
