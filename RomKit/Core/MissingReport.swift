//
//  MissingReport.swift
//  RomKit
//
//  Generate detailed missing ROMs reports for collectors
//

import Foundation

/// Options for generating missing ROM reports
public struct MissingReportOptions {
    public let groupByParent: Bool
    public let includeDevices: Bool
    public let includeBIOS: Bool
    public let includeClones: Bool
    public let showAlternatives: Bool
    public let sortBy: MissingReportSort

    public init(
        groupByParent: Bool = true,
        includeDevices: Bool = false,
        includeBIOS: Bool = true,
        includeClones: Bool = true,
        showAlternatives: Bool = true,
        sortBy: MissingReportSort = .name
    ) {
        self.groupByParent = groupByParent
        self.includeDevices = includeDevices
        self.includeBIOS = includeBIOS
        self.includeClones = includeClones
        self.showAlternatives = showAlternatives
        self.sortBy = sortBy
    }
}

/// Sort options for missing report
public enum MissingReportSort {
    case name
    case year
    case manufacturer
    case missingCount
}

/// A detailed missing ROMs report
public struct MissingReport {
    public let totalGames: Int
    public let completeGames: Int
    public let partialGames: Int
    public let missingGames: Int
    public let totalROMs: Int
    public let foundROMs: Int
    public let missingROMs: Int
    public let totalSize: UInt64
    public let foundSize: UInt64
    public let missingSize: UInt64
    public let missingByCategory: [String: [MissingGame]]
    public let parentCloneGroups: [ParentCloneGroup]
    public let options: MissingReportOptions

    /// Generate HTML report
    public func generateHTML() -> String {
        let header = generateHTMLHeader()
        let summary = generateHTMLSummary()
        let groups = generateHTMLGroups()
        let details = generateHTMLDetails()
        let footer = "</body>\n</html>"

        return header + summary + groups + details + footer
    }

    private func generateHTMLHeader() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>Missing ROMs Report</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 20px; background: #f5f5f5; }
                .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; margin-bottom: 30px; }
                h1 { margin: 0; font-size: 2.5em; }
                .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
                .stat-card { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
                .stat-value { font-size: 2em; font-weight: bold; color: #333; }
                .stat-label { color: #666; margin-top: 5px; }
                .progress-bar { background: #e0e0e0; height: 10px; border-radius: 5px; margin-top: 10px; overflow: hidden; }
                .progress-fill { height: 100%; background: linear-gradient(90deg, #4CAF50, #8BC34A); transition: width 0.3s; }
                .section { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); margin-bottom: 20px; }
                h2 { color: #333; border-bottom: 2px solid #667eea; padding-bottom: 10px; }
                .game-group { margin-bottom: 20px; padding: 15px; background: #f9f9f9; border-radius: 8px; }
                .parent-game { font-weight: bold; color: #667eea; font-size: 1.1em; margin-bottom: 10px; }
                .clone-list { margin-left: 20px; }
                .missing-rom { background: #fff3cd; padding: 8px; margin: 5px 0; border-radius: 5px; border-left: 4px solid #ffc107; }
                .complete { background: #d4edda; border-left-color: #28a745; }
                .partial { background: #cce5ff; border-left-color: #007bff; }
                .missing { background: #f8d7da; border-left-color: #dc3545; }
                .rom-info { font-family: monospace; font-size: 0.9em; color: #666; margin-top: 5px; }
                table { width: 100%; border-collapse: collapse; }
                th { background: #f5f5f5; padding: 10px; text-align: left; font-weight: 600; }
                td { padding: 10px; border-bottom: 1px solid #eee; }
                .badge { display: inline-block; padding: 3px 8px; border-radius: 12px; font-size: 0.85em; font-weight: 600; }
                .badge-bios { background: #e3f2fd; color: #1976d2; }
                .badge-device { background: #f3e5f5; color: #7b1fa2; }
                .badge-parent { background: #e8f5e9; color: #388e3c; }
                .badge-clone { background: #fff8e1; color: #f57c00; }
            </style>
        </head>
        <body>
            <div class="header">
                <h1>🕹️ Missing ROMs Report</h1>
                <p>Generated on \(Date().formatted())</p>
            </div>
        """
    }

    private func generateHTMLSummary() -> String {
        return """
            <div class="summary">
                <div class="stat-card">
                    <div class="stat-value">\(completeGames)/\(totalGames)</div>
                    <div class="stat-label">Complete Games</div>
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: \(completionPercentage)%"></div>
                    </div>
                </div>

                <div class="stat-card">
                    <div class="stat-value">\(foundROMs)/\(totalROMs)</div>
                    <div class="stat-label">ROMs Found</div>
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: \(romCompletionPercentage)%"></div>
                    </div>
                </div>

                <div class="stat-card">
                    <div class="stat-value">\(formatBytes(foundSize))</div>
                    <div class="stat-label">Collection Size</div>
                </div>

                <div class="stat-card">
                    <div class="stat-value">\(formatBytes(missingSize))</div>
                    <div class="stat-label">Missing Size</div>
                </div>
            </div>
        """
    }

    private func generateHTMLGroups() -> String {
        guard options.groupByParent else { return "" }

        var html = """
            <div class="section">
                <h2>Missing Games by Parent/Clone Groups</h2>
        """

        for group in parentCloneGroups {
            let statusClass = group.isComplete ? "complete" : (group.hasAny ? "partial" : "missing")
            html += """
                <div class="game-group \(statusClass)">
                    <div class="parent-game">
                        \(group.parent.name) - \(group.parent.description)
                        <span class="badge badge-parent">PARENT</span>
                    </div>
            """

            if !group.missingROMs.isEmpty {
                html += "<div class='missing-rom'>Missing: "
                html += group.missingROMs.map { $0.name }.joined(separator: ", ")
                html += "</div>"
            }

            if !group.clones.isEmpty {
                html += "<div class='clone-list'>"
                for clone in group.clones {
                    html += """
                        <div>
                            • \(clone.game.name) - \(clone.game.description)
                            <span class="badge badge-clone">CLONE</span>
                    """
                    if !clone.missingROMs.isEmpty {
                        html += " (Missing: \(clone.missingROMs.count) ROMs)"
                    }
                    html += "</div>"
                }
                html += "</div>"
            }

            html += "</div>"
        }

        html += "</div>"
        return html
    }

    private func generateHTMLDetails() -> String {
        var html = """
            <div class="section">
                <h2>Detailed Missing ROMs</h2>
                <table>
                    <thead>
                        <tr>
                            <th>Game</th>
                            <th>ROM Name</th>
                            <th>Size</th>
                            <th>CRC32</th>
                            <th>Status</th>
                        </tr>
                    </thead>
                    <tbody>
        """

        for (_, games) in missingByCategory {
            for missingGame in games {
                for rom in missingGame.missingROMs {
                    html += """
                        <tr>
                            <td>\(missingGame.game.name)</td>
                            <td><code>\(rom.name)</code></td>
                            <td>\(formatBytes(rom.size))</td>
                            <td><code>\(rom.checksums.crc32 ?? "N/A")</code></td>
                            <td>\(missingGame.alternatives.isEmpty ? "Required" : "Alternative Available")</td>
                        </tr>
                    """
                }
            }
        }

        html += """
                    </tbody>
                </table>
            </div>
        """

        return html
    }

    /// Generate plain text report
    public func generateText() -> String {
        let summary = generateTextSummary()
        let groups = generateTextGroups()
        let details = generateTextDetails()
        let footer = "\n================================================================================"

        return summary + groups + details + footer
    }

    private func generateTextSummary() -> String {
        return """
        ================================================================================
                                    MISSING ROMS REPORT
        ================================================================================
        Generated: \(Date().formatted())

        SUMMARY
        -------
        Complete Games:  \(String(format: "%5d", completeGames))/\(totalGames) (\(String(format: "%.1f", completionPercentage))%)
        Partial Games:   \(String(format: "%5d", partialGames))
        Missing Games:   \(String(format: "%5d", missingGames))

        ROMs Found:      \(String(format: "%5d", foundROMs))/\(totalROMs) (\(String(format: "%.1f", romCompletionPercentage))%)
        Missing ROMs:    \(String(format: "%5d", missingROMs))

        Collection Size: \(formatBytes(foundSize))
        Missing Size:    \(formatBytes(missingSize))
        Total Size:      \(formatBytes(totalSize))

        """
    }

    private func generateTextGroups() -> String {
        guard options.groupByParent else { return "" }

        var report = """

        MISSING BY PARENT/CLONE GROUPS
        -------------------------------
        """

        for group in parentCloneGroups.filter({ !$0.isComplete }) {
            report += "\n\n[\(group.parent.name)] \(group.parent.description)\n"

            if !group.missingROMs.isEmpty {
                report += "  PARENT MISSING:\n"
                for rom in group.missingROMs {
                    report += "    - \(rom.name) (\(formatBytes(rom.size)))\n"
                }
            }

            for clone in group.clones.filter({ !$0.missingROMs.isEmpty }) {
                report += "  CLONE [\(clone.game.name)]: \(clone.game.description)\n"
                for rom in clone.missingROMs {
                    report += "    - \(rom.name) (\(formatBytes(rom.size)))\n"
                }
            }
        }

        return report
    }

    private func generateTextDetails() -> String {
        var report = """


        DETAILED MISSING LIST
        ---------------------
        """

        for (category, games) in missingByCategory.sorted(by: { $0.key < $1.key }) {
            report += "\n\n\(category.uppercased())\n"
            report += String(repeating: "-", count: category.count) + "\n"

            for missingGame in games {
                report += "\n[\(missingGame.game.name)] \(missingGame.game.description)\n"
                for rom in missingGame.missingROMs {
                    let crc = rom.checksums.crc32 ?? "????????"
                    report += "  - \(rom.name) (CRC: \(crc), Size: \(formatBytes(rom.size)))\n"
                }

                if !missingGame.alternatives.isEmpty && options.showAlternatives {
                    report += "  Alternatives available in: \(missingGame.alternatives.joined(separator: ", "))\n"
                }
            }
        }

        return report
    }

    private var completionPercentage: Double {
        guard totalGames > 0 else { return 0 }
        return Double(completeGames) / Double(totalGames) * 100
    }

    private var romCompletionPercentage: Double {
        guard totalROMs > 0 else { return 0 }
        return Double(foundROMs) / Double(totalROMs) * 100
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// A game with missing ROMs
public struct MissingGame {
    public let game: any GameEntry
    public let missingROMs: [any ROMItem]
    public let foundROMs: [any ROMItem]
    public let alternatives: [String]
}

/// Parent/clone grouping for reports
public struct ParentCloneGroup {
    public let parent: any GameEntry
    public let clones: [MissingGame]
    public let missingROMs: [any ROMItem]
    public let isComplete: Bool
    public let hasAny: Bool
}

/// Generate missing report from scan results
public class MissingReportGenerator {

    public static func generate(
        from scanResult: ScanResult,
        datFile: any DATFormat,
        options: MissingReportOptions = MissingReportOptions()
    ) -> MissingReport {

        var missingByCategory: [String: [MissingGame]] = [:]
        var parentCloneGroups: [ParentCloneGroup] = []

        // Process games with missing ROMs from scan results
        for scannedGame in scanResult.foundGames where !scannedGame.missingRoms.isEmpty {
                let game = LegacyGameAdapter(game: scannedGame.game)
                let category = categorizeGame(game)
                if shouldInclude(game: game, category: category, options: options) {
                    let missingGame = MissingGame(
                        game: game,
                        missingROMs: scannedGame.missingRoms.map { LegacyROMAdapter(rom: $0) },
                        foundROMs: scannedGame.foundRoms.map { LegacyROMAdapter(rom: $0.rom) },
                        alternatives: findAlternatives(for: game, in: datFile)
                    )
                    missingByCategory[category, default: []].append(missingGame)
                }
            }

        // Group by parent/clone if requested
        if options.groupByParent {
            parentCloneGroups = createParentCloneGroups(
                from: missingByCategory,
                datFile: datFile
            )
        }

        // Calculate statistics from scan results
        let totalGames = scanResult.foundGames.count // This might not be all games, but games we scanned
        let completeGames = scanResult.foundGames.filter { $0.status == .complete }.count
        let partialGames = scanResult.foundGames.filter { $0.status == .incomplete }.count
        let missingGames = scanResult.foundGames.filter { $0.status == .missing }.count

        let totalROMs = scanResult.foundGames.flatMap { $0.game.roms }.count
        let foundROMs = scanResult.foundGames.flatMap { $0.foundRoms }.count
        let missingROMs = scanResult.foundGames.flatMap { $0.missingRoms }.count

        let totalSize = scanResult.foundGames.flatMap { $0.game.roms }.reduce(0) { $0 + $1.size }
        let missingSize = scanResult.foundGames.flatMap { $0.missingRoms }.reduce(0) { $0 + $1.size }

        return MissingReport(
            totalGames: totalGames,
            completeGames: completeGames,
            partialGames: partialGames,
            missingGames: missingGames,
            totalROMs: totalROMs,
            foundROMs: foundROMs,
            missingROMs: missingROMs,
            totalSize: totalSize,
            foundSize: totalSize - missingSize,
            missingSize: missingSize,
            missingByCategory: missingByCategory,
            parentCloneGroups: parentCloneGroups,
            options: options
        )
    }

    private static func categorizeGame(_ game: any GameEntry) -> String {
        // Since we're working with legacy adapters, check metadata instead
        if let cloneOf = game.metadata.cloneOf, !cloneOf.isEmpty {
            return "Clone"
        } else {
            return "Parent"
        }
    }

    private static func shouldInclude(
        game: any GameEntry,
        category: String,
        options: MissingReportOptions
    ) -> Bool {
        switch category {
        case "BIOS":
            return options.includeBIOS
        case "Device":
            return options.includeDevices
        case "Clone":
            return options.includeClones
        default:
            return true
        }
    }

    private static func findAlternatives(
        for game: any GameEntry,
        in datFile: any DATFormat
    ) -> [String] {
        var alternatives: [String] = []

        if let mameGame = game as? MAMEGame,
           let mameMetadata = mameGame.metadata as? MAMEGameMetadata {
            // Check if parent has the ROMs
            if let parentName = mameMetadata.cloneOf ?? mameMetadata.romOf {
                if datFile.games.contains(where: { $0.name == parentName }) {
                    alternatives.append(parentName)
                }
            }

            // Check for other clones - simplified approach
            if let cloneOf = mameMetadata.cloneOf {
                let otherClones = datFile.games
                    .filter { $0.name != game.name && $0.metadata.cloneOf == cloneOf }
                    .map { $0.name }
                alternatives.append(contentsOf: otherClones)
            }
        }

        return alternatives
    }

    private static func createParentCloneGroups(
        from missingByCategory: [String: [MissingGame]],
        datFile: any DATFormat
    ) -> [ParentCloneGroup] {
        // Simplified grouping for legacy compatibility
        var groups: [ParentCloneGroup] = []

        // Group missing games by parent/clone relationship
        let allMissing = missingByCategory.values.flatMap { $0 }
        let parentMissing = allMissing.filter { $0.game.metadata.cloneOf == nil }

        for parentGame in parentMissing {
            let clonesMissing = allMissing.filter {
                $0.game.metadata.cloneOf == parentGame.game.name
            }

            groups.append(ParentCloneGroup(
                parent: parentGame.game,
                clones: clonesMissing,
                missingROMs: parentGame.missingROMs,
                isComplete: false,
                hasAny: !parentGame.foundROMs.isEmpty
            ))
        }

        return groups.sorted { $0.parent.name < $1.parent.name }
    }
}
