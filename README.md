# RomKit

A high-performance Swift library for managing ROM collections, with comprehensive support for MAME and other ROM formats.

## Features

- **Industry-Standard Logiqx DAT Support** (Recommended)
- MAME XML format support (legacy)
- NoIntro and Redump format support
- High-performance ROM scanning and validation
- ROM set rebuilding with multiple styles (split, merged, non-merged)
- Comprehensive MAME inheritance handling (BIOS, devices, parent/clone)
- Native zlib compression support
- Optimized parsing with caching

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

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/RomKit.git", from: "1.0.0")
]
```

## Contributing

Contributions are welcome! Please read our contributing guidelines before submitting PRs.

## License

MIT License - see LICENSE file for details