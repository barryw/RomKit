//
//  TestDATLoader.swift
//  RomKitTests
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation
import Testing
import Compression
@testable import RomKit

/// Helper for loading test DAT files, including compressed ones
struct TestDATLoader {

    /// Load the bundled full MAME DAT for testing
    static func loadFullMAMEDAT() throws -> Data {
        // Get path to test data directory relative to current file
        let currentFilePath = #file
        let currentURL = URL(fileURLWithPath: currentFilePath)
        let testsDir = currentURL.deletingLastPathComponent().deletingLastPathComponent()
        let datPath = testsDir.appendingPathComponent("TestData/Full/MAME_0278.dat.gz")

        guard FileManager.default.fileExists(atPath: datPath.path) else {
            throw TestError.datNotFound("MAME_0278.dat.gz at \(datPath.path)")
        }

        // Load compressed data
        let compressedData = try Data(contentsOf: datPath)

        // Decompress using native zlib
        guard let decompressed = compressedData.gunzipped() else {
            throw TestError.decompressionFailed
        }

        return decompressed
    }

    /// Load a test DAT file from TestData directory
    static func loadTestDAT(named filename: String) throws -> Data {
        let currentFilePath = #file
        let currentURL = URL(fileURLWithPath: currentFilePath)
        let testsDir = currentURL.deletingLastPathComponent().deletingLastPathComponent()
        let datPath = testsDir.appendingPathComponent("TestData").appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: datPath.path) else {
            throw TestError.datNotFound(filename)
        }

        // Check if it's compressed
        if filename.hasSuffix(".gz") {
            let compressedData = try Data(contentsOf: datPath)
            guard let decompressed = compressedData.gunzipped() else {
                throw TestError.decompressionFailed
            }
            return decompressed
        } else {
            // Load uncompressed
            return try Data(contentsOf: datPath)
        }
    }

    /// Get path to test DAT for file-based loading
    static func getTestDATPath(named filename: String) -> String? {
        let currentFilePath = #file
        let currentURL = URL(fileURLWithPath: currentFilePath)
        let testsDir = currentURL.deletingLastPathComponent().deletingLastPathComponent()

        if filename == "MAME_0278.dat.gz" {
            let datPath = testsDir.appendingPathComponent("TestData/Full/MAME_0278.dat.gz")
            return FileManager.default.fileExists(atPath: datPath.path) ? datPath.path : nil
        } else {
            let datPath = testsDir.appendingPathComponent("TestData").appendingPathComponent(filename)
            return FileManager.default.fileExists(atPath: datPath.path) ? datPath.path : nil
        }
    }

    enum TestError: Error, LocalizedError {
        case datNotFound(String)
        case decompressionFailed

        var errorDescription: String? {
            switch self {
            case .datNotFound(let name):
                return "Test DAT file not found: \(name)"
            case .decompressionFailed:
                return "Failed to decompress DAT file"
            }
        }
    }
}

// MARK: - Data Compression Extension

extension Data {
    /// Decompress gzipped data using Foundation's Compression framework
    func gunzipped() -> Data? {
        // Check for gzip magic number
        guard self.count > 2,
              self[0] == 0x1f,
              self[1] == 0x8b else {
            return nil
        }

        // Use NSData's built-in decompression which handles gzip properly
        if #available(macOS 10.15, iOS 13.0, *) {
            do {
                // Try using the built-in decompression
                return try (self as NSData).decompressed(using: .zlib) as Data
            } catch {
                // Fall back to manual decompression
            }
        }

        // Manual fallback using Compression framework
        return self.withUnsafeBytes { bytes in
            guard let pointer = bytes.baseAddress else { return nil }

            // Skip gzip header (10 bytes minimum)
            var headerSize = 10
            var flags: UInt8 = 0

            if self.count > 3 {
                flags = self[3]
            }

            // Skip extra field if present
            if flags & 0x04 != 0 && self.count > headerSize + 2 {
                let extraLen = Int(self[headerSize]) | (Int(self[headerSize + 1]) << 8)
                headerSize += 2 + extraLen
            }

            // Skip filename if present
            if flags & 0x08 != 0 {
                while headerSize < self.count && self[headerSize] != 0 {
                    headerSize += 1
                }
                headerSize += 1
            }

            // Skip comment if present
            if flags & 0x10 != 0 {
                while headerSize < self.count && self[headerSize] != 0 {
                    headerSize += 1
                }
                headerSize += 1
            }

            // Skip header CRC if present
            if flags & 0x02 != 0 {
                headerSize += 2
            }

            // Decompress the actual data (skip header and 8-byte trailer)
            guard headerSize < self.count - 8 else { return nil }

            let compressedSize = self.count - headerSize - 8
            let compressedData = self.subdata(in: headerSize..<(headerSize + compressedSize))

            // Perform decompression
            return compressedData.withUnsafeBytes { compressedBytes in
                guard let compressedPointer = compressedBytes.baseAddress else { return nil }

                let destinationSize = 100 * 1024 * 1024 // 100MB should be enough
                let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
                defer { destinationBuffer.deallocate() }

                let decompressedSize = compression_decode_buffer(
                    destinationBuffer, destinationSize,
                    compressedPointer.bindMemory(to: UInt8.self, capacity: compressedSize),
                    compressedSize,
                    nil,
                    COMPRESSION_ZLIB
                )

                guard decompressedSize > 0 else { return nil }

                return Data(bytes: destinationBuffer, count: decompressedSize)
            }
        }
    }
}