//
//  IndexManagementTypes.swift
//  RomKit
//
//  Public types for index management APIs
//

import Foundation

// MARK: - Index Management Types

/// Represents an indexed directory with basic statistics
public struct IndexedSource: Sendable {
    /// The path to the indexed directory
    public let path: URL

    /// Total number of ROMs in this directory
    public let totalROMs: Int

    /// Total size of all ROMs in bytes
    public let totalSize: Int64

    /// When this directory was last indexed
    public let lastIndexed: Date

    public init(path: URL, totalROMs: Int, totalSize: Int64, lastIndexed: Date) {
        self.path = path
        self.totalROMs = totalROMs
        self.totalSize = totalSize
        self.lastIndexed = lastIndexed
    }
}

/// Detailed statistics for an indexed directory
public struct IndexStatistics: Sendable {
    /// The path to the indexed directory
    public let path: URL

    /// Total number of ROM files
    public let totalROMs: Int

    /// Number of unique games (estimated)
    public let uniqueGames: Int

    /// Number of duplicate ROMs
    public let duplicates: Int

    /// Number of archive files (.zip, .7z)
    public let archives: Int

    /// Number of CHD files
    public let chds: Int

    /// Total size in bytes
    public let totalSize: Int64

    /// When this directory was last indexed
    public let lastIndexed: Date?

    public init(
        path: URL,
        totalROMs: Int,
        uniqueGames: Int,
        duplicates: Int,
        archives: Int,
        chds: Int,
        totalSize: Int64,
        lastIndexed: Date? = nil
    ) {
        self.path = path
        self.totalROMs = totalROMs
        self.uniqueGames = uniqueGames
        self.duplicates = duplicates
        self.archives = archives
        self.chds = chds
        self.totalSize = totalSize
        self.lastIndexed = lastIndexed
    }
}
