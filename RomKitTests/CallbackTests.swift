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
        // Use actor for thread-safe counting
        actor TestTracker {
            var progressCount = 0
            var eventCount = 0
            var scanStarted = false
            var scanCompleted = false

            func incrementProgress() { progressCount += 1 }
            func incrementEvent() { eventCount += 1 }
            func setScanStarted() { scanStarted = true }
            func setScanCompleted() { scanCompleted = true }
        }

        let tracker = TestTracker()

        // Create callbacks
        let callbacks = RomKitCallbacks(
            onProgress: { progress in
                Task { await tracker.incrementProgress() }
                print("Progress: \(progress.current)/\(progress.total) - \(progress.message ?? "")")
            },
            onEvent: { event in
                Task {
                    await tracker.incrementEvent()
                    switch event {
                    case .scanStarted:
                        await tracker.setScanStarted()
                    case .scanCompleted:
                        await tracker.setScanCompleted()
                    default:
                        break
                    }
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

        // Give Tasks time to complete
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Verify callbacks (empty dir won't have progress, but will have events)
        let progressCount = await tracker.progressCount
        let eventCount = await tracker.eventCount
        let scanStarted = await tracker.scanStarted
        let scanCompleted = await tracker.scanCompleted

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
        class CancellationTracker: @unchecked Sendable {
            private let lock = NSLock()
            private var _cancelled = false

            var cancelled: Bool {
                lock.lock()
                defer { lock.unlock() }
                return _cancelled
            }

            func setCancelled() {
                lock.lock()
                defer { lock.unlock() }
                _cancelled = true
            }
        }
        let tracker = CancellationTracker()

        // Create callbacks that cancel after first progress update
        let callbacks = RomKitCallbacks(
            onProgress: { _ in
                tracker.setCancelled()
            },
            shouldCancel: {
                return tracker.cancelled
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
        let cancelled = tracker.cancelled
        #expect(cancelled)

        print("Operation cancelled: \(cancelled)")
        print("Rebuilt: \(results.rebuilt), Failed: \(results.failed), Skipped: \(results.skipped)")
    }

    // MARK: - Progress Calculation Tests

    @Test func testProgressCalculation() async throws {
        actor ProgressTracker {
            var lastProgress: OperationProgress?
            func setProgress(_ progress: OperationProgress) {
                lastProgress = progress
            }
        }
        let tracker = ProgressTracker()

        let callbacks = RomKitCallbacks(
            onProgress: { progress in
                Task { await tracker.setProgress(progress) }

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
        let lastProgress = await tracker.lastProgress
        if let progress = lastProgress {
            print("Final progress: \(progress.current)/\(progress.total) (\(Int(progress.percentage * 100))%)")
            if let time = progress.estimatedTimeRemaining {
                print("Estimated time remaining: \(time) seconds")
            }
        }
    }

    // MARK: - Event Types Tests

    @Test func testEventTypes() async throws {
        actor EventTypeTracker {
            var eventTypes = Set<String>()
            func insert(_ type: String) {
                eventTypes.insert(type)
            }
        }
        let tracker = EventTypeTracker()

        let callbacks = RomKitCallbacks(
            onEvent: { event in
                // Track event types
                Task {
                    switch event {
                    case .scanStarted: await tracker.insert("scanStarted")
                    case .scanningFile: await tracker.insert("scanningFile")
                    case .scanCompleted: await tracker.insert("scanCompleted")
                    case .validationStarted: await tracker.insert("validationStarted")
                    case .validationCompleted: await tracker.insert("validationCompleted")
                    case .archiveOpening: await tracker.insert("archiveOpening")
                    case .warning: await tracker.insert("warning")
                    case .info: await tracker.insert("info")
                    default: break
                    }
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

        // Give Tasks time to complete
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        let eventTypes = await tracker.eventTypes
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
