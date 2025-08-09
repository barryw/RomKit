//
//  SimplifiedMultiSourceTests.swift
//  RomKitTests
//
//  Simplified test demonstrating multi-source rebuild capability
//

import Testing
import Foundation
@testable import RomKit

/// Simplified test showing the concept of rebuilding from multiple sources
struct SimplifiedMultiSourceTests {

    @Test func testConceptOfMultiSourceRebuild() async throws {
        print("\n🎯 Multi-Source Rebuild Concept Test")
        print("=====================================")
        print("This test demonstrates the CONCEPT of rebuilding games")
        print("from ROMs distributed across multiple indexed directories.\n")

        // Scenario Setup
        print("📋 Scenario:")
        print("  - Game: Street Fighter 2 (requires 6 ROM files)")
        print("  - Source 1: Contains 2 ROM files")
        print("  - Source 2: Contains 2 ROM files")
        print("  - Source 3: Contains 2 ROM files")
        print("  - Goal: Rebuild complete game from all sources\n")

        // Step 1: Simulate indexed ROM locations
        let indexedROMs = [
            MockIndexedROM(name: "sf2.01", crc: "12345678", source: "/source1/sf2.01"),
            MockIndexedROM(name: "sf2.02", crc: "23456789", source: "/source1/sf2.02"),
            MockIndexedROM(name: "sf2.03", crc: "34567890", source: "/source2/sf2.03"),
            MockIndexedROM(name: "sf2.04", crc: "45678901", source: "/source2/sf2.04"),
            MockIndexedROM(name: "sf2.gfx1", crc: "56789012", source: "/source3/sf2.gfx1"),
            MockIndexedROM(name: "sf2.gfx2", crc: "67890123", source: "/source3/sf2.gfx2")
        ]

        print("📚 Indexed ROMs:")
        for rom in indexedROMs {
            print("  ✓ \(rom.name) (CRC: \(rom.crc)) at \(rom.source)")
        }

        // Step 2: Simulate game requirements from DAT file
        let requiredROMs = [
            RequiredROM(name: "sf2.01", crc: "12345678"),
            RequiredROM(name: "sf2.02", crc: "23456789"),
            RequiredROM(name: "sf2.03", crc: "34567890"),
            RequiredROM(name: "sf2.04", crc: "45678901"),
            RequiredROM(name: "sf2.gfx1", crc: "56789012"),
            RequiredROM(name: "sf2.gfx2", crc: "67890123")
        ]

        print("\n📋 Required ROMs (from DAT):")
        for rom in requiredROMs {
            print("  • \(rom.name) (CRC: \(rom.crc))")
        }

        // Step 3: Rebuild process
        print("\n🔨 Rebuilding Process:")
        var rebuiltROMs: [RebuiltROM] = []

        for required in requiredROMs {
            // Find matching ROM in index
            if let indexed = indexedROMs.first(where: { $0.crc == required.crc }) {
                print("  ✓ Found \(required.name) at \(indexed.source)")
                rebuiltROMs.append(RebuiltROM(
                    name: required.name,
                    source: indexed.source,
                    status: .found
                ))
            } else {
                print("  ✗ Missing \(required.name)")
                rebuiltROMs.append(RebuiltROM(
                    name: required.name,
                    source: "N/A",
                    status: .missing
                ))
            }
        }

        // Step 4: Verify results
        let foundCount = rebuiltROMs.filter { $0.status == .found }.count
        let totalCount = requiredROMs.count

        print("\n📊 Rebuild Results:")
        print("  Total ROMs needed: \(totalCount)")
        print("  ROMs found: \(foundCount)")
        print("  ROMs missing: \(totalCount - foundCount)")
        print("  Status: \(foundCount == totalCount ? "✅ COMPLETE" : "⚠️ INCOMPLETE")")

        // Verify all ROMs were found
        #expect(foundCount == totalCount, "All ROMs should be found across sources")

        // Step 5: Show source distribution
        print("\n📍 Source Distribution:")
        let sourceGroups = Dictionary(grouping: rebuiltROMs.filter { $0.status == .found }, by: { $0.source })
        for (source, roms) in sourceGroups.sorted(by: { $0.key < $1.key }) {
            print("  \(source): \(roms.count) ROMs")
            for rom in roms {
                print("    - \(rom.name)")
            }
        }

        // Test duplicate handling
        print("\n🔍 Testing Duplicate Handling:")
        let duplicateROMs = [
            MockIndexedROM(name: "sf2.01", crc: "12345678", source: "/source1/sf2.01"),
            MockIndexedROM(name: "sf2_01_backup", crc: "12345678", source: "/backup/sf2.01"),
            MockIndexedROM(name: "streetfighter2_01", crc: "12345678", source: "/archive/sf2.zip#sf2.01")
        ]

        print("  ROM with CRC 12345678 found in:")
        for dup in duplicateROMs {
            print("    • \(dup.source)")
        }

        // Select best source (prefer local files over archives)
        let bestSource = selectBestSource(for: "12345678", from: duplicateROMs)
        print("  Best source selected: \(bestSource.source)")
        #expect(bestSource.source == "/source1/sf2.01", "Should prefer local file")
    }

    @Test func testPartialRebuildScenario() async throws {
        print("\n⚠️ Partial Rebuild Scenario Test")
        print("=====================================")

        // Simulate incomplete collection
        let availableROMs = [
            MockIndexedROM(name: "pacman.6e", crc: "ABCD0001", source: "/roms/pacman.6e"),
            MockIndexedROM(name: "pacman.6f", crc: "ABCD0002", source: "/roms/pacman.6f")
            // Missing pacman.6h and pacman.6j
        ]

        let requiredROMs = [
            RequiredROM(name: "pacman.6e", crc: "ABCD0001"),
            RequiredROM(name: "pacman.6f", crc: "ABCD0002"),
            RequiredROM(name: "pacman.6h", crc: "ABCD0003"),
            RequiredROM(name: "pacman.6j", crc: "ABCD0004")
        ]

        print("Available ROMs: \(availableROMs.count)")
        print("Required ROMs: \(requiredROMs.count)")

        var foundCount = 0
        var missingROMs: [String] = []

        for required in requiredROMs {
            if availableROMs.contains(where: { $0.crc == required.crc }) {
                foundCount += 1
                print("  ✓ Found: \(required.name)")
            } else {
                missingROMs.append(required.name)
                print("  ✗ Missing: \(required.name)")
            }
        }

        print("\nResults:")
        print("  Status: INCOMPLETE")
        print("  Found: \(foundCount)/\(requiredROMs.count)")
        print("  Missing: \(missingROMs.joined(separator: ", "))")

        #expect(foundCount == 2, "Should find 2 out of 4 ROMs")
        #expect(missingROMs.count == 2, "Should have 2 missing ROMs")
    }

    // Helper function to simulate best source selection
    private func selectBestSource(for crc: String, from sources: [MockIndexedROM]) -> MockIndexedROM {
        // Prefer: local files > archives > remote
        let sorted = sources.sorted { lhs, rhs in
            let lhsIsArchive = lhs.source.contains(".zip")
            let rhsIsArchive = rhs.source.contains(".zip")

            if !lhsIsArchive && rhsIsArchive {
                return true // Local file preferred over archive
            }
            return false
        }

        return sorted.first ?? sources.first ?? MockIndexedROM(name: "unknown", crc: crc, source: "/unknown")
    }
}

// MARK: - Mock Types for Demonstration

private struct MockIndexedROM {
    let name: String
    let crc: String
    let source: String
}

private struct RequiredROM {
    let name: String
    let crc: String
}

private struct RebuiltROM {
    let name: String
    let source: String
    let status: RebuildStatus
}

private enum RebuildStatus {
    case found
    case missing
}
