//
//  CallbackTests.swift
//  RomKitTests
//
//  Created by Barry Walker on 8/5/25.
//

import Testing
import Foundation
@testable import RomKit

/// Tests for callback functionality
struct CallbackTests {

    // MARK: - Delegate Pattern Tests

    @Test func testDelegateCallbacks() async throws {
        // Create a test delegate
        let delegate = TestDelegate()

        // Load test DAT
        let data = try TestDATLoader.loadFullMAMEDAT()
        let parser = LogiqxDATParser()
        let datFile = try parser.parse(data: data)

        // Create scanner with delegate
        let scanner = MAMEROMScanner(
            datFile: datFile,
            validator: MAMEROMValidator(),
            archiveHandlers: [],
            delegate: delegate
        )

        // Create test directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("callback_test")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Scan (will be empty but should trigger callbacks)
        _ = try await scanner.scan(directory: tempDir)

        // Verify callbacks were received
        // Empty directory won't have progress updates, but should have events
        #expect(!delegate.events.isEmpty)

        // Check for specific events
        let hasStartEvent = delegate.events.contains { event in
            if case .scanStarted = event { return true }
            return false
        }
        #expect(hasStartEvent)

        let hasCompleteEvent = delegate.events.contains { event in
            if case .scanCompleted = event { return true }
            return false
        }
        #expect(hasCompleteEvent)

        print("Delegate received \(delegate.progressUpdates.count) progress updates")
        print("Delegate received \(delegate.events.count) events")
    }

    // MARK: - Closure Callback Tests

    @Test func testClosureCallbacks() async throws {
        var progressCount = 0
        var eventCount = 0
        var scanStarted = false
        var scanCompleted = false

        // Create callbacks
        let callbacks = RomKitCallbacks(
            onProgress: { progress in
                progressCount += 1
                print("Progress: \(progress.current)/\(progress.total) - \(progress.message ?? "")")
            },
            onEvent: { event in
                eventCount += 1
                switch event {
                case .scanStarted:
                    scanStarted = true
                case .scanCompleted:
                    scanCompleted = true
                default:
                    break
                }
            }
        )

        // Load test DAT
        let data = try TestDATLoader.loadFullMAMEDAT()
        let parser = LogiqxDATParser()
        let datFile = try parser.parse(data: data)

        // Create scanner with callbacks
        let scanner = MAMEROMScanner(
            datFile: datFile,
            validator: MAMEROMValidator(),
            archiveHandlers: [],
            callbacks: callbacks
        )

        // Create test directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("closure_test")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Scan
        _ = try await scanner.scan(directory: tempDir)

        // Verify callbacks (empty dir won't have progress, but will have events)
        #expect(eventCount > 0)
        #expect(scanStarted)
        #expect(scanCompleted)

        print("Received \(progressCount) progress callbacks")
        print("Received \(eventCount) event callbacks")
    }

    // MARK: - Async Stream Tests

    @Test func testAsyncStreamCallbacks() async throws {
        let eventStream = RomKitEventStream()
        var receivedEvents: [RomKitEvent] = []
        var receivedProgress: [OperationProgress] = []

        // Load test DAT
        let data = try TestDATLoader.loadFullMAMEDAT()
        let parser = LogiqxDATParser()
        let datFile = try parser.parse(data: data)

        // Create scanner with event stream
        let scanner = MAMEROMScanner(
            datFile: datFile,
            validator: MAMEROMValidator(),
            archiveHandlers: [],
            eventStream: eventStream
        )

        // Start consuming events in background
        let eventTask = Task {
            for await event in await eventStream.events {
                receivedEvents.append(event)
            }
        }

        let progressTask = Task {
            for await progress in await eventStream.progress {
                receivedProgress.append(progress)
            }
        }

        // Create test directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("stream_test")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Scan
        _ = try await scanner.scan(directory: tempDir)

        // Give streams time to process
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Cancel consuming tasks
        eventTask.cancel()
        progressTask.cancel()

        // Verify we received events
        #expect(!receivedEvents.isEmpty)

        print("Received \(receivedEvents.count) events via async stream")
        print("Received \(receivedProgress.count) progress updates via async stream")
    }

    // MARK: - Cancellation Tests

    @Test func testCancellation() async throws {
        var cancelled = false

        // Create callbacks that cancel after first progress update
        let callbacks = RomKitCallbacks(
            onProgress: { _ in
                cancelled = true
            },
            shouldCancel: {
                return cancelled
            }
        )

        // Load test DAT
        let data = try TestDATLoader.loadFullMAMEDAT()
        let parser = LogiqxDATParser()
        let datFile = try parser.parse(data: data)

        // Create rebuilder with callbacks (rebuilder has more operations to cancel)
        let rebuilder = MAMEROMRebuilder(
            datFile: datFile,
            archiveHandlers: [],
            callbacks: callbacks
        )

        // Create test directories
        let sourceDir = FileManager.default.temporaryDirectory.appendingPathComponent("cancel_source")
        let destDir = FileManager.default.temporaryDirectory.appendingPathComponent("cancel_dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: destDir)
        }

        // Start rebuild (should cancel early)
        let results = try await rebuilder.rebuild(
            from: sourceDir,
            to: destDir,
            options: RebuildOptions()
        )

        // Verify operation was cancelled
        #expect(cancelled)

        print("Operation cancelled: \(cancelled)")
        print("Rebuilt: \(results.rebuilt), Failed: \(results.failed), Skipped: \(results.skipped)")
    }

    // MARK: - Progress Calculation Tests

    @Test func testProgressCalculation() async throws {
        var lastProgress: OperationProgress?

        let callbacks = RomKitCallbacks(
            onProgress: { progress in
                lastProgress = progress

                // Verify progress values
                #expect(progress.current >= 0)
                #expect(progress.total >= progress.current)
                #expect(progress.percentage >= 0 && progress.percentage <= 1.0)
            }
        )

        // Load test DAT
        let data = try TestDATLoader.loadFullMAMEDAT()
        let parser = LogiqxDATParser()
        let datFile = try parser.parse(data: data)

        // Create scanner
        let scanner = MAMEROMScanner(
            datFile: datFile,
            validator: MAMEROMValidator(),
            archiveHandlers: [],
            callbacks: callbacks
        )

        // Create test directory with a file
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("progress_test")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a dummy file
        let dummyFile = tempDir.appendingPathComponent("test.zip")
        try Data().write(to: dummyFile)

        // Scan
        _ = try await scanner.scan(directory: tempDir)

        // Verify final progress
        if let progress = lastProgress {
            print("Final progress: \(progress.current)/\(progress.total) (\(Int(progress.percentage * 100))%)")
            if let time = progress.estimatedTimeRemaining {
                print("Estimated time remaining: \(time) seconds")
            }
        }
    }

    // MARK: - Event Types Tests

    @Test func testEventTypes() async throws {
        var eventTypes = Set<String>()

        let callbacks = RomKitCallbacks(
            onEvent: { event in
                // Track event types
                switch event {
                case .scanStarted: eventTypes.insert("scanStarted")
                case .scanningFile: eventTypes.insert("scanningFile")
                case .scanCompleted: eventTypes.insert("scanCompleted")
                case .validationStarted: eventTypes.insert("validationStarted")
                case .validationCompleted: eventTypes.insert("validationCompleted")
                case .archiveOpening: eventTypes.insert("archiveOpening")
                case .warning: eventTypes.insert("warning")
                case .info: eventTypes.insert("info")
                default: break
                }
            }
        )

        // Load test DAT
        let data = try TestDATLoader.loadFullMAMEDAT()
        let parser = LogiqxDATParser()
        let datFile = try parser.parse(data: data)

        // Create scanner
        let scanner = MAMEROMScanner(
            datFile: datFile,
            validator: MAMEROMValidator(),
            archiveHandlers: [ZIPArchiveHandler()],
            callbacks: callbacks
        )

        // Create test directory with unknown file
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("event_test")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create unknown file to trigger warning
        let unknownFile = tempDir.appendingPathComponent("unknown.zip")
        try Data().write(to: unknownFile)

        // Scan
        _ = try await scanner.scan(directory: tempDir)

        print("Event types received: \(eventTypes.sorted())")

        // Verify basic events
        #expect(eventTypes.contains("scanStarted"))
        #expect(eventTypes.contains("scanCompleted"))
    }
}

// MARK: - Test Helpers

/// Test delegate implementation
class TestDelegate: RomKitDelegate {
    var progressUpdates: [OperationProgress] = []
    var events: [RomKitEvent] = []
    var shouldCancelFlag = false

    func romKit(didUpdateProgress progress: OperationProgress) {
        progressUpdates.append(progress)
    }

    func romKit(didReceiveEvent event: RomKitEvent) {
        events.append(event)
    }

    func romKitShouldCancel() -> Bool {
        return shouldCancelFlag
    }
}