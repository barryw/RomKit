//
//  RomKitCLI.swift
//  RomKit Command Line Interface
//
//  Main entry point for the RomKit CLI tool
//

import ArgumentParser
import Foundation
import RomKit

@main
struct RomKitCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "romkit",
        abstract: "A high-performance ROM management tool for arcade emulation",
        version: Version.current,
        subcommands: [
            Analyze.self,
            Scan.self,
            Verify.self,
            Export.self,
            Rebuild.self,
            Index.self,
            Fixdat.self,
            Missing.self,
            Stats.self,
            Organize.self
        ],
        defaultSubcommand: nil
    )
}

// MARK: - Helper Extensions

extension RomKitCLI {
    static func printHeader(_ text: String) {
        print("\n" + String(repeating: "=", count: 60))
        print(text)
        print(String(repeating: "=", count: 60))
    }

    static func printSection(_ text: String) {
        print("\n" + String(repeating: "-", count: 40))
        print(text)
        print(String(repeating: "-", count: 40))
    }

    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func formatPercentage(_ value: Double) -> String {
        return String(format: "%.1f%%", value * 100)
    }
}
