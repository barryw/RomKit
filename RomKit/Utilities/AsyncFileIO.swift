//
//  AsyncFileIO.swift
//  RomKit
//
//  Async file I/O operations for improved performance
//

import Foundation

public actor AsyncFileIO {

    private static let readChunkSize = 1024 * 1024 * 4 // 4MB chunks
    private static let writeChunkSize = 1024 * 1024 * 4 // 4MB chunks

    public static func readData(from url: URL) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    let data = try Data(contentsOf: url)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static func readDataStreaming(from url: URL, chunkHandler: @escaping @Sendable (Data) async -> Void) async throws {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        await withTaskGroup(of: Void.self) { group in
            var offset: UInt64 = 0
            let fileSize = (try? fileHandle.seekToEnd()) ?? 0
            try? fileHandle.seek(toOffset: 0)

            while offset < fileSize {
                autoreleasepool {
                    if let chunk = try? fileHandle.read(upToCount: readChunkSize), !chunk.isEmpty {
                        group.addTask {
                            await chunkHandler(chunk)
                        }
                        offset += UInt64(chunk.count)
                    } else {
                        return
                    }
                }
            }
        }
    }

    public static func writeData(_ data: Data, to url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    try data.write(to: url)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static func writeDataStreaming(_ data: Data, to url: URL) async throws {
        let chunkSize = writeChunkSize
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    let fileManager = FileManager.default

                    try fileManager.createDirectory(
                        at: url.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )

                    guard fileManager.createFile(atPath: url.path, contents: nil) else {
                        throw CocoaError(.fileWriteFileExists)
                    }

                    let fileHandle = try FileHandle(forWritingTo: url)
                    defer { try? fileHandle.close() }

                    for offset in stride(from: 0, to: data.count, by: chunkSize) {
                        autoreleasepool {
                            let size = min(chunkSize, data.count - offset)
                            let chunk = data.subdata(in: offset..<(offset + size))
                            fileHandle.write(chunk)
                        }
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static func copyFile(from source: URL, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    try FileManager.default.copyItem(at: source, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static func moveFile(from source: URL, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    try FileManager.default.moveItem(at: source, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static func deleteFile(at url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    try FileManager.default.removeItem(at: url)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static func fileExists(at url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let exists = FileManager.default.fileExists(atPath: url.path)
                continuation.resume(returning: exists)
            }
        }
    }

    public static func createDirectory(at url: URL, withIntermediateDirectories: Bool = true) async throws {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    try FileManager.default.createDirectory(
                        at: url,
                        withIntermediateDirectories: withIntermediateDirectories
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static func contentsOfDirectory(at url: URL) async throws -> [URL] {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    let contents = try FileManager.default.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: nil
                    )
                    continuation.resume(returning: contents)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static func enumerateDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]? = nil,
        options: FileManager.DirectoryEnumerationOptions = [],
        handler: @Sendable @escaping (URL) async -> Bool
    ) async throws {
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: options
        )

        await withTaskGroup(of: Bool.self) { group in
            let semaphore = AsyncSemaphore(limit: ProcessInfo.processInfo.activeProcessorCount)

            while let fileURL = enumerator?.nextObject() as? URL {
                group.addTask {
                    await semaphore.wait()
                    let result = await handler(fileURL)
                    await semaphore.signal()
                    return result
                }
            }

            for await shouldContinue in group where !shouldContinue {
                enumerator?.skipDescendants()
            }
        }
    }

    // Use a struct to make file attributes Sendable
    public struct FileAttributes: Sendable {
        public let size: UInt64?
        public let modificationDate: Date?
        public let creationDate: Date?
        public let type: FileAttributeType?
    }

    public static func fileAttributes(at url: URL) async throws -> FileAttributes {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                    let attributes = FileAttributes(
                        size: attrs[.size] as? UInt64,
                        modificationDate: attrs[.modificationDate] as? Date,
                        creationDate: attrs[.creationDate] as? Date,
                        type: attrs[.type] as? FileAttributeType
                    )
                    continuation.resume(returning: attributes)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static func fileSize(at url: URL) async throws -> UInt64 {
        let attributes = try await fileAttributes(at: url)
        return attributes.size ?? 0
    }

    public static func modificationDate(at url: URL) async throws -> Date? {
        let attributes = try await fileAttributes(at: url)
        return attributes.modificationDate
    }
}

private actor AsyncSemaphore {
    private var availablePermits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.availablePermits = limit
    }

    func wait() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        } else {
            availablePermits += 1
        }
    }
}

public extension FileManager {

    func contentsOfDirectoryAsync(at url: URL) async throws -> [URL] {
        try await AsyncFileIO.contentsOfDirectory(at: url)
    }

    func copyItemAsync(at source: URL, to destination: URL) async throws {
        try await AsyncFileIO.copyFile(from: source, to: destination)
    }

    func moveItemAsync(at source: URL, to destination: URL) async throws {
        try await AsyncFileIO.moveFile(from: source, to: destination)
    }

    func removeItemAsync(at url: URL) async throws {
        try await AsyncFileIO.deleteFile(at: url)
    }

    func createDirectoryAsync(at url: URL, withIntermediateDirectories: Bool = true) async throws {
        try await AsyncFileIO.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
    }
}

public extension Data {

    init(contentsOfAsync url: URL) async throws {
        self = try await AsyncFileIO.readData(from: url)
    }

    func writeAsync(to url: URL) async throws {
        try await AsyncFileIO.writeData(self, to: url)
    }
}
