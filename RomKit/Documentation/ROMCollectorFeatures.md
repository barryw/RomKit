# ROM Collector Features Guide

RomKit includes powerful features specifically designed for ROM collectors and preservation enthusiasts. These tools help you manage, analyze, and maintain your ROM collections with professional-grade functionality.

## Overview

The ROM collector features include:

- **Fixdat Generation**: Create DAT files containing only your missing ROMs
- **Missing ROM Reports**: Comprehensive HTML and text reports of collection gaps
- **TorrentZip Support**: Convert ZIP files to standardized TorrentZip format
- **Collection Statistics**: Detailed analytics and health scoring
- **ROM Organization**: Rename and organize ROMs into folder structures

## Getting Started

```swift
import RomKit

let romkit = RomKit()

// Load your DAT file
try romkit.loadDAT(from: "/path/to/mame.dat")

// Scan your ROM directory
let scanResult = try await romkit.scanDirectory("/path/to/roms")
```

## Fixdat Generation

Generate DAT files containing only the ROMs you're missing from your collection.

### Basic Usage

```swift
// Generate a Fixdat in Logiqx XML format
try romkit.generateFixdat(
    from: scanResult,
    to: "/path/to/missing_roms.xml",
    format: .logiqxXML
)

// Generate in ClrMamePro format
try romkit.generateFixdat(
    from: scanResult,
    to: "/path/to/missing_roms.dat", 
    format: .clrmamepro
)
```

### Advanced Fixdat Generation

```swift
// Create custom metadata
let metadata = FixdatMetadata(
    name: "My Missing ROMs",
    description: "ROMs missing from my MAME collection",
    version: "2.0",
    author: "Collection Manager",
    comment: "Generated for acquisition list"
)

// Generate with custom metadata
let fixdat = FixdatGenerator.generateFixdat(
    from: scanResult,
    originalDAT: datFile,
    metadata: metadata
)

// Save in both formats
try fixdat.save(to: "/path/to/missing.xml", format: .logiqxXML)
try fixdat.save(to: "/path/to/missing.dat", format: .clrmamepro)
```

### Fixdat Format Details

**Logiqx XML Format** (Industry Standard):
- Compatible with ClrMamePro, RomCenter, and other tools
- Full XML structure with proper DTD reference
- Includes parent/clone relationships for MAME ROMs
- Supports all ROM attributes (merge, CRC, SHA1, etc.)

**ClrMamePro Format**:
- Native ClrMamePro format
- Compact text-based structure
- Fully compatible with ClrMamePro rebuilder
- Preserves all ROM metadata

## Missing ROM Reports

Generate comprehensive reports showing exactly what's missing from your collection.

### HTML Reports

```swift
// Generate with default options
let report = try romkit.generateMissingReport(from: scanResult)
let html = report.generateHTML()

// Save the report
try html.write(toFile: "/path/to/missing_report.html", 
               atomically: true, encoding: .utf8)
```

### Text Reports

```swift
let report = try romkit.generateMissingReport(from: scanResult)
let text = report.generateText()

// Print to console
print(text)

// Save to file
try text.write(toFile: "/path/to/missing_report.txt",
               atomically: true, encoding: .utf8)
```

### Report Options

```swift
let options = MissingReportOptions(
    groupByParent: true,        // Group clones with parents
    includeDevices: false,      // Exclude device ROMs
    includeBIOS: true,          // Include BIOS ROMs  
    includeClones: true,        // Include clone games
    showAlternatives: true,     // Show alternative ROM sets
    sortBy: .missingCount       // Sort by number of missing ROMs
)

let report = try romkit.generateMissingReport(
    from: scanResult,
    options: options
)
```

### Report Features

**HTML Report Features**:
- Interactive progress bars showing completion
- Color-coded game status (complete/partial/missing)
- Detailed ROM information with checksums
- Parent/clone grouping with expandable sections
- Responsive design for mobile viewing
- Professional styling with gradients

**Text Report Features**:
- Formatted ASCII tables
- Complete summary statistics  
- Detailed missing ROM lists with checksums
- Parent/clone relationships
- Size information in human-readable format

## Collection Statistics

Analyze your collection with detailed statistics and health scoring.

### Basic Statistics

```swift
let stats = try romkit.generateStatistics(from: scanResult)

print("Collection Completion: \(stats.completionPercentage)%")
print("Health Score: \(stats.healthScore)%")
print("Complete Games: \(stats.completeGames)/\(stats.totalGames)")
print("ROM Completion: \(stats.foundROMs)/\(stats.totalROMs)")
```

### Detailed Breakdowns

```swift
// By year
for (year, yearStats) in stats.byYear.sorted(by: { $0.key < $1.key }) {
    let percentage = Double(yearStats.complete) / Double(yearStats.total) * 100
    print("\(year): \(yearStats.complete)/\(yearStats.total) (\(percentage)%)")
}

// By manufacturer
let topManufacturers = stats.byManufacturer
    .sorted { $0.value.total > $1.value.total }
    .prefix(10)

for (manufacturer, mfgStats) in topManufacturers {
    print("\(manufacturer): \(mfgStats.complete)/\(mfgStats.total)")
}
```

### Statistics Reports

```swift
// Generate HTML statistics report
let htmlStats = stats.generateHTMLReport()
try htmlStats.write(toFile: "/path/to/statistics.html",
                   atomically: true, encoding: .utf8)

// Generate text statistics report  
let textStats = stats.generateTextReport()
try textStats.write(toFile: "/path/to/statistics.txt",
                   atomically: true, encoding: .utf8)
```

### Health Score Calculation

The health score is calculated based on:
- Collection completion percentage (primary factor)
- Issues detected in the collection
- Missing BIOS/device dependencies
- Orphaned clone ROMs without parents

**Score Ranges**:
- 90-100%: Excellent collection health
- 70-89%: Good collection health  
- 50-69%: Fair collection health
- Below 50%: Poor collection health

## TorrentZip Support

Convert ZIP files to TorrentZip format for standardized, reproducible archives.

### Single File Conversion

```swift
// Convert in place
try romkit.torrentZip("/path/to/game.zip")

// Convert to new file
try romkit.torrentZip(
    "/path/to/game.zip",
    outputPath: "/path/to/game_torrentzipped.zip"
)
```

### Directory Conversion

```swift
// Convert all ZIPs in directory
try await romkit.torrentZipDirectory("/path/to/roms")

// With progress tracking
try await romkit.torrentZipDirectory("/path/to/roms") { progress in
    print("Converting \(progress.current)/\(progress.total): \(progress.currentFile)")
}
```

### TorrentZip Verification

```swift
// Check if a ZIP is TorrentZip compliant
let isTorrentZip = try romkit.isTorrentZip("/path/to/game.zip")

if isTorrentZip {
    print("✅ File is TorrentZip compliant")
} else {
    print("❌ File is not TorrentZip compliant")
}
```

### TorrentZip Benefits

- **Reproducible**: Same content produces identical archives
- **Standardized**: Consistent file ordering and compression
- **Verification**: Easy to verify archive integrity
- **Sharing**: Ideal for ROM preservation communities

## ROM Organization

Rename and organize your ROM files according to various schemes.

### ROM Renaming

```swift
// Dry run to see what would be renamed
let result = try await romkit.renameROMs(
    in: "/path/to/roms",
    dryRun: true,
    preserveOriginals: false
)

print(result.summary)

// Actually rename the files
let finalResult = try await romkit.renameROMs(
    in: "/path/to/roms", 
    dryRun: false,
    preserveOriginals: true  // Keep originals as backup
)
```

### Collection Organization

```swift
// Organize by manufacturer
let organizeResult = try await romkit.organizeCollection(
    from: "/path/to/source/roms",
    to: "/path/to/organized/roms",
    style: .byManufacturer,
    moveFiles: false  // Copy instead of move
)

print("Organized \(organizeResult.organized.count) files")
print("Created \(organizeResult.folders.count) folders")
```

### Organization Styles

```swift
// Available organization styles
let styles: [OrganizationStyle] = [
    .flat,              // All files in one directory
    .byManufacturer,    // Group by manufacturer
    .byYear,            // Group by release year
    .byGenre,           // Group by game genre
    .byAlphabet,        // Group by first letter (A-Z)
    .byParentClone,     // Separate parents and clones
    .byStatus,          // Group by completion status
    .custom { game in   // Custom grouping function
        return game.metadata.category ?? "Unknown"
    }
]
```

### Progress Tracking

```swift
let result = try await romkit.organizeCollection(
    from: sourceDir,
    to: destDir,
    style: .byManufacturer
) { progress in
    let percent = Double(progress.current) / Double(progress.total) * 100
    print("Progress: \(String(format: "%.1f", percent))% - \(progress.currentFile)")
}
```

## Complete Workflow Example

Here's a complete example showing how to use all the ROM collector features together:

```swift
import RomKit

func analyzeROMCollection() async throws {
    let romkit = RomKit()
    
    // Step 1: Load DAT file
    print("📋 Loading DAT file...")
    try romkit.loadDAT(from: "/path/to/mame.dat")
    
    // Step 2: Scan ROM directory
    print("🔍 Scanning ROM collection...")
    let scanResult = try await romkit.scanDirectory("/path/to/roms")
    
    // Step 3: Generate collection statistics
    print("📊 Generating statistics...")
    let stats = try romkit.generateStatistics(from: scanResult)
    
    print("Collection Status:")
    print("- Total Games: \(stats.totalGames)")
    print("- Complete: \(stats.completeGames) (\(String(format: "%.1f", stats.completionPercentage))%)")
    print("- Health Score: \(String(format: "%.0f", stats.healthScore))%")
    
    // Step 4: Generate missing ROM report
    if stats.missingROMs > 0 {
        print("📋 Generating missing ROM report...")
        let missingReport = try romkit.generateMissingReport(
            from: scanResult,
            options: MissingReportOptions(
                groupByParent: true,
                includeClones: true,
                showAlternatives: true
            )
        )
        
        // Save HTML report
        try missingReport.generateHTML().write(
            toFile: "/path/to/reports/missing_roms.html",
            atomically: true, 
            encoding: .utf8
        )
        
        // Generate Fixdat for missing ROMs
        print("🔧 Generating Fixdat...")
        try romkit.generateFixdat(
            from: scanResult,
            to: "/path/to/fixdats/missing_roms.xml",
            format: .logiqxXML
        )
    }
    
    // Step 5: Generate comprehensive statistics report  
    print("📈 Generating statistics report...")
    try stats.generateHTMLReport().write(
        toFile: "/path/to/reports/collection_statistics.html",
        atomically: true,
        encoding: .utf8
    )
    
    // Step 6: Organize ROM collection
    print("🗂️ Organizing ROM collection...")
    let organizeResult = try await romkit.organizeCollection(
        from: "/path/to/roms",
        to: "/path/to/organized_roms", 
        style: .byManufacturer,
        moveFiles: false
    )
    
    print("✅ Organization complete!")
    print("- Files organized: \(organizeResult.organized.count)")
    print("- Folders created: \(organizeResult.folders.count)")
    
    // Step 7: Convert to TorrentZip format
    print("💾 Converting to TorrentZip format...")
    try await romkit.torrentZipDirectory("/path/to/organized_roms") { progress in
        print("Converting \(progress.current)/\(progress.total): \(progress.currentFile)")
    }
    
    print("🎉 ROM collection analysis complete!")
}

// Run the analysis
try await analyzeROMCollection()
```

## Best Practices

### DAT File Management
- Always use the most recent DAT files for your systems
- Prefer Logiqx XML format for maximum compatibility
- Keep multiple versions for historical comparison

### Collection Organization
- Run dry-run operations first to preview changes
- Always backup your ROMs before organizing
- Use descriptive folder structures for easy navigation

### Fixdat Usage
- Generate Fixdats regularly to track collection progress
- Share Fixdats with other collectors for trading
- Use version numbers to track acquisition progress

### Performance Tips
- Use concurrent operations for large collections
- Enable progress tracking for long-running operations
- Consider using SSD storage for better performance

### Quality Assurance
- Regularly run collection statistics to monitor health
- Address missing BIOS/device ROMs first
- Verify TorrentZip compliance for preservation

## Troubleshooting

### Common Issues

**"Format detection failed"**
- Ensure DAT file is in supported format (Logiqx XML, ClrMamePro, MAME XML)
- Check file encoding (should be UTF-8)
- Verify file is not corrupted

**"Cannot open archive"**
- ZIP file may be corrupted
- File may not be a valid ZIP archive
- Try re-downloading or re-creating the archive

**Empty statistics/reports**
- Ensure DAT file was loaded successfully
- Verify scan directory contains ROM files
- Check that ROM files match DAT entries

**TorrentZip conversion fails**
- Ensure input file is a valid ZIP archive
- Check file permissions for read/write access
- Verify sufficient disk space for conversion

### Getting Help

For additional support:
- Check the RomKit documentation
- Review the test files for usage examples
- Report issues on the project repository

---

*This guide covers the essential ROM collector features in RomKit. For complete API documentation, see the DocC documentation included with the framework.*