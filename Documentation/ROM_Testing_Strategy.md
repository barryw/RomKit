# ROM Testing Strategy

## Legal Compliance

**IMPORTANT**: We NEVER include copyrighted ROM files in the repository.

## Our Approach: Synthetic Test ROMs

Instead of using real ROM files, we generate synthetic test data that:
1. Matches the structure of real ROMs
2. Has correct checksums (CRC32/SHA1)
3. Tests all functionality without legal issues

## Test Coverage

### 1. ROM Verification Tests
- Verify synthetic ROMs match expected checksums
- Test missing ROM detection
- Test corrupted ROM detection
- Test ROM naming variations

### 2. Storage Format Tests

#### Split Sets
- Parent has unique ROMs only
- Clone has changed ROMs only
- BIOS/device ROMs separate
- **Most space-efficient when stored together**

#### Merged Sets
- Parent ZIP contains all clone ROMs
- No separate clone ZIPs
- BIOS still separate
- **Fewer files, moderate size**

#### Non-Merged Sets
- Each ZIP is self-contained
- Includes BIOS, parent, everything
- **Largest but simplest to manage**

### 3. Rebuild Tests
- Take loose ROM files
- Identify them via checksums
- Rebuild into proper sets
- Support all three formats

## Implementation

### Synthetic ROM Generation
```swift
// Generate deterministic test data
func generateSyntheticROM(name: String, size: Int, seed: UInt32) -> Data {
    var data = Data(count: size)
    var rng = seed
    for i in 0..<size {
        rng = (rng * 1664525) + 1013904223 // LCG
        data[i] = UInt8(rng >> 16)
    }
    return data
}
```

### Test Structure
```
testbios/
  ├── bios1.rom (1KB)
  └── bios2.rom (2KB)

parentgame/
  ├── parent1.rom (4KB)
  ├── parent2.rom (8KB)
  └── shared.rom (2KB)

clonegame/
  ├── clone1.rom (4KB)  [unique]
  ├── parent2.rom (8KB) [shared with parent]
  └── shared.rom (2KB)  [shared with parent]
```

## Storage Comparison

| Format | Parent Size | Clone Size | Total | Use Case |
|--------|------------|------------|-------|----------|
| **Split** | 14KB | 4KB | 18KB + BIOS | ROM managers |
| **Merged** | 18KB | N/A | 18KB + BIOS | Collectors |
| **Non-Merged** | 17KB | 17KB | 34KB | Simplicity |

## Testing With Real ROMs (Optional)

Users can test with their own ROMs:

```bash
# Set environment variable to ROM directory
export USER_ROM_PATH="/path/to/your/roms"

# Run tests
swift test --filter testWithRealROMs
```

## Benefits of This Approach

1. **100% Legal** - No copyrighted content
2. **Reproducible** - Same results everywhere
3. **CI/CD Compatible** - Works in automated testing
4. **Complete Coverage** - Tests all functionality
5. **Fast** - No large files to process

## What We Test

- ✅ ROM identification by checksum
- ✅ Parent/clone relationships
- ✅ BIOS dependencies
- ✅ Device ROM requirements
- ✅ All three storage formats
- ✅ Rebuild from loose files
- ✅ Missing ROM detection
- ✅ Duplicate ROM handling
- ✅ Archive compression/extraction

## What We DON'T Test

- ❌ Actual game ROM content
- ❌ Copyrighted material
- ❌ Real MAME ROM sets
- ❌ Commercial games

This approach gives us complete functional testing while staying 100% legal and repository-safe.