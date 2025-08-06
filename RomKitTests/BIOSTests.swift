//
//  BIOSTests.swift
//  RomKitTests
//
//  Created by Barry Walker on 8/5/25.
//

import Testing
import Foundation
@testable import RomKit

struct BIOSTests {
    
    let testDataPath = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .appendingPathComponent("TestData")
    
    @Test func testBIOSDetection() async throws {
        let datPath = testDataPath.appendingPathComponent("neogeo_sample.xml")
        let data = try Data(contentsOf: datPath)
        
        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: data)
        
        let biosManager = MAMEBIOSManager(datFile: datFile)
        
        // Check BIOS detection
        #expect(biosManager.isBIOS("neogeo") == true)
        #expect(biosManager.isBIOS("mslug") == false)
        #expect(biosManager.isBIOS("kof98") == false)
        
        // Check all BIOS sets
        let allBios = biosManager.allBIOSSets
        #expect(allBios.count == 1)
        #expect(allBios.first?.name == "neogeo")
    }
    
    @Test func testBIOSDependencies() async throws {
        let datPath = testDataPath.appendingPathComponent("neogeo_sample.xml")
        let data = try Data(contentsOf: datPath)
        
        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: data)
        
        let biosManager = MAMEBIOSManager(datFile: datFile)
        
        // Check dependencies for Metal Slug
        let mslugDeps = biosManager.getDependencies(for: "mslug")
        #expect(mslugDeps.contains("neogeo"))
        
        // Check dependencies for KOF98
        let kof98Deps = biosManager.getDependencies(for: "kof98")
        #expect(kof98Deps.contains("neogeo"))
        
        // Check which games depend on Neo Geo BIOS
        let neogeoDependent = biosManager.getDependents(of: "neogeo")
        #expect(neogeoDependent.contains("mslug"))
        #expect(neogeoDependent.contains("kof98"))
    }
    
    @Test func testRequiredROMs() async throws {
        let datPath = testDataPath.appendingPathComponent("neogeo_sample.xml")
        let data = try Data(contentsOf: datPath)
        
        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: data)
        
        let biosManager = MAMEBIOSManager(datFile: datFile)
        
        // Get all required ROMs for Metal Slug (should include BIOS ROMs)
        let requiredROMs = biosManager.getAllRequiredROMs(for: "mslug")
        
        // Should have game ROMs + BIOS ROMs
        let gameROMs = requiredROMs.filter { !$0.isFromBIOS }
        let biosROMs = requiredROMs.filter { $0.isFromBIOS }
        
        #expect(gameROMs.count > 0)
        #expect(biosROMs.count > 0)
        
        // Check specific BIOS ROMs are included
        let hasSFixBios = biosROMs.contains { $0.rom.name == "sfix.sfix" }
        let hasLoRom = biosROMs.contains { $0.rom.name == "000-lo.lo" }
        
        #expect(hasSFixBios)
        #expect(hasLoRom)
        
        print("Metal Slug requires \(gameROMs.count) game ROMs and \(biosROMs.count) BIOS ROMs")
    }
    
    @Test func testBIOSROMCategories() async throws {
        let datPath = testDataPath.appendingPathComponent("neogeo_sample.xml")
        let data = try Data(contentsOf: datPath)
        
        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: data)
        
        let biosManager = MAMEBIOSManager(datFile: datFile)
        
        // Get all required ROMs for Metal Slug
        let requiredROMs = biosManager.getAllRequiredROMs(for: "mslug")
        
        // Categorize ROMs
        var categories: [String: Int] = [:]
        for rom in requiredROMs {
            categories[rom.category, default: 0] += 1
        }
        
        print("ROM Categories for Metal Slug:")
        for (category, count) in categories {
            print("  \(category): \(count) ROMs")
        }
        
        #expect(categories["Game"] ?? 0 > 0)
        #expect(categories["BIOS"] ?? 0 > 0)
    }
    
    @Test func testScanningWithBIOS() async throws {
        // This test shows how scanning should handle BIOS dependencies
        let datPath = testDataPath.appendingPathComponent("neogeo_sample.xml")
        
        let romKit = RomKitGeneric()
        try romKit.loadDAT(from: datPath, format: "mame")
        
        #expect(romKit.isLoaded == true)
        
        // In a real scan, the scanner would:
        // 1. Check if mslug.zip exists
        // 2. Check if neogeo.zip exists (for BIOS)
        // 3. Report missing BIOS if not found
        // 4. Validate ROMs from both sets
        
        if let datFile = romKit.currentDATFile as? MAMEDATFile {
            let biosManager = MAMEBIOSManager(datFile: datFile)
            
            // Verify the BIOS requirement is detected
            let mslugBios = biosManager.getRequiredBIOS(for: "mslug")
            #expect(mslugBios?.name == "neogeo")
            
            // Count total required files
            let allRequired = biosManager.getAllRequiredROMs(for: "mslug")
            print("To run Metal Slug, you need \(allRequired.count) total ROM files")
        }
    }
}