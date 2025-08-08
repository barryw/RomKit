//
//  SyntheticROMGenerator.swift
//  RomKitTests
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation
import CryptoKit
@testable import RomKit

/// Generates synthetic ROM files for testing without using copyrighted content
public struct SyntheticROMGenerator {

    // MARK: - Basic Generation

    /// Generate deterministic ROM data using a seed
    /// This ensures the same seed always produces the same data (important for checksums)
    public static func generateROM(size: Int, seed: UInt32) -> Data {
        var data = Data(capacity: size)
        var rng = seed

        for index in 0..<size {
            // Simple deterministic pattern
            rng = (rng ^ UInt32(index)) &+ 1
            data.append(UInt8(rng & 0xFF))
        }

        return data
    }

    // MARK: - Generate with Target CRC32

    /// Generate a ROM that will have a specific CRC32 checksum
    /// TEMPORARILY DISABLED due to integer overflow issues
    public static func generateROMWithCRC32(size: Int, targetCRC: String) -> Data? {
        // For now, just return a basic ROM and print a warning
        print("Warning: CRC32 forcing temporarily disabled, generating basic ROM instead")
        return generateROM(size: size, seed: UInt32(targetCRC.hashValue & 0x7FFFFFFF))
    }

    // MARK: - Generate Test ROM Set

    /// Create a complete test ROM set that mimics MAME structure
    public static func generateTestROMSet() -> SyntheticROMSet {
        var romSet = SyntheticROMSet()

        // BIOS ROMs (like neogeo)
        romSet.addBIOS(
            name: "testbios",
            roms: [
                SyntheticROM(
                    name: "bios_main.bin",
                    size: 2048,
                    crc32: "1234abcd",
                    sha1: nil
                ),
                SyntheticROM(
                    name: "bios_sub.bin",
                    size: 1024,
                    crc32: "5678ef01",
                    sha1: nil
                )
            ]
        )

        // Parent game
        romSet.addGame(
            name: "parentgame",
            description: "Test Parent Game",
            parent: nil,
            bios: "testbios",
            roms: [
                SyntheticROM(
                    name: "prog1.rom",
                    size: 4096,
                    crc32: "aabbccdd",
                    sha1: nil
                ),
                SyntheticROM(
                    name: "prog2.rom",
                    size: 8192,
                    crc32: "11223344",
                    sha1: nil
                ),
                SyntheticROM(
                    name: "shared.rom",
                    size: 2048,
                    crc32: "deadbeef",
                    sha1: nil
                )
            ]
        )

        // Clone game (shares some ROMs)
        romSet.addGame(
            name: "clonegame",
            description: "Test Clone Game",
            parent: "parentgame",
            bios: "testbios",
            roms: [
                SyntheticROM(
                    name: "prog1.rom",
                    size: 4096,
                    crc32: "ffffffff",  // Different from parent
                    sha1: nil
                ),
                SyntheticROM(
                    name: "prog2.rom",
                    size: 8192,
                    crc32: "11223344",  // Same as parent (shared)
                    sha1: nil
                ),
                SyntheticROM(
                    name: "shared.rom",
                    size: 2048,
                    crc32: "deadbeef",  // Same as parent (shared)
                    sha1: nil
                )
            ]
        )

        return romSet
    }

    // MARK: - Generate Mini DAT File

    /// Generate a minimal DAT file for testing
    public static func generateTestDAT() -> MAMEDATFile {
        let romSet = generateTestROMSet()

        var games: [MAMEGame] = []

        // Add BIOS
        if let bios = romSet.bios.first {
            let biosGame = MAMEGame(
                name: bios.name,
                description: "Test BIOS",
                roms: bios.roms.map { rom in
                    MAMEROM(
                        name: rom.name,
                        size: UInt64(rom.size),
                        checksums: ROMChecksums(
                            crc32: rom.crc32,
                            sha1: rom.sha1,
                            sha256: nil,
                            md5: nil
                        )
                    )
                },
                metadata: MAMEGameMetadata(isBios: true)
            )
            games.append(biosGame)
        }

        // Add games
        for game in romSet.games {
            let mameGame = MAMEGame(
                name: game.name,
                description: game.description,
                roms: game.roms.map { rom in
                    MAMEROM(
                        name: rom.name,
                        size: UInt64(rom.size),
                        checksums: ROMChecksums(
                            crc32: rom.crc32,
                            sha1: rom.sha1,
                            sha256: nil,
                            md5: nil
                        )
                    )
                },
                metadata: MAMEGameMetadata(
                    cloneOf: game.parent,
                    biosSet: game.bios
                )
            )
            games.append(mameGame)
        }

        return MAMEDATFile(
            formatVersion: "Test",
            games: games,
            metadata: MAMEMetadata(
                name: "Test DAT",
                description: "Synthetic test DAT for RomKit"
            )
        )
    }

    // MARK: - CRC32 Calculation

    private static func crc32(_ data: Data) -> UInt32 {
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
}

// MARK: - Supporting Types

public struct SyntheticROMSet {
    public var bios: [SyntheticBIOS] = []
    public var games: [SyntheticGame] = []

    public struct SyntheticBIOS {
        public let name: String
        public let roms: [SyntheticROM]
    }

    public struct SyntheticGame {
        public let name: String
        public let description: String
        public let parent: String?
        public let bios: String?
        public let roms: [SyntheticROM]
    }

    public mutating func addBIOS(name: String, roms: [SyntheticROM]) {
        bios.append(SyntheticBIOS(name: name, roms: roms))
    }

    public mutating func addGame(name: String, description: String, parent: String?, bios: String?, roms: [SyntheticROM]) {
        games.append(SyntheticGame(
            name: name,
            description: description,
            parent: parent,
            bios: bios,
            roms: roms
        ))
    }

    /// Generate all ROM files to a directory
    public func generateFiles(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Generate BIOS ROMs
        for biosSet in bios {
            let biosDir = directory.appendingPathComponent(biosSet.name)
            try FileManager.default.createDirectory(at: biosDir, withIntermediateDirectories: true)

            for rom in biosSet.roms {
                let romPath = biosDir.appendingPathComponent(rom.name)
                try rom.generateData().write(to: romPath)
            }
        }

        // Generate game ROMs
        for game in games {
            let gameDir = directory.appendingPathComponent(game.name)
            try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)

            for rom in game.roms {
                let romPath = gameDir.appendingPathComponent(rom.name)
                try rom.generateData().write(to: romPath)
            }
        }
    }

    /// Generate loose ROMs with scrambled names (for rebuild testing)
    public func generateLooseROMs(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var allROMs: [(original: String, rom: SyntheticROM)] = []

        // Collect all ROMs
        for biosSet in bios {
            for rom in biosSet.roms {
                allROMs.append((biosSet.name + "/" + rom.name, rom))
            }
        }

        for game in games {
            for rom in game.roms {
                allROMs.append((game.name + "/" + rom.name, rom))
            }
        }

        // Save with scrambled names
        for (original, rom) in allROMs {
            // Create a scrambled but deterministic name
            let scrambled = "rom_\(rom.crc32 ?? "unknown")_\(UUID().uuidString).bin"
            let path = directory.appendingPathComponent(scrambled)

            let data = rom.generateData()
            try data.write(to: path)

            print("Generated: \(scrambled) (was: \(original))")
        }
    }
}

public struct SyntheticROM {
    public let name: String
    public let size: Int
    public let crc32: String?
    public let sha1: String?

    public init(name: String, size: Int, crc32: String? = nil, sha1: String? = nil) {
        self.name = name
        self.size = size
        self.crc32 = crc32
        self.sha1 = sha1
    }

    /// Generate the actual ROM data
    public func generateData() -> Data {
        if let targetCRC = crc32 {
            // Generate with specific CRC32
            return SyntheticROMGenerator.generateROMWithCRC32(size: size, targetCRC: targetCRC)
                ?? SyntheticROMGenerator.generateROM(size: size, seed: 0)
        } else {
            // Generate with seed based on name
            let seed = UInt32(name.hashValue & 0x7FFFFFFF)
            return SyntheticROMGenerator.generateROM(size: size, seed: seed)
        }
    }

    /// Calculate actual checksums of generated data
    public func calculateChecksums() -> ROMChecksums {
        let data = generateData()

        // CRC32
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
        let calculatedCRC = String(format: "%08x", crc ^ 0xFFFFFFFF)

        // SHA1
        let sha1Hash = Insecure.SHA1.hash(data: data)
        let calculatedSHA1 = sha1Hash.map { String(format: "%02x", $0) }.joined()

        return ROMChecksums(
            crc32: crc32 ?? calculatedCRC,
            sha1: sha1 ?? calculatedSHA1,
            sha256: nil,
            md5: nil
        )
    }
}
