#!/bin/bash
#
# Build minimal lib7z for RomKit
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EXTERNAL_DIR="$PROJECT_ROOT/External"

echo "Building lib7z for RomKit..."

cd "$EXTERNAL_DIR"

# Clean previous build
rm -rf p7zip lib7z

# Copy from /tmp if we already cloned it
if [ -d "/tmp/p7zip" ]; then
    echo "Using existing p7zip clone..."
    cp -r /tmp/p7zip .
else
    echo "Cloning p7zip..."
    git clone --depth 1 https://github.com/p7zip-project/p7zip.git
fi

cd p7zip

# Build just the 7z format support we need
echo "Compiling 7z library..."

# Create output directory
mkdir -p ../lib7z/lib
mkdir -p ../lib7z/include

# Compile essential 7z sources
SOURCES=(
    # Core
    "C/7zAlloc.c"
    "C/7zArcIn.c"
    "C/7zBuf.c"
    "C/7zBuf2.c"
    "C/7zCrc.c"
    "C/7zCrcOpt.c"
    "C/7zDec.c"
    "C/7zFile.c"
    "C/7zStream.c"
    "C/Alloc.c"
    "C/CpuArch.c"
    "C/Delta.c"
    "C/LzFind.c"
    "C/LzmaDec.c"
    "C/Lzma2Dec.c"
    "C/Bcj2.c"
    "C/Bra.c"
    "C/Bra86.c"
    "C/BraIA64.c"
    "C/Ppmd7.c"
    "C/Ppmd7Dec.c"
    # Additional decoders
    "C/Sha256.c"
    "C/Threads.c"
)

CFLAGS="-O2 -fPIC -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE -DNDEBUG"

if [[ "$OSTYPE" == "darwin"* ]]; then
    # Set deployment target for macOS 14 compatibility
    export MACOSX_DEPLOYMENT_TARGET=14.0
    CFLAGS="$CFLAGS -arch arm64 -arch x86_64 -mmacosx-version-min=14.0"
fi

# Compile each source file
OBJECTS=()
for src in "${SOURCES[@]}"; do
    obj="${src%.c}.o"
    echo "Compiling $src..."
    cc $CFLAGS -I./C -I./CPP -c "$src" -o "$obj"
    OBJECTS+=("$obj")
done

# Create static library
echo "Creating static library..."
ar rcs ../lib7z/lib/lib7z.a "${OBJECTS[@]}"

# Copy headers
echo "Copying headers..."
cp C/*.h ../lib7z/include/

# Clean up object files
rm -f "${OBJECTS[@]}"

echo "lib7z build complete!"
echo "Library: $EXTERNAL_DIR/lib7z/lib/lib7z.a"
echo "Headers: $EXTERNAL_DIR/lib7z/include/"