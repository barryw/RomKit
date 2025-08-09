# RomKit CLI Documentation

RomKit is a high-performance command-line tool for managing, analyzing, and rebuilding ROM collections, with special optimization for MAME ROM sets.

## Installation

```bash
# Build from source
swift build -c release --product romkit
cp .build/release/romkit /usr/local/bin/

# Or run directly
./.build/debug/romkit --help
```

## Commands

### `analyze` - Verify ROM Collections

Analyzes a directory of ROM files against a DAT file to determine completeness.

```bash
romkit analyze <rom-directory> <dat-file> [options]
```

#### Options:
- `-v, --verbose` - Show detailed information for each game
- `--gpu` - Use GPU acceleration for hash computation (for files >10MB)
- `--show-progress` - Display progress during analysis
- `-o, --output <file>` - Export results to JSON file
- `--json` - Output analysis as JSON to stdout (for piping)

#### Examples:

```bash
# Basic analysis
romkit analyze ~/mame/roms ~/mame/mame0256.xml

# Detailed analysis with progress
romkit analyze ~/mame/roms ~/mame/mame0256.xml --verbose --show-progress

# Export results to JSON for processing
romkit analyze ~/mame/roms ~/mame/mame0256.xml --json > analysis.json

# Pipeline to rebuild command
romkit analyze ~/mame/roms ~/mame/mame0256.xml --json | \
  romkit rebuild ~/mame/mame0256.xml ~/mame/output --from-analysis -
```

#### Output:
- **Complete**: All required ROM files present with correct CRC
- **Incomplete**: Some ROM files missing  
- **Broken**: ROM files present but with incorrect CRC
- **Missing**: Games with no ROM files found
- **Unrecognized**: Files not referenced in the DAT

---

### `rebuild` - Rebuild ROM Sets

Rebuilds complete ROM sets by searching for required ROMs across multiple source directories.

```bash
romkit rebuild <dat-file> <output-directory> --source <dir1> [--source <dir2>...] [options]
```

#### Options:
- `--source <dir>` - Source directories to search for ROMs (required, multiple allowed)
- `-s, --style <style>` - Rebuild style: `split`, `merged`, or `non-merged` (default: split)
- `-m, --missing` - Only rebuild missing or incomplete sets
- `-v, --verify/--no-verify` - Verify CRC32 checksums during rebuild (default: verify)
- `--gpu` - Use GPU acceleration for hash computation
- `--show-progress` - Show progress during rebuild
- `--cache-file <file>` - SQLite index cache file location
- `-d, --dry-run` - Perform a dry run without copying files
- `-p, --parallel <n>` - Number of parallel operations (default: 4)
- `--from-analysis <file>` - Rebuild based on JSON analysis (use `-` for stdin)

#### Examples:

```bash
# Basic rebuild from multiple sources
romkit rebuild mame0256.xml output/ --source ~/roms --source /mnt/nas/roms

# Rebuild only missing sets with progress
romkit rebuild mame0256.xml output/ --source ~/roms --missing --show-progress

# Dry run to see what would be rebuilt
romkit rebuild mame0256.xml output/ --source ~/roms --dry-run

# Rebuild from analysis pipeline
romkit analyze current/ mame.dat --json | \
  romkit rebuild mame.dat fixed/ --source backups/ --from-analysis -
```

#### Rebuild Styles:
- **split**: Each game in its own ZIP (default)
- **merged**: Clone sets merged with parent
- **non-merged**: All ROMs including parent ROMs in each set

---

### `verify` - Verify ROM Integrity

Verifies ROM files against their expected checksums from a DAT file.

```bash
romkit verify <rom-directory> <dat-file> [options]
```

#### Options:
- `--show-progress` - Display verification progress
- `--stop-on-error` - Stop verification on first error
- `--gpu` - Use GPU acceleration for large files

#### Examples:

```bash
# Verify all ROMs
romkit verify ~/mame/roms ~/mame/mame0256.xml --show-progress

# Quick verification (stop on first error)
romkit verify ~/mame/roms ~/mame/mame0256.xml --stop-on-error
```

---

### `fixdat` - Generate Fixdat Files

Creates DAT files containing only the ROMs missing from your collection.

```bash
romkit fixdat <rom-directory> <dat-file> <output-path> [options]
```

#### Options:
- `-f, --format <format>` - Output format: `logiqx` or `clrmamepro` (default: logiqx)
- `--include-devices` - Include device ROMs in fixdat
- `--include-bios` - Include BIOS ROMs in fixdat
- `--include-clones` - Include clone games in fixdat
- `--show-progress` - Display progress during analysis
- `-v, --verbose` - Show detailed information

#### Examples:

```bash
# Generate Logiqx XML fixdat
romkit fixdat ~/roms ~/mame.dat ~/missing.xml

# Generate ClrMamePro format
romkit fixdat ~/roms ~/mame.dat ~/missing.dat --format clrmamepro

# Include all ROM types
romkit fixdat ~/roms ~/mame.dat ~/missing.xml \
  --include-devices --include-bios --include-clones
```

---

### `missing` - Generate Missing ROM Reports

Creates detailed HTML or text reports showing missing ROMs.

```bash
romkit missing <rom-directory> <dat-file> [options]
```

#### Options:
- `-o, --output <file>` - Output file path (without extension)
- `-f, --format <format>` - Report format: `html`, `text`, or `both` (default: both)
- `--group-by-parent` - Group clone games with parents
- `--include-devices` - Include device ROMs
- `--include-bios` - Include BIOS ROMs
- `--include-clones` - Include clone games
- `--show-alternatives` - Show alternative ROM sources
- `--sort-by <field>` - Sort by: `name`, `missing`, `manufacturer`, `year`
- `--show-progress` - Display progress
- `-v, --verbose` - Verbose output

#### Examples:

```bash
# Generate both HTML and text reports
romkit missing ~/roms ~/mame.dat -o missing_report

# HTML only, grouped by parent
romkit missing ~/roms ~/mame.dat -o report -f html --group-by-parent

# Sort by most missing ROMs
romkit missing ~/roms ~/mame.dat --sort-by missing
```

---

### `stats` - Collection Statistics

Generates comprehensive statistics and health reports for your collection.

```bash
romkit stats <rom-directory> <dat-file> [options]
```

#### Options:
- `-o, --output <file>` - Output file path (without extension)
- `-f, --format <format>` - Format: `html`, `text`, `console`, or `all` (default: console)
- `--by-year` - Show breakdown by year
- `--by-manufacturer` - Show breakdown by manufacturer
- `--show-chd` - Show CHD statistics
- `--show-issues` - Show detected issues
- `--show-progress` - Display progress
- `-v, --verbose` - Verbose output

#### Examples:

```bash
# Display statistics in console
romkit stats ~/roms ~/mame.dat

# Generate HTML report with full details
romkit stats ~/roms ~/mame.dat -o stats -f html \
  --by-year --by-manufacturer --show-issues

# Quick health check
romkit stats ~/roms ~/mame.dat | grep "Health Score"
```

---

### `organize` - Organize ROM Collection

Organizes and renames ROM files according to various schemes.

```bash
romkit organize <source> <dat-file> [options]
```

#### Options:
- `-d, --destination <dir>` - Destination directory for organized ROMs
- `-s, --style <style>` - Organization style: `flat`, `manufacturer`, `year`, `genre`, `alphabet`, `parent-clone`, `status`
- `--rename` - Rename ROMs according to DAT file
- `--move` - Move files instead of copying
- `--clean-names` - Remove region codes and version numbers
- `-n, --dry-run` - Preview changes without applying
- `--preserve-originals` - Keep original files when renaming
- `--show-progress` - Display progress
- `-v, --verbose` - Verbose output

#### Examples:

```bash
# Organize by manufacturer
romkit organize ~/roms ~/mame.dat -d ~/organized -s manufacturer

# Rename ROMs in place
romkit organize ~/roms ~/mame.dat --rename --dry-run

# Full organization with renaming
romkit organize ~/roms ~/mame.dat -d ~/organized \
  -s year --rename --clean-names --show-progress
```

---

### `index` - Manage ROM Index

Manages the SQLite index used for fast ROM lookups across multiple directories.

```bash
romkit index <subcommand> [options]
```

#### Subcommands:
- `add <directory>` - Add directory to index
- `remove <directory>` - Remove directory from index
- `refresh [directory]` - Refresh all or specific directory
- `list` - Show indexed directories with statistics
- `stats` - Display detailed index statistics
- `verify` - Check for stale entries
- `clear` - Clear entire index

#### Examples:

```bash
# Add directories to index
romkit index add ~/mame/roms
romkit index add /mnt/nas/arcade

# View indexed sources
romkit index list

# Refresh after adding new ROMs
romkit index refresh ~/mame/roms

# View statistics
romkit index stats
```

---

## JSON Output Format

The `--json` flag outputs structured data for pipeline processing:

```json
{
  "metadata": {
    "dat_file": "mame0256.xml",
    "analyzed_at": "2024-01-15T10:30:00Z",
    "source_directory": "/home/user/roms",
    "total_games": 45861
  },
  "complete": {
    "pacman": {
      "status": "complete",
      "roms": [
        {
          "name": "pacman.6e",
          "crc32": "c1e6ab10",
          "size": 4096,
          "location": "pacman.zip"
        }
      ]
    }
  },
  "incomplete": { ... },
  "broken": { ... },
  "missing": ["game1", "game2"],
  "unrecognized": [
    {
      "path": "unknown.zip",
      "size": 1234
    }
  ]
}
```

---

## Performance Tips

### For MAME Collections

1. **Initial Indexing**: Build the index once for faster subsequent operations
   ```bash
   romkit rebuild mame.dat temp/ --source ~/roms --cache-file ~/.romkit/index.db --dry-run
   ```

2. **GPU Acceleration**: Only beneficial for large files (>10MB). Most MAME ROMs are <1MB, so `--gpu` won't help.

3. **Parallel Operations**: Increase parallel operations for faster rebuilds
   ```bash
   romkit rebuild mame.dat output/ --source ~/roms --parallel 8
   ```

### For Large Files

1. **Use GPU**: For CD/DVD images and modern console ROMs
   ```bash
   romkit analyze ~/ps2/games dat.xml --gpu --show-progress
   ```

2. **Cache Results**: Save analysis for later use
   ```bash
   romkit analyze ~/games dat.xml --json > analysis.json
   ```

---

## Pipeline Examples

### Find and Fix Broken ROMs

```bash
# Find broken games
romkit analyze roms/ mame.dat --json | \
  jq -r '.broken | keys[]' > broken.txt

# Rebuild only broken games
cat broken.txt | \
  xargs -I {} romkit rebuild mame.dat output/ --source backups/ --game {}
```

### Progressive Rebuild

```bash
# Analyze current state
romkit analyze output/ mame.dat --json > current.json

# Find what needs work
jq '.incomplete + .broken | keys' current.json > todo.txt

# Rebuild from multiple sources
romkit rebuild mame.dat output/ \
  --source ~/downloads \
  --source /mnt/nas/roms \
  --source ~/backups \
  --from-analysis current.json
```

### Verify After Rebuild

```bash
# Rebuild and verify in one pipeline
romkit rebuild mame.dat output/ --source roms/ && \
romkit analyze output/ mame.dat --json | \
jq -e '.incomplete == {} and .broken == {}'
```

---

## Environment Variables

- `ROMKIT_CACHE_DIR` - Default cache directory (default: `~/.cache/romkit`)
- `ROMKIT_INDEX_DB` - Default index database path
- `ROMKIT_PARALLEL` - Default parallelism level
- `NO_COLOR` - Disable colored output

---

## File Support

### ROM Files
- Individual: `.rom`, `.bin`, `.chd`, `.neo`, `.a78`, `.col`, `.int`, `.vec`, `.ws`, `.wsc`
- Archives: `.zip` (full support with CRC extraction)

### DAT Formats
- **Logiqx XML** (recommended - 70% smaller, 4x faster)
- **MAME XML** (legacy - larger files, slower parsing)
- **ClrMamePro** (basic support)

---

## Exit Codes

- `0` - Success
- `1` - General error
- `2` - Invalid arguments
- `3` - File not found
- `4` - Verification failed
- `5` - Rebuild incomplete

---

## Troubleshooting

### "Bad file descriptor" errors
- Occurs with too many open files
- Solution: Increase ulimit: `ulimit -n 4096`

### Slow analysis on network drives
- Network I/O is slower than local
- Solution: Use `--cache-file` to cache results locally

### GPU not providing speedup
- GPU only helps with files >10MB
- Most MAME ROMs are <1MB
- Solution: Don't use `--gpu` for MAME

### Out of memory with large DAT files
- Some DAT files have 40,000+ games
- Solution: Use streaming parser (automatic for MAME DATs)

---

## License

[Your License Here]

## Contributing

[Contributing guidelines]

## Support

[Support information]