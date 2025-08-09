#!/usr/bin/env swift

import Foundation
import SQLite3

// Test indexing directly with SQLite to diagnose the issue

let dbPath = "/Users/barry/Library/Caches/RomKit/romkit_index.db"
print("Checking database: \(dbPath)")

var db: OpaquePointer?
if sqlite3_open(dbPath, &db) == SQLITE_OK {
    print("Database opened successfully")
    
    // Check total ROMs
    var statement: OpaquePointer?
    let query = "SELECT COUNT(*) as count, COUNT(DISTINCT crc32) as unique_count FROM roms"
    
    if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
        if sqlite3_step(statement) == SQLITE_ROW {
            let totalROMs = sqlite3_column_int(statement, 0)
            let uniqueROMs = sqlite3_column_int(statement, 1)
            print("\nTotal ROMs in database: \(totalROMs)")
            print("Unique CRCs: \(uniqueROMs)")
        }
        sqlite3_finalize(statement)
    }
    
    // Check sources
    let sourceQuery = "SELECT path, rom_count, total_size FROM sources"
    if sqlite3_prepare_v2(db, sourceQuery, -1, &statement, nil) == SQLITE_OK {
        print("\nSources:")
        while sqlite3_step(statement) == SQLITE_ROW {
            if let pathPtr = sqlite3_column_text(statement, 0) {
                let path = String(cString: pathPtr)
                let romCount = sqlite3_column_int(statement, 1)
                let totalSize = sqlite3_column_int64(statement, 2)
                print("  Path: \(path)")
                print("    ROMs: \(romCount)")
                print("    Size: \(totalSize / 1024 / 1024) MB")
            }
        }
        sqlite3_finalize(statement)
    }
    
    // Check some sample ROMs
    let sampleQuery = "SELECT name, size, crc32, location_type, location_path FROM roms LIMIT 10"
    if sqlite3_prepare_v2(db, sampleQuery, -1, &statement, nil) == SQLITE_OK {
        print("\nSample ROMs:")
        while sqlite3_step(statement) == SQLITE_ROW {
            if let namePtr = sqlite3_column_text(statement, 0),
               let locationTypePtr = sqlite3_column_text(statement, 3),
               let locationPathPtr = sqlite3_column_text(statement, 4) {
                let name = String(cString: namePtr)
                let size = sqlite3_column_int64(statement, 1)
                let crc32Ptr = sqlite3_column_text(statement, 2)
                let crc32 = crc32Ptr != nil ? String(cString: crc32Ptr!) : "no-crc"
                let locType = String(cString: locationTypePtr)
                let locPath = String(cString: locationPathPtr)
                print("  \(name): \(size) bytes, CRC=\(crc32)")
                print("    Type: \(locType), Path: \(locPath)")
            }
        }
        sqlite3_finalize(statement)
    }
    
    // Check location_type distribution
    let typeQuery = "SELECT location_type, COUNT(*) FROM roms GROUP BY location_type"
    if sqlite3_prepare_v2(db, typeQuery, -1, &statement, nil) == SQLITE_OK {
        print("\nROMs by location type:")
        while sqlite3_step(statement) == SQLITE_ROW {
            if let typePtr = sqlite3_column_text(statement, 0) {
                let type = String(cString: typePtr)
                let count = sqlite3_column_int(statement, 1)
                print("  \(type): \(count)")
            }
        }
        sqlite3_finalize(statement)
    }
    
    // Check if we're missing location_entry for archives
    let archiveQuery = "SELECT COUNT(*) FROM roms WHERE location_type = 'archive' AND location_entry IS NULL"
    if sqlite3_prepare_v2(db, archiveQuery, -1, &statement, nil) == SQLITE_OK {
        if sqlite3_step(statement) == SQLITE_ROW {
            let nullEntries = sqlite3_column_int(statement, 0)
            if nullEntries > 0 {
                print("\n⚠️ WARNING: \(nullEntries) archive entries have NULL location_entry")
            }
        }
        sqlite3_finalize(statement)
    }
    
    sqlite3_close(db)
} else {
    print("Failed to open database")
}