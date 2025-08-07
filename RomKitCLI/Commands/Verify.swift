//
//  Verify.swift
//  RomKit CLI - Verify Command
//
//  Verify integrity of ROM files
//

import ArgumentParser
import Foundation
import RomKit

struct Verify: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Verify the integrity of ROM files"
    )

    @Argument(help: "Path to the ROM file or directory to verify")
    var path: String

    @Flag(name: .shortAndLong, help: "Use GPU acceleration")
    var gpu = false

    mutating func run() async throws {
        let url = URL(fileURLWithPath: path)

        RomKitCLI.printHeader("✅ Verifying ROM Integrity")
        print("📁 Path: \(url.path)")

        // Basic verification for now
        if url.pathExtension.lowercased() == "zip" {
            let handler = ParallelZIPArchiveHandler()
            let entries = try handler.listContents(of: url)

            print("📦 ZIP Archive contains \(entries.count) files")

            for entry in entries {
                print("  ✓ \(entry.path) - CRC: \(entry.crc32 ?? "N/A")")
            }
        } else {
            print("⚠️  Verify command is not yet fully implemented")
        }
    }
}
