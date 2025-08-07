//
//  Scan.swift
//  RomKit CLI - Scan Command
//
//  Quick scan of ROM directory to list contents
//

import ArgumentParser
import Foundation
import RomKit

struct Scan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Quickly scan a ROM directory and list contents"
    )
    
    @Argument(help: "Path to the ROM directory to scan")
    var path: String
    
    @Flag(name: .shortAndLong, help: "Compute hashes for all files")
    var hashes = false
    
    @Flag(name: .shortAndLong, help: "Use GPU acceleration")
    var gpu = false
    
    mutating func run() async throws {
        let url = URL(fileURLWithPath: path)
        
        RomKitCLI.printHeader("🔍 Scanning ROM Directory")
        print("📁 Path: \(url.path)")
        
        let scanner = ConcurrentScanner()
        let results = try await scanner.scanDirectory(
            at: url,
            computeHashes: hashes
        ) { current, total in
            print("Scanning: \(current)/\(total)", terminator: "\r")
            fflush(stdout)
        }
        
        print("\n✅ Found \(results.count) files")
        
        var totalSize: UInt64 = 0
        var archives = 0
        
        for result in results {
            totalSize += result.size
            if result.isArchive { archives += 1 }
        }
        
        print("📊 Total size: \(RomKitCLI.formatFileSize(Int64(totalSize)))")
        print("📦 Archives: \(archives)")
        print("📄 Other files: \(results.count - archives)")
    }
}