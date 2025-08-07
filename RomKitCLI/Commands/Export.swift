//
//  Export.swift
//  RomKit CLI - Export Command
//
//  Export ROM data to various formats
//

import ArgumentParser
import Foundation
import RomKit

struct Export: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Export ROM data to various formats"
    )

    @Argument(help: "Path to the DAT file to export")
    var datPath: String

    @Option(name: .shortAndLong, help: "Output format (json, csv, xml)")
    var format: String = "json"

    @Option(name: .shortAndLong, help: "Output file path")
    var output: String

    mutating func run() async throws {
        let datURL = URL(fileURLWithPath: datPath)

        RomKitCLI.printHeader("📤 Exporting ROM Data")
        print("📄 DAT File: \(datURL.lastPathComponent)")
        print("📊 Format: \(format)")

        // Load DAT file
        let data = try Data(contentsOf: datURL)
        let parser = MAMEFastParser()
        let mameDatFile = try await parser.parseXMLParallel(data: data)

        print("✅ Loaded \(mameDatFile.games.count) games")

        // Export based on format
        switch format.lowercased() {
        case "json":
            // Convert to exportable format
            let exportData = mameDatFile.games.map { game in
                [
                    "name": game.name,
                    "description": game.description,
                    "year": game.metadata.year ?? "",
                    "manufacturer": game.metadata.manufacturer ?? "",
                    "romCount": game.items.count
                ] as [String: Any]
            }

            let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: URL(fileURLWithPath: output))

        case "csv":
            var csv = "Name,Description,Year,Manufacturer,ROM Count\n"
            for game in mameDatFile.games {
                let year = game.metadata.year ?? ""
                let manufacturer = game.metadata.manufacturer ?? ""
                csv += "\"\(game.name)\",\"\(game.description)\",\"\(year)\",\"\(manufacturer)\",\(game.items.count)\n"
            }
            try csv.write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)

        default:
            throw ValidationError("Unsupported format: \(format)")
        }

        print("✅ Exported to: \(output)")
    }
}