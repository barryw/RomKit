//
//  TestDATLoader.swift
//  RomKitTests
//
//  Utility for loading test DAT files
//

import Foundation

/// Helper for loading test DAT files from various sources
public struct TestDATLoader {

    /// Load the full MAME 0.278 DAT file for testing
    /// This is a large compressed file used for performance and parsing tests
    public static func loadFullMAMEDAT() throws -> Data {
        // Try multiple possible paths for the test data
        let possiblePaths = [
            "/Users/barry/XCode Projects/RomKit/RomKitTests/TestData/Full/MAME_0278.dat",
            "./RomKitTests/TestData/Full/MAME_0278.dat",
            "../RomKitTests/TestData/Full/MAME_0278.dat",
            "../../RomKitTests/TestData/Full/MAME_0278.dat"
        ]

        // Also try using #file as a fallback
        let currentFilePath = #file
        let currentURL = URL(fileURLWithPath: currentFilePath)
        let testsDir = currentURL.deletingLastPathComponent().deletingLastPathComponent()
        let fileDerivedPath = testsDir.appendingPathComponent("TestData/Full/MAME_0278.dat").path

        let allPaths = possiblePaths + [fileDerivedPath]

        for path in allPaths {
            if FileManager.default.fileExists(atPath: path) {
                return try Data(contentsOf: URL(fileURLWithPath: path))
            }
        }

        // Try compressed version as fallback
        let compressedPaths = allPaths.map { $0 + ".gz" }
        for path in compressedPaths {
            if FileManager.default.fileExists(atPath: path) {
                // Return compressed data - caller should handle if they need decompressed
                return try Data(contentsOf: URL(fileURLWithPath: path))
            }
        }

        throw TestError.datNotFound("MAME_0278.dat")
    }

    /// Load a test DAT file by name from TestData directory
    public static func loadTestDAT(named filename: String) throws -> Data {
        let currentFilePath = #file
        let currentURL = URL(fileURLWithPath: currentFilePath)
        let testsDir = currentURL.deletingLastPathComponent().deletingLastPathComponent()

        // Check different possible locations
        let possiblePaths = [
            testsDir.appendingPathComponent("TestData/Full").appendingPathComponent(filename),
            testsDir.appendingPathComponent("TestData").appendingPathComponent(filename)
        ]

        for datPath in possiblePaths {
            if FileManager.default.fileExists(atPath: datPath.path) {
                // Check if it's compressed
                if filename.hasSuffix(".gz") {
                    // Try to find uncompressed version first
                    let uncompressedName = String(filename.dropLast(3))
                    let uncompressedPath = datPath.deletingLastPathComponent().appendingPathComponent(uncompressedName)

                    if FileManager.default.fileExists(atPath: uncompressedPath.path) {
                        return try Data(contentsOf: uncompressedPath)
                    }

                    // For compressed files without uncompressed version
                    // Read the compressed file and return it as-is
                    // Tests that need decompressed data should handle this
                    return try Data(contentsOf: datPath)
                } else {
                    // Load uncompressed
                    return try Data(contentsOf: datPath)
                }
            }
        }

        throw TestError.datNotFound(filename)
    }

    /// Get path to test DAT for file-based loading
    static func getTestDATPath(named filename: String) -> String? {
        // Use absolute path for reliability
        if filename == "MAME_0278.dat.gz" {
            let path = "/Users/barry/XCode Projects/RomKit/RomKitTests/TestData/Full/MAME_0278.dat.gz"
            return FileManager.default.fileExists(atPath: path) ? path : nil
        } else {
            let basePath = "/Users/barry/XCode Projects/RomKit/RomKitTests/TestData/"
            let path = basePath + filename
            return FileManager.default.fileExists(atPath: path) ? path : nil
        }
    }

    enum TestError: Error, LocalizedError {
        case datNotFound(String)
        case decompressionFailed
        case invalidGzipFormat

        var errorDescription: String? {
            switch self {
            case .datNotFound(let name):
                return "Test DAT file not found: \(name)"
            case .decompressionFailed:
                return "Failed to decompress DAT file"
            case .invalidGzipFormat:
                return "Invalid gzip format"
            }
        }
    }
}
