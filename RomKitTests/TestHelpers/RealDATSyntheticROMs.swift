//
//  RealDATSyntheticROMs.swift
//  RomKitTests
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation
@testable import RomKit

/// Generate synthetic ROMs that match real MAME DAT entries
/// These files will have the correct size and CRC32 to pass validation
public struct RealDATSyntheticROMs {

    /// Generate synthetic ROMs for specific games from the bundled DAT
    public static func generateSyntheticROMs(for gameNames: [String], to directory: URL) throws {
        // Load the bundled DAT
        let data = try TestDATLoader.loadFullMAMEDAT()
        let parser = LogiqxDATParser()
        let datFile = try parser.parse(data: data)

        // Find requested games
        for gameName in gameNames {
            guard let game = datFile.games.first(where: { $0.name == gameName }) else {
                print("Game '\(gameName)' not found in DAT")
                continue
            }

            guard let mameGame = game as? MAMEGame else { continue }

            // Create game directory
            let gameDir = directory.appendingPathComponent(gameName)
            try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)

            print("\nGenerating synthetic ROMs for: \(gameName)")
            print("  Description: \(mameGame.description)")

            // Generate each ROM
            for rom in mameGame.items {
                guard let mameRom = rom as? MAMEROM else { continue }

                let romPath = gameDir.appendingPathComponent(mameRom.name)

                // Generate data with matching CRC32
                if let crc = mameRom.checksums.crc32 {
                    let syntheticData = generateWithCRC32(
                        size: Int(mameRom.size),
                        targetCRC: crc
                    )

                    try syntheticData.write(to: romPath)

                    // Verify it matches
                    let actualCRC = calculateCRC32(syntheticData)
                    let matches = actualCRC.lowercased() == crc.lowercased()

                    print("    \(mameRom.name): \(mameRom.size) bytes, CRC: \(crc) [\(matches ? "✓" : "✗")]")
                }
            }
        }
    }

    /// Generate synthetic ROMs for popular/small games
    public static func generatePopularGames(to directory: URL) throws {
        // These are some small, well-known games that are good for testing
        let testGames = [
            "puckman",    // Pac-Man (parent)
            "pacman",     // Pac-Man (US clone)
            "mspacman",   // Ms. Pac-Man
            "galaga",     // Galaga
            "dkong",      // Donkey Kong
            "frogger",    // Frogger
            "asteroid",   // Asteroids
            "invaders",   // Space Invaders
        ]

        try generateSyntheticROMs(for: testGames, to: directory)
    }

    /// Generate data that will produce a specific CRC32
    public static func generateWithCRC32(size: Int, targetCRC: String) -> Data {
        guard size >= 4 else {
            // Too small to manipulate CRC
            return Data(repeating: 0, count: size)
        }

        // Parse target CRC
        let targetValue = UInt32(targetCRC, radix: 16) ?? 0

        // Generate base data (size - 4 bytes)
        var data = Data(count: size - 4)

        // Fill with pattern based on target CRC (for variety)
        var seed = targetValue
        for index in 0..<(size - 4) {
            seed = (seed &* 1664525) &+ 1013904223 // LCG
            data[index] = UInt8((seed >> 16) & 0xFF)
        }

        // Calculate current CRC32 of base data
        let currentCRC = crc32ForData(data)

        // Calculate the 4 bytes needed to force the target CRC
        // This uses the mathematical property that CRC32 is linear
        let forcedValue = forceTargetCRC(currentCRC: currentCRC, targetCRC: targetValue)

        // Append the forcing bytes
        data.append(UInt8(forcedValue & 0xFF))
        data.append(UInt8((forcedValue >> 8) & 0xFF))
        data.append(UInt8((forcedValue >> 16) & 0xFF))
        data.append(UInt8((forcedValue >> 24) & 0xFF))

        return data
    }

    /// Calculate what bytes to append to force a target CRC32
    private static func forceTargetCRC(currentCRC: UInt32, targetCRC: UInt32) -> UInt32 {
        // This works because CRC32 has the property that:
        // CRC(data + bytes) = CRC(data) XOR CRC(bytes)
        // So we need bytes where CRC(bytes) = currentCRC XOR targetCRC

        var desired = currentCRC ^ targetCRC

        // Reverse the CRC32 operation for 4 bytes
        for _ in 0..<32 {
            if desired & 0x80000000 != 0 {
                desired = (desired &<< 1) ^ 0x04C11DB7
            } else {
                desired = desired &<< 1
            }
        }

        return desired ^ 0xFFFFFFFF
    }

    /// Calculate CRC32 for data
    private static func crc32ForData(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF

        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }

        return crc ^ 0xFFFFFFFF
    }

    /// Calculate and return CRC32 as hex string
    public static func calculateCRC32(_ data: Data) -> String {
        let crc = crc32ForData(data)
        return String(format: "%08x", crc)
    }

    /// Verify a synthetic ROM matches expected properties
    public static func verifySyntheticROM(at path: URL, expectedCRC: String, expectedSize: Int) -> Bool {
        guard let data = try? Data(contentsOf: path) else { return false }

        // Check size
        guard data.count == expectedSize else {
            print("Size mismatch: expected \(expectedSize), got \(data.count)")
            return false
        }

        // Check CRC32
        let actualCRC = calculateCRC32(data)
        guard actualCRC.lowercased() == expectedCRC.lowercased() else {
            print("CRC mismatch: expected \(expectedCRC), got \(actualCRC)")
            return false
        }

        return true
    }

    /// Create a test scenario with specific games
    public static func createTestScenario() throws -> (directory: URL, games: [String]) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("synthetic_test_\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Generate a few small games
        let games = ["puckman", "galaga", "dkong"]
        try generateSyntheticROMs(for: games, to: tempDir)

        return (tempDir, games)
    }
}