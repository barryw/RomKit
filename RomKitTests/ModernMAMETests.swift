//
//  ModernMAMETests.swift
//  RomKitTests
//
//  Created by Barry Walker on 8/5/25.
//

import Testing
import Foundation
@testable import RomKit

struct ModernMAMETests {
    
    let testDataPath = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .appendingPathComponent("TestData")
    
    @Test func testModernMAMEFormat() async throws {
        let datPath = testDataPath.appendingPathComponent("modern_mame_sample.xml")
        let data = try Data(contentsOf: datPath)
        
        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: data)
        
        #expect(datFile.games.count == 1)
        
        guard let game = datFile.games.first as? MAMEGame else {
            Issue.record("Failed to get first game")
            return
        }
        
        #expect(game.name == "005")
        #expect(game.description == "005")
        
        guard let metadata = game.metadata as? MAMEGameMetadata else {
            Issue.record("Failed to get metadata")
            return
        }
        
        #expect(metadata.year == "1981")
        #expect(metadata.manufacturer == "Sega")
        #expect(metadata.sourceFile == "sega/segag80r.cpp")
    }
    
    @Test func testDeviceRefs() async throws {
        let datPath = testDataPath.appendingPathComponent("modern_mame_sample.xml")
        let data = try Data(contentsOf: datPath)
        
        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: data)
        
        guard let game = datFile.games.first as? MAMEGame,
              let metadata = game.metadata as? MAMEGameMetadata else {
            Issue.record("Failed to get game metadata")
            return
        }
        
        // Check device references
        #expect(metadata.deviceRefs.contains("z80"))
        #expect(metadata.deviceRefs.contains("gfxdecode"))
        #expect(metadata.deviceRefs.contains("palette"))
        #expect(metadata.deviceRefs.contains("screen"))
        #expect(metadata.deviceRefs.contains("speaker"))
        #expect(metadata.deviceRefs.contains("i8255"))
        #expect(metadata.deviceRefs.contains("samples"))
        #expect(metadata.deviceRefs.contains("sega005_sound"))
        #expect(metadata.deviceRefs.count == 8)
    }
    
    @Test func testChips() async throws {
        let datPath = testDataPath.appendingPathComponent("modern_mame_sample.xml")
        let data = try Data(contentsOf: datPath)
        
        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: data)
        
        guard let game = datFile.games.first as? MAMEGame,
              let metadata = game.metadata as? MAMEGameMetadata else {
            Issue.record("Failed to get game metadata")
            return
        }
        
        #expect(metadata.chips.count == 4)
        
        // Check CPU chip
        let cpuChip = metadata.chips.first { $0.type == "cpu" }
        #expect(cpuChip != nil)
        #expect(cpuChip?.name == "Zilog Z80")
        #expect(cpuChip?.tag == "maincpu")
        #expect(cpuChip?.clock == 3867120)
        
        // Check audio chips
        let audioChips = metadata.chips.filter { $0.type == "audio" }
        #expect(audioChips.count == 3)
    }
    
    @Test func testDisplay() async throws {
        let datPath = testDataPath.appendingPathComponent("modern_mame_sample.xml")
        let data = try Data(contentsOf: datPath)
        
        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: data)
        
        guard let game = datFile.games.first as? MAMEGame,
              let metadata = game.metadata as? MAMEGameMetadata,
              let display = metadata.display else {
            Issue.record("Failed to get display info")
            return
        }
        
        #expect(display.type == "raster")
        #expect(display.rotate == 270)
        #expect(display.width == 256)
        #expect(display.height == 224)
        #expect(display.refresh == 60.0)
        #expect(display.pixelClock == 5156160)
        #expect(display.hTotal == 328)
        #expect(display.vTotal == 262)
    }
    
    @Test func testSound() async throws {
        let datPath = testDataPath.appendingPathComponent("modern_mame_sample.xml")
        let data = try Data(contentsOf: datPath)
        
        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: data)
        
        guard let game = datFile.games.first as? MAMEGame,
              let metadata = game.metadata as? MAMEGameMetadata,
              let sound = metadata.sound else {
            Issue.record("Failed to get sound info")
            return
        }
        
        #expect(sound.channels == 1)
    }
    
    @Test func testInput() async throws {
        let datPath = testDataPath.appendingPathComponent("modern_mame_sample.xml")
        let data = try Data(contentsOf: datPath)
        
        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: data)
        
        guard let game = datFile.games.first as? MAMEGame,
              let metadata = game.metadata as? MAMEGameMetadata,
              let input = metadata.input else {
            Issue.record("Failed to get input info")
            return
        }
        
        #expect(input.players == 2)
        #expect(input.coins == 2)
        #expect(input.service == true)
        #expect(input.controls.count == 2)
        
        // Check player 1 control
        let p1Control = input.controls.first { $0.player == 1 }
        #expect(p1Control != nil)
        #expect(p1Control?.type == "joy")
        #expect(p1Control?.buttons == 1)
        #expect(p1Control?.ways == 4)
    }
    
    @Test func testDipSwitches() async throws {
        let datPath = testDataPath.appendingPathComponent("modern_mame_sample.xml")
        let data = try Data(contentsOf: datPath)
        
        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: data)
        
        guard let game = datFile.games.first as? MAMEGame,
              let metadata = game.metadata as? MAMEGameMetadata else {
            Issue.record("Failed to get game metadata")
            return
        }
        
        #expect(metadata.dipswitches.count == 2)
        
        // Check Coin A dipswitch
        let coinDip = metadata.dipswitches.first { $0.name == "Coin A" }
        #expect(coinDip != nil)
        #expect(coinDip?.tag == "D1D0")
        #expect(coinDip?.mask == 15)
        #expect(coinDip?.locations.count == 2)
        #expect(coinDip?.values.count == 3)
        
        // Check default value
        let defaultValue = coinDip?.values.first { $0.isDefault }
        #expect(defaultValue?.name == "1 Coin/1 Credit")
        #expect(defaultValue?.value == 3)
    }
    
    @Test func testDriver() async throws {
        let datPath = testDataPath.appendingPathComponent("modern_mame_sample.xml")
        let data = try Data(contentsOf: datPath)
        
        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: data)
        
        guard let game = datFile.games.first as? MAMEGame,
              let metadata = game.metadata as? MAMEGameMetadata,
              let driver = metadata.driver else {
            Issue.record("Failed to get driver info")
            return
        }
        
        #expect(driver.status == "imperfect")
        #expect(driver.emulation == "good")
        #expect(driver.savestate == "unsupported")
    }
    
    @Test func testFeatures() async throws {
        let datPath = testDataPath.appendingPathComponent("modern_mame_sample.xml")
        let data = try Data(contentsOf: datPath)
        
        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: data)
        
        guard let game = datFile.games.first as? MAMEGame,
              let metadata = game.metadata as? MAMEGameMetadata else {
            Issue.record("Failed to get game metadata")
            return
        }
        
        #expect(metadata.features.count == 1)
        
        let soundFeature = metadata.features.first { $0.type == "sound" }
        #expect(soundFeature != nil)
        #expect(soundFeature?.status == "imperfect")
    }
    
    @Test func testSamples() async throws {
        let datPath = testDataPath.appendingPathComponent("modern_mame_sample.xml")
        let data = try Data(contentsOf: datPath)
        
        let parser = MAMEDATParser()
        let datFile = try parser.parse(data: data)
        
        guard let game = datFile.games.first as? MAMEGame else {
            Issue.record("Failed to get game")
            return
        }
        
        #expect(game.samples.count == 4)
        #expect(game.samples.contains { $0.name == "lexplode" })
        #expect(game.samples.contains { $0.name == "shoot" })
    }
}