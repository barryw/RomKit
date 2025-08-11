//
//  Organize.swift
//  RomKitCLI
//
//  Organize and rename ROM collections
//

import ArgumentParser
import Foundation
import RomKit

struct Organize: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Organize ROM collection into structured folders",
        discussion: """
            Organizes your ROM collection into a structured folder hierarchy.
            Supports various organization styles including by manufacturer, year, genre, etc.
            Can also rename ROM files according to DAT file specifications.
            """
    )

    @Argument(help: "Source directory containing ROM files")
    var source: String

    @Argument(help: "DAT file for ROM identification")
    var datFile: String

    @Option(name: .shortAndLong, help: "Destination directory for organized ROMs")
    var destination: String?

    @Option(name: .shortAndLong, help: "Organization style: flat, manufacturer, year, genre, alphabet, parent-clone, status")
    var style: String = "manufacturer"

    @Flag(name: .long, help: "Rename ROMs according to DAT file")
    var rename = false

    @Flag(name: .long, help: "Move files instead of copying")
    var move = false

    @Flag(name: .long, help: "Clean filenames (remove region codes, version numbers)")
    var cleanNames = false

    @Flag(name: .long, help: "Dry run - show what would be done without making changes")
    var dryRun = false

    @Flag(name: .long, help: "Preserve original files when renaming")
    var preserveOriginals = false

    @Flag(name: .long, help: "Show progress during operation")
    var showProgress = false

    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose = false

    func run() async throws {
        let startTime = Date()

        print("🗂️  Organizing ROM Collection")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        if dryRun {
            print("⚠️  DRY RUN MODE - No files will be modified")
        }

        // Initialize RomKit
        let romkit = RomKit()

        // Load DAT file
        if verbose {
            print("📋 Loading DAT file: \(datFile)")
        }
        let datURL = URL(fileURLWithPath: datFile)
        try await romkit.loadDAT(from: datURL.path)

        // Determine organization style
        let organizationStyle = parseOrganizationStyle(style)

        // Handle rename-only operation
        if rename && destination == nil {
            try await performRename(romkit: romkit)
            return
        }

        // Handle organization operation
        if let dest = destination {
            try await performOrganization(romkit: romkit, destination: dest, style: organizationStyle)
        } else {
            print("❌ Error: Destination directory required for organization")
            print("   Use --rename flag for in-place renaming only")
            throw ExitCode.failure
        }

        let elapsedTime = Date().timeIntervalSince(startTime)
        print("\n⏱️  Time elapsed: \(String(format: "%.2f", elapsedTime)) seconds")
    }

    private func performRename(romkit: RomKit) async throws {
        print("\n📝 Renaming ROMs according to DAT file")
        print("   Source: \(source)")
        print("   Preserve originals: \(preserveOriginals)")

        if verbose {
            print("\n🔍 Analyzing files for renaming...")
        }

        let result = try await romkit.renameROMs(
            in: source,
            dryRun: dryRun
        )

        print("\n📊 Rename Results:")
        print("   Files to rename: \(result.renamed.count)")
        print("   Files to skip: \(result.skipped.count)")
        print("   Errors: \(result.errors.count)")

        if verbose && !result.renamed.isEmpty {
            print("\n📝 Rename Operations:")
            for (oldName, newName) in result.renamed.prefix(10) {
                print("   \(oldName) → \(newName)")
            }
            if result.renamed.count > 10 {
                print("   ... and \(result.renamed.count - 10) more")
            }
        }

        if !result.errors.isEmpty {
            print("\n⚠️  Errors encountered:")
            for (file, error) in result.errors.prefix(5) {
                print("   \(file): \(error)")
            }
        }

        if dryRun {
            print("\n💡 Run without --dry-run to apply changes")
        } else {
            print("\n✅ Renaming complete!")
            print(result.summary)
        }
    }

    private func performOrganization(romkit: RomKit, destination: String, style: OrganizationStyle) async throws {
        print("\n🗂️  Organizing ROM collection")
        print("   Source: \(source)")
        print("   Destination: \(destination)")
        print("   Style: \(styleDescription(style))")
        print("   Operation: \(move ? "Move" : "Copy")")

        if verbose {
            print("\n🔍 Analyzing collection structure...")
        }

        let result = try await romkit.organizeCollection(
            from: source,
            to: destination,
            style: style
        )

        print("\n📊 Organization Results:")
        print("   Files organized: \(result.organized.count)")
        print("   Folders created: \(result.folders.count)")
        print("   Errors: \(result.errors.count)")

        if verbose && !result.organized.isEmpty {
            print("\n📁 Organization Structure:")
            // Show sample of organization
            let folderGroups = Dictionary(grouping: result.organized) { $0.folder }
            for (folder, files) in folderGroups.sorted(by: { $0.key < $1.key }).prefix(5) {
                print("   \(folder)/")
                for file in files.prefix(3) {
                    print("      └─ \(file.file)")
                }
                if files.count > 3 {
                    print("      └─ ... and \(files.count - 3) more")
                }
            }
            if folderGroups.count > 5 {
                print("   ... and \(folderGroups.count - 5) more folders")
            }
        }

        if !result.errors.isEmpty {
            print("\n⚠️  Errors encountered:")
            for (file, error) in result.errors.prefix(5) {
                print("   \(file): \(error)")
            }
        }

        if dryRun {
            print("\n💡 Run without --dry-run to apply changes")
        } else {
            print("\n✅ Organization complete!")
            print(result.summary)
        }
    }

    private func parseOrganizationStyle(_ style: String) -> OrganizationStyle {
        switch style.lowercased() {
        case "flat":
            return .flat
        case "manufacturer", "mfg":
            return .byManufacturer
        case "year":
            return .byYear
        case "genre":
            return .byGenre
        case "alphabet", "alpha":
            return .byAlphabet
        case "parent-clone", "parentclone":
            return .byParentClone
        case "status":
            return .byStatus
        default:
            print("⚠️  Unknown style '\(style)', using manufacturer")
            return .byManufacturer
        }
    }

    private func styleDescription(_ style: OrganizationStyle) -> String {
        switch style {
        case .flat:
            return "Flat (no folders)"
        case .byManufacturer:
            return "By Manufacturer"
        case .byYear:
            return "By Year"
        case .byGenre:
            return "By Genre"
        case .byAlphabet:
            return "By Alphabet"
        case .byParentClone:
            return "Parent/Clone separation"
        case .byStatus:
            return "By completion status"
        case .custom:
            return "Custom organization"
        }
    }
}
