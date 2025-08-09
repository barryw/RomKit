//
//  MAMEModels.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation

// MARK: - MAME DAT Format Implementation

public struct MAMEDATFile: DATFormat, Sendable {
    public let formatName = "MAME"
    public let formatVersion: String?
    public let games: [any GameEntry]
    public let metadata: any DATMetadata

    public init(formatVersion: String? = nil, games: [MAMEGame], metadata: MAMEMetadata) {
        self.formatVersion = formatVersion
        self.games = games
        self.metadata = metadata
    }
}

public struct MAMEMetadata: DATMetadata, Codable, Sendable {
    public let name: String
    public let description: String
    public let version: String?
    public let author: String?
    public let date: String?
    public let comment: String?
    public let url: String?
    public let build: String?

    public init(
        name: String,
        description: String,
        version: String? = nil,
        author: String? = nil,
        date: String? = nil,
        comment: String? = nil,
        url: String? = nil,
        build: String? = nil
    ) {
        self.name = name
        self.description = description
        self.version = version
        self.author = author
        self.date = date
        self.comment = comment
        self.url = url
        self.build = build
    }
}

public struct MAMEGame: GameEntry, Sendable {
    public let identifier: String
    public let name: String
    public let description: String
    public let items: [any ROMItem]
    public let metadata: any GameMetadata
    public let disks: [MAMEDisk]
    public let samples: [MAMESample]

    public init(
        name: String,
        description: String,
        roms: [MAMEROM] = [],
        disks: [MAMEDisk] = [],
        samples: [MAMESample] = [],
        metadata: MAMEGameMetadata
    ) {
        self.identifier = name
        self.name = name
        self.description = description
        self.items = roms
        self.disks = disks
        self.samples = samples
        self.metadata = metadata
    }
}

public struct MAMEGameMetadata: GameMetadata, Codable, Sendable {
    public let year: String?
    public let manufacturer: String?
    public let category: String?
    public let cloneOf: String?
    public let romOf: String?
    public let sampleOf: String?
    public let sourceFile: String?
    public let isBios: Bool
    public let isDevice: Bool
    public let isMechanical: Bool
    public let runnable: Bool
    public let biosSet: String?  // BIOS this game uses (e.g., "neogeo")
    public let deviceRefs: [String]  // Device ROMs needed (e.g., ["ym2608"])

    // New elements from modern MAME format
    public let chips: [MAMEChip]
    public let display: MAMEDisplay?
    public let sound: MAMESound?
    public let input: MAMEInput?
    public let dipswitches: [MAMEDipSwitch]
    public let driver: MAMEDriver?
    public let features: [MAMEFeature]

    public init(
        year: String? = nil,
        manufacturer: String? = nil,
        category: String? = nil,
        cloneOf: String? = nil,
        romOf: String? = nil,
        sampleOf: String? = nil,
        sourceFile: String? = nil,
        isBios: Bool = false,
        isDevice: Bool = false,
        isMechanical: Bool = false,
        runnable: Bool = true,
        biosSet: String? = nil,
        deviceRefs: [String] = [],
        chips: [MAMEChip] = [],
        display: MAMEDisplay? = nil,
        sound: MAMESound? = nil,
        input: MAMEInput? = nil,
        dipswitches: [MAMEDipSwitch] = [],
        driver: MAMEDriver? = nil,
        features: [MAMEFeature] = []
    ) {
        self.year = year
        self.manufacturer = manufacturer
        self.category = category
        self.cloneOf = cloneOf
        self.romOf = romOf
        self.sampleOf = sampleOf
        self.sourceFile = sourceFile
        self.isBios = isBios
        self.isDevice = isDevice
        self.isMechanical = isMechanical
        self.runnable = runnable
        self.biosSet = biosSet
        self.deviceRefs = deviceRefs
        self.chips = chips
        self.display = display
        self.sound = sound
        self.input = input
        self.dipswitches = dipswitches
        self.driver = driver
        self.features = features
    }
}

public struct MAMEROM: ROMItem, Codable, Sendable {
    public let name: String
    public let size: UInt64
    public let checksums: ROMChecksums
    public let status: ROMStatus
    public let attributes: ROMAttributes
    public let region: String?
    public let offset: String?

    public init(
        name: String,
        size: UInt64,
        checksums: ROMChecksums,
        status: ROMStatus = .good,
        attributes: ROMAttributes = ROMAttributes(),
        region: String? = nil,
        offset: String? = nil
    ) {
        self.name = name
        self.size = size
        self.checksums = checksums
        self.status = status
        self.attributes = attributes
        self.region = region
        self.offset = offset
    }
}

public struct MAMEDisk: ROMItem, Codable, Sendable {
    public let name: String
    public let size: UInt64
    public let checksums: ROMChecksums
    public let status: ROMStatus
    public let attributes: ROMAttributes
    public let index: Int?

    public init(
        name: String,
        checksums: ROMChecksums,
        status: ROMStatus = .good,
        attributes: ROMAttributes = ROMAttributes(),
        index: Int? = nil
    ) {
        self.name = name
        self.size = 0 // CHD size is typically not stored in DAT
        self.checksums = checksums
        self.status = status
        self.attributes = attributes
        self.index = index
    }
}

public struct MAMESample: Codable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

// MARK: - Additional MAME Elements

public struct MAMEChip: Codable, Sendable {
    public let type: String
    public let tag: String
    public let name: String
    public let clock: Int?

    public init(type: String, tag: String, name: String, clock: Int? = nil) {
        self.type = type
        self.tag = tag
        self.name = name
        self.clock = clock
    }
}

public struct MAMEDisplay: Codable, Sendable {
    public let tag: String
    public let type: String
    public let rotate: Int
    public let width: Int
    public let height: Int
    public let refresh: Double
    public let pixelClock: Int?
    public let hTotal: Int?
    public let hbEnd: Int?
    public let hbStart: Int?
    public let vTotal: Int?
    public let vbEnd: Int?
    public let vbStart: Int?

    public init(tag: String, type: String, rotate: Int, width: Int, height: Int,
                refresh: Double, pixelClock: Int? = nil, hTotal: Int? = nil,
                hbEnd: Int? = nil, hbStart: Int? = nil, vTotal: Int? = nil,
                vbEnd: Int? = nil, vbStart: Int? = nil) {
        self.tag = tag
        self.type = type
        self.rotate = rotate
        self.width = width
        self.height = height
        self.refresh = refresh
        self.pixelClock = pixelClock
        self.hTotal = hTotal
        self.hbEnd = hbEnd
        self.hbStart = hbStart
        self.vTotal = vTotal
        self.vbEnd = vbEnd
        self.vbStart = vbStart
    }
}

public struct MAMESound: Codable, Sendable {
    public let channels: Int

    public init(channels: Int) {
        self.channels = channels
    }
}

public struct MAMEInput: Codable, Sendable {
    public let players: Int
    public let coins: Int?
    public let service: Bool
    public let controls: [MAMEControl]

    public init(players: Int, coins: Int? = nil, service: Bool = false, controls: [MAMEControl] = []) {
        self.players = players
        self.coins = coins
        self.service = service
        self.controls = controls
    }
}

public struct MAMEControl: Codable, Sendable {
    public let type: String
    public let player: Int?
    public let buttons: Int?
    public let ways: Int?

    public init(type: String, player: Int? = nil, buttons: Int? = nil, ways: Int? = nil) {
        self.type = type
        self.player = player
        self.buttons = buttons
        self.ways = ways
    }
}

public struct MAMEDipSwitch: Codable, Sendable {
    public let name: String
    public let tag: String
    public let mask: Int
    public let locations: [MAMEDipLocation]
    public let values: [MAMEDipValue]

    public init(name: String, tag: String, mask: Int, locations: [MAMEDipLocation] = [], values: [MAMEDipValue] = []) {
        self.name = name
        self.tag = tag
        self.mask = mask
        self.locations = locations
        self.values = values
    }
}

public struct MAMEDipLocation: Codable, Sendable {
    public let name: String
    public let number: String

    public init(name: String, number: String) {
        self.name = name
        self.number = number
    }
}

public struct MAMEDipValue: Codable, Sendable {
    public let name: String
    public let value: Int
    public let isDefault: Bool

    public init(name: String, value: Int, isDefault: Bool = false) {
        self.name = name
        self.value = value
        self.isDefault = isDefault
    }
}

public struct MAMEDriver: Codable, Sendable {
    public let status: String
    public let emulation: String
    public let savestate: String

    public init(status: String, emulation: String, savestate: String) {
        self.status = status
        self.emulation = emulation
        self.savestate = savestate
    }
}

public struct MAMEFeature: Codable, Sendable {
    public let type: String
    public let status: String

    public init(type: String, status: String) {
        self.type = type
        self.status = status
    }
}
