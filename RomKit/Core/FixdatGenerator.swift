//
//  FixdatGenerator.swift
//  RomKit
//
//  Generate Fixdat files for missing ROMs in correct Logiqx XML format
//

import Foundation

/// Generates Fixdat files for missing ROMs
public class FixdatGenerator {

    /// Generate a Fixdat from scan results
    public static func generateFixdat(
        from scanResult: ScanResult,
        originalDAT: any DATFormat,
        metadata: FixdatMetadata? = nil
    ) -> FixdatFile {

        var gamesNeeded: [Game] = []

        // Process games with missing ROMs from scan results
        for scannedGame in scanResult.foundGames where !scannedGame.missingRoms.isEmpty {
                // Create a game entry with only the missing ROMs
                let fixGame = Game(
                    name: scannedGame.game.name,
                    description: scannedGame.game.description,
                    cloneOf: scannedGame.game.cloneOf,
                    romOf: scannedGame.game.romOf,
                    year: scannedGame.game.year,
                    manufacturer: scannedGame.game.manufacturer,
                    roms: scannedGame.missingRoms
                )
                gamesNeeded.append(fixGame)
        }

        let fixMetadata = metadata ?? FixdatMetadata(
            name: "Fix for \(originalDAT.metadata.name)",
            description: "Missing ROMs from \(originalDAT.metadata.description)",
            version: originalDAT.metadata.version ?? "1.0",
            author: "RomKit",
            date: ISO8601DateFormatter().string(from: Date())
        )

        return FixdatFile(
            games: gamesNeeded.map { LegacyGameAdapter(game: $0) },
            metadata: fixMetadata
        )
    }

    /// Generate Logiqx XML format Fixdat
    public static func generateLogiqxXML(from fixdat: FixdatFile) -> String {
        var xml = generateXMLHeader()
        xml += generateXMLMetadata(fixdat.metadata)

        for game in fixdat.games {
            xml += generateXMLGame(game)
        }

        xml += "</datafile>\n"
        return xml
    }

    private static func generateXMLHeader() -> String {
        return """
<?xml version="1.0"?>
<!DOCTYPE datafile PUBLIC "-//Logiqx//DTD ROM Management Datafile//EN" "http://www.logiqx.com/Dats/datafile.dtd">
<datafile>
"""
    }

    private static func generateXMLMetadata(_ metadata: FixdatMetadata) -> String {
        var xml = "\t<header>\n"
        xml += "\t\t<name>\(escapeXML(metadata.name))</name>\n"
        xml += "\t\t<description>\(escapeXML(metadata.description))</description>\n"
        xml += "\t\t<version>\(escapeXML(metadata.version))</version>\n"
        xml += "\t\t<author>\(escapeXML(metadata.author))</author>\n"
        xml += "\t\t<date>\(escapeXML(metadata.date))</date>\n"
        if let comment = metadata.comment {
            xml += "\t\t<comment>\(escapeXML(comment))</comment>\n"
        }
        xml += "\t</header>\n"
        return xml
    }

    private static func generateXMLGame(_ game: any GameEntry) -> String {
        var xml = "\t<game name=\"\(escapeXML(game.name))\">\n"
        xml += "\t\t<description>\(escapeXML(game.description))</description>\n"

        // Add MAME-specific metadata
        xml += generateXMLMAMEMetadata(game)

        // Add ROMs
        for item in game.items {
            xml += generateXMLROM(item)
        }

        // Add disks if MAME game
        if let mameGame = game as? MAMEGame {
            for disk in mameGame.disks {
                xml += generateXMLDisk(disk)
            }
        }

        xml += "\t</game>\n"
        return xml
    }

    private static func generateXMLMAMEMetadata(_ game: any GameEntry) -> String {
        var xml = ""
        if let mameGame = game as? MAMEGame,
           let mameMetadata = mameGame.metadata as? MAMEGameMetadata {
            if let cloneOf = mameMetadata.cloneOf {
                xml += "\t\t<cloneof>\(escapeXML(cloneOf))</cloneof>\n"
            }
            if let romOf = mameMetadata.romOf {
                xml += "\t\t<romof>\(escapeXML(romOf))</romof>\n"
            }
            if let sampleOf = mameMetadata.sampleOf {
                xml += "\t\t<sampleof>\(escapeXML(sampleOf))</sampleof>\n"
            }
        }
        return xml
    }

    private static func generateXMLROM(_ item: any ROMItem) -> String {
        var xml = "\t\t<rom"
        xml += " name=\"\(escapeXML(item.name))\""
        xml += " size=\"\(item.size)\""

        if let crc = item.checksums.crc32 {
            xml += " crc=\"\(crc.lowercased())\""
        }
        if let sha1 = item.checksums.sha1 {
            xml += " sha1=\"\(sha1.lowercased())\""
        }
        if let md5 = item.checksums.md5 {
            xml += " md5=\"\(md5.lowercased())\""
        }
        if let merge = item.attributes.merge {
            xml += " merge=\"\(escapeXML(merge))\""
        }

        xml += "/>\n"
        return xml
    }

    private static func generateXMLDisk(_ disk: MAMEDisk) -> String {
        var xml = "\t\t<disk"
        xml += " name=\"\(escapeXML(disk.name))\""
        if let sha1 = disk.checksums.sha1 {
            xml += " sha1=\"\(sha1.lowercased())\""
        }
        if let md5 = disk.checksums.md5 {
            xml += " md5=\"\(md5.lowercased())\""
        }
        if let merge = disk.attributes.merge {
            xml += " merge=\"\(escapeXML(merge))\""
        }
        xml += "/>\n"
        return xml
    }

    /// Generate ClrMamePro format Fixdat
    public static func generateClrMameProDAT(from fixdat: FixdatFile) -> String {
        var dat = generateCMPHeader(fixdat.metadata)

        for game in fixdat.games {
            dat += generateCMPGame(game)
        }

        return dat
    }

    private static func generateCMPHeader(_ metadata: FixdatMetadata) -> String {
        var dat = "clrmamepro (\n"
        dat += "\tname \"\(metadata.name)\"\n"
        dat += "\tdescription \"\(metadata.description)\"\n"
        dat += "\tversion \"\(metadata.version)\"\n"
        dat += "\tauthor \"\(metadata.author)\"\n"
        dat += "\tdate \"\(metadata.date)\"\n"
        if let comment = metadata.comment {
            dat += "\tcomment \"\(comment)\"\n"
        }
        dat += ")\n\n"
        return dat
    }

    private static func generateCMPGame(_ game: any GameEntry) -> String {
        var dat = "game (\n"
        dat += "\tname \"\(game.name)\"\n"
        dat += "\tdescription \"\(game.description)\"\n"

        // Add MAME metadata
        dat += generateCMPMAMEMetadata(game)

        // Add ROMs
        for item in game.items {
            dat += generateCMPROM(item)
        }

        // Add disks if MAME game
        if let mameGame = game as? MAMEGame {
            for disk in mameGame.disks {
                dat += generateCMPDisk(disk)
            }
        }

        dat += ")\n\n"
        return dat
    }

    private static func generateCMPMAMEMetadata(_ game: any GameEntry) -> String {
        var dat = ""
        if let mameGame = game as? MAMEGame,
           let mameMetadata = mameGame.metadata as? MAMEGameMetadata {
            if let cloneOf = mameMetadata.cloneOf {
                dat += "\tcloneof \"\(cloneOf)\"\n"
            }
            if let romOf = mameMetadata.romOf {
                dat += "\tromof \"\(romOf)\"\n"
            }
        }
        return dat
    }

    private static func generateCMPROM(_ item: any ROMItem) -> String {
        var dat = "\trom ( "
        dat += "name \"\(item.name)\" "
        dat += "size \(item.size) "

        if let crc = item.checksums.crc32 {
            dat += "crc \(crc.lowercased()) "
        }
        if let sha1 = item.checksums.sha1 {
            dat += "sha1 \(sha1.lowercased()) "
        }
        if let md5 = item.checksums.md5 {
            dat += "md5 \(md5.lowercased()) "
        }
        if let merge = item.attributes.merge {
            dat += "merge \"\(merge)\" "
        }

        dat += ")\n"
        return dat
    }

    private static func generateCMPDisk(_ disk: MAMEDisk) -> String {
        var dat = "\tdisk ( "
        dat += "name \"\(disk.name)\" "

        if let sha1 = disk.checksums.sha1 {
            dat += "sha1 \(sha1.lowercased()) "
        }
        if let md5 = disk.checksums.md5 {
            dat += "md5 \(md5.lowercased()) "
        }
        if let merge = disk.attributes.merge {
            dat += "merge \"\(merge)\" "
        }

        dat += ")\n"
        return dat
    }

    private static func escapeXML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

/// Metadata for a Fixdat file
public struct FixdatMetadata {
    public let name: String
    public let description: String
    public let version: String
    public let author: String
    public let date: String
    public let comment: String?

    public init(
        name: String,
        description: String,
        version: String = "1.0",
        author: String = "RomKit",
        date: String? = nil,
        comment: String? = nil
    ) {
        self.name = name
        self.description = description
        self.version = version
        self.author = author
        self.date = date ?? ISO8601DateFormatter().string(from: Date())
        self.comment = comment
    }
}

/// A Fixdat file containing games with missing ROMs
public struct FixdatFile {
    public let games: [any GameEntry]
    public let metadata: FixdatMetadata

    /// Save the Fixdat to a file
    public func save(to path: String, format: FixdatFormat = .logiqxXML) throws {
        let content: String
        switch format {
        case .logiqxXML:
            content = FixdatGenerator.generateLogiqxXML(from: self)
        case .clrmamepro:
            content = FixdatGenerator.generateClrMameProDAT(from: self)
        }

        let url = URL(fileURLWithPath: path)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Supported Fixdat formats
public enum FixdatFormat {
    case logiqxXML
    case clrmamepro
}
