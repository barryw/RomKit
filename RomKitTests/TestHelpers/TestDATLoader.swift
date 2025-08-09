//
//  TestDATLoader.swift
//  RomKitTests
//
//  Utility for loading test DAT files
//

import Foundation
import Compression

/// Helper for loading test DAT files from various sources
public struct TestDATLoader {
    
    /// Load the full MAME 0.278 DAT file for testing
    /// This is a large compressed file used for performance and parsing tests
    public static func loadFullMAMEDAT() throws -> Data {
        let filename = "MAME_0278.dat.gz"
        
        // Try to find the DAT file in TestData/Full/
        let currentFilePath = #file
        let currentURL = URL(fileURLWithPath: currentFilePath)
        let testsDir = currentURL.deletingLastPathComponent().deletingLastPathComponent()
        let datPath = testsDir.appendingPathComponent("TestData/Full").appendingPathComponent(filename)
        
        guard FileManager.default.fileExists(atPath: datPath.path) else {
            throw TestError.datNotFound(filename)
        }
        
        let compressedData = try Data(contentsOf: datPath)
        
        // Use Foundation's decompression - zlib handles gzip format
        if let decompressed = try? (compressedData as NSData).decompressed(using: .zlib) as Data {
            return decompressed
        }
        
        throw TestError.decompressionFailed
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
                    let compressedData = try Data(contentsOf: datPath)
                    
                    // Use Foundation's built-in decompression - zlib handles gzip format
                    if let decompressed = try? (compressedData as NSData).decompressed(using: .zlib) as Data {
                        return decompressed
                    }
                    
                    throw TestError.decompressionFailed
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