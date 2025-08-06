# MAME ROM Format Documentation

## Important: Use Logiqx DAT Files for ROM Management

**For ROM management, we strongly recommend using Logiqx DAT files instead of MAME XML files:**

- **70% smaller** file size (89MB vs 321MB)
- **4x faster** parsing (4 seconds vs 16+ seconds)
- **Industry standard** format used by all ROM managers
- **Stable format** that hasn't changed in years
- **ROM-focused** data without unnecessary emulation details

Download Logiqx DAT files from:
- [Progetto-SNAPS](https://www.progettosnaps.net/dats/)
- [Pleasuredome DAT-o-MATIC](http://www.pleasuredome.org.uk/datomatic/)

Only use MAME XML files if you need the full emulation metadata (display settings, input configurations, etc.)

## The Fucking Mess Explained

Yes, MAME's ROM organization is confusing as hell. Here's why and how it actually works:

## Core Concepts

### 1. ROM Inheritance Hierarchy

MAME ROMs are organized in a complex inheritance tree:

```
BIOS ROMs (e.g., neogeo.zip)
    ↓
Device ROMs (e.g., namco51.zip) 
    ↓
Parent ROMs (e.g., puckman.zip)
    ↓
Clone ROMs (e.g., pacman.zip)
```

### 2. Key XML Attributes

- **romof**: Points to the parent ROM set that contains shared ROM files
- **cloneof**: Indicates this is a variant/clone of another game
- **sampleof**: Points to parent for shared audio samples
- **bios**: Specifies which BIOS is required (e.g., bios="neogeo")
- **device_ref**: Lists required device ROM sets
- **merge**: Indicates if a ROM can be merged with parent

### 3. ROM Set Types

#### Non-Merged Sets
- Every ZIP contains EVERYTHING needed to run
- Includes BIOS, devices, parent ROMs - all duplicated
- Pros: Simple, self-contained
- Cons: ~2x the storage space

#### Split Sets
- Parent has its ROMs
- Clones have only changed ROMs
- BIOS and devices are separate
- Pros: Space efficient
- Cons: Need multiple files to run

#### Merged Sets
- Parent ZIP contains all clone ROMs too
- BIOS and devices still separate
- Pros: Most space efficient
- Cons: Can't separate individual clones

## Real Example: Metal Slug

To run Metal Slug, you actually need ROMs from multiple sources:

1. **mslug.zip** - The game's specific ROMs (9 files)
2. **neogeo.zip** - Neo-Geo BIOS ROMs (31 files)
3. Various device ROMs if referenced

Total: 40+ ROM files from different ZIPs!

## XML Structure

```xml
<!-- BIOS Set -->
<machine name="neogeo" isbios="yes">
    <rom name="sfix.sfix" size="131072" crc="c2ea0cfd"/>
    <!-- ... more BIOS ROMs ... -->
</machine>

<!-- Game requiring BIOS -->
<machine name="mslug" bios="neogeo">
    <rom name="201-p1.p1" size="2097152" crc="08d8daa5"/>
    <!-- ... game-specific ROMs ... -->
    <device_ref name="z80"/>
    <device_ref name="ym2610"/>
</machine>

<!-- Clone with parent -->
<machine name="pacman" cloneof="puckman" romof="puckman">
    <!-- Only contains changed ROMs -->
    <rom name="pacman.6e" size="4096" crc="c1e6ab10"/>
    <!-- Merged ROMs reference parent -->
    <rom name="pm1_chg1.5e" merge="pm1_chg1.5e" size="4096"/>
</machine>
```

## How ROMs Are Located

When MAME loads a game, it searches for ROMs in this order:

1. The game's own ZIP
2. Parent ROM set (if romof is specified)
3. BIOS ROM set (if bios is specified)
4. Device ROM sets (for each device_ref)

## RomKit Implementation

RomKit handles this through:

1. **MAMEBIOSManager** - Tracks BIOS and device dependencies
2. **Parent/Clone tracking** - Via cloneOf and romOf attributes
3. **Merge handling** - The "merge" attribute on individual ROMs
4. **Device references** - Collected from device_ref elements

### Key Methods

```swift
// Get all ROMs needed for a game
biosManager.getAllRequiredROMs(for: "mslug")
// Returns ROMs from: mslug.zip, neogeo.zip, device sets

// Check dependencies
biosManager.getDependencies(for: "pacman")  
// Returns: ["puckman"] (the parent)

// Check if something is a BIOS
biosManager.isBIOS("neogeo")  // true
```

## The Bottom Line

MAME's ROM organization is complex because it's trying to:
1. Document arcade hardware accurately
2. Save storage space through deduplication
3. Handle complex hardware relationships (BIOS, devices, clones)

It's not pretty, but it works and has preserved arcade history for 25+ years.

## References

- [MAME Official Docs - About ROMs and Sets](https://docs.mamedev.org/usingmame/aboutromsets.html)
- [RomVault Wiki - Merge Types](https://wiki.romvault.com/doku.php?id=merge_types)
- [PleasureDome - MAME Sets](https://pleasuredome.github.io/pleasuredome/mame/)