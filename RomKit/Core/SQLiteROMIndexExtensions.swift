//
//  SQLiteROMIndexExtensions.swift
//  RomKit
//
//  Extensions and helper methods for SQLiteROMIndex
//

import Foundation

// MARK: - SQLiteROMIndex Utility Extensions

extension SQLiteROMIndex {

    /// Format bytes into human-readable string
    func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unitIndex = 0

        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }

        return String(format: "%.2f %@", size, units[unitIndex])
    }

    /// Check if a file is likely a ROM based on extension
    func isROMFile(url: URL) -> Bool {
        let romExtensions = [
            "rom", "bin", "chd", "neo", "a78", "col", "int", "vec",
            "ws", "wsc", "nes", "sfc", "smc", "gb", "gbc", "gba",
            "nds", "3ds", "n64", "z64", "v64", "gen", "md", "smd",
            "gg", "sms", "pce", "iso", "cue", "ccd", "pbp"
        ]
        return romExtensions.contains(url.pathExtension.lowercased())
    }

    /// Extract SQL queries to constants for better organization
    struct Queries {
        static let createROMTable = """
            CREATE TABLE IF NOT EXISTS roms (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                size INTEGER NOT NULL,
                crc32 TEXT,
                sha1 TEXT,
                md5 TEXT,
                location_type TEXT NOT NULL,
                location_path TEXT NOT NULL,
                location_entry TEXT,
                last_modified INTEGER NOT NULL,
                last_verified INTEGER,
                UNIQUE(location_path, location_entry)
            )
            """

        static let createSourcesTable = """
            CREATE TABLE IF NOT EXISTS sources (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                path TEXT UNIQUE NOT NULL,
                last_scan INTEGER NOT NULL,
                rom_count INTEGER DEFAULT 0,
                total_size INTEGER DEFAULT 0
            )
            """

        static let createDuplicatesTable = """
            CREATE TABLE IF NOT EXISTS duplicates (
                crc32 TEXT NOT NULL,
                rom_id INTEGER NOT NULL,
                FOREIGN KEY(rom_id) REFERENCES roms(id) ON DELETE CASCADE
            )
            """

        static let insertROM = """
            INSERT OR REPLACE INTO roms
            (name, size, crc32, sha1, md5, location_type, location_path, location_entry, last_modified)
            VALUES (?, ?, ?, NULL, NULL, ?, ?, ?, ?)
            """

        static let findByCRC = """
            SELECT name, size, crc32, sha1, md5, location_type, location_path, location_entry, last_modified
            FROM roms
            WHERE crc32 = ? COLLATE NOCASE
            ORDER BY location_type ASC, last_modified DESC
            """

        static let findByName = """
            SELECT name, size, crc32, sha1, md5, location_type, location_path, location_entry, last_modified
            FROM roms
            WHERE name LIKE ? COLLATE NOCASE
            ORDER BY name, location_type ASC
            """

        static let findDuplicates = """
            SELECT crc32, COUNT(*) as count, GROUP_CONCAT(location_path || COALESCE('::' || location_entry, ''), '|||') as locations
            FROM roms
            WHERE crc32 IS NOT NULL AND crc32 != ''
            GROUP BY crc32
            HAVING count > 1
            ORDER BY count DESC
            """

        static let countDuplicates = """
            SELECT COUNT(*) FROM (
                SELECT crc32 FROM roms
                WHERE crc32 IS NOT NULL AND crc32 != ''
                GROUP BY crc32 HAVING COUNT(*) > 1
            )
            """
    }
}
