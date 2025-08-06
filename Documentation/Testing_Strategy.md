# RomKit Testing Strategy

## Bundled Test Data

RomKit includes a compressed MAME 0.278 Logiqx DAT file for comprehensive, self-contained testing.

### Benefits

1. **No External Dependencies**: Tests run without environment variables or external files
2. **Consistent Testing**: All developers and CI/CD use the same test data
3. **Real-World Data**: 48,588 actual MAME games for realistic testing
4. **Efficient Storage**: 10MB compressed (7.6:1 ratio), 78MB decompressed
5. **Fast Performance**: ~4.5 second parse time on modern hardware

### Test Data Location

```
RomKitTests/TestData/Full/MAME_0278.dat.gz
```

### Using the Bundled DAT

```swift
// Load the bundled DAT file
let data = try TestDATLoader.loadFullMAMEDAT()

// Parse with Logiqx parser (primary format)
let parser = LogiqxDATParser()
let datFile = try parser.parse(data: data)
```

## Test Organization

### Core Test Suites

1. **BundledDATTests**: Tests using the bundled compressed DAT
2. **LogiqxPrimaryFormatTests**: Verifies Logiqx is the preferred format
3. **DATFormatComparisonTests**: Compares format performance
4. **MAMEInheritanceTests**: Tests BIOS/device/parent/clone relationships
5. **RealROMTests**: Optional tests with actual ROM files (requires ROMKIT_TEST_ROM_PATH)

### Running Tests

```bash
# Run all tests
swift test

# Run specific test suites
swift test --filter BundledDATTests
swift test --filter LogiqxPrimaryFormatTests

# Run with real ROMs (optional)
export ROMKIT_TEST_ROM_PATH="/path/to/roms"
swift test --filter RealROMTests
```

## Performance Benchmarks

Using the bundled MAME 0.278 DAT:

| Metric | Value |
|--------|-------|
| Compressed Size | 10 MB |
| Decompressed Size | 78 MB |
| Compression Ratio | 7.6:1 |
| Parse Time | ~4.5 seconds |
| Games Parsed | 48,588 |
| Parse Rate | ~10,800 games/sec |

## Migration from Environment Variables

Previously, tests required:
- `ROMKIT_TEST_DAT_PATH` - Path to MAME XML file
- `ROMKIT_TEST_ROM_PATH` - Path to ROM directory

Now:
- DAT file testing uses bundled data (no env vars needed)
- Only `ROMKIT_TEST_ROM_PATH` needed for optional ROM scanning tests

## Test Data Updates

To update the bundled DAT file:

1. Download latest Logiqx DAT from [Progetto-SNAPS](https://www.progettosnaps.net/dats/)
2. Compress with gzip: `gzip -9 "MAME 0.XXX.dat"`
3. Replace `RomKitTests/TestData/Full/MAME_0278.dat.gz`
4. Update version references in tests

## CI/CD Integration

The bundled DAT makes CI/CD trivial:

```yaml
# GitHub Actions example
- name: Run Tests
  run: swift test
  # No setup needed - tests are self-contained!
```

## Test Coverage

The bundled DAT provides comprehensive coverage:

- 48,588 games
- 700+ BIOS sets
- 1,000+ device sets
- Complex parent/clone relationships
- All ROM merge scenarios
- Real checksums and metadata

This ensures RomKit is tested against real-world complexity, not simplified mock data.