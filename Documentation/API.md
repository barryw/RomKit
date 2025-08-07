# RomKit API Documentation

RomKit provides a Swift library for ROM management with comprehensive support for MAME, NoIntro, and other ROM formats.

## Core Classes

### RomKit

The main interface for ROM management operations.

```swift
import RomKit

let romkit = RomKit()
```

#### Methods

##### `loadDAT(from:)`
Loads a DAT file (auto-detects format).

```swift
try romkit.loadDAT(from: URL(fileURLWithPath: "/path/to/mame.dat"))
```

##### `loadLogiqxDAT(from:)`
Explicitly loads a Logiqx format DAT file (recommended).

```swift
try romkit.loadLogiqxDAT(from: URL(fileURLWithPath: "/path/to/logiqx.dat"))
```

##### `scanDirectory(_:)`
Scans a directory for ROM files and validates against loaded DAT.

```swift
let result = try await romkit.scanDirectory("/path/to/roms")
print("Found \(result.completeGames.count) complete games")
```

##### `generateAuditReport(from:)`
Creates an audit report from scan results.

```swift
let report = romkit.generateAuditReport(from: scanResult)
print("Missing ROMs: \(report.missingROMs.count)")
```

##### `rebuildSet(from:to:style:)`
Rebuilds ROM sets in specified format.

```swift
try await romkit.rebuildSet(
    from: sourceURL,
    to: destinationURL,
    style: .split  // or .merged, .nonMerged
)
```

---

### ROMIndexManager

Manages SQLite-based ROM indexing for fast multi-source lookups.

```swift
import RomKit

// Initialize with optional database path
let indexManager = try await ROMIndexManager(
    databasePath: URL(fileURLWithPath: "~/.romkit/index.db")
)
```

#### Methods

##### `addSource(_:showProgress:)`
Adds a directory to the index.

```swift
try await indexManager.addSource(
    URL(fileURLWithPath: "/path/to/roms"),
    showProgress: true
)
```

##### `removeSource(_:showProgress:)`
Removes a source from the index.

```swift
try await indexManager.removeSource(romDirectory, showProgress: true)
```

##### `refreshSources(_:showProgress:)`
Refreshes indexed sources to detect changes.

```swift
// Refresh all sources
try await indexManager.refreshSources(nil, showProgress: true)

// Refresh specific sources
try await indexManager.refreshSources([source1, source2], showProgress: false)
```

##### `findROM(crc32:)`
Finds a ROM by CRC32 checksum.

```swift
if let rom = await indexManager.findROM(crc32: "8e68533e") {
    print("Found: \(rom.name)")
    print("Locations: \(rom.locations.count)")
    for location in rom.locations {
        print("  - \(location.path)")
    }
}
```

##### `findByName(pattern:limit:)`
Searches for ROMs by name with SQL wildcards.

```swift
// Fuzzy search
let results = await indexManager.findByName(pattern: "%street fighter%", limit: 20)

// Exact search
let exact = await indexManager.findByName(pattern: "pacman.zip")
```

##### `findBestSource(for:)`
Finds the best available source for a ROM (prefers local files).

```swift
let rom = ROM(name: "pacman.6e", size: 4096, crc: "c1e6ab10", status: .good)
if let source = await indexManager.findBestSource(for: rom) {
    print("Best source: \(source.location.displayPath)")
}
```

##### `findDuplicates(minCopies:)`
Finds ROMs that exist in multiple locations.

```swift
let duplicates = await indexManager.findDuplicates(minCopies: 3)
for dup in duplicates {
    print("\(dup.crc32): \(dup.count) copies, \(formatBytes(dup.potentialSpaceSaved)) saveable")
}
```

##### `analyzeIndex()`
Generates comprehensive index analysis.

```swift
let analysis = await indexManager.analyzeIndex()
print("Total ROMs: \(analysis.totalROMs)")
print("Unique ROMs: \(analysis.uniqueROMs)")
print("Duplication rate: \(analysis.duplicatePercentage)%")
print("Space wasted: \(formatBytes(analysis.spaceWasted))")

// Show recommendations
for recommendation in analysis.recommendations {
    print("• \(recommendation)")
}
```

##### `verify(removeStale:showProgress:)`
Verifies all indexed files still exist.

```swift
let result = try await indexManager.verify(
    removeStale: true,
    showProgress: true
)
print("Valid: \(result.valid), Stale: \(result.stale), Removed: \(result.removed)")
```

---

## Data Types

### ROM
Represents a single ROM file.

```swift
public struct ROM {
    public let name: String
    public let size: UInt64
    public let crc: String?
    public let md5: String?
    public let sha1: String?
    public let sha256: String?
    public let status: Status?
    
    public enum Status: String {
        case good = "good"
        case bad = "bad"
        case nodump = "nodump"
    }
}
```

### Game
Represents a game/machine with its ROMs.

```swift
public struct Game {
    public let name: String
    public let description: String
    public let year: String?
    public let manufacturer: String?
    public let roms: [ROM]
    public let parent: String?      // Parent set name
    public let romOf: String?       // ROM parent
    public let cloneOf: String?     // Clone parent
    public let sampleOf: String?    // Sample parent
}
```

### ROMInfo
Information about a ROM and all its locations.

```swift
public struct ROMInfo {
    public let crc32: String
    public let name: String
    public let size: UInt64
    public let locations: [ROMLocationInfo]
    
    public var copyCount: Int { locations.count }
    public var hasDuplicates: Bool { locations.count > 1 }
}
```

### ROMSearchResult
Search result from index queries.

```swift
public struct ROMSearchResult {
    public let name: String
    public let crc32: String?
    public let size: UInt64
    public let location: String
}
```

### IndexAnalysis
Comprehensive index statistics and analysis.

```swift
public struct IndexAnalysis: Codable {
    public let totalROMs: Int
    public let uniqueROMs: Int
    public let totalSize: UInt64
    public let duplicateGroups: Int
    public let totalDuplicates: Int
    public let spaceWasted: UInt64
    public let sources: [SourceInfo]
    public let recommendations: [String]
    
    public var duplicatePercentage: Double
    public var averageDuplicationFactor: Double
}
```

---

## Archive Handling

### ArchiveHandler Protocol

Protocol for implementing archive format support.

```swift
public protocol ArchiveHandler {
    var supportedExtensions: [String] { get }
    
    func canHandle(url: URL) -> Bool
    func listContents(of url: URL) throws -> [ArchiveEntry]
    func extract(entry: ArchiveEntry, from url: URL) throws -> Data
    func extractAll(from url: URL, to destination: URL) throws
    func create(at url: URL, with entries: [(name: String, data: Data)]) throws
}
```

### Built-in Handlers

#### FastZIPArchiveHandler
High-performance ZIP handler using native zlib.

```swift
let handler = FastZIPArchiveHandler()
let entries = try handler.listContents(of: zipURL)
for entry in entries {
    print("\(entry.path): CRC32=\(entry.crc32 ?? "unknown")")
}
```

#### ParallelZIPArchiveHandler
Multi-threaded ZIP processing for large archives.

```swift
let handler = ParallelZIPArchiveHandler()
try await handler.extractAllAsync(from: zipURL, to: destinationURL)
```

---

## Hash Computation

### HashComputer

Provides various hash computation methods with optional GPU acceleration.

```swift
public class HashComputer {
    // CPU-based hashing
    public static func computeCRC32(data: Data) -> String
    public static func computeMD5(data: Data) -> String
    public static func computeSHA1(data: Data) -> String
    public static func computeSHA256(data: Data) -> String
    
    // GPU-accelerated hashing (Metal)
    public static func computeCRC32GPU(data: Data) async -> String?
    public static func computeSHA256GPU(data: Data) async -> String?
}
```

Usage:

```swift
let data = try Data(contentsOf: romURL)

// CPU computation
let crc32 = HashComputer.computeCRC32(data: data)

// GPU computation for large files
if data.count > 10_000_000 {  // 10MB threshold
    if let gpuCRC = await HashComputer.computeCRC32GPU(data: data) {
        print("GPU CRC32: \(gpuCRC)")
    }
}
```

---

## Error Handling

### RomKitError

All RomKit operations can throw typed errors:

```swift
public enum RomKitError: Error {
    case datNotLoaded
    case invalidDATFormat(String)
    case fileNotFound(String)
    case invalidROMFormat(String)
    case indexError(String)
    case verificationFailed(String)
    case rebuildFailed(String)
}
```

Example error handling:

```swift
do {
    try romkit.loadDAT(from: datURL)
    let result = try await romkit.scanDirectory(romDirectory)
} catch RomKitError.datNotLoaded {
    print("Please load a DAT file first")
} catch RomKitError.invalidDATFormat(let message) {
    print("Invalid DAT format: \(message)")
} catch {
    print("Unexpected error: \(error)")
}
```

---

## Performance Considerations

### Memory Management

For large collections (40,000+ games):

```swift
// Use streaming parser for MAME XML
let parser = StreamingMAMEParser()
parser.parse(url: mameXMLURL) { game in
    // Process each game individually
    processGame(game)
}
```

### Parallel Processing

```swift
// Configure parallel operations
let config = RebuildConfiguration(
    parallelOperations: ProcessInfo.processInfo.activeProcessorCount,
    useGPU: true,
    verifyCRC: true
)

try await romkit.rebuild(with: config)
```

### Index Optimization

```swift
// Optimize index after large imports
try await indexManager.optimize()

// Export statistics for analysis
try await indexManager.exportStatistics(to: statsURL)
```

---

## Examples

### Complete ROM Audit

```swift
import RomKit

func auditROMs() async throws {
    let romkit = RomKit()
    
    // Load DAT file
    try romkit.loadDAT(from: URL(fileURLWithPath: "mame.dat"))
    
    // Scan ROM directory
    let scanResult = try await romkit.scanDirectory("/path/to/roms")
    
    // Generate report
    let report = romkit.generateAuditReport(from: scanResult)
    
    // Output results
    print("=== ROM Audit Report ===")
    print("Complete: \(report.completeGames.count)")
    print("Incomplete: \(report.incompleteGames.count)")
    print("Missing: \(report.missingGames.count)")
    print("Broken: \(report.brokenGames.count)")
    
    // Export to JSON
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let jsonData = try encoder.encode(report)
    try jsonData.write(to: URL(fileURLWithPath: "audit_report.json"))
}
```

### Multi-Source Rebuild

```swift
import RomKit

func rebuildFromMultipleSources() async throws {
    let romkit = RomKit()
    let indexManager = try await ROMIndexManager()
    
    // Load DAT
    try romkit.loadDAT(from: URL(fileURLWithPath: "mame.dat"))
    
    // Index all sources
    let sources = [
        "/path/to/roms1",
        "/path/to/roms2",
        "/mnt/nas/arcade"
    ]
    
    for source in sources {
        try await indexManager.addSource(URL(fileURLWithPath: source))
    }
    
    // Rebuild using index
    let games = romkit.allGames()
    var rebuilt = 0
    var failed = 0
    
    for game in games {
        var complete = true
        var gameROMs: [(String, Data)] = []
        
        for rom in game.roms {
            if let source = await indexManager.findBestSource(for: rom) {
                let data = try Data(contentsOf: URL(fileURLWithPath: source.location.displayPath))
                gameROMs.append((rom.name, data))
            } else {
                complete = false
                break
            }
        }
        
        if complete {
            let outputPath = URL(fileURLWithPath: "/output/\(game.name).zip")
            let handler = FastZIPArchiveHandler()
            try handler.create(at: outputPath, with: gameROMs)
            rebuilt += 1
        } else {
            failed += 1
        }
    }
    
    print("Rebuilt: \(rebuilt), Failed: \(failed)")
}
```

---

## License

MIT License - see LICENSE file for details