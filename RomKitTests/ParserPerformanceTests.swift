//
//  ParserPerformanceTests.swift
//  RomKitTests
//
//  Created by Barry Walker on 8/5/25.
//

import Testing
import Foundation
@testable import RomKit

struct ParserPerformanceTests {

    let testDataPath = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .appendingPathComponent("TestData")

    @Test func testXMLParsingPerformance() async throws {
        let datPath = testDataPath.appendingPathComponent("mame_sample.xml")
        let data = try Data(contentsOf: datPath)

        // Test standard parser
        let standardStart = Date()
        let standardParser = MAMEDATParser()
        let standardResult = try standardParser.parse(data: data)
        let standardTime = Date().timeIntervalSince(standardStart)

        // Test optimized parser
        let optimizedStart = Date()
        let fastParser = MAMEFastParser()
        let optimizedResult = try fastParser.parseXMLStreaming(data: data)
        let optimizedTime = Date().timeIntervalSince(optimizedStart)

        print("Parsing Performance:")
        print("  Standard: \(String(format: "%.4f", standardTime)) seconds")
        print("  Optimized: \(String(format: "%.4f", optimizedTime)) seconds")
        print("  Speedup: \(String(format: "%.1fx", standardTime / optimizedTime))")

        #expect(!standardResult.games.isEmpty)
        #expect(!optimizedResult.games.isEmpty)
    }

    @Test func testRealDATPerformance() async throws {
        // Use bundled DAT file
        print("Loading bundled DAT file...")
        let loadStart = Date()
        let data = try TestDATLoader.loadFullMAMEDAT()
        let loadTime = Date().timeIntervalSince(loadStart)
        print("  Load time: \(String(format: "%.2f", loadTime)) seconds (includes decompression)")
        print("  Decompressed size: \(data.count / 1024 / 1024) MB")

        // Test Logiqx parser (the primary format)
        print("Testing Logiqx parser (primary format)...")
        let logiqxStart = Date()
        let logiqxParser = LogiqxDATParser()
        let logiqxResult = try logiqxParser.parse(data: data)
        let logiqxTime = Date().timeIntervalSince(logiqxStart)

        // Test optimized parser for comparison
        print("Testing optimized XML parser...")
        let optimizedStart = Date()
        let fastParser = MAMEFastParser()
        let optimizedResult = try fastParser.parseXMLStreaming(data: data)
        let optimizedTime = Date().timeIntervalSince(optimizedStart)

        print("\nPerformance Results:")
        print("  Decompressed size: \(data.count / 1024 / 1024) MB")
        print("  Logiqx parser:")
        print("    Time: \(String(format: "%.2f", logiqxTime)) seconds")
        print("    Games: \(logiqxResult.games.count)")
        print("    Rate: \(String(format: "%.0f", Double(logiqxResult.games.count) / logiqxTime)) games/sec")
        print("  Optimized XML parser:")
        print("    Time: \(String(format: "%.2f", optimizedTime)) seconds")
        print("    Games: \(optimizedResult.games.count)")
        print("    Rate: \(String(format: "%.0f", Double(optimizedResult.games.count) / optimizedTime)) games/sec")

        // Logiqx should be faster
        #expect(logiqxResult.games.count > 48000)
    }

    @Test func testBinaryConversion() async throws {
        let datPath = testDataPath.appendingPathComponent("mame_sample.xml")
        let data = try Data(contentsOf: datPath)
        let binaryPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test.mamebin")

        let fastParser = MAMEFastParser()

        // Convert to binary
        print("Converting to binary format...")
        let convertStart = Date()
        try fastParser.convertToBinary(xmlData: data, outputPath: binaryPath)
        let convertTime = Date().timeIntervalSince(convertStart)

        // Check file sizes
        let xmlSize = data.count
        let binarySize = try FileManager.default.attributesOfItem(atPath: binaryPath.path)[.size] as? Int ?? 0

        print("Format Comparison:")
        print("  XML size: \(xmlSize / 1024) KB")
        print("  Binary size: \(binarySize / 1024) KB")
        print("  Compression: \(String(format: "%.1f%%", Double(binarySize) / Double(xmlSize) * 100))")
        print("  Conversion time: \(String(format: "%.4f", convertTime)) seconds")

        // Test loading speeds
        let xmlStart = Date()
        let xmlResult = try MAMEDATParser().parse(data: data)
        let xmlTime = Date().timeIntervalSince(xmlStart)

        let binaryStart = Date()
        let binaryResult = try fastParser.parseFromBinary(at: binaryPath)
        let binaryTime = Date().timeIntervalSince(binaryStart)

        print("Loading Performance:")
        print("  XML: \(String(format: "%.4f", xmlTime)) seconds")
        print("  Binary: \(String(format: "%.4f", binaryTime)) seconds")
        print("  Speedup: \(String(format: "%.1fx", xmlTime / binaryTime))")

        #expect(xmlResult.games.count == binaryResult.games.count)

        // Cleanup
        try? FileManager.default.removeItem(at: binaryPath)
    }

    @Test func testMemoryUsage() async throws {
        let datPath = testDataPath.appendingPathComponent("mame_sample.xml")
        let data = try Data(contentsOf: datPath)

        // Measure memory before
        let memoryBefore = getMemoryUsage()

        // Parse
        let parser = MAMEDATParser()
        let result = try parser.parse(data: data)

        // Measure memory after
        let memoryAfter = getMemoryUsage()
        let memoryUsed = memoryAfter - memoryBefore

        print("Memory Usage:")
        print("  Before: \(memoryBefore / 1024 / 1024) MB")
        print("  After: \(memoryAfter / 1024 / 1024) MB")
        print("  Used: \(memoryUsed / 1024 / 1024) MB")
        print("  Games: \(result.games.count)")
        print("  Per game: \(memoryUsed / result.games.count) bytes")

        #expect(!result.games.isEmpty)
    }

    private func getMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
}