//
//  LegacyAdapters.swift
//  RomKit
//
//  Legacy type adapters for new ROM collector features
//

import Foundation

// MARK: - Legacy Adapters

struct LegacyGameAdapter: GameEntry {
    let game: Game

    var identifier: String { game.name }
    var name: String { game.name }
    var description: String { game.description }
    var items: [any ROMItem] {
        game.roms.map { LegacyROMAdapter(rom: $0) }
    }
    var metadata: GameMetadata {
        LegacyGameMetadataAdapter(
            year: game.year,
            manufacturer: game.manufacturer,
            category: nil,
            cloneOf: game.cloneOf,
            romOf: game.romOf,
            sampleOf: game.sampleOf,
            sourceFile: nil
        )
    }
}

struct LegacyROMAdapter: ROMItem {
    let rom: ROM

    var name: String { rom.name }
    var size: UInt64 { rom.size }
    var checksums: ROMChecksums {
        ROMChecksums(
            crc32: rom.crc,
            sha1: rom.sha1,
            md5: rom.md5
        )
    }
    var status: ROMStatus { rom.status }
    var attributes: ROMAttributes {
        ROMAttributes(merge: rom.merge)
    }
}

struct LegacyGameMetadataAdapter: GameMetadata {
    let year: String?
    let manufacturer: String?
    let category: String?
    let cloneOf: String?
    let romOf: String?
    let sampleOf: String?
    let sourceFile: String?
}
