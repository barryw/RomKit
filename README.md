<div align="center">
  <img src="Images/romkit-logo.svg" alt="RomKit Logo" width="800">
  
  A high-performance Swift library and CLI for managing ROM collections, with comprehensive support for MAME and other ROM formats.
  
  [![CI/CD Pipeline](https://github.com/barryw/RomKit/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/barryw/RomKit/actions/workflows/ci-cd.yml)
  [![Latest Release](https://img.shields.io/github/v/release/barryw/RomKit?include_prereleases)](https://github.com/barryw/RomKit/releases/latest)
  [![Code Coverage](https://img.shields.io/codecov/c/github/barryw/RomKit)](https://codecov.io/gh/barryw/RomKit)
  [![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
  [![Platforms](https://img.shields.io/badge/Platforms-macOS%2013%2B%20%7C%20iOS%2016%2B-blue)](https://developer.apple.com)
  [![SPM Compatible](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
  [![License](https://img.shields.io/github/license/barryw/RomKit)](LICENSE)
  [![Documentation](https://img.shields.io/badge/docs-DocC-blue)](https://github.com/barryw/RomKit/wiki)
</div>

## Features

### Library
- **Industry-Standard Logiqx DAT Support** (Recommended)
- MAME XML format support (legacy)
- NoIntro and Redump format support
- High-performance ROM scanning and validation
- ROM set rebuilding with multiple styles (split, merged, non-merged)
- Comprehensive MAME inheritance handling (BIOS, devices, parent/clone)
- Native zlib compression support
- Optimized parsing with caching

### CLI Tool
- 🔍 **Analyze** - Verify ROM collections against DAT files
- 🔨 **Rebuild** - Reconstruct ROM sets from multiple sources
- 🗄️ **Index Management** - SQLite-based ROM indexing for fast multi-source lookups
- 🔎 **Smart Search** - Find ROMs by name or CRC32 with fuzzy matching
- 📊 **JSON Pipeline** - Unix-style composability for automation
- ⚡ **GPU Acceleration** - Metal acceleration for hash computation
- 📈 **Progress Tracking** - Real-time progress and ETA
- 🔁 **Deduplication** - Track and manage duplicate ROMs across sources

## DAT File Formats

### Recommended: Logiqx DAT Files

RomKit prioritizes **Logiqx DAT files** as they are the industry standard for ROM management. Benefits include:

- **70% smaller file size** compared to MAME XML
- **4x faster parsing** performance
- **Stable format** that hasn't changed in years
- **Universal compatibility** with all ROM managers
- **ROM-focused data** without unnecessary emulation details

```swift
import RomKit

let romkit = RomKit()

// Auto-detect format (will prefer Logiqx if detected)
try romkit.loadDAT(from: "/path/to/MAME.dat")

// Or explicitly load Logiqx format
try romkit.loadLogiqxDAT(from: "/path/to/MAME.dat")
```

### Legacy: MAME XML Files

MAME's native XML format is still supported but not recommended due to:
- Large file sizes (300+ MB)
- Slower parsing (20+ seconds)
- Contains excessive emulation details not needed for ROM management
- Format changes with each MAME release

```swift
// Explicitly load MAME XML format (not recommended)
try romkit.loadMAMEDAT(from: "/path/to/mame.xml")
```

## Where to Get DAT Files

### Logiqx DAT Files (Recommended)
- [Progetto-SNAPS DAT Files](https://www.progettosnaps.net/dats/)
- [Pleasuredome DAT-o-MATIC](http://www.pleasuredome.org.uk/datomatic/)
- [No-Intro DAT Files](https://datomatic.no-intro.org/)

### MAME XML (Legacy)
- Generate from MAME: `mame -listxml > mame.xml`

## Usage

### Basic ROM Scanning

```swift
import RomKit

// Initialize RomKit
let romkit = RomKit()

// Load a Logiqx DAT file (recommended)
try romkit.loadDAT(from: "/path/to/MAME.dat")

// Scan ROM directory
let scanResult = try await romkit.scanDirectory("/path/to/roms")

// Generate audit report
let report = romkit.generateAuditReport(from: scanResult)
print("Complete games: \(report.completeGames.count)")
print("Incomplete games: \(report.incompleteGames.count)")
```

### ROM Index Management

```swift
import RomKit

// Initialize index manager
let indexManager = try await ROMIndexManager()

// Add sources to index
try await indexManager.addSource(URL(fileURLWithPath: "/path/to/roms"))
try await indexManager.addSource(URL(fileURLWithPath: "/mnt/nas/roms"))

// Search for ROMs
if let rom = await indexManager.findROM(crc32: "8e68533e") {
    print("Found: \(rom.name) in \(rom.locations.count) location(s)")
}

// Search by name with fuzzy matching
let results = await indexManager.findByName(pattern: "%pacman%")
for result in results {
    print("\(result.name): \(result.crc32 ?? "unknown")")
}

// Find duplicates
let duplicates = await indexManager.findDuplicates(minCopies: 3)
print("Found \(duplicates.count) ROMs with 3+ copies")
```

### Generic Format Support

```swift
import RomKit

// Use the generic interface for multi-format support
let romkit = RomKitGeneric()

// Load any supported format
try romkit.loadDAT(from: "/path/to/file.dat")

// Check loaded format
print("Loaded format: \(romkit.currentFormat ?? "Unknown")")

// Scan and rebuild work the same regardless of format
let results = try await romkit.scan(directory: "/path/to/roms")
```

## Performance

### Parsing Performance Comparison

| Format | File Size | Parse Time | Games/sec |
|--------|-----------|------------|-----------|
| Logiqx DAT | 89 MB | ~4 seconds | 12,500 |
| MAME XML | 321 MB | ~16 seconds | 3,125 |

### Why Logiqx is Faster

Logiqx DAT files are optimized for ROM management:
- Only includes ROM checksums and metadata
- Skips display configuration, input mappings, driver status
- Simplified XML structure
- 70% smaller file size means less I/O

## Testing

RomKit includes a compressed MAME 0.278 Logiqx DAT file (10MB compressed, 78MB uncompressed) for comprehensive testing. This ensures:
- Tests run without external dependencies
- Consistent testing across all environments
- Real-world performance benchmarks
- CI/CD compatibility

The bundled DAT achieves 7.6:1 compression ratio, making it practical to include in the repository.

## Requirements

- Swift 5.9+
- macOS 13.0+ / iOS 16.0+
- Xcode 15.0+

## Installation

### CLI Tool

```bash
# Clone and build
git clone https://github.com/yourusername/RomKit.git
cd RomKit
swift build -c release --product romkit

# Install system-wide (optional)
sudo cp .build/release/romkit /usr/local/bin/

# Or use directly
./.build/release/romkit --help
```

### Swift Package Manager (Library)

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/RomKit.git", from: "1.0.0")
]
```

## CLI Usage

See [CLI Documentation](Documentation/CLI.md) for complete command reference.

### Quick Examples

```bash
# Analyze ROM collection
romkit analyze ~/mame/roms ~/mame/mame0256.xml --show-progress --gpu

# Index ROM directories for fast searching
romkit index add ~/mame/roms --show-progress
romkit index add /mnt/nas/roms
romkit index stats  # View index statistics

# Search indexed ROMs
romkit index find "street fighter" --fuzzy
romkit index find 8e68533e  # Search by CRC32

# Rebuild complete sets from multiple sources
romkit rebuild ~/mame/mame0256.xml ~/mame/output \
  --source ~/downloads \
  --source /mnt/nas/roms \
  --show-progress

# JSON pipeline for targeted rebuild
romkit analyze ~/mame/roms ~/mame/mame0256.xml --json | \
  jq '.incomplete + .broken' | \
  romkit rebuild ~/mame/mame0256.xml ~/mame/fixed --from-analysis -
```

## Contributing

Contributions are welcome! Please read our contributing guidelines before submitting PRs.

## License

MIT License - see LICENSE file for details
