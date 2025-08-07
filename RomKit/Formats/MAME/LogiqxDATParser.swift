//
//  LogiqxDATParser.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation

/// Parser for Logiqx-format DAT files (smaller, ROM-focused)
public class LogiqxDATParser: BaseXMLParser, DATParser {
    public typealias DATType = MAMEDATFile

    private var games: [MAMEGame] = []
    private var currentGame: MAMEGame?
    private var currentRoms: [MAMEROM] = []
    private var currentElement: String = ""
    private var currentElementText: String = ""
    private var metadata: MAMEMetadata?
    private var inHeader: Bool = false
    private var headerData: [String: String] = [:]
    private var currentGameData: [String: String] = [:]
    private var currentDeviceRefs: [String] = []

    public func canParse(data: Data) -> Bool {
        // Use base class utility to check format
        return checkXMLFormat(data: data, rootElement: "datafile") ||
               checkXMLFormat(data: data, rootElement: "game") ||
               (String(data: data.prefix(500), encoding: .utf8)?.contains("Logiqx") ?? false)
    }

    public func parse(data: Data) throws -> MAMEDATFile {
        reset()

        // Pre-allocate for better performance
        games.reserveCapacity(50000)

        let parser = XMLParser(data: data)
        parser.delegate = self

        // Optimize parser settings
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        let startTime = Date()
        guard parser.parse() else {
            throw MAMEParserError.parsingFailed(parser.parserError?.localizedDescription ?? "Unknown error")
        }
        let parseTime = Date().timeIntervalSince(startTime)

        print("Logiqx parser: \(games.count) games in \(String(format: "%.2f", parseTime))s")

        guard let metadata = metadata else {
            throw MAMEParserError.missingMetadata
        }

        return MAMEDATFile(
            formatVersion: metadata.version ?? "Logiqx",
            games: games,
            metadata: metadata
        )
    }

    public func parse(url: URL) throws -> MAMEDATFile {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    private func reset() {
        games = []
        currentGame = nil
        currentRoms = []
        currentElement = ""
        currentElementText = ""
        metadata = nil
        inHeader = false
        headerData = [:]
        currentGameData = [:]
        currentDeviceRefs = []
    }
}

// MARK: - XML Parser Delegate

extension LogiqxDATParser: XMLParserDelegate {

    public func parser(_ parser: XMLParser, didStartElement elementName: String,
                      namespaceURI: String?, qualifiedName qName: String?,
                      attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentElementText = ""

        switch elementName {
        case "header":
            inHeader = true

        case "machine", "game":
            parseGame(attributes: attributeDict)

        case "rom":
            parseROM(attributes: attributeDict)

        case "device_ref":
            if let name = attributeDict["name"] {
                currentDeviceRefs.append(name)
            }

        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String,
                      namespaceURI: String?, qualifiedName qName: String?) {

        if inHeader {
            switch elementName {
            case "name", "description", "version", "date", "author", "email", "homepage", "url":
                headerData[elementName] = currentElementText.trimmingCharacters(in: .whitespacesAndNewlines)

            case "header":
                // Finalize header
                metadata = MAMEMetadata(
                    name: headerData["name"] ?? "Unknown",
                    description: headerData["description"] ?? "",
                    version: headerData["version"],
                    author: headerData["author"],
                    date: headerData["date"],
                    comment: nil,
                    url: headerData["url"],
                    build: nil
                )
                inHeader = false
                headerData = [:]

            default:
                break
            }
        } else if currentGame != nil {
            // Handle game child elements
            switch elementName {
            case "description", "year", "manufacturer":
                currentGameData[elementName] = currentElementText.trimmingCharacters(in: .whitespacesAndNewlines)

            default:
                break
            }
        }

        switch elementName {
        case "machine", "game":
            finalizeCurrentGame()

        default:
            break
        }

        currentElementText = ""
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentElementText += string
    }

    private func parseGame(attributes: [String: String]) {
        guard let name = attributes["name"] else { return }

        currentGameData = [:]
        currentGameData["name"] = name
        currentGameData["sourcefile"] = attributes["sourcefile"]
        currentGameData["cloneof"] = attributes["cloneof"]
        currentGameData["romof"] = attributes["romof"]
        currentGameData["sampleof"] = attributes["sampleof"]
        currentGameData["isbios"] = attributes["isbios"]
        currentGameData["isdevice"] = attributes["isdevice"]

        // Temporary game
        let gameMetadata = MAMEGameMetadata(
            year: nil,
            manufacturer: nil,
            cloneOf: attributes["cloneof"],
            romOf: attributes["romof"],
            sampleOf: attributes["sampleof"],
            sourceFile: attributes["sourcefile"],
            isBios: attributes["isbios"] == "yes",
            isDevice: attributes["isdevice"] == "yes"
        )

        currentGame = MAMEGame(
            name: name,
            description: name,
            metadata: gameMetadata
        )

        currentRoms = []
        currentDeviceRefs = []
    }

    private func parseROM(attributes: [String: String]) {
        guard let name = attributes["name"],
              let sizeString = attributes["size"],
              let size = UInt64(sizeString) else { return }

        let checksums = ROMChecksums(
            crc32: attributes["crc"],
            sha1: attributes["sha1"],
            sha256: attributes["sha256"],
            md5: attributes["md5"]
        )

        let statusString = attributes["status"] ?? "good"
        let status = ROMStatus(rawValue: statusString) ?? .good

        let romAttributes = ROMAttributes(
            merge: attributes["merge"],
            date: attributes["date"],
            optional: attributes["optional"] == "yes"
        )

        let rom = MAMEROM(
            name: name,
            size: size,
            checksums: checksums,
            status: status,
            attributes: romAttributes,
            region: attributes["region"],
            offset: attributes["offset"]
        )

        currentRoms.append(rom)
    }

    private func finalizeCurrentGame() {
        guard let game = currentGame else { return }

        // Create final metadata
        let finalMetadata = MAMEGameMetadata(
            year: currentGameData["year"],
            manufacturer: currentGameData["manufacturer"],
            cloneOf: currentGameData["cloneof"],
            romOf: currentGameData["romof"],
            sampleOf: currentGameData["sampleof"],
            sourceFile: currentGameData["sourcefile"],
            isBios: currentGameData["isbios"] == "yes",
            isDevice: currentGameData["isdevice"] == "yes",
            biosSet: nil,  // Not in Logiqx format
            deviceRefs: currentDeviceRefs
        )

        let finalGame = MAMEGame(
            name: game.name,
            description: currentGameData["description"] ?? game.name,
            roms: currentRoms,
            disks: [],  // Not parsing disks for now
            samples: [],  // Not parsing samples for now
            metadata: finalMetadata
        )

        games.append(finalGame)

        currentGame = nil
        currentRoms = []
        currentGameData = [:]
        currentDeviceRefs = []
    }
}