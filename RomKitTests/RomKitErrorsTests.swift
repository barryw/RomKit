//
//  RomKitErrorsTests.swift
//  RomKitTests
//
//  Tests for RomKitErrors to improve code coverage
//

import Testing
import Foundation
@testable import RomKit

struct RomKitErrorsTests {

    @Test func testConfigurationErrors() {
        // Test all configuration error cases
        let errors: [ConfigurationError] = [
            .missingCacheDirectory,
            .invalidPath("/invalid/path"),
            .missingConfiguration("testKey"),
            .invalidConfiguration(key: "badKey", value: "badValue")
        ]

        for error in errors {
            #expect(error.category == .configuration)
            #expect(error.errorDescription != nil)
            #expect(!error.localizedDescription.isEmpty)

            // Check severity levels
            switch error {
            case .missingCacheDirectory:
                #expect(error.severity == .critical)
            case .invalidPath:
                #expect(error.severity == .error)
            case .missingConfiguration:
                #expect(error.severity == .error)
            case .invalidConfiguration:
                #expect(error.severity == .warning)
            }

            // All should have recovery suggestions
            #expect(error.suggestedRecovery != nil)
        }
    }

    @Test func testFileSystemErrors() {
        let testURL = URL(fileURLWithPath: "/test/file.rom")
        let errors: [FileSystemError] = [
            .fileNotFound(testURL),
            .directoryNotFound(testURL),
            .insufficientPermissions(testURL),
            .diskFull,
            .fileCorrupted(testURL, reason: "Bad CRC"),
            .writeFailed(testURL, underlyingError: nil)
        ]

        for error in errors {
            #expect(error.category == .fileSystem)
            #expect(error.errorDescription != nil)
            #expect(error.suggestedRecovery != nil)

            // Check critical errors
            if case .diskFull = error {
                #expect(error.severity == .critical)
            }
        }
    }

    @Test func testParsingErrors() {
        let errors: [ParsingError] = [
            .invalidFormat("XML"),
            .unsupportedVersion("2.0"),
            .malformedXML(line: 10, column: 5, reason: "Unexpected character"),
            .missingRequiredField("name"),
            .invalidDataType(field: "size", expected: "integer", got: "string")
        ]

        for error in errors {
            #expect(error.category == .parsing)
            #expect(error.errorDescription != nil)
            #expect(error.suggestedRecovery != nil)

            // Missing field should be warning
            if case .missingRequiredField = error {
                #expect(error.severity == .warning)
            } else {
                #expect(error.severity == .error)
            }
        }

        // Test malformed XML without line/column
        let malformedNoLocation = ParsingError.malformedXML(line: nil, column: nil, reason: "Generic error")
        #expect(malformedNoLocation.errorDescription?.contains("Malformed XML") == true)
    }

    @Test func testScanningErrors() {
        let testURL = URL(fileURLWithPath: "/test/rom.bin")
        let errors: [ScanningError] = [
            .noResultsFound,
            .scanCancelled,
            .invalidROMStructure(testURL, reason: "Invalid header"),
            .duplicateROM(name: "game.rom", locations: [testURL]),
            .missingDependency("libzip")
        ]

        for error in errors {
            #expect(error.category == .scanning)
            #expect(error.errorDescription != nil)

            // Check severities
            switch error {
            case .scanCancelled:
                #expect(error.severity == .info)
                #expect(error.suggestedRecovery == nil)
            case .duplicateROM:
                #expect(error.severity == .warning)
            default:
                #expect(error.severity == .error)
            }
        }
    }

    @Test func testArchiveErrors() {
        let testURL = URL(fileURLWithPath: "/test/archive.zip")
        let errors: [ArchiveHandlingError] = [
            .unsupportedFormat("RAR"),
            .corruptedArchive(testURL, details: "Bad header"),
            .extractionFailed(testURL, reason: "Disk full"),
            .compressionFailed(reason: "Out of memory"),
            .invalidFileName("file<>name.rom"),
            .passwordProtected(testURL)
        ]

        for error in errors {
            #expect(error.category == .archive)
            #expect(error.errorDescription != nil)
            #expect(error.suggestedRecovery != nil)

            // Password protected should be warning
            if case .passwordProtected = error {
                #expect(error.severity == .warning)
            }
        }

        // Test corrupted archive without details
        let corruptedNoDetails = ArchiveHandlingError.corruptedArchive(testURL, details: nil)
        #expect(corruptedNoDetails.errorDescription?.contains("Corrupted archive") == true)
    }

    @Test func testDatabaseErrors() {
        let errors: [DatabaseError] = [
            .connectionFailed("Connection refused"),
            .queryFailed("SELECT * FROM roms", underlyingError: nil),
            .corruptedDatabase,
            .migrationFailed(from: 1, to: 2, reason: "Schema mismatch"),
            .transactionFailed("Deadlock"),
            .databaseLocked,
            .databaseError("Generic error"),
            .invalidPath("/bad/path.db")
        ]

        for error in errors {
            #expect(error.category == .database)
            #expect(error.errorDescription != nil)
            #expect(error.suggestedRecovery != nil)

            // Check critical errors
            if case .corruptedDatabase = error {
                #expect(error.severity == .critical)
            } else if case .databaseLocked = error {
                #expect(error.severity == .warning)
            }
        }

        // Test query failed with underlying error
        struct TestError: LocalizedError {
            var errorDescription: String? { "Test error" }
        }
        let queryError = DatabaseError.queryFailed("SELECT", underlyingError: TestError())
        #expect(queryError.errorDescription?.contains("Test error") == true)
    }

    @Test func testValidationErrors() {
        let errors: [ValidationError] = [
            .checksumMismatch(expected: "ABCD1234", got: "EFGH5678"),
            .sizeMismatch(expected: 1024, got: 2048),
            .missingRequiredROM("game.rom"),
            .invalidROMContent("Bad header"),
            .validationSkipped(reason: "User cancelled")
        ]

        for error in errors {
            #expect(error.category == .validation)
            #expect(error.errorDescription != nil)

            // Check severities
            switch error {
            case .validationSkipped:
                #expect(error.severity == .info)
                #expect(error.suggestedRecovery == nil)
            case .checksumMismatch, .sizeMismatch:
                #expect(error.severity == .error)
            default:
                #expect(error.severity == .warning)
            }
        }
    }

    @Test func testErrorCollection() {
        var collection = ErrorCollection()

        // Test empty collection
        #expect(collection.isEmpty)
        #expect(collection.isEmpty)
        #expect(collection.hasCriticalErrors == false)

        // Add various errors
        collection.append(ConfigurationError.missingCacheDirectory) // Critical
        collection.append(FileSystemError.fileNotFound(URL(fileURLWithPath: "/test"))) // Error
        collection.append(ValidationError.validationSkipped(reason: "Test")) // Info
        collection.append(DatabaseError.databaseLocked) // Warning

        #expect(collection.count == 4)
        #expect(!collection.isEmpty)
        #expect(collection.hasCriticalErrors) // Has critical error

        // Test critical errors filtering
        let criticalErrors = collection.criticalErrors
        #expect(criticalErrors.count == 1)

        // Test grouping by category
        let configErrors = collection.grouped(by: .configuration)
        #expect(configErrors.count == 1)

        let validationErrors = collection.grouped(by: .validation)
        #expect(validationErrors.count == 1)

        // Test formatted output
        let formatted = collection.formatted()
        #expect(formatted.contains("CRITICAL"))
        #expect(formatted.contains("ERROR"))
        #expect(formatted.contains("WARNING"))
        #expect(formatted.contains("INFO"))
        #expect(formatted.contains("💡")) // Recovery suggestion

        // Test batch append
        var newCollection = ErrorCollection()
        let errors: [RomKitErrorProtocol] = [
            FileSystemError.diskFull,
            ScanningError.noResultsFound
        ]
        newCollection.append(contentsOf: errors)
        #expect(newCollection.count == 2)
    }

    @Test func testErrorCategoriesAndSeverities() {
        // Test that all error categories are distinct
        let categories: [ErrorCategory] = [
            .configuration, .fileSystem, .parsing, .validation,
            .scanning, .rebuilding, .database, .network, .archive
        ]
        let uniqueCategories = Set(categories)
        #expect(uniqueCategories.count == categories.count)

        // Test severity ordering
        let severities: [ErrorSeverity] = [.critical, .error, .warning, .info]
        let uniqueSeverities = Set(severities)
        #expect(uniqueSeverities.count == severities.count)
    }
}
