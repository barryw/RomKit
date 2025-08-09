//
//  ROMOrganizer.swift
//  RomKit
//
//  ROM renaming and organization utilities
//

import Foundation

/// Options for organizing ROM collections
public enum OrganizationStyle {
    case flat                    // All ROMs in one directory
    case byManufacturer         // Manufacturer/game.zip
    case byYear                 // Year/game.zip
    case byGenre                // Genre/game.zip
    case byAlphabet             // A-Z/game.zip
    case byParentClone          // Parents/game.zip, Clones/game.zip
    case byStatus               // Complete/game.zip, Incomplete/game.zip
    case custom(groupBy: (any GameEntry) -> String)
}

/// ROM organization and renaming handler
public class ROMOrganizer {

    private let datFile: any DATFormat
    private let fileManager = FileManager.default

    public init(datFile: any DATFormat) {
        self.datFile = datFile
    }

    /// Rename ROMs to match DAT file names
    public func renameROMs(
        in directory: URL,
        dryRun: Bool = true,
        preserveOriginals: Bool = false,
        progress: ((RenameProgress) -> Void)? = nil
    ) async throws -> RenameResult {

        let renamed: [(from: String, to: String)] = []
        let skipped: [(file: String, reason: String)] = []
        let errors: [(file: String, error: Error)] = []

        // For now, this is a simplified implementation that would need to be
        // integrated with the actual scanning infrastructure
        // This is a placeholder that shows the expected interface

        return RenameResult(
            renamed: renamed,
            skipped: skipped,
            errors: errors,
            dryRun: dryRun
        )
    }

    /// Organize ROM collection into folders
    public func organizeCollection(
        from source: URL,
        to destination: URL,
        style: OrganizationStyle,
        createFolders: Bool = true,
        moveFiles: Bool = false,
        progress: ((OrganizeProgress) -> Void)? = nil
    ) async throws -> OrganizeResult {

        let organized: [(file: String, folder: String)] = []
        let errors: [(file: String, error: Error)] = []

        // For now, this is a simplified implementation that would need to be
        // integrated with the actual scanning infrastructure
        // This is a placeholder that shows the expected interface

        return OrganizeResult(
            organized: organized,
            errors: errors,
            folders: []
        )
    }

    /// Clean ROM filenames (remove region codes, version numbers, etc.)
    public func cleanFilenames(
        in directory: URL,
        removeRegionCodes: Bool = true,
        removeVersionNumbers: Bool = true,
        removeExtraInfo: Bool = true,
        dryRun: Bool = true
    ) throws -> RenameResult {

        var renamed: [(from: String, to: String)] = []
        var skipped: [(file: String, reason: String)] = []
        var errors: [(file: String, error: Error)] = []

        let files = try getZipFiles(in: directory)

        for fileURL in files {
            let result = processFile(
                fileURL,
                removeRegionCodes: removeRegionCodes,
                removeVersionNumbers: removeVersionNumbers,
                removeExtraInfo: removeExtraInfo,
                dryRun: dryRun
            )

            switch result {
            case .renamed(let from, let to):
                renamed.append((from: from, to: to))
            case .skipped(let file, let reason):
                skipped.append((file: file, reason: reason))
            case .error(let file, let error):
                errors.append((file: file, error: error))
            case .unchanged:
                break
            }
        }

        return RenameResult(
            renamed: renamed,
            skipped: skipped,
            errors: errors,
            dryRun: dryRun
        )
    }

    private enum ProcessResult {
        case renamed(from: String, to: String)
        case skipped(file: String, reason: String)
        case error(file: String, error: Error)
        case unchanged
    }

    private func getZipFiles(in directory: URL) throws -> [URL] {
        var files: [URL] = []
        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsSubdirectoryDescendants]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension.lowercased() == "zip" {
                files.append(fileURL)
            }
        }
        return files
    }

    private func processFile(
        _ fileURL: URL,
        removeRegionCodes: Bool,
        removeVersionNumbers: Bool,
        removeExtraInfo: Bool,
        dryRun: Bool
    ) -> ProcessResult {

        let originalName = fileURL.deletingPathExtension().lastPathComponent
        let cleanedName = cleanFilename(
            originalName,
            removeRegionCodes: removeRegionCodes,
            removeVersionNumbers: removeVersionNumbers,
            removeExtraInfo: removeExtraInfo
        )

        guard cleanedName != originalName else { return .unchanged }

        let newURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(cleanedName)
            .appendingPathExtension("zip")

        if fileManager.fileExists(atPath: newURL.path) {
            return .skipped(file: fileURL.lastPathComponent, reason: "Target file already exists")
        }

        if !dryRun {
            do {
                try fileManager.moveItem(at: fileURL, to: newURL)
                return .renamed(from: fileURL.lastPathComponent, to: newURL.lastPathComponent)
            } catch {
                return .error(file: fileURL.lastPathComponent, error: error)
            }
        } else {
            return .renamed(from: fileURL.lastPathComponent, to: cleanedName + ".zip")
        }
    }

    private func cleanFilename(
        _ name: String,
        removeRegionCodes: Bool,
        removeVersionNumbers: Bool,
        removeExtraInfo: Bool
    ) -> String {

        var cleanedName = name

        if removeRegionCodes {
            cleanedName = removeRegions(from: cleanedName)
        }

        if removeVersionNumbers {
            cleanedName = removeVersions(from: cleanedName)
        }

        if removeExtraInfo {
            cleanedName = removeExtras(from: cleanedName)
        }

        return cleanedName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removeRegions(from name: String) -> String {
        var result = name
        result = result.replacingOccurrences(
            of: #"\s*\([^)]+\)"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\s*\[[^\]]+\]"#,
            with: "",
            options: .regularExpression
        )
        return result
    }

    private func removeVersions(from name: String) -> String {
        return name.replacingOccurrences(
            of: #"\s+(v|V|rev|Rev|REV)\s*[\d.]+[a-zA-Z]?"#,
            with: "",
            options: .regularExpression
        )
    }

    private func removeExtras(from name: String) -> String {
        var result = name
        let extras = ["Proto", "Beta", "Demo", "Sample", "Alt", "Hack"]
        for extra in extras {
            result = result.replacingOccurrences(
                of: #"\s+\(?"# + extra + #"\)?"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    private func determineFolder(for game: any GameEntry, style: OrganizationStyle) -> String {
        switch style {
        case .flat:
            return ""
        case .byManufacturer:
            return folderByManufacturer(game)
        case .byYear:
            return folderByYear(game)
        case .byGenre:
            return folderByGenre(game)
        case .byAlphabet:
            return folderByAlphabet(game)
        case .byParentClone:
            return folderByParentClone(game)
        case .byStatus:
            return "Unknown" // Would need scan results
        case .custom(let groupBy):
            return sanitizeFolderName(groupBy(game))
        }
    }

    private func folderByManufacturer(_ game: any GameEntry) -> String {
        if let manufacturer = game.metadata.manufacturer {
            return sanitizeFolderName(manufacturer)
        }
        return "Unknown"
    }

    private func folderByYear(_ game: any GameEntry) -> String {
        return game.metadata.year ?? "Unknown"
    }

    private func folderByGenre(_ game: any GameEntry) -> String {
        if let category = game.metadata.category {
            return sanitizeFolderName(category)
        }
        return "Unknown"
    }

    private func folderByAlphabet(_ game: any GameEntry) -> String {
        let firstChar = game.name.prefix(1).uppercased()
        if firstChar.rangeOfCharacter(from: .letters) != nil {
            return firstChar
        }
        return "#" // For numbers and special characters
    }

    private func folderByParentClone(_ game: any GameEntry) -> String {
        return game.metadata.cloneOf == nil ? "Parents" : "Clones"
    }

    private func sanitizeFolderName(_ name: String) -> String {
        // Remove invalid characters for folder names
        let invalidChars = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }
}

/// Result of rename operation
public struct RenameResult {
    public let renamed: [(from: String, to: String)]
    public let skipped: [(file: String, reason: String)]
    public let errors: [(file: String, error: Error)]
    public let dryRun: Bool

    public var summary: String {
        """
        Rename Operation \(dryRun ? "(DRY RUN)" : "Complete"):
        ✅ Renamed: \(renamed.count) files
        ⏭️ Skipped: \(skipped.count) files
        ❌ Errors: \(errors.count) files
        """
    }
}

/// Result of organize operation
public struct OrganizeResult {
    public let organized: [(file: String, folder: String)]
    public let errors: [(file: String, error: Error)]
    public let folders: [String]

    public var summary: String {
        """
        Organization Complete:
        ✅ Organized: \(organized.count) files
        📁 Folders created: \(folders.count)
        ❌ Errors: \(errors.count) files
        """
    }
}

/// Progress tracking for rename operations
public struct RenameProgress {
    public let current: Int
    public let total: Int
    public let currentFile: String
    public let action: RenameAction

    public enum RenameAction {
        case renamed
        case wouldRename
        case skipped
        case error
    }
}

/// Progress tracking for organize operations
public struct OrganizeProgress {
    public let current: Int
    public let total: Int
    public let currentFile: String
    public let folder: String
}
