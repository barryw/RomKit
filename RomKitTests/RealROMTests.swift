//
//  RealROMTests.swift
//  RomKitTests
//
//  Created by Barry Walker on 8/5/25.
//

import Testing
import Foundation
@testable import RomKit

/// Tests designed to work with real MAME ROM sets
/// These tests use the bundled DAT file and optionally scan real ROMs if:
/// - ROMKIT_TEST_ROM_PATH environment variable is set to your ROM directory
///
/// To run these tests with real ROMs:
/// export ROMKIT_TEST_ROM_PATH="/path/to/your/roms"
/// swift test --filter RealROMTests
struct RealROMTests {
    
    let romPath: URL?
    let hasRealROMs: Bool
    
    init() {
        let env = ProcessInfo.processInfo.environment
        
        if let romPathStr = env["ROMKIT_TEST_ROM_PATH"] {
            self.romPath = URL(fileURLWithPath: romPathStr)
            self.hasRealROMs = true
            print("Real ROM scanning enabled:")
            print("  ROM Path: \(romPathStr)")
        } else {
            self.romPath = nil
            self.hasRealROMs = false
            print("Real ROM scanning disabled. Set ROMKIT_TEST_ROM_PATH to enable.")
        }
    }
    
    @Test func testRealMAMEDATLoading() async throws {
        // Always test with bundled DAT
        print("Loading bundled MAME DAT...")
        let data = try TestDATLoader.loadFullMAMEDAT()
        
        let startTime = Date()
        let parser = LogiqxDATParser()
        let datFile = try parser.parse(data: data)
        let loadTime = Date().timeIntervalSince(startTime)
        
        print("Loaded MAME DAT:")
        print("  Games: \(datFile.games.count)")
        print("  Load time: \(String(format: "%.2f", loadTime)) seconds")
        
        #expect(datFile.games.count > 0)
        
        // Count different types
        let biosManager = MAMEBIOSManager(datFile: datFile)
        let biosCount = biosManager.allBIOSSets.count
        let deviceCount = biosManager.allDeviceSets.count
        
        print("  BIOS sets: \(biosCount)")
        print("  Device sets: \(deviceCount)")
        
        // Find games with complex dependencies
        var complexGames: [(name: String, deps: Int)] = []
        for game in datFile.games.prefix(100) {  // Check first 100 for performance
            guard let mameGame = game as? MAMEGame else { continue }
            let deps = biosManager.getDependencies(for: mameGame.name)
            if deps.count > 2 {
                complexGames.append((mameGame.name, deps.count))
            }
        }
        
        print("  Games with 3+ dependencies: \(complexGames.count)")
        for (name, depCount) in complexGames.prefix(5) {
            print("    - \(name): \(depCount) dependencies")
        }
    }
    
    @Test func testRealROMScanning() async throws {
        guard hasRealROMs, let romPath = romPath else {
            print("Skipping: Real ROM scanning not enabled")
            return
        }
        
        // Load bundled DAT
        print("Loading bundled DAT...")
        let data = try TestDATLoader.loadFullMAMEDAT()
        let parser = LogiqxDATParser()
        let datFile = try parser.parse(data: data)
        
        // Create scanner
        let handler = MAMEFormatHandler()
        let scanner = handler.createScanner(for: datFile)
        
        // Scan ROMs
        print("Scanning ROM directory: \(romPath.path)")
        let startTime = Date()
        let results = try await scanner.scan(directory: romPath)
        let scanTime = Date().timeIntervalSince(startTime)
        
        print("Scan Results:")
        print("  Scan time: \(String(format: "%.2f", scanTime)) seconds")
        print("  Found games: \(results.foundGames.count)")
        print("  Unknown files: \(results.unknownFiles.count)")
        
        // Analyze results
        var completeGames = 0
        var incompleteGames = 0
        var missingGames = 0
        
        for game in results.foundGames {
            switch game.status {
            case .complete:
                completeGames += 1
            case .incomplete:
                incompleteGames += 1
            case .missing:
                missingGames += 1
            case .unknown:
                // Handle unknown status
                break
            }
        }
        
        print("  Complete: \(completeGames)")
        print("  Incomplete: \(incompleteGames)")
        print("  Missing: \(missingGames)")
        
        #expect(results.foundGames.count > 0 || results.unknownFiles.count > 0)
    }
    
    @Test func testSpecificGameValidation() async throws {
        guard hasRealROMs, let romPath = romPath else {
            print("Skipping: Real ROM scanning not enabled")
            return
        }
        
        // Games to test (adjust based on what you have)
        let testGames = ["mslug", "neogeo", "pacman", "galaga", "sf2"]
        
        // Load bundled DAT
        let data = try TestDATLoader.loadFullMAMEDAT()
        let parser = LogiqxDATParser()
        let datFile = try parser.parse(data: data)
        let biosManager = MAMEBIOSManager(datFile: datFile)
        
        for gameName in testGames {
            guard datFile.games.first(where: { ($0 as? MAMEGame)?.name == gameName }) != nil else {
                print("\(gameName): Not found in DAT")
                continue
            }
            
            // Check if ZIP exists
            let zipPath = romPath.appendingPathComponent("\(gameName).zip")
            if FileManager.default.fileExists(atPath: zipPath.path) {
                print("\n\(gameName):")
                print("  Found: \(zipPath.lastPathComponent)")
                
                // Get requirements
                let requiredROMs = biosManager.getAllRequiredROMs(for: gameName)
                let byCategory = Dictionary(grouping: requiredROMs, by: { $0.category })
                
                print("  Requires:")
                for (category, roms) in byCategory {
                    print("    - \(category): \(roms.count) ROMs")
                }
                
                // List ROM dependencies (not internal device drivers)
                let romDeps = biosManager.getROMDependencies(for: gameName)
                if !romDeps.isEmpty {
                    print("  ROM Dependencies: \(romDeps.joined(separator: ", "))")
                    
                    // Check if dependencies exist
                    for dep in romDeps {
                        let depZip = romPath.appendingPathComponent("\(dep).zip")
                        let depExists = FileManager.default.fileExists(atPath: depZip.path)
                        print("    - \(dep).zip: \(depExists ? "✓" : "✗ MISSING")")
                    }
                }
                
                // Also show all dependencies for debugging
                let allDeps = biosManager.getDependencies(for: gameName)
                if allDeps.count > romDeps.count {
                    let internalDevices = allDeps.subtracting(romDeps)
                    print("  Internal devices (not ROM files): \(internalDevices.sorted().joined(separator: ", "))")
                }
            } else {
                print("\(gameName): Not found")
            }
        }
    }
    
    @Test func testBIOSAndDeviceAvailability() async throws {
        guard hasRealROMs, let romPath = romPath else {
            print("Skipping: Real ROM scanning not enabled")
            return
        }
        
        // Load bundled DAT
        let data = try TestDATLoader.loadFullMAMEDAT()
        let parser = LogiqxDATParser()
        let datFile = try parser.parse(data: data)
        let biosManager = MAMEBIOSManager(datFile: datFile)
        
        print("\nBIOS Sets:")
        for bios in biosManager.allBIOSSets.prefix(10) {
            let zipPath = romPath.appendingPathComponent("\(bios.name).zip")
            let exists = FileManager.default.fileExists(atPath: zipPath.path)
            print("  \(bios.name): \(exists ? "✓" : "✗")")
            
            if exists {
                // Count games that need this BIOS
                let dependents = biosManager.getDependents(of: bios.name)
                print("    Required by \(dependents.count) games")
            }
        }
        
        print("\nDevice Sets:")
        for device in biosManager.allDeviceSets.prefix(10) {
            let zipPath = romPath.appendingPathComponent("\(device.name).zip")
            let exists = FileManager.default.fileExists(atPath: zipPath.path)
            print("  \(device.name): \(exists ? "✓" : "✗")")
            
            if exists {
                // Count games that need this device
                let dependents = biosManager.getDependents(of: device.name)
                print("    Required by \(dependents.count) games")
            }
        }
    }
    
    @Test func testMergeScenarios() async throws {
        guard hasRealROMs, let romPath = romPath else {
            print("Skipping: Real ROM scanning not enabled")
            return
        }
        
        // Load bundled DAT
        let data = try TestDATLoader.loadFullMAMEDAT()
        let parser = LogiqxDATParser()
        let datFile = try parser.parse(data: data)
        
        // Find parent/clone pairs that exist
        print("\nParent/Clone Analysis:")
        
        var foundPairs: [(parent: String, clone: String)] = []
        
        for game in datFile.games {
            guard let mameGame = game as? MAMEGame,
                  let metadata = mameGame.metadata as? MAMEGameMetadata,
                  let cloneOf = metadata.cloneOf else { continue }
            
            let parentZip = romPath.appendingPathComponent("\(cloneOf).zip")
            let cloneZip = romPath.appendingPathComponent("\(mameGame.name).zip")
            
            if FileManager.default.fileExists(atPath: parentZip.path) &&
               FileManager.default.fileExists(atPath: cloneZip.path) {
                foundPairs.append((cloneOf, mameGame.name))
                
                if foundPairs.count <= 5 {
                    print("  \(cloneOf) → \(mameGame.name)")
                    
                    // Count merged ROMs
                    let mameROMs = mameGame.items.compactMap { $0 as? MAMEROM }
                    let mergedROMs = mameROMs.filter { $0.attributes.merge != nil }
                    print("    Merged ROMs: \(mergedROMs.count)/\(mameROMs.count)")
                }
            }
        }
        
        print("  Total parent/clone pairs found: \(foundPairs.count)")
    }
}

// MARK: - Test Utilities

extension RealROMTests {
    
    /// Analyzes a ROM set to determine its merge type
    func analyzeMergeType(at path: URL, datFile: MAMEDATFile) throws -> String {
        // This would analyze the actual ZIP contents to determine
        // if it's split, merged, or non-merged
        // Implementation would require reading ZIP files
        return "unknown"
    }
    
    /// Validates ROM integrity
    func validateROM(at path: URL, against rom: MAMEROM) throws -> Bool {
        // This would extract and validate the ROM against checksums
        // Implementation would require ZIP extraction and hashing
        return false
    }
}