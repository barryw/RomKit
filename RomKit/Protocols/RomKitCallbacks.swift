//
//  RomKitCallbacks.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation

// MARK: - Progress Reporting

/// Represents the progress of an operation
public struct OperationProgress: Sendable {
    /// Current item being processed
    public let current: Int

    /// Total number of items to process
    public let total: Int

    /// Percentage complete (0.0 to 1.0)
    public var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }

    /// Human-readable description of current operation
    public let message: String?

    /// Estimated time remaining in seconds
    public let estimatedTimeRemaining: TimeInterval?

    /// Current file or game being processed
    public let currentItem: String?

    public init(current: Int, total: Int, message: String? = nil,
                estimatedTimeRemaining: TimeInterval? = nil, currentItem: String? = nil) {
        self.current = current
        self.total = total
        self.message = message
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.currentItem = currentItem
    }
}

// MARK: - Event Types

/// Events that can occur during ROM operations
public enum RomKitEvent: Sendable {
    // Scanning events
    case scanStarted(path: String, fileCount: Int)
    case scanningFile(url: URL, index: Int, total: Int)
    case gameFound(name: String, status: GameCompletionStatus)
    case scanCompleted(gamesFound: Int, duration: TimeInterval)

    // Validation events
    case validationStarted(itemName: String)
    case validationCompleted(itemName: String, isValid: Bool, errors: [String])

    // Rebuild events
    case rebuildStarted(source: String, destination: String)
    case rebuildingGame(name: String, index: Int, total: Int)
    case gameRebuilt(name: String, success: Bool)
    case rebuildCompleted(rebuilt: Int, failed: Int, duration: TimeInterval)

    // Archive events
    case archiveOpening(url: URL)
    case archiveExtracting(fileName: String, size: UInt64)
    case archiveCreating(url: URL)
    case archiveAdding(fileName: String, size: UInt64)

    // Error events
    case error(RomKitCallbackError)
    case warning(String)

    // General events
    case info(String)
    case debug(String)
}

// MARK: - Error Types

public enum RomKitCallbackError: Error, LocalizedError, Sendable {
    case fileNotFound(path: String)
    case archiveCorrupted(url: URL)
    case validationFailed(item: String, reason: String)
    case rebuildFailed(game: String, reason: String)
    case insufficientSpace(required: UInt64, available: UInt64)
    case cancelled
    case unknown(any Error)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .archiveCorrupted(let url):
            return "Archive corrupted: \(url.lastPathComponent)"
        case .validationFailed(let item, let reason):
            return "Validation failed for \(item): \(reason)"
        case .rebuildFailed(let game, let reason):
            return "Rebuild failed for \(game): \(reason)"
        case .insufficientSpace(let required, let available):
            let reqMB = required / 1024 / 1024
            let availMB = available / 1024 / 1024
            return "Insufficient space: \(reqMB)MB required, \(availMB)MB available"
        case .cancelled:
            return "Operation cancelled"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Callback Protocols

/// Protocol for receiving callbacks during ROM operations
public protocol RomKitDelegate: AnyObject {
    /// Called when progress updates
    func romKit(didUpdateProgress progress: OperationProgress)

    /// Called when an event occurs
    func romKit(didReceiveEvent event: RomKitEvent)

    /// Called to check if operation should be cancelled
    func romKitShouldCancel() -> Bool
}

/// Default implementation makes all methods optional
public extension RomKitDelegate {
    func romKit(didUpdateProgress progress: OperationProgress) {}
    func romKit(didReceiveEvent event: RomKitEvent) {}
    func romKitShouldCancel() -> Bool { false }
}

// MARK: - Async/Await Event Stream

/// Modern async/await based event streaming
public actor RomKitEventStream {
    private var eventContinuation: AsyncStream<RomKitEvent>.Continuation?
    private var progressContinuation: AsyncStream<OperationProgress>.Continuation?

    /// Stream of events
    public private(set) lazy var events: AsyncStream<RomKitEvent> = {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }()

    /// Stream of progress updates
    public private(set) lazy var progress: AsyncStream<OperationProgress> = {
        AsyncStream { continuation in
            self.progressContinuation = continuation
        }
    }()

    /// Send an event
    public func send(event: RomKitEvent) {
        eventContinuation?.yield(event)
    }

    /// Send a progress update
    public func send(progress: OperationProgress) {
        progressContinuation?.yield(progress)
    }

    /// Complete the streams
    public func finish() {
        eventContinuation?.finish()
        progressContinuation?.finish()
    }
}

// MARK: - Closure-based Callbacks

/// Closure-based callback configuration
public struct RomKitCallbacks: Sendable {
    /// Called on progress updates
    public var onProgress: (@Sendable (OperationProgress) -> Void)?

    /// Called on events
    public var onEvent: (@Sendable (RomKitEvent) -> Void)?

    /// Called to check cancellation
    public var shouldCancel: (@Sendable () -> Bool)?

    /// Called on completion
    public var onCompletion: (@Sendable (Result<Void, any Error>) -> Void)?

    public init(
        onProgress: (@Sendable (OperationProgress) -> Void)? = nil,
        onEvent: (@Sendable (RomKitEvent) -> Void)? = nil,
        shouldCancel: (@Sendable () -> Bool)? = nil,
        onCompletion: (@Sendable (Result<Void, any Error>) -> Void)? = nil
    ) {
        self.onProgress = onProgress
        self.onEvent = onEvent
        self.shouldCancel = shouldCancel
        self.onCompletion = onCompletion
    }
}

// MARK: - Callback Manager

/// Manages callbacks for ROM operations
public final class CallbackManager {
    private weak var delegate: (any RomKitDelegate)?
    private var callbacks: RomKitCallbacks?
    private let eventStream: RomKitEventStream?

    /// Operation start time for duration calculations
    private let startTime = Date()

    /// Track items processed for progress
    private var itemsProcessed = 0
    private var totalItems = 0

    public init(delegate: (any RomKitDelegate)? = nil,
                callbacks: RomKitCallbacks? = nil,
                eventStream: RomKitEventStream? = nil) {
        self.delegate = delegate
        self.callbacks = callbacks
        self.eventStream = eventStream
    }

    /// Send a progress update
    public func sendProgress(current: Int, total: Int, message: String? = nil, currentItem: String? = nil) {
        let elapsed = Date().timeIntervalSince(startTime)
        let itemsPerSecond = elapsed > 0 ? Double(current) / elapsed : 0
        let remaining = itemsPerSecond > 0 ? Double(total - current) / itemsPerSecond : nil

        let progress = OperationProgress(
            current: current,
            total: total,
            message: message,
            estimatedTimeRemaining: remaining,
            currentItem: currentItem
        )

        delegate?.romKit(didUpdateProgress: progress)
        callbacks?.onProgress?(progress)

        if let stream = eventStream {
            Task.detached { [weak stream] in
                await stream?.send(progress: progress)
            }
        }
    }

    /// Send an event
    public func sendEvent(_ event: RomKitEvent) {
        delegate?.romKit(didReceiveEvent: event)
        callbacks?.onEvent?(event)

        if let stream = eventStream {
            Task.detached { [weak stream] in
                await stream?.send(event: event)
            }
        }
    }

    /// Check if operation should be cancelled
    public func shouldCancel() -> Bool {
        return delegate?.romKitShouldCancel() ?? callbacks?.shouldCancel?() ?? false
    }

    /// Send completion
    public func sendCompletion(_ result: Result<Void, any Error>) {
        callbacks?.onCompletion?(result)

        if let stream = eventStream {
            Task.detached { [weak stream] in
                await stream?.finish()
            }
        }
    }
}

// MARK: - Protocol Extensions for Callback Support

/// Extension to add callback support to scanners
public protocol CallbackSupportedScanner: ROMScanner {
    var callbackManager: CallbackManager? { get set }
}

/// Extension to add callback support to rebuilders
public protocol CallbackSupportedRebuilder: ROMRebuilder {
    var callbackManager: CallbackManager? { get set }
}

/// Extension to add callback support to validators
public protocol CallbackSupportedValidator: ROMValidator {
    var callbackManager: CallbackManager? { get set }
}
