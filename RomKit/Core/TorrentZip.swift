//
//  TorrentZip.swift
//  RomKit
//
//  TorrentZip support for standardized ZIP archives
//

import Foundation
import Compression
import zlib

/// Structure representing a file in a TorrentZip archive
struct TorrentZipFile {
    let name: String
    let data: Data
    let date: Date
    let crc: UInt32
}

/// TorrentZip handler for creating and verifying standardized ZIP files
public class TorrentZip {

    /// TorrentZip signature in the ZIP comment field
    private static let torrentZipSignature = "TORRENTZIPPED-"

    /// Check if a ZIP file is TorrentZip compliant
    public static func isTorrentZip(at url: URL) throws -> Bool {
        guard url.pathExtension.lowercased() == "zip" else {
            return false
        }

        let data = try Data(contentsOf: url)

        // Check for TorrentZip signature in ZIP comment
        // The comment is at the end of the ZIP file
        if let commentRange = findZIPComment(in: data) {
            let comment = String(data: data[commentRange], encoding: .utf8) ?? ""
            return comment.hasPrefix(torrentZipSignature)
        }

        return false
    }

    /// Convert a ZIP file to TorrentZip format
    public static func convertToTorrentZip(
        at url: URL,
        outputURL: URL? = nil,
        progress: ((Double) -> Void)? = nil
    ) throws {
        let output = outputURL ?? url
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".zip")

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Extract all files
        let entries = try ZIPArchiveHandler().listContents(of: url)
        var files: [TorrentZipFile] = []

        for (index, entry) in entries.enumerated() {
            progress?(Double(index) / Double(entries.count) * 0.5)

            let data = try ZIPArchiveHandler().extract(entry: entry, from: url)
            let crc = calculateCRC32(data: data)

            // Use a fixed date for all files (for reproducibility)
            let fixedDate = Date(timeIntervalSince1970: 1103073502) // TorrentZip standard date

            files.append(TorrentZipFile(
                name: entry.path,
                data: data,
                date: fixedDate,
                crc: crc
            ))
        }

        // Sort files by name (case-insensitive, as per TorrentZip spec)
        files.sort { $0.name.lowercased() < $1.name.lowercased() }

        // Create new ZIP with sorted files
        try createTorrentZip(files: files, to: tempURL, progress: { progressValue in
            progress?(0.5 + progressValue * 0.5)
        })

        // Replace original if needed
        if output == url {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tempURL, to: output)

        progress?(1.0)
    }

    /// Create a TorrentZip from files
    private static func createTorrentZip(
        files: [TorrentZipFile],
        to url: URL,
        progress: ((Double) -> Void)? = nil
    ) throws {
        var zipData = Data()
        var centralDirectory = Data()
        var fileOffsets: [UInt32] = []

        // Write files
        for (index, file) in files.enumerated() {
            progress?(Double(index) / Double(files.count))

            let offset = UInt32(zipData.count)
            fileOffsets.append(offset)

            // Local file header
            var localHeader = Data()
            localHeader.append(contentsOf: [0x50, 0x4B, 0x03, 0x04]) // Signature
            localHeader.append(contentsOf: [0x14, 0x00]) // Version needed
            localHeader.append(contentsOf: [0x00, 0x00]) // Flags (no compression)
            localHeader.append(contentsOf: [0x00, 0x00]) // Compression method (stored)

            // DOS date/time (fixed for TorrentZip)
            let dosTime = dateToDOSTime(file.date)
            localHeader.append(contentsOf: withUnsafeBytes(of: dosTime.littleEndian) { Array($0) })

            // CRC-32
            localHeader.append(contentsOf: withUnsafeBytes(of: file.crc.littleEndian) { Array($0) })

            // Sizes
            let size = UInt32(file.data.count)
            localHeader.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) }) // Compressed
            localHeader.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) }) // Uncompressed

            // Name length
            let nameData = Data(file.name.utf8)
            localHeader.append(contentsOf: withUnsafeBytes(of: UInt16(nameData.count).littleEndian) { Array($0) })
            localHeader.append(contentsOf: [0x00, 0x00]) // Extra field length

            // Name and data
            localHeader.append(nameData)
            localHeader.append(file.data)

            zipData.append(localHeader)

            // Central directory entry
            var cdEntry = Data()
            cdEntry.append(contentsOf: [0x50, 0x4B, 0x01, 0x02]) // Signature
            cdEntry.append(contentsOf: [0x14, 0x00]) // Version made by
            cdEntry.append(contentsOf: [0x14, 0x00]) // Version needed
            cdEntry.append(contentsOf: [0x00, 0x00]) // Flags
            cdEntry.append(contentsOf: [0x00, 0x00]) // Compression method
            cdEntry.append(contentsOf: withUnsafeBytes(of: dosTime.littleEndian) { Array($0) })
            cdEntry.append(contentsOf: withUnsafeBytes(of: file.crc.littleEndian) { Array($0) })
            cdEntry.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
            cdEntry.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
            cdEntry.append(contentsOf: withUnsafeBytes(of: UInt16(nameData.count).littleEndian) { Array($0) })
            cdEntry.append(contentsOf: [0x00, 0x00]) // Extra field length
            cdEntry.append(contentsOf: [0x00, 0x00]) // Comment length
            cdEntry.append(contentsOf: [0x00, 0x00]) // Disk number
            cdEntry.append(contentsOf: [0x00, 0x00]) // Internal attributes
            cdEntry.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // External attributes
            cdEntry.append(contentsOf: withUnsafeBytes(of: offset.littleEndian) { Array($0) })
            cdEntry.append(nameData)

            centralDirectory.append(cdEntry)
        }

        // Write central directory
        let cdOffset = UInt32(zipData.count)
        zipData.append(centralDirectory)

        // End of central directory
        var eocd = Data()
        eocd.append(contentsOf: [0x50, 0x4B, 0x05, 0x06]) // Signature
        eocd.append(contentsOf: [0x00, 0x00]) // Disk number
        eocd.append(contentsOf: [0x00, 0x00]) // Disk with CD
        eocd.append(contentsOf: withUnsafeBytes(of: UInt16(files.count).littleEndian) { Array($0) }) // Entries on disk
        eocd.append(contentsOf: withUnsafeBytes(of: UInt16(files.count).littleEndian) { Array($0) }) // Total entries
        eocd.append(contentsOf: withUnsafeBytes(of: UInt32(centralDirectory.count).littleEndian) { Array($0) })
        eocd.append(contentsOf: withUnsafeBytes(of: cdOffset.littleEndian) { Array($0) })

        // TorrentZip comment
        let comment = generateTorrentZipComment()
        eocd.append(contentsOf: withUnsafeBytes(of: UInt16(comment.count).littleEndian) { Array($0) })
        eocd.append(Data(comment.utf8))

        zipData.append(eocd)

        // Write to file
        try zipData.write(to: url)

        progress?(1.0)
    }

    /// Generate TorrentZip comment
    private static func generateTorrentZipComment() -> String {
        let crc = "00000000" // This would be the CRC of the ZIP itself
        return "\(torrentZipSignature)\(crc)"
    }

    /// Find ZIP comment in data
    private static func findZIPComment(in data: Data) -> Range<Data.Index>? {
        // Look for End of Central Directory signature
        let eocdSignature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]

        // Search from end (EOCD is at the end)
        let searchStart = max(0, data.count - 65536) // Max comment size
        let searchData = data[searchStart...]

        if let range = searchData.range(of: Data(eocdSignature)) {
            // Comment length is at offset 20-21 from EOCD signature
            let commentLengthOffset = range.lowerBound + 20
            if commentLengthOffset + 2 <= data.endIndex {
                let commentLength = data[commentLengthOffset..<commentLengthOffset+2]
                    .withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }

                let commentStart = commentLengthOffset + 2
                let commentEnd = commentStart + Int(commentLength)

                if commentEnd <= data.count {
                    return commentStart..<commentEnd
                }
            }
        }

        return nil
    }

    /// Convert date to DOS time format
    private static func dateToDOSTime(_ date: Date) -> UInt32 {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        let year = max(0, (components.year ?? 1980) - 1980)
        let month = components.month ?? 1
        let day = components.day ?? 1
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = (components.second ?? 0) / 2 // DOS time has 2-second resolution

        let dosDate = UInt16((year << 9) | (month << 5) | day)
        let dosTime = UInt16((hour << 11) | (minute << 5) | second)

        return (UInt32(dosDate) << 16) | UInt32(dosTime)
    }

    /// Calculate CRC32
    private static func calculateCRC32(data: Data) -> UInt32 {
        return data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            return UInt32(crc32(0, baseAddress, UInt32(data.count)))
        }
    }

    /// Verify all ZIPs in a directory are TorrentZip compliant
    public static func verifyDirectory(
        at url: URL,
        recursive: Bool = true
    ) throws -> TorrentZipVerificationResult {
        var compliant: [URL] = []
        var nonCompliant: [URL] = []
        var errors: [(URL, any Error)] = []

        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: recursive ? [] : [.skipsSubdirectoryDescendants]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension.lowercased() == "zip" {
                do {
                    if try isTorrentZip(at: fileURL) {
                        compliant.append(fileURL)
                    } else {
                        nonCompliant.append(fileURL)
                    }
                } catch {
                    errors.append((fileURL, error))
                }
            }
        }

        return TorrentZipVerificationResult(
            compliant: compliant,
            nonCompliant: nonCompliant,
            errors: errors
        )
    }

    /// Convert all ZIPs in a directory to TorrentZip format
    public static func convertDirectory(
        at url: URL,
        recursive: Bool = true,
        parallel: Bool = true,
        progress: (@Sendable (TorrentZipProgress) -> Void)? = nil
    ) async throws {
        let result = try verifyDirectory(at: url, recursive: recursive)
        let total = result.nonCompliant.count

        // Use an actor to safely track progress in concurrent code
        actor ProgressTracker {
            private var completed = 0

            func increment() -> Int {
                completed += 1
                return completed
            }
        }

        let tracker = ProgressTracker()

        if parallel {
            await withTaskGroup(of: Void.self) { group in
                for zipURL in result.nonCompliant {
                    group.addTask {
                        do {
                            try TorrentZip.convertToTorrentZip(at: zipURL)
                            let currentCount = await tracker.increment()
                            progress?(TorrentZipProgress(
                                current: currentCount,
                                total: total,
                                currentFile: zipURL.lastPathComponent
                            ))
                        } catch {
                            print("Failed to convert \(zipURL.lastPathComponent): \(error)")
                        }
                    }
                }
            }
        } else {
            for zipURL in result.nonCompliant {
                try convertToTorrentZip(at: zipURL)
                let currentCount = await tracker.increment()
                progress?(TorrentZipProgress(
                    current: currentCount,
                    total: total,
                    currentFile: zipURL.lastPathComponent
                ))
            }
        }
    }
}

/// Result of TorrentZip verification
public struct TorrentZipVerificationResult: Sendable {
    public let compliant: [URL]
    public let nonCompliant: [URL]
    public let errors: [(URL, any Error)]

    public var summary: String {
        """
        TorrentZip Verification Results:
        ✅ Compliant: \(compliant.count)
        ❌ Non-compliant: \(nonCompliant.count)
        ⚠️ Errors: \(errors.count)
        Total ZIPs: \(compliant.count + nonCompliant.count + errors.count)
        """
    }
}

/// Progress tracking for TorrentZip operations
public struct TorrentZipProgress: Sendable {
    public let current: Int
    public let total: Int
    public let currentFile: String

    public var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total) * 100
    }
}
