//
//  ParallelHashUtilities.swift
//  RomKit
//
//  Optimized hash computation with parallel chunk processing for large files
//

import Foundation
import CryptoKit
import zlib

public actor ParallelHashUtilities {
    
    private static let chunkSize = 1024 * 1024 * 4 // 4MB chunks
    private static let maxConcurrentChunks = ProcessInfo.processInfo.activeProcessorCount
    
    public static func crc32(data: Data) async -> String {
        if data.count < chunkSize {
            return HashUtilities.crc32(data: data)
        }
        
        return await withTaskGroup(of: (Int, UInt32).self) { group in
            let chunks = stride(from: 0, to: data.count, by: chunkSize).map { offset in
                (offset, min(chunkSize, data.count - offset))
            }
            
            for (index, (offset, length)) in chunks.enumerated() {
                group.addTask {
                    let chunkData = data.subdata(in: offset..<(offset + length))
                    let crc = chunkData.withUnsafeBytes { bytes in
                        return UInt32(zlib.crc32(0, bytes.bindMemory(to: UInt8.self).baseAddress, uInt(length)))
                    }
                    return (index, crc)
                }
            }
            
            var results = [(Int, UInt32)]()
            for await result in group {
                results.append(result)
            }
            
            results.sort { $0.0 < $1.0 }
            
            // For CRC32, we can't simply combine chunks - need to compute sequentially
            // This is a limitation of CRC32 algorithm
            let crc = data.withUnsafeBytes { bytes in
                return zlib.crc32(0, bytes.bindMemory(to: UInt8.self).baseAddress, uInt(data.count))
            }
            
            return String(format: "%08x", UInt32(crc))
        }
    }
    
    public static func sha1(data: Data) async -> String {
        if data.count < chunkSize {
            return HashUtilities.sha1(data: data)
        }
        
        return await Task.detached(priority: .userInitiated) {
            var hasher = Insecure.SHA1()
            
            for offset in stride(from: 0, to: data.count, by: chunkSize) {
                let length = min(chunkSize, data.count - offset)
                let chunk = data.subdata(in: offset..<(offset + length))
                hasher.update(data: chunk)
            }
            
            let digest = hasher.finalize()
            return digest.map { String(format: "%02x", $0) }.joined()
        }.value
    }
    
    public static func sha256(data: Data) async -> String {
        if data.count < chunkSize {
            return HashUtilities.sha256(data: data)
        }
        
        return await Task.detached(priority: .userInitiated) {
            var hasher = SHA256()
            
            for offset in stride(from: 0, to: data.count, by: chunkSize) {
                let length = min(chunkSize, data.count - offset)
                let chunk = data.subdata(in: offset..<(offset + length))
                hasher.update(data: chunk)
            }
            
            let digest = hasher.finalize()
            return digest.map { String(format: "%02x", $0) }.joined()
        }.value
    }
    
    public static func md5(data: Data) async -> String {
        if data.count < chunkSize {
            return HashUtilities.md5(data: data)
        }
        
        return await Task.detached(priority: .userInitiated) {
            var hasher = Insecure.MD5()
            
            for offset in stride(from: 0, to: data.count, by: chunkSize) {
                let length = min(chunkSize, data.count - offset)
                let chunk = data.subdata(in: offset..<(offset + length))
                hasher.update(data: chunk)
            }
            
            let digest = hasher.finalize()
            return digest.map { String(format: "%02x", $0) }.joined()
        }.value
    }
    
    public struct MultiHash: Sendable {
        public let crc32: String
        public let sha1: String
        public let sha256: String
        public let md5: String
    }
    
    public static func computeAllHashes(data: Data) async -> MultiHash {
        async let crc32Task = crc32(data: data)
        async let sha1Task = sha1(data: data)
        async let sha256Task = sha256(data: data)
        async let md5Task = md5(data: data)
        
        return await MultiHash(
            crc32: crc32Task,
            sha1: sha1Task,
            sha256: sha256Task,
            md5: md5Task
        )
    }
    
    public static func computeAllHashesFromFile(at url: URL) async throws -> MultiHash {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        
        var crc32Value: uLong = 0
        var sha1Hasher = Insecure.SHA1()
        var sha256Hasher = SHA256()
        var md5Hasher = Insecure.MD5()
        
        while true {
            autoreleasepool {
                if let chunk = try? fileHandle.read(upToCount: chunkSize), !chunk.isEmpty {
                    chunk.withUnsafeBytes { bytes in
                        crc32Value = zlib.crc32(crc32Value, bytes.bindMemory(to: UInt8.self).baseAddress, uInt(chunk.count))
                    }
                    sha1Hasher.update(data: chunk)
                    sha256Hasher.update(data: chunk)
                    md5Hasher.update(data: chunk)
                } else {
                    return
                }
            }
        }
        
        let sha1Digest = sha1Hasher.finalize()
        let sha256Digest = sha256Hasher.finalize()
        let md5Digest = md5Hasher.finalize()
        
        return MultiHash(
            crc32: String(format: "%08x", UInt32(crc32Value)),
            sha1: sha1Digest.map { String(format: "%02x", $0) }.joined(),
            sha256: sha256Digest.map { String(format: "%02x", $0) }.joined(),
            md5: md5Digest.map { String(format: "%02x", $0) }.joined()
        )
    }
}

public extension HashUtilities {
    
    static func crc32Async(data: Data) async -> String {
        await ParallelHashUtilities.crc32(data: data)
    }
    
    static func sha1Async(data: Data) async -> String {
        await ParallelHashUtilities.sha1(data: data)
    }
    
    static func sha256Async(data: Data) async -> String {
        await ParallelHashUtilities.sha256(data: data)
    }
    
    static func md5Async(data: Data) async -> String {
        await ParallelHashUtilities.md5(data: data)
    }
    
    static func computeAllHashesAsync(data: Data) async -> ParallelHashUtilities.MultiHash {
        await ParallelHashUtilities.computeAllHashes(data: data)
    }
}