#!/bin/bash

# Script to build lib7z if it doesn't exist
# This ensures the library is available on any machine that clones the repo

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
LIB7Z_DIR="$PROJECT_ROOT/External/lib7z"
LIB7Z_LIB="$LIB7Z_DIR/lib/lib7z.a"
P7ZIP_DIR="$PROJECT_ROOT/External/p7zip"

# Check if lib7z.a exists
if [ -f "$LIB7Z_LIB" ]; then
    echo "lib7z.a already exists at $LIB7Z_LIB"
    exit 0
fi

echo "Building lib7z..."

# Create directories
mkdir -p "$LIB7Z_DIR/lib"
mkdir -p "$LIB7Z_DIR/include"

# Check if p7zip source exists
if [ ! -d "$P7ZIP_DIR" ]; then
    echo "Error: p7zip source not found at $P7ZIP_DIR"
    echo "The p7zip source should be committed to the repository"
    exit 1
fi

# Build the library
cd "$P7ZIP_DIR/C" || exit 1

# Compile all necessary source files
echo "Compiling 7z library files..."
cc -c -O2 -I. \
    7zAlloc.c \
    7zArcIn.c \
    7zBuf.c \
    7zBuf2.c \
    7zCrc.c \
    7zCrcOpt.c \
    7zDec.c \
    7zFile.c \
    7zStream.c \
    Aes.c \
    AesOpt.c \
    Alloc.c \
    Bcj2.c \
    Bra.c \
    Bra86.c \
    BraIA64.c \
    CpuArch.c \
    Delta.c \
    LzmaDec.c \
    Lzma2Dec.c \
    Ppmd7.c \
    Ppmd7Dec.c \
    Sha256.c \
    Xz.c \
    XzCrc64.c \
    XzDec.c 2>/dev/null

# Create static library
echo "Creating static library..."
ar rcs "$LIB7Z_LIB" *.o

# Copy headers
echo "Copying headers..."
cp *.h "$LIB7Z_DIR/include/"

# Clean up object files
rm -f *.o

echo "lib7z built successfully at $LIB7Z_LIB"