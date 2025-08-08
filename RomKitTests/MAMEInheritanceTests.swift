//
//  MAMEInheritanceTests.swift
//  RomKitTests
//
//  Created by Barry Walker on 8/5/25.
//

import Testing
import Foundation
@testable import RomKit

struct MAMEInheritanceTests {

    let testDataPath = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .appendingPathComponent("TestData")

    var datFile: MAMEDATFile!
    var biosManager: MAMEBIOSManager!

    init() async throws {
        let datPath = testDataPath.appendingPathComponent("mame_inheritance_test.xml")
        let data = try Data(contentsOf: datPath)
        let parser = MAMEDATParser()
        datFile = try parser.parse(data: data)
        biosManager = MAMEBIOSManager(datFile: datFile)
    }

    // MARK: - BIOS Tests

    @Test func testBIOSIdentification() async throws {
        #expect(biosManager.isBIOS("neogeo") == true)
        #expect(biosManager.isBIOS("mslug") == false)
        #expect(biosManager.isBIOS("galaga") == false)

        let allBios = biosManager.allBIOSSets
        #expect(allBios.count == 1)
        #expect(allBios.first?.name == "neogeo")
    }

    @Test func testBIOSDependencies() async throws {
        // Metal Slug requires Neo-Geo BIOS
        let mslugDeps = biosManager.getDependencies(for: "mslug")
        #expect(mslugDeps.contains("neogeo"))

        // Metal Slug X requires Neo-Geo BIOS and inherits from Metal Slug
        let mslugxDeps = biosManager.getDependencies(for: "mslugx")
        #expect(mslugxDeps.contains("neogeo"))
        #expect(mslugxDeps.contains("mslug"))

        // Galaga doesn't require BIOS
        let galagaDeps = biosManager.getDependencies(for: "galaga")
        #expect(!galagaDeps.contains("neogeo"))
    }

    @Test func testBIOSROMRequirements() async throws {
        let requiredROMs = biosManager.getAllRequiredROMs(for: "mslug")

        // Should include both game ROMs and BIOS ROMs
        let gameROMs = requiredROMs.filter { !$0.isFromBIOS }
        let biosROMs = requiredROMs.filter { $0.isFromBIOS }

        #expect(gameROMs.count == 4)  // mslug has 4 ROMs
        #expect(biosROMs.count == 5)  // neogeo BIOS has 5 ROMs in our test

        // Check specific BIOS ROMs are included
        let hasSfix = biosROMs.contains { $0.rom.name == "sfix.sfix" }
        let hasLoRom = biosROMs.contains { $0.rom.name == "000-lo.lo" }
        #expect(hasSfix)
        #expect(hasLoRom)
    }

    // MARK: - Device Tests

    @Test func testDeviceIdentification() async throws {
        #expect(biosManager.isDevice("namco51") == true)
        #expect(biosManager.isDevice("namco54") == true)
        #expect(biosManager.isDevice("galaga") == false)

        let allDevices = biosManager.allDeviceSets
        #expect(allDevices.count == 2)
    }

    @Test func testDeviceDependencies() async throws {
        // Galaga requires Namco custom chips
        let galagaDeps = biosManager.getDependencies(for: "galaga")
        #expect(galagaDeps.contains("namco51"))
        #expect(galagaDeps.contains("namco54"))

        // Clone also requires the same devices
        let galagaoDeps = biosManager.getDependencies(for: "galagao")
        #expect(galagaoDeps.contains("namco51"))
        #expect(galagaoDeps.contains("namco54"))
        #expect(galagaoDeps.contains("galaga"))  // Also depends on parent
    }

    @Test func testDeviceROMRequirements() async throws {
        let requiredROMs = biosManager.getAllRequiredROMs(for: "galaga")

        let gameROMs = requiredROMs.filter { !$0.isFromDevice }
        let deviceROMs = requiredROMs.filter { $0.isFromDevice }

        #expect(gameROMs.count == 4)  // galaga has 4 ROMs
        #expect(deviceROMs.count == 2)  // 2 device ROMs (namco51, namco54)

        // Check specific device ROMs
        let has51xx = deviceROMs.contains { $0.rom.name == "51xx.bin" }
        let has54xx = deviceROMs.contains { $0.rom.name == "54xx.bin" }
        #expect(has51xx)
        #expect(has54xx)
    }

    // MARK: - Parent/Clone Tests

    @Test func testParentCloneRelationships() async throws {
        // Find clones
        let pacmanGame = datFile.games.first { ($0 as? MAMEGame)?.name == "pacman" } as? MAMEGame
        let pacmanMeta = pacmanGame?.metadata as? MAMEGameMetadata

        #expect(pacmanMeta?.cloneOf == "puckman")
        #expect(pacmanMeta?.romOf == "puckman")

        // Find parent
        let puckmanGame = datFile.games.first { ($0 as? MAMEGame)?.name == "puckman" } as? MAMEGame
        let puckmanMeta = puckmanGame?.metadata as? MAMEGameMetadata

        #expect(puckmanMeta?.cloneOf == nil)
        #expect(puckmanMeta?.romOf == nil)
    }

    @Test func testCloneROMInheritance() async throws {
        let pacmanGame = datFile.games.first { ($0 as? MAMEGame)?.name == "pacman" } as? MAMEGame

        // Check for merged ROMs
        let mergedROMs = pacmanGame?.items.compactMap { $0 as? MAMEROM }.filter { rom in
            rom.attributes.merge != nil
        }

        #expect(mergedROMs?.count == 2)  // Two graphics ROMs are merged from parent

        // Check specific merged ROM
        let mergedGfx = pacmanGame?.items.compactMap { $0 as? MAMEROM }.first { $0.name == "pm1_chg1.5e" }
        #expect(mergedGfx?.attributes.merge == "pm1_chg1.5e")
    }

    @Test func testStandaloneBootleg() async throws {
        // Bootleg has no parent/clone relationships
        let bootlegGame = datFile.games.first { ($0 as? MAMEGame)?.name == "pacmanbl" } as? MAMEGame
        let bootlegMeta = bootlegGame?.metadata as? MAMEGameMetadata

        #expect(bootlegMeta?.cloneOf == nil)
        #expect(bootlegMeta?.romOf == nil)

        // All ROMs are self-contained
        let mergedROMs = bootlegGame?.items.compactMap { $0 as? MAMEROM }.filter { rom in
            rom.attributes.merge != nil
        }
        #expect(mergedROMs?.isEmpty ?? true)
    }

    // MARK: - Complex Inheritance Tests

    @Test func testComplexInheritanceChain() async throws {
        // mslugx inherits from: neogeo (BIOS) + mslug (parent)
        let requiredROMs = biosManager.getAllRequiredROMs(for: "mslugx")

        let categories = Dictionary(grouping: requiredROMs, by: { $0.category })

        #expect(categories["BIOS"]?.count ?? 0 > 0)
        #expect(categories["Parent"]?.count ?? 0 > 0)
        #expect(categories["Game"]?.count ?? 0 > 0)

        // Verify specific inheritance
        let sources = Set(requiredROMs.map { $0.sourceSet })
        #expect(sources.contains("neogeo"))  // BIOS
        #expect(sources.contains("mslug"))   // Parent
        #expect(sources.contains("mslugx"))  // Self
    }

    @Test func testGalagaCloneFullInheritance() async throws {
        // galagao needs: galaga (parent) + namco51 + namco54 (devices)
        let requiredROMs = biosManager.getAllRequiredROMs(for: "galagao")

        let sources = Set(requiredROMs.map { $0.sourceSet })
        #expect(sources.contains("galaga"))   // Parent
        #expect(sources.contains("galagao"))  // Self
        #expect(sources.contains("namco51"))  // Device
        #expect(sources.contains("namco54"))  // Device

        // Count by category
        let byCategory = Dictionary(grouping: requiredROMs, by: { $0.category })
        #expect(byCategory["Parent"]?.count ?? 0 > 0)
        #expect(byCategory["Device"]?.count ?? 0 > 0)
        #expect(byCategory["Game"]?.count ?? 0 > 0)
    }

    // MARK: - Merge Mode Simulation Tests

    @Test func testNonMergedSetRequirements() async throws {
        // In non-merged mode, mslug.zip would contain:
        // - All mslug ROMs
        // - All neogeo BIOS ROMs
        // - All device ROMs

        let requiredROMs = biosManager.getAllRequiredROMs(for: "mslug")
        let totalCount = requiredROMs.count

        print("Non-merged mslug.zip would contain \(totalCount) ROM files")
        #expect(totalCount == 9)  // 4 game + 5 BIOS
    }

    @Test func testSplitSetRequirements() async throws {
        // In split mode:
        // - mslug.zip contains only mslug ROMs
        // - neogeo.zip is separate
        // - devices are separate

        let mslugGame = datFile.games.first { ($0 as? MAMEGame)?.name == "mslug" } as? MAMEGame
        let mslugOnlyCount = mslugGame?.items.count ?? 0

        print("Split mode mslug.zip contains \(mslugOnlyCount) ROM files")
        print("Also needs: neogeo.zip")

        #expect(mslugOnlyCount == 4)
    }

    @Test func testMergedSetRequirements() async throws {
        // In merged mode:
        // - puckman.zip contains puckman + pacman ROMs
        // - Shared ROMs are stored once

        let puckmanGame = datFile.games.first { ($0 as? MAMEGame)?.name == "puckman" } as? MAMEGame
        let pacmanGame = datFile.games.first { ($0 as? MAMEGame)?.name == "pacman" } as? MAMEGame

        let puckmanROMs = Set(puckmanGame?.items.map { $0.name } ?? [])
        let pacmanROMs = Set(pacmanGame?.items.map { $0.name } ?? [])

        let uniqueROMs = puckmanROMs.union(pacmanROMs)
        let sharedROMs = puckmanROMs.intersection(pacmanROMs)

        print("Merged puckman.zip would contain:")
        print("  - \(puckmanROMs.count) puckman ROMs")
        print("  - \(pacmanROMs.count) pacman ROMs")
        print("  - \(sharedROMs.count) shared ROMs (stored once)")
        print("  - Total unique: \(uniqueROMs.count) ROM files")

        #expect(sharedROMs.count == 2)  // Two graphics ROMs are shared
    }

    // MARK: - Validation Scenarios

    @Test func testMissingBIOSDetection() async throws {
        // Simulate scanning mslug without neogeo BIOS
        _ = datFile.games.first { ($0 as? MAMEGame)?.name == "mslug" } as? MAMEGame
        let requiredBIOS = biosManager.getRequiredBIOS(for: "mslug")

        #expect(requiredBIOS?.name == "neogeo")

        // In a real scan, if neogeo.zip is missing:
        let allRequired = biosManager.getAllRequiredROMs(for: "mslug")
        let missingBIOSROMs = allRequired.filter { $0.isFromBIOS }

        print("Without neogeo.zip, mslug is missing \(missingBIOSROMs.count) BIOS ROMs")
        #expect(!missingBIOSROMs.isEmpty)
    }

    @Test func testMissingDeviceDetection() async throws {
        // Simulate scanning galaga without device ROMs
        let allRequired = biosManager.getAllRequiredROMs(for: "galaga")
        let missingDeviceROMs = allRequired.filter { $0.isFromDevice }

        print("Without device ZIPs, galaga is missing \(missingDeviceROMs.count) device ROMs")
        #expect(missingDeviceROMs.count == 2)
    }
}
