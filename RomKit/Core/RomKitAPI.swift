//
//  RomKitAPI.swift
//  RomKit
//
//  Created by RomKit on 8/5/25.
//

import Foundation

// MARK: - Public API Types for DAT Access

/// Header information from a loaded DAT file
public struct DATHeader: Sendable {
    public let name: String
    public let description: String
    public let version: String
    public let author: String?
    public let homepage: String?
    public let url: String?
    public let date: String?
    public let comment: String?

    public init(
        name: String,
        description: String,
        version: String,
        author: String? = nil,
        homepage: String? = nil,
        url: String? = nil,
        date: String? = nil,
        comment: String? = nil
    ) {
        self.name = name
        self.description = description
        self.version = version
        self.author = author
        self.homepage = homepage
        self.url = url
        self.date = date
        self.comment = comment
    }
}

/// Represents a game/machine entry from the DAT file
public struct GameInfo: Sendable {
    public let name: String
    public let description: String?
    public let year: String?
    public let manufacturer: String?
    public let cloneOf: String?
    public let romOf: String?
    public let isBios: Bool
    public let isDevice: Bool
    public let roms: [ROMEntry]
    public let disks: [DiskInfo]

    public init(
        name: String,
        description: String? = nil,
        year: String? = nil,
        manufacturer: String? = nil,
        cloneOf: String? = nil,
        romOf: String? = nil,
        isBios: Bool = false,
        isDevice: Bool = false,
        roms: [ROMEntry] = [],
        disks: [DiskInfo] = []
    ) {
        self.name = name
        self.description = description
        self.year = year
        self.manufacturer = manufacturer
        self.cloneOf = cloneOf
        self.romOf = romOf
        self.isBios = isBios
        self.isDevice = isDevice
        self.roms = roms
        self.disks = disks
    }

    /// Returns true if this is a parent game (not a clone)
    public var isParent: Bool {
        return cloneOf == nil
    }

    /// Returns true if this is a clone of another game
    public var isClone: Bool {
        return cloneOf != nil
    }
}

/// Represents a ROM file entry from the DAT
public struct ROMEntry: Sendable {
    public let name: String
    public let size: Int
    public let crc: String
    public let md5: String?
    public let sha1: String?
    public let status: String
    public let merge: String?

    public init(
        name: String,
        size: Int,
        crc: String,
        md5: String? = nil,
        sha1: String? = nil,
        status: String = "good",
        merge: String? = nil
    ) {
        self.name = name
        self.size = size
        self.crc = crc
        self.md5 = md5
        self.sha1 = sha1
        self.status = status
        self.merge = merge
    }
}

/// Represents a disk (CHD) file entry from the DAT
public struct DiskInfo: Sendable {
    public let name: String
    public let sha1: String
    public let md5: String?
    public let status: String
    public let merge: String?

    public init(
        name: String,
        sha1: String,
        md5: String? = nil,
        status: String = "good",
        merge: String? = nil
    ) {
        self.name = name
        self.sha1 = sha1
        self.md5 = md5
        self.status = status
        self.merge = merge
    }
}

/// Supported DAT file formats
public enum DATFormatType: String, CaseIterable, Sendable {
    case logiqx = "logiqx"
    case mameXML = "mame"
    case noIntro = "nointro"
    case redump = "redump"
    case unknown = "unknown"

    public var displayName: String {
        switch self {
        case .logiqx: return "Logiqx XML"
        case .mameXML: return "MAME XML"
        case .noIntro: return "No-Intro"
        case .redump: return "Redump"
        case .unknown: return "Unknown"
        }
    }
}
