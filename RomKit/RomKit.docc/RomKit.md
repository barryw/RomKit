# ``RomKit``

A powerful Swift framework for managing, validating, and rebuilding ROM collections using DAT files from various cataloging projects.

## Overview

RomKit provides comprehensive tools for ROM collectors and preservation enthusiasts to manage their ROM collections efficiently. Whether you're working with MAME arcade games, console cartridges cataloged by No-Intro, or disc-based games from Redump, RomKit offers a unified Swift API to validate, audit, and organize your collection.

### Key Features

- **Multi-format DAT Support**: Parse DAT files from Logiqx XML, MAME XML, No-Intro, and Redump formats
- **Intelligent Scanning**: Recursively scan directories and archives to identify ROMs
- **Checksum Validation**: Verify ROM integrity using CRC32, SHA1, and MD5 checksums
- **Detailed Auditing**: Generate comprehensive reports on collection completeness
- **Flexible Rebuilding**: Organize ROMs in split, merged, or non-merged sets
- **Performance Optimized**: Concurrent scanning, GPU-accelerated hashing, and efficient caching
- **Archive Support**: Transparently handle ZIP archives and other compressed formats

## Getting Started

### Installation

Add RomKit to your Swift package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/RomKit.git", from: "1.0.0")
]
```

### Quick Start

Here's a simple example to get you started with RomKit:

```swift
import RomKit

// Initialize RomKit
let romkit = RomKit()

// Load a DAT file (auto-detects format)
try romkit.loadDAT(from: "/path/to/mame.dat")

// Scan your ROM directory
let scanResult = try await romkit.scanDirectory("/path/to/roms")

// Generate an audit report
let report = romkit.generateAuditReport(from: scanResult)
print("Complete games: \(report.completeGames.count)")
print("Missing games: \(report.missingGames.count)")

// Rebuild ROM sets in split format
try await romkit.rebuild(
    from: "/path/to/source",
    to: "/path/to/destination",
    style: .split
)
```

## DAT File Formats

RomKit supports multiple DAT file formats used by different preservation communities:

### Logiqx XML (Recommended)
The industry-standard format supported by most ROM management tools. RomKit automatically detects and prefers this format.

```swift
try romkit.loadLogiqxDAT(from: "/path/to/logiqx.dat")
```

### MAME XML
Native MAME format with comprehensive device and BIOS information for arcade emulation.

```swift
try romkit.loadMAMEDAT(from: "/path/to/mame.xml")
```

### No-Intro
Specialized format for cartridge-based console games with detailed preservation metadata.

### Redump
Format designed for disc-based games, including support for CUE/BIN and CHD formats.

## Scanning and Validation

RomKit's scanning engine provides deep inspection of your ROM collection:

```swift
let scanResult = try await romkit.scanDirectory("/path/to/roms")

// Analyze scan results
for game in scanResult.foundGames {
    switch game.status {
    case .complete:
        print("✅ \(game.game.name): Complete!")
    case .incomplete:
        print("⚠️ \(game.game.name): Missing \(game.missingRoms.count) ROMs")
        for rom in game.missingRoms {
            print("  - Missing: \(rom.name)")
        }
    case .missing:
        print("❌ \(game.game.name): Not found")
    }
}

// Identify unknown files
for unknownFile in scanResult.unknownFiles {
    print("❓ Unknown file: \(unknownFile)")
}
```

## Rebuild Styles

RomKit supports three standard rebuild styles for organizing ROM collections:

### Split Sets
Each game gets its own archive. Clone games only contain ROMs unique to that clone, referencing the parent for shared ROMs.

**Pros**: Minimal storage usage, clear parent/clone relationships
**Cons**: Requires parent ROMs to run clones

### Merged Sets
Clone games are merged into their parent's archive. One archive contains the parent and all its clones.

**Pros**: Convenient organization, fewer files
**Cons**: Larger archives, must extract specific games

### Non-Merged Sets
Each game archive is completely self-contained with all required ROMs, including those shared with parents.

**Pros**: Each game is independently playable
**Cons**: Maximum storage usage due to duplication

```swift
// Rebuild in your preferred style
try await romkit.rebuild(from: source, to: destination, style: .split)
try await romkit.rebuild(from: source, to: destination, style: .merged)
try await romkit.rebuild(from: source, to: destination, style: .nonMerged)
```

## Audit Reports

Generate detailed reports on your collection's completeness:

```swift
let report = romkit.generateAuditReport(from: scanResult)

// Access detailed statistics
print("Total games: \(report.statistics.totalGames)")
print("Complete: \(report.statistics.completeGames)")
print("Incomplete: \(report.statistics.incompleteGames)")
print("Missing: \(report.statistics.missingGames)")

// Get specific information
for incomplete in report.incompleteGames {
    print("\(incomplete.gameName):")
    print("  Missing ROMs: \(incomplete.missingRoms.joined(separator: ", "))")
    print("  Bad ROMs: \(incomplete.badRoms.joined(separator: ", "))")
}
```

## Performance Optimization

RomKit is designed for performance with large ROM collections:

### Concurrent Operations
```swift
// Specify custom concurrency level
let romkit = RomKit(concurrencyLevel: 8)
```

### GPU Acceleration
When available, RomKit automatically uses Metal GPU acceleration for checksum calculations, providing significant speedups for large files.

### Caching
Parsed DAT files are automatically cached to speed up subsequent operations.

## Error Handling

RomKit provides detailed error information for robust error handling:

```swift
do {
    try romkit.loadDAT(from: datPath)
    let result = try await romkit.scanDirectory(romPath)
    // Process results
} catch RomKitError.datFileNotLoaded {
    print("Please load a DAT file first")
} catch RomKitError.invalidPath(let path) {
    print("Invalid path: \(path)")
} catch RomKitError.scanFailed(let reason) {
    print("Scan failed: \(reason)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Advanced Features

### Multi-Source Scanning
RomKit can scan multiple directories and intelligently merge results, finding the best source for each ROM based on availability and integrity.

### BIOS and Device Dependencies
Full support for MAME's complex BIOS and device ROM dependencies, ensuring all required files are identified.

### Archive Management
Transparent handling of compressed archives with support for nested extraction and creation.

### Duplicate Detection
Intelligent duplicate detection across multiple sources, helping you identify and manage redundant files.

## Topics

### Essentials
- ``RomKit/RomKit``
- ``RomKit/loadDAT(from:)``
- ``RomKit/scanDirectory(_:)``
- ``RomKit/generateAuditReport(from:)``

### DAT Loading
- ``RomKit/loadLogiqxDAT(from:)``
- ``RomKit/loadMAMEDAT(from:)``

### Rebuilding
- ``RomKit/rebuild(from:to:style:)``
- ``RebuildStyle``
- ``RebuildStyle/split``
- ``RebuildStyle/merged``
- ``RebuildStyle/nonMerged``

### Results and Reports
- ``ScanResult``
- ``AuditReport``
- ``ScannedGame``
- ``AuditStatistics``

### Error Handling
- ``RomKitError``
- ``RomKitError/datFileNotLoaded``
- ``RomKitError/invalidPath(_:)``
- ``RomKitError/scanFailed(_:)``
- ``RomKitError/rebuildFailed(_:)``