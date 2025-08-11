//
//  ROMDetector.swift
//  RomKit
//
//  Intelligent ROM file detection without relying solely on extensions
//

import Foundation

public struct ROMDetector {

    // MARK: - Magic Bytes / Headers

    private static let romSignatures: [(magic: [UInt8], offset: Int, name: String)] = [
        // NES: "NES\x1A"
        ([0x4E, 0x45, 0x53, 0x1A], 0, "NES"),

        // Game Boy/Color: Nintendo logo at 0x104-0x133
        ([0xCE, 0xED, 0x66, 0x66], 0x104, "Game Boy"),

        // N64: Various formats
        ([0x80, 0x37, 0x12, 0x40], 0, "N64 (z64)"),
        ([0x37, 0x80, 0x40, 0x12], 0, "N64 (v64)"),
        ([0x40, 0x12, 0x37, 0x80], 0, "N64 (n64)"),

        // PlayStation PSX executables
        ([0x50, 0x53, 0x2D, 0x58], 0, "PSX"),

        // Sega Genesis/Mega Drive: "SEGA" at various offsets
        ([0x53, 0x45, 0x47, 0x41], 0x100, "Genesis/MD"),
        ([0x53, 0x45, 0x47, 0x41], 0x101, "Genesis/MD"),
        ([0x53, 0x45, 0x47, 0x41], 0x200, "Genesis/MD"),  // Also check 0x200

        // Super Nintendo SMC header
        ([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xAA, 0xBB, 0x04], 0x1F0, "SNES SMC"),

        // Atari 2600: Usually starts with 0x78 (SEI instruction)
        ([0x78], 0, "Atari 2600"),

        // Atari 7800: "ATARI7800"
        ([0x41, 0x54, 0x41, 0x52, 0x49, 0x37, 0x38, 0x30, 0x30], 1, "Atari 7800"),

        // Lynx: "LYNX"
        ([0x4C, 0x59, 0x4E, 0x58], 0, "Lynx"),

        // PC Engine/TurboGrafx: Often has specific patterns
        ([0x40, 0x00, 0x00, 0x00], 0x1FF0, "PC Engine"),

        // Neo Geo: "NEO-GEO"
        ([0x4E, 0x45, 0x4F, 0x2D, 0x47, 0x45, 0x4F], 0x100, "Neo Geo")
    ]

    // MARK: - File Size Validation

    private static let validROMSizes: Set<Int> = {
        var sizes = Set<Int>()

        // Common power-of-2 sizes from 1KB to 64MB
        var size = 1024
        while size <= 64 * 1024 * 1024 {
            sizes.insert(size)
            size *= 2
        }

        // Common non-power-of-2 sizes
        sizes.insert(40960)     // 40KB (some NES)
        sizes.insert(49152)     // 48KB
        sizes.insert(384 * 1024) // 384KB
        sizes.insert(768 * 1024) // 768KB
        sizes.insert(1536 * 1024) // 1.5MB
        sizes.insert(3 * 1024 * 1024) // 3MB
        sizes.insert(5 * 1024 * 1024) // 5MB
        sizes.insert(6 * 1024 * 1024) // 6MB

        // Add sizes with headers (512 byte SMC header)
        for baseSize in [512 * 1024, 1024 * 1024, 2 * 1024 * 1024, 4 * 1024 * 1024] {
            sizes.insert(baseSize + 512)
        }

        return sizes
    }()

    // MARK: - Detection Methods

    /// Check if a file is likely a ROM based on its content
    public static func isLikelyROM(at url: URL) -> Bool {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? fileHandle.close() }

        // Get file size
        let fileSize = (try? fileHandle.seekToEnd()) ?? 0
        fileHandle.seek(toFileOffset: 0)

        // Check file size constraints
        if !isValidROMSize(Int(fileSize)) {
            // Don't reject based on size alone, but it's a negative signal
        }

        // Read first 8KB for analysis
        let headerData = fileHandle.readData(ofLength: 8192)
        guard !headerData.isEmpty else { return false }

        // Check for known ROM signatures
        if hasROMSignature(headerData, fileSize: Int(fileSize)) {
            return true
        }

        // Check for text file indicators (strong negative signals)
        if isLikelyTextFile(headerData) {
            return false
        }

        // Check for other binary file formats we should exclude
        if isKnownNonROMFormat(headerData) {
            return false
        }

        // Check entropy (binary files have high entropy)
        if !hasSufficientEntropy(headerData) {
            return false
        }

        // If it's a binary file with reasonable size, consider it a potential ROM
        return true
    }

    /// Check if data contains known ROM signatures
    private static func hasROMSignature(_ data: Data, fileSize: Int) -> Bool {
        let bytes = [UInt8](data)

        for (magic, offset, name) in romSignatures where offset + magic.count <= bytes.count {
            let slice = Array(bytes[offset..<(offset + magic.count)])
            if slice == magic {
                // print("DEBUG: Found \(name) signature at offset \(offset)")
                return true
            }
        }

        // Special checks for SNES (no header)
        if fileSize >= 0x8000 && (fileSize & 0x7FFF) == 0 {
            // Check for valid SNES header at 0x7FC0 or 0xFFC0
            if data.count >= 0x7FD5 {
                let loRomHeader = Array(bytes[0x7FC0..<min(0x7FD5, bytes.count)])
                if isValidSNESHeader(loRomHeader) {
                    return true
                }
            }
        }

        return false
    }

    /// Check if the file size matches common ROM sizes
    private static func isValidROMSize(_ size: Int) -> Bool {
        // Allow any file under 64MB
        if size > 64 * 1024 * 1024 {
            return false
        }

        // Very small files unlikely to be ROMs
        if size < 256 {
            return false
        }

        // Check if it's a known good size
        if validROMSizes.contains(size) {
            return true
        }

        // Allow files that are close to power-of-2 sizes (within 512 bytes for headers)
        var testSize = 1024
        while testSize <= 64 * 1024 * 1024 {
            if abs(size - testSize) <= 512 {
                return true
            }
            testSize *= 2
        }

        // For flexibility, accept any size - let the DAT matching decide
        return true
    }

    /// Check if data looks like a text file
    private static func isLikelyTextFile(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(1024))

        // Check for UTF-8 BOM
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return true
        }

        // Check for high proportion of printable ASCII
        let printableCount = bytes.filter { byte in
            (byte >= 0x20 && byte <= 0x7E) || byte == 0x09 || byte == 0x0A || byte == 0x0D
        }.count

        let printableRatio = Double(printableCount) / Double(bytes.count)
        if printableRatio > 0.95 {
            return true
        }

        // Check for null bytes (binary indicator)
        let nullCount = bytes.filter { $0 == 0 }.count
        if nullCount > bytes.count / 4 {
            // Lots of nulls, probably binary
            return false
        }

        return false
    }

    /// Check for known non-ROM binary formats
    private static func isKnownNonROMFormat(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(16))
        guard bytes.count >= 4 else { return false }

        // PDF
        if bytes.starts(with: [0x25, 0x50, 0x44, 0x46]) { return true }

        // PNG
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true }

        // JPEG
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return true }

        // GIF
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return true }

        // ZIP (but we want to keep these for ROM archives)
        // if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return true }

        // ELF executable
        if bytes.starts(with: [0x7F, 0x45, 0x4C, 0x46]) { return true }

        // Mach-O executable
        if bytes.starts(with: [0xCF, 0xFA, 0xED, 0xFE]) { return true }
        if bytes.starts(with: [0xCE, 0xFA, 0xED, 0xFE]) { return true }

        // Windows PE executable
        if bytes.starts(with: [0x4D, 0x5A]) {
            // Could be DOS stub for ROM, need more checking
            // For now, don't exclude
        }

        return false
    }

    /// Check if data has sufficient entropy to be a ROM
    private static func hasSufficientEntropy(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(1024))
        guard !bytes.isEmpty else { return false }

        // Count unique bytes
        let uniqueBytes = Set(bytes).count
        let uniqueRatio = Double(uniqueBytes) / Double(min(bytes.count, 256))

        // Binary files typically have higher entropy
        return uniqueRatio > 0.1  // At least 10% unique bytes
    }

    /// Check for valid SNES header
    private static func isValidSNESHeader(_ header: [UInt8]) -> Bool {
        guard header.count >= 21 else { return false }

        // Check for reasonable values in header fields
        // Checksum complement at offset 0x1C-0x1D + checksum at 0x1E-0x1F should = 0xFFFF
        if header.count >= 32 {
            let complement = UInt16(header[0x1C]) | (UInt16(header[0x1D]) << 8)
            let checksum = UInt16(header[0x1E]) | (UInt16(header[0x1F]) << 8)
            if complement ^ checksum == 0xFFFF {
                return true
            }
        }

        return false
    }

    // MARK: - Public API

    /// Determine if a file should be indexed as a potential ROM
    public static func shouldIndexFile(at url: URL) -> Bool {
        // First check common ROM extensions for fast path
        let ext = url.pathExtension.lowercased()
        if ConcurrentScanner.defaultExtensions.contains(ext) {
            return true
        }

        // For files with unknown extensions, do content analysis
        // Skip obviously non-ROM extensions
        let skipExtensions = Set(["txt", "md", "json", "xml", "html", "css", "js",
                                 "pdf", "doc", "docx", "xls", "xlsx",
                                 "jpg", "jpeg", "png", "gif", "bmp",
                                 "mp3", "mp4", "avi", "mov", "mkv",
                                 "log", "bak", "tmp", "swp", "lock"])

        if skipExtensions.contains(ext) {
            return false
        }

        // Analyze file content
        return isLikelyROM(at: url)
    }
}