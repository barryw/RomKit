//
//  LegacyTypes.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation

// MARK: - Legacy Types for Backward Compatibility

public struct DATFile {
    public let name: String
    public let description: String
    public let version: String?
    public let author: String?
    public let games: [Game]

    public init(name: String, description: String, version: String? = nil, author: String? = nil, games: [Game]) {
        self.name = name
        self.description = description
        self.version = version
        self.author = author
        self.games = games
    }
}

public struct Game {
    public let name: String
    public let description: String
    public let cloneOf: String?
    public let romOf: String?
    public let sampleOf: String?
    public let year: String?
    public let manufacturer: String?
    public let roms: [ROM]
    public let disks: [Disk]

    public init(
        name: String,
        description: String,
        cloneOf: String? = nil,
        romOf: String? = nil,
        sampleOf: String? = nil,
        year: String? = nil,
        manufacturer: String? = nil,
        roms: [ROM] = [],
        disks: [Disk] = []
    ) {
        self.name = name
        self.description = description
        self.cloneOf = cloneOf
        self.romOf = romOf
        self.sampleOf = sampleOf
        self.year = year
        self.manufacturer = manufacturer
        self.roms = roms
        self.disks = disks
    }

    public var isClone: Bool {
        return cloneOf != nil
    }

    public var isParent: Bool {
        return cloneOf == nil
    }
}

public struct ROM {
    public let name: String
    public let size: UInt64
    public let crc: String?
    public let sha1: String?
    public let md5: String?
    public let status: ROMStatus
    public let merge: String?

    public init(
        name: String,
        size: UInt64,
        crc: String? = nil,
        sha1: String? = nil,
        md5: String? = nil,
        status: ROMStatus = .good,
        merge: String? = nil
    ) {
        self.name = name
        self.size = size
        self.crc = crc
        self.sha1 = sha1
        self.md5 = md5
        self.status = status
        self.merge = merge
    }
}

public struct Disk {
    public let name: String
    public let sha1: String?
    public let md5: String?
    public let status: ROMStatus
    public let merge: String?

    public init(
        name: String,
        sha1: String? = nil,
        md5: String? = nil,
        status: ROMStatus = .good,
        merge: String? = nil
    ) {
        self.name = name
        self.sha1 = sha1
        self.md5 = md5
        self.status = status
        self.merge = merge
    }
}

// Already defined in protocols, using that one
// public enum ROMStatus: String {
//     case good = "good"
//     case baddump = "baddump"
//     case nodump = "nodump"
//     case verified = "verified"
// }

// MARK: - Legacy Scan Types

public struct ScanResult {
    public let scannedPath: String
    public let foundGames: [ScannedGame]
    public let unknownFiles: [String]
    public let scanDate: Date

    public init(scannedPath: String, foundGames: [ScannedGame], unknownFiles: [String], scanDate: Date = Date()) {
        self.scannedPath = scannedPath
        self.foundGames = foundGames
        self.unknownFiles = unknownFiles
        self.scanDate = scanDate
    }
}

public struct ScannedGame {
    public let game: Game
    public let foundRoms: [ScannedROM]
    public let missingRoms: [ROM]
    public let status: GameStatus

    public init(game: Game, foundRoms: [ScannedROM], missingRoms: [ROM]) {
        self.game = game
        self.foundRoms = foundRoms
        self.missingRoms = missingRoms

        if missingRoms.isEmpty && !foundRoms.isEmpty {
            let hasAllGood = foundRoms.allSatisfy { $0.status == .good }
            self.status = hasAllGood ? .complete : .incomplete
        } else if foundRoms.isEmpty {
            self.status = .missing
        } else {
            self.status = .incomplete
        }
    }
}

public struct ScannedROM {
    public let rom: ROM
    public let filePath: String
    public let hash: FileHash?
    public let status: ROMValidationStatus

    public init(rom: ROM, filePath: String, hash: FileHash?, status: ROMValidationStatus) {
        self.rom = rom
        self.filePath = filePath
        self.hash = hash
        self.status = status
    }
}

public enum GameStatus {
    case complete
    case incomplete
    case missing
}

public enum ROMValidationStatus {
    case good
    case bad
    case unknown
}

public struct FileHash {
    public let crc32: String
    public let sha1: String
    public let md5: String
    public let size: UInt64

    public init(crc32: String, sha1: String, md5: String, size: UInt64) {
        self.crc32 = crc32
        self.sha1 = sha1
        self.md5 = md5
        self.size = size
    }

    public func matches(rom: ROM) -> Bool {
        if let romCRC = rom.crc, romCRC.lowercased() != crc32.lowercased() {
            return false
        }
        if let romSHA1 = rom.sha1, romSHA1.lowercased() != sha1.lowercased() {
            return false
        }
        if let romMD5 = rom.md5, romMD5.lowercased() != md5.lowercased() {
            return false
        }
        return rom.size == size
    }
}

// MARK: - Legacy Audit Types

public struct AuditReport: Codable {
    public let scanDate: Date
    public let scannedPath: String
    public let totalGames: Int
    public let completeGames: [String]
    public let incompleteGames: [IncompleteGame]
    public let missingGames: [String]
    public let badRoms: [BadROM]
    public let unknownFiles: [String]
    public let statistics: AuditStatistics

    public init(
        scanDate: Date,
        scannedPath: String,
        totalGames: Int,
        completeGames: [String],
        incompleteGames: [IncompleteGame],
        missingGames: [String],
        badRoms: [BadROM],
        unknownFiles: [String],
        statistics: AuditStatistics
    ) {
        self.scanDate = scanDate
        self.scannedPath = scannedPath
        self.totalGames = totalGames
        self.completeGames = completeGames
        self.incompleteGames = incompleteGames
        self.missingGames = missingGames
        self.badRoms = badRoms
        self.unknownFiles = unknownFiles
        self.statistics = statistics
    }
}

public struct IncompleteGame: Codable {
    public let gameName: String
    public let missingRoms: [String]
    public let badRoms: [String]

    public init(gameName: String, missingRoms: [String], badRoms: [String]) {
        self.gameName = gameName
        self.missingRoms = missingRoms
        self.badRoms = badRoms
    }
}

public struct BadROM: Codable {
    public let gameName: String
    public let romName: String
    public let expectedCRC: String?
    public let actualCRC: String?
    public let expectedSize: UInt64
    public let actualSize: UInt64

    public init(
        gameName: String,
        romName: String,
        expectedCRC: String?,
        actualCRC: String?,
        expectedSize: UInt64,
        actualSize: UInt64
    ) {
        self.gameName = gameName
        self.romName = romName
        self.expectedCRC = expectedCRC
        self.actualCRC = actualCRC
        self.expectedSize = expectedSize
        self.actualSize = actualSize
    }
}

public struct AuditStatistics: Codable {
    public let totalGames: Int
    public let completeGames: Int
    public let incompleteGames: Int
    public let missingGames: Int
    public let totalRoms: Int
    public let goodRoms: Int
    public let badRoms: Int
    public let missingRoms: Int
    public let completionPercentage: Double

    public init(
        totalGames: Int,
        completeGames: Int,
        incompleteGames: Int,
        missingGames: Int,
        totalRoms: Int,
        goodRoms: Int,
        badRoms: Int,
        missingRoms: Int
    ) {
        self.totalGames = totalGames
        self.completeGames = completeGames
        self.incompleteGames = incompleteGames
        self.missingGames = missingGames
        self.totalRoms = totalRoms
        self.goodRoms = goodRoms
        self.badRoms = badRoms
        self.missingRoms = missingRoms
        self.completionPercentage = totalGames > 0 ? (Double(completeGames) / Double(totalGames)) * 100.0 : 0.0
    }
}
