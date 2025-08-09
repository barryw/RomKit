//
//  CollectionStatisticsModels.swift
//  RomKit
//
//  Statistics model types for collection analysis
//

import Foundation

/// Statistics for a specific year
public struct YearStatistics {
    public let year: String
    public let total: Int
    public let complete: Int
    public let partial: Int
    public let missing: Int
}

/// Statistics for a manufacturer
public struct ManufacturerStatistics {
    public let manufacturer: String
    public let total: Int
    public let complete: Int
    public let partial: Int
    public let missing: Int
}

/// Statistics for a category
public struct CategoryStatistics {
    public let category: String
    public let total: Int
    public let complete: Int
    public let partial: Int
    public let missing: Int
}

/// CHD-specific statistics
public struct CHDStatistics {
    public let totalCHDs: Int
    public let foundCHDs: Int
    public let missingCHDs: Int
    public let totalSize: UInt64
    public let foundSize: UInt64
    public let missingSize: UInt64
}

/// Collection issue
public struct CollectionIssue {
    public enum IssueType {
        case duplicateROMs
        case corruptedFiles
        case wrongNaming
        case missingBIOS
        case missingDevice
        case orphanedClones
        case sizeMismatch
    }

    public let type: IssueType
    public let description: String
    public let severity: IssueSeverity
    public let affectedFiles: [String]

    public enum IssueSeverity {
        case critical
        case warning
        case info
    }
}
