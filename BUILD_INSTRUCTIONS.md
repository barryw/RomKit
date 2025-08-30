# Build Instructions

## Prerequisites

RomKit requires lib7z for 7-Zip archive support. The library is already built and included in the repository at `External/lib7z/lib/lib7z.a`.

## Building

```bash
swift build
```

## If lib7z is missing

If you get a linker error about missing lib7z, run:

```bash
./Scripts/build_lib7z_if_needed.sh
```

This will build lib7z from the included p7zip source code.

## Running Tests

```bash
swift test
```

## Note for Contributors

The lib7z.a binary is committed to the repository to make building easier. If you need to rebuild it from source, use the script mentioned above.