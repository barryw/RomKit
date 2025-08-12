//
//  DATAccessExample.swift
//  RomKit
//
//  Example demonstrating how to access loaded DAT file data
//

import Foundation
import RomKit

func demonstrateDATAccess() async throws {
    // Initialize RomKit
    let romKit = RomKit()

    // Load a DAT file (auto-detects format)
    let datPath = "/path/to/mame.dat"
    try await romKit.loadDAT(from: datPath)

    // Access DAT header information
    if let header = romKit.datHeader {
        print("DAT Information:")
        print("  Name: \(header.name)")
        print("  Description: \(header.description)")
        print("  Version: \(header.version)")
        print("  Author: \(header.author ?? "Unknown")")
        print("  Date: \(header.date ?? "Unknown")")
    }

    // Quick access properties
    print("\nCollection Statistics:")
    print("  Format: \(romKit.datFormat.displayName)")
    print("  Total Games: \(romKit.gameCount)")
    print("  Total ROMs: \(romKit.totalROMCount)")

    // Access games collection
    let games = romKit.games
    print("\nFirst 5 games:")
    for game in games.prefix(5) {
        print("  - \(game.name): \(game.description ?? "No description")")
        if !game.roms.isEmpty {
            print("    ROMs: \(game.roms.count)")
        }
    }

    // Search functionality
    print("\nSearch Examples:")

    // Find a specific game
    if let game = romKit.findGame(name: "pacman") {
        print("Found game: \(game.name)")
        print("  Year: \(game.year ?? "Unknown")")
        print("  Manufacturer: \(game.manufacturer ?? "Unknown")")
    }

    // Find games by CRC
    let crc = "12345678"
    let gamesWithCRC = romKit.findGamesByCRC(crc)
    print("\nGames containing ROM with CRC \(crc): \(gamesWithCRC.count)")

    // Search by description
    let searchResults = romKit.searchGamesByDescription("Street Fighter")
    print("\nGames matching 'Street Fighter': \(searchResults.count)")

    // Parent/Clone relationships
    let parents = romKit.getParentGames()
    let clones = romKit.getCloneGames()
    print("\nParent games: \(parents.count)")
    print("Clone games: \(clones.count)")

    // Get clones of a specific parent
    if let firstParent = parents.first {
        let parentClones = romKit.getClones(of: firstParent.name)
        print("\nClones of '\(firstParent.name)': \(parentClones.count)")
    }

    // Get all game names (useful for UI lists)
    let allNames = romKit.getAllGameNames()
    print("\nTotal unique game names: \(allNames.count)")
}

// Example: Custom filtering and analysis
func analyzeCollection(romKit: RomKit) {
    let games = romKit.games

    // Find games by year
    let games1980s = games.filter { game in
        guard let year = game.year else { return false }
        return year.starts(with: "198")
    }
    print("Games from the 1980s: \(games1980s.count)")

    // Find games by manufacturer
    let capcomGames = games.filter { game in
        game.manufacturer?.lowercased().contains("capcom") ?? false
    }
    print("Capcom games: \(capcomGames.count)")

    // Find BIOS and device entries
    let biosEntries = games.filter { $0.isBios }
    let deviceEntries = games.filter { $0.isDevice }
    print("BIOS entries: \(biosEntries.count)")
    print("Device entries: \(deviceEntries.count)")

    // Analyze ROM sizes
    var totalSize: Int = 0
    for game in games {
        for rom in game.roms {
            totalSize += rom.size
        }
    }
    let totalSizeMB = Double(totalSize) / (1024 * 1024)
    print("Total ROM size: \(String(format: "%.2f", totalSizeMB)) MB")
}
