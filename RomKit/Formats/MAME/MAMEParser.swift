//
//  MAMEParser.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation

public class MAMEDATParser: NSObject, DATParser {
    public typealias DATType = MAMEDATFile

    private var games: [MAMEGame] = []
    private var currentGame: MAMEGame?
    private var currentRoms: [MAMEROM] = []
    private var currentDisks: [MAMEDisk] = []
    private var currentSamples: [MAMESample] = []
    private var currentElement: String = ""
    private var currentElementText: String = ""
    private var metadata: MAMEMetadata?
    private var inHeader: Bool = false
    private var headerData: [String: String] = [:]
    private var currentGameData: [String: String] = [:]

    // New element collections
    private var currentChips: [MAMEChip] = []
    private var currentDisplay: MAMEDisplay?
    private var currentSound: MAMESound?
    private var currentInput: MAMEInput?
    private var currentDipSwitches: [MAMEDipSwitch] = []
    private var currentDriver: MAMEDriver?
    private var currentFeatures: [MAMEFeature] = []
    private var currentControls: [MAMEControl] = []
    private var currentDipSwitch: MAMEDipSwitch?
    private var currentDipLocations: [MAMEDipLocation] = []
    private var currentDipValues: [MAMEDipValue] = []

    public override init() {
        super.init()
    }

    public func canParse(data: Data) -> Bool {
        guard let xmlString = String(data: data.prefix(1000), encoding: .utf8) else {
            return false
        }

        return xmlString.contains("<datafile") ||
               xmlString.contains("<mame") ||
               xmlString.contains("<!DOCTYPE mame")
    }

    public func parse(data: Data) throws -> MAMEDATFile {
        reset()

        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            throw MAMEParserError.parsingFailed(parser.parserError?.localizedDescription ?? "Unknown error")
        }

        guard let metadata = metadata else {
            throw MAMEParserError.missingMetadata
        }

        return MAMEDATFile(
            formatVersion: metadata.version,
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
        currentDisks = []
        currentSamples = []
        currentElement = ""
        currentElementText = ""
        metadata = nil
        inHeader = false
        headerData = [:]
        currentGameData = [:]

        // Reset new elements
        currentChips = []
        currentDisplay = nil
        currentSound = nil
        currentInput = nil
        currentDipSwitches = []
        currentDriver = nil
        currentFeatures = []
        currentControls = []
        currentDipSwitch = nil
        currentDipLocations = []
        currentDipValues = []
    }
}

// MARK: - XML Parser Delegate

extension MAMEDATParser: XMLParserDelegate {
    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentElementText = ""

        handleStartElement(elementName: elementName, attributes: attributeDict)
    }

    private func handleStartElement(elementName: String, attributes: [String: String]) {
        // Group related elements to reduce complexity
        if handleHeaderElements(elementName: elementName, attributes: attributes) {
            return
        }

        if handleGameElements(elementName: elementName, attributes: attributes) {
            return
        }

        if handleHardwareElements(elementName: elementName, attributes: attributes) {
            return
        }

        if handleInputElements(elementName: elementName, attributes: attributes) {
            return
        }
    }

    private func handleHeaderElements(elementName: String, attributes: [String: String]) -> Bool {
        switch elementName {
        case "datafile", "mame":
            parseDatafileHeader(attributes: attributes)
            return true
        case "header":
            inHeader = true
            parseHeader(attributes: attributes)
            return true
        default:
            return false
        }
    }

    private func handleGameElements(elementName: String, attributes: [String: String]) -> Bool {
        switch elementName {
        case "game", "machine":
            parseGame(attributes: attributes)
            return true
        case "rom":
            parseROM(attributes: attributes)
            return true
        case "disk":
            parseDisk(attributes: attributes)
            return true
        case "sample":
            parseSample(attributes: attributes)
            return true
        case "device_ref":
            parseDeviceRef(attributes: attributes)
            return true
        default:
            return false
        }
    }

    private func handleHardwareElements(elementName: String, attributes: [String: String]) -> Bool {
        switch elementName {
        case "chip":
            parseChip(attributes: attributes)
            return true
        case "display":
            parseDisplay(attributes: attributes)
            return true
        case "sound":
            parseSound(attributes: attributes)
            return true
        case "driver":
            parseDriver(attributes: attributes)
            return true
        case "feature":
            parseFeature(attributes: attributes)
            return true
        default:
            return false
        }
    }

    private func handleInputElements(elementName: String, attributes: [String: String]) -> Bool {
        switch elementName {
        case "input":
            parseInput(attributes: attributes)
            return true
        case "control":
            parseControl(attributes: attributes)
            return true
        case "dipswitch":
            parseDipSwitch(attributes: attributes)
            return true
        case "diplocation":
            parseDipLocation(attributes: attributes)
            return true
        case "dipvalue":
            parseDipValue(attributes: attributes)
            return true
        default:
            return false
        }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        handleEndElement(elementName: elementName)
        currentElementText = ""
    }

    private func handleEndElement(elementName: String) {
        if inHeader {
            handleHeaderEndElement(elementName: elementName)
        } else if currentGame != nil {
            handleGameEndElement(elementName: elementName)
        }

        handleFinalizationElements(elementName: elementName)
    }

    private func handleHeaderEndElement(elementName: String) {
        switch elementName {
        case "name", "description", "version", "author", "date", "comment", "url":
            headerData[elementName] = currentElementText.trimmingCharacters(in: .whitespacesAndNewlines)
        case "header":
            finalizeHeader()
        default:
            break
        }
    }

    private func handleGameEndElement(elementName: String) {
        switch elementName {
        case "description", "year", "manufacturer":
            currentGameData[elementName] = currentElementText.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            break
        }
    }

    private func handleFinalizationElements(elementName: String) {
        switch elementName {
        case "game", "machine":
            finalizeCurrentGame()
        case "input":
            finalizeCurrentInput()
        case "dipswitch":
            finalizeCurrentDipSwitch()
        default:
            break
        }
    }

    private func finalizeHeader() {
        metadata = MAMEMetadata(
            name: headerData["name"] ?? metadata?.name ?? "Unknown",
            description: headerData["description"] ?? metadata?.description ?? "",
            version: headerData["version"] ?? metadata?.version,
            author: headerData["author"],
            date: headerData["date"],
            comment: headerData["comment"],
            url: headerData["url"],
            build: metadata?.build
        )
        inHeader = false
        headerData = [:]
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentElementText += string
    }

    private func parseDatafileHeader(attributes: [String: String]) {
        if metadata == nil {
            metadata = MAMEMetadata(
                name: attributes["build"] ?? "Unknown",
                description: attributes["debug"] ?? "",
                version: attributes["version"],
                build: attributes["build"]
            )
        }
    }

    private func parseHeader(attributes: [String: String]) {
        // Header element contains child elements, not attributes in MAME XML
        // We'll handle these in parser:foundCharacters if needed
        // For now, create/update metadata if not already created
        if metadata == nil {
            metadata = MAMEMetadata(
                name: "Unknown",
                description: "",
                version: nil,
                build: nil
            )
        }
    }

    private func parseGame(attributes: [String: String]) {
        guard let name = attributes["name"] else { return }

        // Clear game data for new game
        currentGameData = [:]

        // Store attributes in currentGameData (may be overridden by child elements)
        currentGameData["name"] = name
        if let desc = attributes["description"] {
            currentGameData["description"] = desc
        }
        if let year = attributes["year"] {
            currentGameData["year"] = year
        }
        if let manufacturer = attributes["manufacturer"] {
            currentGameData["manufacturer"] = manufacturer
        }

        // Parse device references from deviceref_N attributes
        var deviceRefs: [String] = []
        for (key, value) in attributes where key.hasPrefix("deviceref_") {
            deviceRefs.append(value)
        }

        // Store other attributes temporarily
        currentGameData["cloneof"] = attributes["cloneof"]
        currentGameData["romof"] = attributes["romof"]
        currentGameData["sampleof"] = attributes["sampleof"]
        currentGameData["sourcefile"] = attributes["sourcefile"]
        currentGameData["isbios"] = attributes["isbios"]
        currentGameData["isdevice"] = attributes["isdevice"]
        currentGameData["ismechanical"] = attributes["ismechanical"]
        currentGameData["runnable"] = attributes["runnable"]
        currentGameData["bios"] = attributes["bios"]
        currentGameData["deviceRefs"] = deviceRefs.joined(separator: ",")

        // Create temporary game (will be finalized with child element data)
        let gameMetadata = MAMEGameMetadata(
            year: nil,
            manufacturer: nil,
            cloneOf: attributes["cloneof"],
            romOf: attributes["romof"],
            sampleOf: attributes["sampleof"],
            sourceFile: attributes["sourcefile"],
            isBios: attributes["isbios"] == "yes",
            isDevice: attributes["isdevice"] == "yes",
            isMechanical: attributes["ismechanical"] == "yes",
            runnable: attributes["runnable"] != "no",
            biosSet: attributes["bios"],
            deviceRefs: deviceRefs
        )

        currentGame = MAMEGame(
            name: name,
            description: name,  // Will be updated from child elements
            metadata: gameMetadata
        )

        currentRoms = []
        currentDisks = []
        currentSamples = []
        currentChips = []
        currentDisplay = nil
        currentSound = nil
        currentInput = nil
        currentDipSwitches = []
        currentDriver = nil
        currentFeatures = []
        currentControls = []
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

    private func parseDisk(attributes: [String: String]) {
        guard let name = attributes["name"] else { return }

        let checksums = ROMChecksums(
            sha1: attributes["sha1"],
            sha256: attributes["sha256"],
            md5: attributes["md5"]
        )

        let statusString = attributes["status"] ?? "good"
        let status = ROMStatus(rawValue: statusString) ?? .good

        let diskAttributes = ROMAttributes(
            merge: attributes["merge"],
            optional: attributes["optional"] == "yes"
        )

        let indexValue = attributes["index"].flatMap { Int($0) }

        let disk = MAMEDisk(
            name: name,
            checksums: checksums,
            status: status,
            attributes: diskAttributes,
            index: indexValue
        )

        currentDisks.append(disk)
    }

    private func parseSample(attributes: [String: String]) {
        guard let name = attributes["name"] else { return }
        currentSamples.append(MAMESample(name: name))
    }

    private func parseDeviceRef(attributes: [String: String]) {
        guard let name = attributes["name"] else { return }
        if !currentGameData["deviceRefs", default: ""].isEmpty {
            currentGameData["deviceRefs", default: ""] += ","
        }
        currentGameData["deviceRefs", default: ""] += name
    }

    private func parseChip(attributes: [String: String]) {
        guard let name = attributes["name"],
              let type = attributes["type"] else { return }

        let chip = MAMEChip(
            type: type,
            tag: attributes["tag"] ?? "",
            name: name,
            clock: attributes["clock"].flatMap { Int($0) }
        )
        currentChips.append(chip)
    }

    private func parseDisplay(attributes: [String: String]) {
        guard let type = attributes["type"],
              let refresh = attributes["refresh"].flatMap({ Double($0) }) else { return }

        currentDisplay = MAMEDisplay(
            tag: attributes["tag"] ?? "",
            type: type,
            rotate: attributes["rotate"].flatMap { Int($0) } ?? 0,
            width: attributes["width"].flatMap { Int($0) } ?? 0,
            height: attributes["height"].flatMap { Int($0) } ?? 0,
            refresh: refresh,
            pixelClock: attributes["pixclock"].flatMap { Int($0) },
            hTotal: attributes["htotal"].flatMap { Int($0) },
            hbEnd: attributes["hbend"].flatMap { Int($0) },
            hbStart: attributes["hbstart"].flatMap { Int($0) },
            vTotal: attributes["vtotal"].flatMap { Int($0) },
            vbEnd: attributes["vbend"].flatMap { Int($0) },
            vbStart: attributes["vbstart"].flatMap { Int($0) }
        )
    }

    private func parseSound(attributes: [String: String]) {
        guard let channels = attributes["channels"].flatMap({ Int($0) }) else { return }
        currentSound = MAMESound(channels: channels)
    }

    private func parseInput(attributes: [String: String]) {
        guard let players = attributes["players"].flatMap({ Int($0) }) else { return }

        currentInput = MAMEInput(
            players: players,
            coins: attributes["coins"].flatMap { Int($0) },
            service: attributes["service"] == "yes",
            controls: []  // Will be filled when input element closes
        )
        currentControls = []
    }

    private func parseControl(attributes: [String: String]) {
        guard let type = attributes["type"] else { return }

        let control = MAMEControl(
            type: type,
            player: attributes["player"].flatMap { Int($0) },
            buttons: attributes["buttons"].flatMap { Int($0) },
            ways: attributes["ways"].flatMap { Int($0) }
        )
        currentControls.append(control)
    }

    private func parseDipSwitch(attributes: [String: String]) {
        guard let name = attributes["name"],
              let tag = attributes["tag"],
              let mask = attributes["mask"].flatMap({ Int($0) }) else { return }

        currentDipSwitch = MAMEDipSwitch(
            name: name,
            tag: tag,
            mask: mask,
            locations: [],
            values: []
        )
        currentDipLocations = []
        currentDipValues = []
    }

    private func parseDipLocation(attributes: [String: String]) {
        guard let name = attributes["name"],
              let number = attributes["number"] else { return }

        currentDipLocations.append(MAMEDipLocation(name: name, number: number))
    }

    private func parseDipValue(attributes: [String: String]) {
        guard let name = attributes["name"],
              let value = attributes["value"].flatMap({ Int($0) }) else { return }

        currentDipValues.append(MAMEDipValue(
            name: name,
            value: value,
            isDefault: attributes["default"] == "yes"
        ))
    }

    private func parseDriver(attributes: [String: String]) {
        guard let status = attributes["status"],
              let emulation = attributes["emulation"],
              let savestate = attributes["savestate"] else { return }

        currentDriver = MAMEDriver(
            status: status,
            emulation: emulation,
            savestate: savestate
        )
    }

    private func parseFeature(attributes: [String: String]) {
        guard let type = attributes["type"] else { return }

        currentFeatures.append(MAMEFeature(
            type: type,
            status: attributes["status"] ?? ""
        ))
    }

    private func finalizeCurrentInput() {
        guard var input = currentInput else { return }
        input = MAMEInput(
            players: input.players,
            coins: input.coins,
            service: input.service,
            controls: currentControls
        )
        currentInput = input
        currentControls = []
    }

    private func finalizeCurrentDipSwitch() {
        guard var dipSwitch = currentDipSwitch else { return }
        dipSwitch = MAMEDipSwitch(
            name: dipSwitch.name,
            tag: dipSwitch.tag,
            mask: dipSwitch.mask,
            locations: currentDipLocations,
            values: currentDipValues
        )
        currentDipSwitches.append(dipSwitch)
        currentDipSwitch = nil
        currentDipLocations = []
        currentDipValues = []
    }

    private func finalizeCurrentGame() {
        guard let game = currentGame else { return }

        // Parse device refs from stored string
        let deviceRefs = currentGameData["deviceRefs"]?.split(separator: ",").map { String($0) } ?? []

        // Create final metadata with both attribute and child element data
        let finalMetadata = MAMEGameMetadata(
            year: currentGameData["year"],
            manufacturer: currentGameData["manufacturer"],
            cloneOf: currentGameData["cloneof"],
            romOf: currentGameData["romof"],
            sampleOf: currentGameData["sampleof"],
            sourceFile: currentGameData["sourcefile"],
            isBios: currentGameData["isbios"] == "yes",
            isDevice: currentGameData["isdevice"] == "yes",
            isMechanical: currentGameData["ismechanical"] == "yes",
            runnable: currentGameData["runnable"] != "no",
            biosSet: currentGameData["bios"],
            deviceRefs: deviceRefs,
            chips: currentChips,
            display: currentDisplay,
            sound: currentSound,
            input: currentInput,
            dipswitches: currentDipSwitches,
            driver: currentDriver,
            features: currentFeatures
        )

        let finalGame = MAMEGame(
            name: game.name,
            description: currentGameData["description"] ?? game.name,
            roms: currentRoms,
            disks: currentDisks,
            samples: currentSamples,
            metadata: finalMetadata
        )

        games.append(finalGame)

        currentGame = nil
        currentRoms = []
        currentDisks = []
        currentSamples = []
        currentGameData = [:]
        currentChips = []
        currentDisplay = nil
        currentSound = nil
        currentInput = nil
        currentDipSwitches = []
        currentDriver = nil
        currentFeatures = []
    }
}

public enum MAMEParserError: Error, LocalizedError {
    case parsingFailed(String)
    case missingMetadata

    public var errorDescription: String? {
        switch self {
        case .parsingFailed(let reason):
            return "XML parsing failed: \(reason)"
        case .missingMetadata:
            return "DAT file is missing required metadata"
        }
    }
}
