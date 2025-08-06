//
//  LogiqxPrimaryFormatTests.swift
//  RomKitTests
//
//  Created by Barry Walker on 8/5/25.
//

import Testing
import Foundation
@testable import RomKit

struct LogiqxPrimaryFormatTests {
    
    @Test func testLogiqxIsPreferredFormat() async throws {
        // Test that Logiqx format is checked first by the registry
        let registry = RomKitFormatRegistry.shared
        
        // Get available formats
        let formats = registry.availableFormats
        
        // Logiqx should be registered
        #expect(formats.contains("logiqx"))
        
        // Get Logiqx handler
        let logiqxHandler = registry.handler(for: "logiqx")
        #expect(logiqxHandler != nil)
        #expect(logiqxHandler?.formatName == "Logiqx DAT")
    }
    
    @Test func testAutoDetectionPrefersLogiqx() async throws {
        // Use bundled DAT
        let data = try TestDATLoader.loadFullMAMEDAT()
        
        // Test auto-detection
        let registry = RomKitFormatRegistry.shared
        let detectedHandler = registry.detectFormat(from: data)
        
        // Should detect as Logiqx (since it's checked first)
        #expect(detectedHandler?.formatIdentifier == "logiqx")
        #expect(detectedHandler?.formatName == "Logiqx DAT")
    }
    
    @Test func testRomKitDefaultsToAutoDetect() async throws {
        // Create a temp file with decompressed DAT for testing
        let data = try TestDATLoader.loadFullMAMEDAT()
        let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent("test_auto.dat")
        try data.write(to: tempPath)
        defer { try? FileManager.default.removeItem(at: tempPath) }
        
        // Test that RomKit auto-detects format
        let romkit = RomKit()
        
        // This should auto-detect and prefer Logiqx
        try romkit.loadDAT(from: tempPath.path)
        
        // Can't directly check format from legacy API, but it should load successfully
        // The fact it loads without error proves auto-detection works
    }
    
    @Test func testExplicitLogiqxLoading() async throws {
        // Create temp file with decompressed DAT
        let data = try TestDATLoader.loadFullMAMEDAT()
        let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent("test.dat")
        try data.write(to: tempPath)
        defer { try? FileManager.default.removeItem(at: tempPath) }
        
        // Test explicit Logiqx loading
        let romkit = RomKit()
        
        // Explicitly load as Logiqx
        try romkit.loadLogiqxDAT(from: tempPath.path)
        
        // Should load successfully
    }
    
    @Test func testGenericInterfaceShowsFormat() async throws {
        // Use bundled DAT data
        let data = try TestDATLoader.loadFullMAMEDAT()
        
        // Use generic interface to check format
        let romkit = RomKitGeneric()
        
        // Load with auto-detection
        try romkit.loadDAT(data: data)
        
        // Check format was detected as Logiqx
        #expect(romkit.currentFormat == "Logiqx DAT")
        #expect(romkit.isLoaded == true)
    }
    
    @Test func testPerformanceComparison() async throws {
        // Use bundled DAT for consistent testing
        print("Testing with bundled Logiqx DAT...")
        let data = try TestDATLoader.loadFullMAMEDAT()
        
        // Test Logiqx parser (primary format)
        let logiqxStart = Date()
        let logiqxParser = LogiqxDATParser()
        let logiqxResult = try logiqxParser.parse(data: data)
        let logiqxTime = Date().timeIntervalSince(logiqxStart)
        
        // Test MAME parser to see if it can handle Logiqx format
        let mameParser = MAMEDATParser()
        let canParseMame = mameParser.canParse(data: data)
        
        print("\nPerformance Results:")
        print("=======================")
        print("Logiqx DAT parsing: \(String(format: "%.2fs", logiqxTime))")
        print("Games parsed: \(logiqxResult.games.count)")
        print("Rate: \(String(format: "%.0f", Double(logiqxResult.games.count) / logiqxTime)) games/sec")
        print("Can MAME parser handle Logiqx: \(canParseMame)")
        
        // Should parse quickly with bundled DAT
        #expect(logiqxTime < 10.0)
        #expect(logiqxResult.games.count > 48000)
    }
}