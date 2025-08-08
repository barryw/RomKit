//
//  SimplePerfComparisonTests.swift
//  RomKitTests
//
//  Simplified CPU vs GPU performance comparison tests
//

import Testing
import Foundation
@testable import RomKit

@Suite("Simple Performance Comparison")
struct SimplePerfComparisonTests {

    @Test("Compare CPU vs GPU hash performance")
    func testCPUvsGPUHashPerformance() async throws {
        print("\n🏁 CPU vs GPU Hash Performance Comparison")
        print(String(repeating: "=", count: 50))

        // Test with different file sizes
        let testSizes = [
            (1024 * 100, "100KB"),
            (1024 * 1024, "1MB"),
            (1024 * 1024 * 10, "10MB"),
            (1024 * 1024 * 50, "50MB")
        ]

        print("Size       | CPU (ms)  | GPU (ms)  | Winner   ")
        print(String(repeating: "-", count: 50))

        for (size, label) in testSizes {
            let data = Data(repeating: 0xAB, count: size)

            // CPU timing
            let cpuStart = Date()
            let cpuCRC = HashUtilities.crc32(data: data)
            let cpuSHA = HashUtilities.sha256(data: data)
            let cpuTime = Date().timeIntervalSince(cpuStart) * 1000 // Convert to ms

            // GPU timing
            let gpuStart = Date()
            let gpuHashes = await ParallelHashUtilities.computeAllHashes(data: data)
            let gpuTime = Date().timeIntervalSince(gpuStart) * 1000 // Convert to ms

            // Verify correctness
            #expect(cpuCRC == gpuHashes.crc32, "CRC32 should match")
            #expect(cpuSHA == gpuHashes.sha256, "SHA256 should match")

            let winner = cpuTime < gpuTime ? "CPU" : "GPU"
            let labelPad = label.padding(toLength: 10, withPad: " ", startingAt: 0)
            let cpuStr = String(format: "%8.2f", cpuTime)
            let gpuStr = String(format: "%8.2f", gpuTime)
            let winnerPad = winner.padding(toLength: 8, withPad: " ", startingAt: 0)
            print("\(labelPad) | \(cpuStr) | \(gpuStr) | \(winnerPad)")
        }

        print(String(repeating: "-", count: 50))
        print("✅ Test completed - hashes match between CPU and GPU")
    }

    @Test("Compare sequential vs parallel archive operations")
    func testSequentialVsParallelArchive() async throws {
        print("\n📦 Sequential vs Parallel Archive Performance")
        print(String(repeating: "=", count: 50))

        let tempDir = FileManager.default.temporaryDirectory
        let testFiles = [
            ("file1.dat", Data(repeating: 0x01, count: 1024 * 10)),
            ("file2.dat", Data(repeating: 0x02, count: 1024 * 20)),
            ("file3.dat", Data(repeating: 0x03, count: 1024 * 30)),
            ("file4.dat", Data(repeating: 0x04, count: 1024 * 40)),
            ("file5.dat", Data(repeating: 0x05, count: 1024 * 50))
        ]

        let handler = ParallelZIPArchiveHandler()

        // Sequential timing
        let seqZip = tempDir.appendingPathComponent("seq_test.zip")
        let seqStart = Date()
        try handler.create(at: seqZip, with: testFiles)
        let seqTime = Date().timeIntervalSince(seqStart) * 1000

        // Parallel timing
        let parZip = tempDir.appendingPathComponent("par_test.zip")
        let parStart = Date()
        try await handler.createAsync(at: parZip, with: testFiles)
        let parTime = Date().timeIntervalSince(parStart) * 1000

        print("Sequential: \(String(format: "%.2f", seqTime)) ms")
        print("Parallel:   \(String(format: "%.2f", parTime)) ms")

        let speedup = seqTime / parTime
        if speedup > 1.0 {
            print("🚀 Parallel is \(String(format: "%.2fx", speedup)) faster!")
        } else {
            print("Sequential is faster for this workload")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: seqZip)
        try? FileManager.default.removeItem(at: parZip)

        #expect(speedup > 0, "Should have valid speedup measurement")
    }

    @Test("Measure real-world ROM processing performance")
    func testRealWorldPerformance() async throws {
        print("\n🎮 Real-World ROM Processing Performance")
        print(String(repeating: "=", count: 50))

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("perf_\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create 10 test ROM files
        print("Creating test ROM files...")
        for index in 0..<10 {
            let romData = Data(repeating: UInt8(index), count: 1024 * 500) // 500KB each
            let romPath = tempDir.appendingPathComponent("rom\(index).dat")
            try romData.write(to: romPath)
        }

        // Sequential processing
        print("\nSequential Processing:")
        let seqStart = Date()

        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        var seqHashes: [String] = []
        for file in files {
            let data = try Data(contentsOf: file)
            seqHashes.append(HashUtilities.crc32(data: data))
        }

        let seqTime = Date().timeIntervalSince(seqStart)
        print("  Time: \(String(format: "%.3f", seqTime))s")
        print("  Processed: \(seqHashes.count) files")

        // Parallel processing
        print("\nParallel Processing:")
        let parStart = Date()

        var parHashes: [String] = []
        await withTaskGroup(of: String?.self) { group in
            for file in files {
                group.addTask {
                    guard let data = try? Data(contentsOf: file) else { return nil }
                    return await ParallelHashUtilities.crc32(data: data)
                }
            }

            for await hash in group {
                if let hash = hash {
                    parHashes.append(hash)
                }
            }
        }

        let parTime = Date().timeIntervalSince(parStart)
        print("  Time: \(String(format: "%.3f", parTime))s")
        print("  Processed: \(parHashes.count) files")

        let speedup = seqTime / parTime
        print("\n🏆 Performance Result:")
        print("  Speedup: \(String(format: "%.2fx", speedup))")

        if speedup > 1.0 {
            let improvement = (speedup - 1) * 100
            print("  ✅ Parallel is \(String(format: "%.0f%%", improvement)) faster!")
        } else {
            print("  ℹ️ Sequential is currently faster")
        }

        #expect(seqHashes.count == parHashes.count, "Should process same number of files")
    }
}
