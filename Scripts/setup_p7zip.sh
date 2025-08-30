#!/bin/bash
#
# Script to download and build p7zip for RomKit
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EXTERNAL_DIR="$PROJECT_ROOT/External"
P7ZIP_DIR="$EXTERNAL_DIR/p7zip"

echo "Setting up p7zip for RomKit..."

# Create External directory
mkdir -p "$EXTERNAL_DIR"
cd "$EXTERNAL_DIR"

# Check if p7zip already exists
if [ -d "$P7ZIP_DIR" ]; then
    echo "p7zip directory already exists. Removing old version..."
    rm -rf "$P7ZIP_DIR"
fi

# Download p7zip source
echo "Downloading p7zip source..."
P7ZIP_VERSION="23.01"
curl -L "https://github.com/p7zip-project/p7zip/archive/refs/tags/v${P7ZIP_VERSION}.tar.gz" -o p7zip.tar.gz

# Extract
echo "Extracting p7zip..."
tar -xzf p7zip.tar.gz
mv "p7zip-${P7ZIP_VERSION}" p7zip
rm p7zip.tar.gz

cd "$P7ZIP_DIR"

# Apply macOS-specific patches if on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Applying macOS patches..."
    
    # Create makefile for macOS
    cat > makefile.macosx_arm64 << 'EOF'
# Makefile for macOS ARM64 (Apple Silicon)

OPTFLAGS=-O2 -arch arm64

ALLFLAGS=${OPTFLAGS} \
    -DENV_UNIX \
    -D_FILE_OFFSET_BITS=64 \
    -D_LARGEFILE_SOURCE \
    -DNDEBUG \
    -D_REENTRANT \
    -DENV_UNIX \
    -D_7ZIP_LARGE_PAGES \
    -DBREAK_HANDLER \
    -DUNICODE \
    -D_UNICODE \
    -DUNIX_USE_WIN_FILE

CXX=c++ -std=c++17
CC=cc
LINK_SHARED=-bundle

LOCAL_LIBS=-lpthread
LIBS=$(LOCAL_LIBS)

OBJ_CRC32=$(OBJ_CRC32_C)
EOF

    # Use the macOS makefile
    cp makefile.macosx_arm64 makefile.machine
fi

# Build only the library components we need
echo "Building p7zip library..."
make -j$(sysctl -n hw.ncpu 2>/dev/null || nproc) 7z

# Create a simplified library for linking
echo "Creating static library for RomKit..."
mkdir -p "$P7ZIP_DIR/lib"

# Find all object files we need for 7z support
find . -name "*.o" -path "*/7z/*" -o -name "*.o" -path "*/Common/*" -o -name "*.o" -path "*/Compress/*" | while read obj; do
    ar -r "$P7ZIP_DIR/lib/lib7z.a" "$obj" 2>/dev/null || true
done

# Create pkg-config file for easier integration
cat > "$P7ZIP_DIR/lib/p7zip.pc" << EOF
prefix=$P7ZIP_DIR
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/CPP

Name: p7zip
Description: 7-Zip library
Version: $P7ZIP_VERSION
Libs: -L\${libdir} -l7z -lz -lbz2
Cflags: -I\${includedir}
EOF

echo "p7zip setup complete!"
echo ""
echo "Library location: $P7ZIP_DIR/lib/lib7z.a"
echo "Headers location: $P7ZIP_DIR/CPP"
echo ""
echo "You can now build RomKit with 7z support."