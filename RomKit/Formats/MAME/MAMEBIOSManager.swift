//
//  MAMEBIOSManager.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation

// MARK: - BIOS and Device Management

public class MAMEBIOSManager {
    private let datFile: MAMEDATFile
    private var biosCache: [String: MAMEGame] = [:]
    private var deviceCache: [String: MAMEGame] = [:]
    private var dependencyMap: [String: Set<String>] = [:]
    
    public init(datFile: MAMEDATFile) {
        self.datFile = datFile
        buildCaches()
    }
    
    private func buildCaches() {
        for game in datFile.games {
            guard let mameGame = game as? MAMEGame,
                  let metadata = mameGame.metadata as? MAMEGameMetadata else { continue }
            
            // Cache BIOS sets
            if metadata.isBios {
                biosCache[mameGame.name] = mameGame
            }
            
            // Cache device sets
            if metadata.isDevice {
                deviceCache[mameGame.name] = mameGame
            }
            
            // Build dependency map
            var dependencies = Set<String>()
            
            // Add BIOS dependency
            if let biosSet = metadata.biosSet {
                dependencies.insert(biosSet)
            }
            
            // Add device dependencies - but only if they're actual device ROM sets
            for deviceRef in metadata.deviceRefs {
                if deviceCache[deviceRef] != nil {
                    dependencies.insert(deviceRef)
                }
            }
            
            // Add parent ROM dependencies (for clones)
            if let romOf = metadata.romOf {
                dependencies.insert(romOf)
            }
            
            if !dependencies.isEmpty {
                dependencyMap[mameGame.name] = dependencies
            }
        }
    }
    
    // MARK: - Public API
    
    /// Get all BIOS sets in the DAT
    public var allBIOSSets: [MAMEGame] {
        return Array(biosCache.values)
    }
    
    /// Get all device sets in the DAT
    public var allDeviceSets: [MAMEGame] {
        return Array(deviceCache.values)
    }
    
    /// Check if a game is a BIOS
    public func isBIOS(_ gameName: String) -> Bool {
        return biosCache[gameName] != nil
    }
    
    /// Check if a game is a device
    public func isDevice(_ gameName: String) -> Bool {
        return deviceCache[gameName] != nil
    }
    
    /// Get all dependencies for a game (BIOS, devices, parent ROMs)
    public func getDependencies(for gameName: String) -> Set<String> {
        return dependencyMap[gameName] ?? []
    }
    
    /// Get only ROM-containing dependencies (BIOS, device ROMs, parent games)
    /// Filters out internal MAME device drivers like "z80", "speaker", etc.
    public func getROMDependencies(for gameName: String) -> Set<String> {
        let allDeps = dependencyMap[gameName] ?? []
        return allDeps.filter { dep in
            // Only include if it's an actual ROM set (BIOS, device ROM, or game)
            return biosCache[dep] != nil || 
                   deviceCache[dep] != nil || 
                   datFile.games.contains { ($0 as? MAMEGame)?.name == dep }
        }
    }
    
    /// Get all games that depend on a specific BIOS or device
    public func getDependents(of biosOrDevice: String) -> [String] {
        return dependencyMap.compactMap { (game, deps) in
            deps.contains(biosOrDevice) ? game : nil
        }
    }
    
    /// Get the required BIOS for a game
    public func getRequiredBIOS(for gameName: String) -> MAMEGame? {
        guard let game = datFile.games.first(where: { ($0 as? MAMEGame)?.name == gameName }) as? MAMEGame,
              let metadata = game.metadata as? MAMEGameMetadata,
              let biosSet = metadata.biosSet else { return nil }
        
        return biosCache[biosSet]
    }
    
    /// Get all required ROMs including dependencies
    public func getAllRequiredROMs(for gameName: String) -> [RequiredROM] {
        var requiredROMs: [RequiredROM] = []
        var processedSets = Set<String>()
        var setsToProcess = [gameName]
        
        while !setsToProcess.isEmpty {
            let currentSet = setsToProcess.removeFirst()
            
            guard !processedSets.contains(currentSet) else { continue }
            processedSets.insert(currentSet)
            
            // Find the game/BIOS/device
            guard let game = findGame(named: currentSet) else { continue }
            
            // Add its ROMs
            for rom in game.items {
                guard let mameRom = rom as? MAMEROM else { continue }
                
                requiredROMs.append(RequiredROM(
                    rom: mameRom,
                    sourceSet: currentSet,
                    isFromBIOS: biosCache[currentSet] != nil,
                    isFromDevice: deviceCache[currentSet] != nil,
                    isFromParent: currentSet != gameName && !biosCache.keys.contains(currentSet) && !deviceCache.keys.contains(currentSet)
                ))
            }
            
            // Add dependencies to process - but only BIOS, real devices, and parent ROMs
            if let deps = dependencyMap[currentSet] {
                // Filter to only include actual ROM-containing dependencies
                let romDeps = deps.filter { dep in
                    // Include if it's a BIOS, a real device ROM, or a parent game
                    return biosCache[dep] != nil || 
                           deviceCache[dep] != nil || 
                           findGame(named: dep) != nil
                }
                setsToProcess.append(contentsOf: romDeps.filter { !processedSets.contains($0) })
            }
        }
        
        return requiredROMs
    }
    
    private func findGame(named name: String) -> MAMEGame? {
        if let bios = biosCache[name] {
            return bios
        }
        if let device = deviceCache[name] {
            return device
        }
        return datFile.games.first { ($0 as? MAMEGame)?.name == name } as? MAMEGame
    }
}

// MARK: - Required ROM Info

public struct RequiredROM {
    public let rom: MAMEROM
    public let sourceSet: String
    public let isFromBIOS: Bool
    public let isFromDevice: Bool
    public let isFromParent: Bool
    
    public var category: String {
        if isFromBIOS { return "BIOS" }
        if isFromDevice { return "Device" }
        if isFromParent { return "Parent" }
        return "Game"
    }
}