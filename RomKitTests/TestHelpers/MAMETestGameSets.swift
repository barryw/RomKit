//
//  MAMETestGameSets.swift
//  RomKitTests
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation
@testable import RomKit

/// Curated sets of MAME games for comprehensive testing
public struct MAMETestGameSets {

    // MARK: - Classic Arcade (1970s-1980s)

    public static let classicArcade = [
        // Early classics
        "pong",         // 1972 - One of the first
        "asteroid",     // 1979 - Vector graphics
        "invaders",     // 1978 - Space Invaders

        // Golden Age
        "puckman",      // 1980 - Pac-Man (Japan parent)
        "pacman",       // 1980 - Pac-Man (US clone)
        "mspacman",     // 1981 - Ms. Pac-Man (enhancement)
        "galaga",       // 1981 - Classic shooter
        "dkong",        // 1981 - Donkey Kong
        "dkongjr",      // 1982 - Donkey Kong Jr
        "frogger",      // 1981 - Frogger
        "defender",     // 1980 - Williams classic
        "robotron",     // 1982 - Twin-stick shooter
        "joust",        // 1982 - Unique gameplay
        "qbert",        // 1982 - Isometric puzzle
        "digdug",       // 1982 - Namco classic
        "centipede",    // 1980 - Trackball game
        "missile"      // 1980 - Missile Command
    ]

    // MARK: - Neo-Geo Games (Complex BIOS dependencies)

    public static let neoGeoGames = [
        // These ALL require neogeo.zip BIOS
        "mslug",        // Metal Slug
        "mslug2",       // Metal Slug 2
        "mslugx",       // Metal Slug X (clone of mslug2)
        "kof94",        // King of Fighters '94
        "kof95",        // King of Fighters '95
        "kof96",        // King of Fighters '96
        "fatfury",      // Fatal Fury
        "samsho",       // Samurai Shodown
        "puzzledp",     // Puzzle De Pon
        "blazstar",     // Blazing Star
        "pulstar",      // Pulstar
        "viewpoin",     // Viewpoint
        "aof",          // Art of Fighting
        "lastblad",     // Last Blade
        "shocktro"     // Shock Troopers
    ]

    // MARK: - CPS1 Games (Capcom - Complex parent/clone)

    public static let cps1Games = [
        "sf2",          // Street Fighter II (parent)
        "sf2ce",        // SF2: Champion Edition (clone)
        "sf2hf",        // SF2: Hyper Fighting (clone)
        "sf2t",         // SF2: Turbo (clone)
        "1941",         // 1941: Counter Attack
        "ghouls",       // Ghouls'n Ghosts
        "strider",      // Strider
        "willow",       // Willow
        "ffight",       // Final Fight
        "dino",         // Cadillacs and Dinosaurs
        "punisher"     // The Punisher
    ]

    // MARK: - CPS2 Games (Requires qsound device)

    public static let cps2Games = [
        "ssf2",         // Super Street Fighter II
        "ssf2t",        // Super SF2 Turbo
        "xmcota",       // X-Men: Children of the Atom
        "msh",          // Marvel Super Heroes
        "mvsc",         // Marvel vs. Capcom
        "ddtod",        // Dungeons & Dragons: Tower of Doom
        "ddsom",        // Dungeons & Dragons: Shadow over Mystara
        "19xx"         // 19XX: The War Against Destiny
    ]

    // MARK: - Namco System 1 (Multiple device ROMs)

    public static let namcoSystem1Games = [
        // These require namco51, namco52, namco53, namco54 device ROMs
        "pacland",      // Pac-Land
        "baraduke",     // Baraduke
        "metro",        // Metro-Cross
        "wldcourt"     // World Court
    ]

    // MARK: - Sega System 16 (Complex hardware)

    public static let system16Games = [
        "shinobi",      // Shinobi
        "goldnaxe",     // Golden Axe
        "altbeast",     // Altered Beast
        "outrun",       // OutRun
        "hangon"       // Hang-On
    ]

    // MARK: - Modern Games (2000s+, complex dependencies)

    public static let modernGames = [
        "kof2002",      // King of Fighters 2002 (Neo-Geo)
        "mslug5",       // Metal Slug 5 (Neo-Geo)
        "samsho5",      // Samurai Shodown V (Neo-Geo)
        "rotd",         // Rage of the Dragons (Neo-Geo)
        "matrimelee"   // Matrimelee (Neo-Geo)
    ]

    // MARK: - Weird/Edge Cases

    public static let edgeCases = [
        // Multiple BIOS options
        "neogeo",       // The BIOS itself (not a game)

        // Prototype/unreleased
        "puckmanb",     // Pac-Man bootleg
        "puckmod",      // Pac-Man speedup hack

        // Requires special hardware
        "area51",       // Area 51 (requires CHD)
        "kinst",        // Killer Instinct (requires CHD)

        // Multi-board games
        "playch10",     // PlayChoice-10 BIOS
        "pc_smb",       // Super Mario Bros (PlayChoice)

        // Mahjong (different input system)
        "jantotsu",     // Mahjong game

        // Mechanical games (not fully emulated)
        "allied",       // Allied System (mechanical)

        // Calculator/computer
        "ti74",         // TI-74 calculator
        "zx81",         // ZX81 computer

        // Very large ROM sets
        "gauntlet",     // Gauntlet (many ROMs)

        // Games with samples
        "dkong",        // Uses sample files
        "galaga"       // Uses sample files
    ]

    // MARK: - Test Subsets

    /// Small set for quick testing
    public static let quickTest = [
        "puckman",      // Simple parent
        "pacman",       // Clone of puckman
        "mslug",        // Neo-Geo game (BIOS dependency)
        "dkong"        // Has samples
    ]

    /// Medium set covering major scenarios
    public static let standardTest = [
        // Parents and clones
        "puckman", "pacman",
        "mspacman",

        // Neo-Geo (BIOS)
        "neogeo", "mslug", "kof94",

        // CPS1/CPS2
        "sf2", "sf2ce",

        // Namco (devices)
        "pacland",

        // Samples
        "dkong", "galaga"
    ]

    /// Comprehensive test covering all scenarios
    public static let comprehensiveTest =
        classicArcade +
        neoGeoGames.prefix(5) +
        cps1Games.prefix(3) +
        cps2Games.prefix(2) +
        namcoSystem1Games.prefix(2) +
        edgeCases.prefix(5)

    // MARK: - Helper Methods

    /// Get game info from bundled DAT
    public static func getGameInfo(for gameName: String) throws -> MAMEGame? {
        let data = try TestDATLoader.loadFullMAMEDAT()
        let parser = LogiqxDATParser()
        let datFile = try parser.parse(data: data)

        return datFile.games.first { $0.name == gameName } as? MAMEGame
    }

    /// Analyze a game's dependencies
    public static func analyzeDependencies(for gameName: String) throws {
        guard let game = try getGameInfo(for: gameName) else {
            print("Game '\(gameName)' not found")
            return
        }

        print("\n=== \(gameName) ===")
        print("Description: \(game.description)")
        print("ROMs: \(game.items.count)")

        if let cloneOf = game.metadata.cloneOf {
            print("Clone of: \(cloneOf)")
        }

        if let romOf = game.metadata.romOf {
            print("ROM of: \(romOf)")
        }

        // Cast to MAME-specific metadata to access extended properties
        if let mameMetadata = game.metadata as? MAMEGameMetadata {
            if let biosSet = mameMetadata.biosSet {
                print("BIOS: \(biosSet)")
            }

            if !mameMetadata.deviceRefs.isEmpty {
                print("Devices: \(mameMetadata.deviceRefs.joined(separator: ", "))")
            }

            if mameMetadata.isBios {
                print("Type: BIOS")
            }

            if mameMetadata.isDevice {
                print("Type: Device ROM")
            }
        }

        // Calculate total size
        let totalSize = game.items.reduce(0) { $0 + $1.size }
        print("Total size: \(totalSize / 1024) KB")
    }

    /// Generate synthetic ROMs for a test set
    public static func generateTestSet(_ games: [String], to directory: URL) throws {
        print("Generating synthetic ROMs for \(games.count) games...")

        var successCount = 0
        var failCount = 0
        var totalSize: UInt64 = 0

        for game in games {
            do {
                if let gameInfo = try getGameInfo(for: game) {
                    try RealDATSyntheticROMs.generateSyntheticROMs(for: [game], to: directory)
                    successCount += 1
                    totalSize += gameInfo.items.reduce(0) { $0 + $1.size }
                } else {
                    print("  ⚠️ \(game): Not found in DAT")
                    failCount += 1
                }
            } catch {
                print("  ❌ \(game): \(error)")
                failCount += 1
            }
        }

        print("\nGeneration complete:")
        print("  ✅ Success: \(successCount)")
        print("  ❌ Failed: \(failCount)")
        print("  💾 Total size: \(totalSize / 1024 / 1024) MB")
    }

    /// Find games with specific characteristics
    public static func findGamesWithCharacteristics() throws {
        let data = try TestDATLoader.loadFullMAMEDAT()
        let parser = LogiqxDATParser()
        let datFile = try parser.parse(data: data)

        var biosGames: [String] = []
        var deviceGames: [String] = []
        var multiDeviceGames: [String] = []
        var largeGames: [String] = []
        var sampleGames: [String] = []

        for game in datFile.games {
            guard let mameGame = game as? MAMEGame else { continue }

            // Cast to MAMEGameMetadata to access MAME-specific properties
            if let mameMetadata = mameGame.metadata as? MAMEGameMetadata {
                if mameMetadata.biosSet != nil {
                    biosGames.append(game.name)
                }

                if !mameMetadata.deviceRefs.isEmpty {
                    deviceGames.append(game.name)
                    if mameMetadata.deviceRefs.count > 2 {
                        multiDeviceGames.append(game.name)
                    }
                }
            }

            let totalSize = mameGame.items.reduce(0) { $0 + $1.size }
            if totalSize > 10_000_000 { // > 10MB
                largeGames.append(game.name)
            }

            if mameGame.metadata.sampleOf != nil || !mameGame.samples.isEmpty {
                sampleGames.append(game.name)
            }
        }

        print("\nGame Characteristics:")
        print("  BIOS-dependent: \(biosGames.count) games")
        print("  Device-dependent: \(deviceGames.count) games")
        print("  Multi-device: \(multiDeviceGames.count) games")
        print("  Large (>10MB): \(largeGames.count) games")
        print("  Sample-using: \(sampleGames.count) games")

        // Show some examples
        print("\nExample multi-device games:")
        for game in multiDeviceGames.prefix(5) {
            if let info = try getGameInfo(for: game),
               let mameMetadata = info.metadata as? MAMEGameMetadata {
                print("  \(game): \(mameMetadata.deviceRefs.joined(separator: ", "))")
            }
        }
    }
}
