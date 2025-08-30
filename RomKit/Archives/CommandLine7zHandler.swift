//
//  CommandLine7zHandler.swift
//  RomKit
//
//  7-Zip archive handler using command-line 7z tool
//

import Foundation

/// 7z archive handler that uses the command-line 7z tool
/// This is used as a fallback when lib7z has issues (e.g., in CI)
public final class CommandLine7zHandler: ArchiveHandler, @unchecked Sendable {
    public let supportedExtensions = ["7z"]
    private let sevenZipPath: String
    
    public init() {
        // Try to find 7z in common locations
        let possiblePaths = [
            "/opt/homebrew/bin/7z",     // Apple Silicon homebrew
            "/usr/local/bin/7z",         // Intel homebrew
            "/usr/bin/7z",               // System location
            "/opt/local/bin/7z",         // MacPorts
            "/usr/local/bin/7za",        // Alternative name
            "/opt/homebrew/bin/7za"      // Alternative name on Apple Silicon
        ]
        
        self.sevenZipPath = possiblePaths.first { path in
            FileManager.default.fileExists(atPath: path)
        } ?? "/usr/local/bin/7z"  // Default fallback
    }
    
    public func canHandle(url: URL) -> Bool {
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
            return false
        }
        
        // Check if file exists
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    public func listContents(of url: URL) throws -> [ArchiveEntry] {
        // Use 7z l command to list contents
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sevenZipPath)
        process.arguments = ["l", "-slt", url.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw ArchiveError.cannotOpenArchive("7z command failed with status \(process.terminationStatus)")
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        // Parse the technical listing format
        var entries: [ArchiveEntry] = []
        var currentEntry: [String: String] = [:]
        
        for line in output.components(separatedBy: .newlines) {
            if line.isEmpty && !currentEntry.isEmpty {
                // End of entry
                if let path = currentEntry["Path"],
                   let sizeStr = currentEntry["Size"],
                   let size = UInt64(sizeStr),
                   currentEntry["Attributes"]?.contains("D") != true {
                    // Skip directories
                    entries.append(ArchiveEntry(
                        path: path,
                        compressedSize: size,
                        uncompressedSize: size,
                        modificationDate: nil,
                        crc32: currentEntry["CRC"]?.lowercased()
                    ))
                }
                currentEntry = [:]
            } else if line.contains(" = ") {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 {
                    currentEntry[parts[0]] = parts[1]
                }
            }
        }
        
        return entries
    }
    
    public func extract(entry: ArchiveEntry, from url: URL) throws -> Data {
        // Create temp directory for extraction
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("7z_extract_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Extract specific file
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sevenZipPath)
        process.arguments = ["e", "-o\(tempDir.path)", url.path, entry.path, "-y"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw ArchiveError.extractionFailed("7z extraction failed with status \(process.terminationStatus)")
        }
        
        // Read the extracted file
        let extractedFile = tempDir.appendingPathComponent(URL(fileURLWithPath: entry.path).lastPathComponent)
        guard FileManager.default.fileExists(atPath: extractedFile.path) else {
            throw ArchiveError.extractionFailed("Extracted file not found")
        }
        
        return try Data(contentsOf: extractedFile)
    }
    
    public func extractAll(from url: URL, to destinationURL: URL) throws {
        // Extract all files
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sevenZipPath)
        process.arguments = ["x", "-o\(destinationURL.path)", url.path, "-y"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw ArchiveError.extractionFailed("7z extraction failed with status \(process.terminationStatus)")
        }
    }
    
    public func create(at url: URL, with files: [(name: String, data: Data)]) throws {
        // Create temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("7z_create_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Write files to temp directory
        for (name, data) in files {
            let fileURL = tempDir.appendingPathComponent(name)
            let fileDir = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: fileDir.path) {
                try FileManager.default.createDirectory(at: fileDir, withIntermediateDirectories: true)
            }
            try data.write(to: fileURL)
        }
        
        // Create 7z archive
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sevenZipPath)
        process.arguments = ["a", "-t7z", url.path, "\(tempDir.path)/*", "-mx=5"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw ArchiveError.creationFailed("7z creation failed with status \(process.terminationStatus)")
        }
    }
}