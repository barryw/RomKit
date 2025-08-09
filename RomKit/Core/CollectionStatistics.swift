//
//  CollectionStatistics.swift
//  RomKit
//
//  Comprehensive collection statistics and generation
//

import Foundation

/// Comprehensive collection statistics
public struct CollectionStatistics {
    // Overall stats
    public let totalGames: Int
    public let completeGames: Int
    public let partialGames: Int
    public let missingGames: Int
    public let completionPercentage: Double

    // ROM stats
    public let totalROMs: Int
    public let foundROMs: Int
    public let missingROMs: Int
    public let duplicateROMs: Int
    public let romCompletionPercentage: Double

    // Size stats
    public let totalSize: UInt64
    public let collectionSize: UInt64
    public let missingSize: UInt64
    public let duplicateSize: UInt64

    // Breakdown by year
    public let byYear: [String: YearStatistics]

    // Breakdown by manufacturer
    public let byManufacturer: [String: ManufacturerStatistics]

    // Breakdown by category
    public let byCategory: [String: CategoryStatistics]

    // Special categories
    public let biosStats: CategoryStatistics
    public let deviceStats: CategoryStatistics
    public let parentStats: CategoryStatistics
    public let cloneStats: CategoryStatistics

    // CHD stats
    public let chdStats: CHDStatistics?

    // File format breakdown
    public let fileFormats: [String: Int]

    // Health score (0-100)
    public let healthScore: Double

    // Issues found
    public let issues: [CollectionIssue]
}

/// Generate collection statistics
public class StatisticsGenerator {

    public static func generate(
        from scanResult: ScanResult,
        datFile: any DATFormat
    ) -> CollectionStatistics {

        // Calculate basic stats from scan results
        let totalGames = scanResult.foundGames.count
        let completeGames = scanResult.foundGames.filter { $0.status == .complete }.count
        let partialGames = scanResult.foundGames.filter { $0.status == .incomplete }.count
        let missingGames = scanResult.foundGames.filter { $0.status == .missing }.count

        let totalROMs = scanResult.foundGames.flatMap { $0.game.roms }.count
        let foundROMs = scanResult.foundGames.flatMap { $0.foundRoms }.count
        let missingROMs = scanResult.foundGames.flatMap { $0.missingRoms }.count

        // Calculate sizes
        let totalSize = scanResult.foundGames.flatMap { $0.game.roms }
            .reduce(0) { $0 + $1.size }
        let missingSize = scanResult.foundGames.flatMap { $0.missingRoms }
            .reduce(0) { $0 + $1.size }
        let collectionSize = totalSize - missingSize

        // Analyze by year from scan results
        let byYear = analyzeByYear(from: scanResult)

        // Analyze by manufacturer from scan results
        let byManufacturer = analyzeByManufacturer(from: scanResult)

        // Special categories from scan results
        let parentGames = scanResult.foundGames.filter { $0.game.cloneOf == nil }
        let cloneGames = scanResult.foundGames.filter { $0.game.cloneOf != nil }

        let biosStats = CategoryStatistics(category: "BIOS", total: 0, complete: 0, partial: 0, missing: 0)
        let deviceStats = CategoryStatistics(category: "Device", total: 0, complete: 0, partial: 0, missing: 0)
        let parentStats = calculateCategoryStatsFromScanned(for: parentGames, category: "Parent")
        let cloneStats = calculateCategoryStatsFromScanned(for: cloneGames, category: "Clone")

        // Detect issues
        let issues = detectIssues(scanResult: scanResult, datFile: datFile)

        // Calculate health score
        let healthScore = calculateHealthScore(
            completionPercentage: totalGames > 0 ? Double(completeGames) / Double(totalGames) * 100 : 0.0,
            issues: issues
        )

        return CollectionStatistics(
            totalGames: totalGames,
            completeGames: completeGames,
            partialGames: partialGames,
            missingGames: missingGames,
            completionPercentage: totalGames > 0 ? Double(completeGames) / Double(totalGames) * 100 : 0.0,
            totalROMs: totalROMs,
            foundROMs: foundROMs,
            missingROMs: missingROMs,
            duplicateROMs: 0, // Would need additional tracking
            romCompletionPercentage: totalROMs > 0 ? Double(foundROMs) / Double(totalROMs) * 100 : 0.0,
            totalSize: totalSize,
            collectionSize: collectionSize,
            missingSize: missingSize,
            duplicateSize: 0, // Would need additional tracking
            byYear: byYear,
            byManufacturer: byManufacturer,
            byCategory: [:],
            biosStats: biosStats,
            deviceStats: deviceStats,
            parentStats: parentStats,
            cloneStats: cloneStats,
            chdStats: nil, // Would need CHD tracking
            fileFormats: [:],
            healthScore: healthScore,
            issues: issues
        )
    }

    private static func analyzeByYear(from scanResult: ScanResult) -> [String: YearStatistics] {
        var byYear: [String: YearStatistics] = [:]

        for scannedGame in scanResult.foundGames {
            if let year = scannedGame.game.year {
                let stats = byYear[year] ?? YearStatistics(
                    year: year,
                    total: 0,
                    complete: 0,
                    partial: 0,
                    missing: 0
                )

                byYear[year] = YearStatistics(
                    year: year,
                    total: stats.total + 1,
                    complete: stats.complete + (scannedGame.status == .complete ? 1 : 0),
                    partial: stats.partial + (scannedGame.status == .incomplete ? 1 : 0),
                    missing: stats.missing + (scannedGame.status == .missing ? 1 : 0)
                )
            }
        }

        return byYear
    }

    private static func analyzeByManufacturer(from scanResult: ScanResult) -> [String: ManufacturerStatistics] {
        var byManufacturer: [String: ManufacturerStatistics] = [:]

        for scannedGame in scanResult.foundGames {
            if let manufacturer = scannedGame.game.manufacturer {
                let stats = byManufacturer[manufacturer] ?? ManufacturerStatistics(
                    manufacturer: manufacturer,
                    total: 0,
                    complete: 0,
                    partial: 0,
                    missing: 0
                )

                byManufacturer[manufacturer] = ManufacturerStatistics(
                    manufacturer: manufacturer,
                    total: stats.total + 1,
                    complete: stats.complete + (scannedGame.status == .complete ? 1 : 0),
                    partial: stats.partial + (scannedGame.status == .incomplete ? 1 : 0),
                    missing: stats.missing + (scannedGame.status == .missing ? 1 : 0)
                )
            }
        }

        return byManufacturer
    }

    private static func calculateCategoryStatsFromScanned(
        for games: [ScannedGame],
        category: String
    ) -> CategoryStatistics {
        let complete = games.filter { $0.status == .complete }.count
        let partial = games.filter { $0.status == .incomplete }.count
        let missing = games.filter { $0.status == .missing }.count

        return CategoryStatistics(
            category: category,
            total: games.count,
            complete: complete,
            partial: partial,
            missing: missing
        )
    }

    private static func detectIssues(
        scanResult: ScanResult,
        datFile: any DATFormat
    ) -> [CollectionIssue] {
        var issues: [CollectionIssue] = []

        // Check for orphaned clones from scan results
        let clones = scanResult.foundGames.filter { $0.game.cloneOf != nil }
        for clone in clones {
            if let parentName = clone.game.cloneOf {
                let parentFound = scanResult.foundGames.contains { $0.game.name == parentName }

                if !parentFound && clone.status == .complete {
                    issues.append(CollectionIssue(
                        type: .orphanedClones,
                        description: "Clone '\(clone.game.name)' found but parent '\(parentName)' is missing",
                        severity: .warning,
                        affectedFiles: [clone.game.name]
                    ))
                }
            }
        }

        return issues
    }

    private static func calculateHealthScore(
        completionPercentage: Double,
        issues: [CollectionIssue]
    ) -> Double {
        var score = completionPercentage

        // Deduct points for issues
        for issue in issues {
            switch issue.severity {
            case .critical:
                score -= 10
            case .warning:
                score -= 5
            case .info:
                score -= 1
            }
        }

        return max(0, min(100, score))
    }
}
