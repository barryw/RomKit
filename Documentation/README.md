# RomKit Documentation

Welcome to the RomKit documentation! This directory contains comprehensive guides for using RomKit's library and CLI tools.

## Documentation Index

### Core Documentation

- **[API Documentation](API.md)** - Complete Swift API reference for the RomKit library
- **[CLI Documentation](CLI.md)** - Command-line interface usage and examples
- **[ROM Collector Features](../RomKit/Documentation/ROMCollectorFeatures.md)** - Advanced features for ROM collectors

### Technical Documentation

- **[MAME ROM Format](MAME_ROM_Format.md)** - Understanding MAME's ROM structure and inheritance
- **[Testing Strategy](Testing_Strategy.md)** - Comprehensive testing approach
- **[ROM Testing Strategy](ROM_Testing_Strategy.md)** - Specific ROM testing methodologies
- **[Performance Optimization](Performance_Optimization.md)** - Performance improvements and benchmarks
- **[Memory Safety Fixes](Memory_Safety_Fixes.md)** - Memory management and safety improvements

## Quick Start

### Library Usage

```swift
import RomKit

// Initialize RomKit
let romkit = RomKit()

// Load a DAT file (auto-detects format, prefers Logiqx)
try romkit.loadDAT(from: "/path/to/mame.dat")

// Scan your ROM directory
let scanResult = try await romkit.scanDirectory("/path/to/roms")

// Generate audit report
let report = romkit.generateAuditReport(from: scanResult)
print("Complete games: \(report.completeGames.count)")
```

### CLI Usage

```bash
# Analyze ROM collection
romkit analyze ~/mame/roms ~/mame/mame.dat --show-progress

# Rebuild ROM sets
romkit rebuild ~/mame/mame.dat ~/mame/output \
  --source ~/downloads \
  --source /mnt/nas/roms \
  --show-progress
```

## Key Features

### 🚀 Performance
- Industry-standard Logiqx DAT support (70% smaller, 4x faster than MAME XML)
- GPU acceleration for hash computation
- Concurrent scanning and processing
- SQLite-based indexing for fast lookups

### 📊 ROM Collection Management
- **Fixdat Generation** - Create DAT files for missing ROMs
- **Missing ROM Reports** - HTML and text reports with detailed statistics
- **Collection Statistics** - Health scoring and completion tracking
- **ROM Organization** - Rename and organize by manufacturer, year, genre, etc.
- **TorrentZip Support** - Standardized ZIP format for preservation

### 🔧 Advanced Features
- Multi-source ROM rebuilding
- Parent/clone relationship handling
- BIOS and device dependency management
- Duplicate ROM detection and tracking
- JSON pipeline support for automation

## Supported Formats

| Format | Status | Notes |
|--------|--------|-------|
| Logiqx XML | ✅ Recommended | Industry standard, optimal performance |
| MAME XML | ✅ Supported | Legacy format, slower parsing |
| ClrMamePro | ✅ Supported | Native ClrMamePro format |
| No-Intro | ✅ Supported | Cartridge-based systems |
| Redump | ✅ Supported | Disc-based systems |

## Performance Benchmarks

| Operation | Performance | Notes |
|-----------|------------|-------|
| Logiqx DAT Parse | ~12,500 games/sec | 48,588 games in 4 seconds |
| MAME XML Parse | ~3,125 games/sec | 48,588 games in 16 seconds |
| ROM Scanning | ~1,000 files/sec | With concurrent processing |
| Hash Computation | ~500 MB/sec | With GPU acceleration |

## System Requirements

- **Swift**: 5.9 or later
- **macOS**: 13.0+ / iOS 16.0+
- **Xcode**: 15.0+ (for development)
- **Memory**: 512MB minimum, 2GB recommended
- **Storage**: Varies by ROM collection size

## Getting Help

- **Issues**: [GitHub Issues](https://github.com/barryw/RomKit/issues)
- **Discussions**: [GitHub Discussions](https://github.com/barryw/RomKit/discussions)
- **Wiki**: [GitHub Wiki](https://github.com/barryw/RomKit/wiki)

## Contributing

Contributions are welcome! Please read the contributing guidelines before submitting PRs.

## License

RomKit is released under the MIT License. See the [LICENSE](../LICENSE) file for details.