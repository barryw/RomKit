//
//  ConcurrentScanner.swift
//  RomKit
//
//  High-performance concurrent directory scanning
//

import Foundation

public actor ConcurrentScanner {
    
    private let maxConcurrentScans: Int
    private let fileExtensions: Set<String>
    
    public init(maxConcurrentScans: Int = ProcessInfo.processInfo.activeProcessorCount,
                fileExtensions: Set<String> = ["zip", "7z", "rar", "chd"]) {
        self.maxConcurrentScans = maxConcurrentScans
        self.fileExtensions = fileExtensions
    }
    
    public struct ScanResult {
        public let url: URL
        public let size: UInt64
        public let modificationDate: Date
        public let isArchive: Bool
        public let hash: String?
    }
    
    public func scanDirectory(
        at url: URL,
        computeHashes: Bool = false,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async throws -> [ScanResult] {
        
        let files = try await discoverFiles(at: url)
        var results: [ScanResult] = []
        results.reserveCapacity(files.count)
        
        let totalFiles = files.count
        var processedFiles = 0
        
        await withTaskGroup(of: ScanResult?.self) { group in
            let semaphore = AsyncSemaphore(limit: maxConcurrentScans)
            
            for file in files {
                group.addTask {
                    await semaphore.wait()
                    let result = await self.scanFile(file, computeHash: computeHashes)
                    await semaphore.signal()
                    return result
                }
            }
            
            for await result in group {
                if let result = result {
                    results.append(result)
                    processedFiles += 1
                    progressHandler?(processedFiles, totalFiles)
                }
            }
        }
        
        return results.sorted { $0.url.path < $1.url.path }
    }
    
    private func discoverFiles(at url: URL) async throws -> [URL] {
        var discoveredFiles: [URL] = []
        let fileManager = FileManager.default
        
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw CocoaError(.fileReadUnknown)
        }
        
        for case let fileURL as URL in enumerator {
            autoreleasepool {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                    
                    if resourceValues.isRegularFile == true {
                        let ext = fileURL.pathExtension.lowercased()
                        if fileExtensions.isEmpty || fileExtensions.contains(ext) {
                            discoveredFiles.append(fileURL)
                        }
                    }
                } catch {
                    print("Error accessing file: \(fileURL.path)")
                }
            }
        }
        
        return discoveredFiles
    }
    
    private func scanFile(_ url: URL, computeHash: Bool) async -> ScanResult? {
        do {
            let attributes = try await AsyncFileIO.fileAttributes(at: url)
            
            let size = attributes[.size] as? UInt64 ?? 0
            let modDate = attributes[.modificationDate] as? Date ?? Date()
            let ext = url.pathExtension.lowercased()
            let isArchive = ["zip", "7z", "rar", "chd"].contains(ext)
            
            var hash: String? = nil
            if computeHash {
                // Always compute hash when requested, regardless of size
                let data = try await AsyncFileIO.readData(from: url)
                hash = await ParallelHashUtilities.crc32(data: data)
            }
            
            return ScanResult(
                url: url,
                size: size,
                modificationDate: modDate,
                isArchive: isArchive,
                hash: hash
            )
        } catch {
            print("Error scanning file \(url.path): \(error)")
            return nil
        }
    }
    
    public func scanDirectoryBatched(
        at url: URL,
        batchSize: Int = 100,
        batchHandler: @escaping ([ScanResult]) async -> Void
    ) async throws {
        
        let files = try await discoverFiles(at: url)
        
        for batchStart in stride(from: 0, to: files.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, files.count)
            let batch = Array(files[batchStart..<batchEnd])
            
            let batchResults = await withTaskGroup(of: ScanResult?.self) { group in
                for file in batch {
                    group.addTask {
                        await self.scanFile(file, computeHash: false)
                    }
                }
                
                var results: [ScanResult] = []
                for await result in group {
                    if let result = result {
                        results.append(result)
                    }
                }
                return results
            }
            
            await batchHandler(batchResults)
        }
    }
    
    public func findDuplicates(in directory: URL) async throws -> [[ScanResult]] {
        let allFiles = try await scanDirectory(at: directory, computeHashes: true)
        
        var duplicateGroups: [String: [ScanResult]] = [:]
        
        for file in allFiles {
            if let hash = file.hash {
                duplicateGroups[hash, default: []].append(file)
            }
        }
        
        return duplicateGroups.values.filter { $0.count > 1 }
    }
    
    public func scanArchiveContents(at url: URL) async throws -> [ArchiveEntry] {
        let ext = url.pathExtension.lowercased()
        
        switch ext {
        case "zip":
            let handler = ParallelZIPArchiveHandler()
            return try handler.listContents(of: url)
        default:
            let handler = FastZIPArchiveHandler()
            return try handler.listContents(of: url)
        }
    }
}

private actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    init(limit: Int) {
        self.count = limit
    }
    
    func wait() async {
        if count > 0 {
            count -= 1
            return
        }
        
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
    
    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            count += 1
        }
    }
}

public extension URL {
    
    func scanContentsAsync(computeHashes: Bool = false) async throws -> [ConcurrentScanner.ScanResult] {
        let scanner = ConcurrentScanner()
        return try await scanner.scanDirectory(at: self, computeHashes: computeHashes)
    }
    
    func findDuplicatesAsync() async throws -> [[ConcurrentScanner.ScanResult]] {
        let scanner = ConcurrentScanner()
        return try await scanner.findDuplicates(in: self)
    }
}