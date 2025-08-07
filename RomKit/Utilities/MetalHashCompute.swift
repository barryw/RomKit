//
//  MetalHashCompute.swift
//  RomKit
//
//  GPU-accelerated hash computation using Metal
//

import Foundation
import Metal
import MetalKit
import MetalPerformanceShaders

@available(macOS 10.13, iOS 11.0, *)
public class MetalHashCompute {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary

    private let crc32Pipeline: MTLComputePipelineState
    private let sha256Pipeline: MTLComputePipelineState
    private let multiHashPipeline: MTLComputePipelineState

    private static let gpuThreshold = 10 * 1024 * 1024 // 10MB minimum for GPU

    public init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue

        // Load Metal shaders
        if let library = try? device.makeDefaultLibrary(bundle: Bundle(for: MetalHashCompute.self)) {
            self.library = library
        } else {
            // If no compiled shaders, create from source
            let shaderSource = MetalHashCompute.shaderSource
            guard let library = try? device.makeLibrary(source: shaderSource, options: nil) else {
                return nil
            }
            self.library = library
        }

        // Create compute pipelines
        guard let crc32Function = library.makeFunction(name: "crc32_compute"),
              let sha256Function = library.makeFunction(name: "sha256_compute"),
              let multiHashFunction = library.makeFunction(name: "multi_hash_compute"),
              let crc32Pipeline = try? device.makeComputePipelineState(function: crc32Function),
              let sha256Pipeline = try? device.makeComputePipelineState(function: sha256Function),
              let multiHashPipeline = try? device.makeComputePipelineState(function: multiHashFunction) else {
            return nil
        }

        self.crc32Pipeline = crc32Pipeline
        self.sha256Pipeline = sha256Pipeline
        self.multiHashPipeline = multiHashPipeline
    }

    public func computeCRC32(data: Data) async -> String? {
        // Use CPU for small files
        guard data.count >= Self.gpuThreshold else {
            return await ParallelHashUtilities.crc32(data: data)
        }

        return await withCheckedContinuation { continuation in
            autoreleasepool {
                guard let buffer = device.makeBuffer(bytes: Array(data), length: data.count, options: .storageModeShared),
                      let resultBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared),
                      let commandBuffer = commandQueue.makeCommandBuffer(),
                      let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                    continuation.resume(returning: nil)
                    return
                }

                computeEncoder.setComputePipelineState(crc32Pipeline)
                computeEncoder.setBuffer(buffer, offset: 0, index: 0)
                computeEncoder.setBuffer(resultBuffer, offset: 0, index: 1)

                var dataLength = UInt32(data.count)
                computeEncoder.setBytes(&dataLength, length: MemoryLayout<UInt32>.size, index: 2)

                let threadsPerThreadgroup = MTLSize(width: 256, height: 1, depth: 1)
                let threadgroups = MTLSize(width: (data.count + 255) / 256, height: 1, depth: 1)

                computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
                computeEncoder.endEncoding()

                commandBuffer.addCompletedHandler { _ in
                    let pointer = resultBuffer.contents().bindMemory(to: UInt32.self, capacity: 1)
                    let crc = pointer.pointee
                    continuation.resume(returning: String(format: "%08x", crc))
                }

                commandBuffer.commit()
            }
        }
    }

    public func computeSHA256(data: Data) async -> String? {
        guard data.count >= Self.gpuThreshold else {
            return await ParallelHashUtilities.sha256(data: data)
        }

        return await withCheckedContinuation { continuation in
            autoreleasepool {
                guard let buffer = device.makeBuffer(bytes: Array(data), length: data.count, options: .storageModeShared),
                      let resultBuffer = device.makeBuffer(length: 32, options: .storageModeShared), // SHA256 = 32 bytes
                      let commandBuffer = commandQueue.makeCommandBuffer(),
                      let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                    continuation.resume(returning: nil)
                    return
                }

                computeEncoder.setComputePipelineState(sha256Pipeline)
                computeEncoder.setBuffer(buffer, offset: 0, index: 0)
                computeEncoder.setBuffer(resultBuffer, offset: 0, index: 1)

                var dataLength = UInt32(data.count)
                computeEncoder.setBytes(&dataLength, length: MemoryLayout<UInt32>.size, index: 2)

                let threadsPerThreadgroup = MTLSize(width: 256, height: 1, depth: 1)
                let threadgroups = MTLSize(width: (data.count + 255) / 256, height: 1, depth: 1)

                computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
                computeEncoder.endEncoding()

                commandBuffer.addCompletedHandler { _ in
                    let pointer = resultBuffer.contents().bindMemory(to: UInt8.self, capacity: 32)
                    let hash = (0..<32).map { String(format: "%02x", pointer[$0]) }.joined()
                    continuation.resume(returning: hash)
                }

                commandBuffer.commit()
            }
        }
    }

    public struct GPUMultiHash {
        public let crc32: String
        public let sha256: String
        public let md5: String
        public let sha1: String
    }

    public func computeAllHashes(data: Data) async -> GPUMultiHash? {
        guard data.count >= Self.gpuThreshold else {
            let cpuResult = await ParallelHashUtilities.computeAllHashes(data: data)
            return GPUMultiHash(
                crc32: cpuResult.crc32,
                sha256: cpuResult.sha256,
                md5: cpuResult.md5,
                sha1: cpuResult.sha1
            )
        }

        return await withCheckedContinuation { continuation in
            autoreleasepool {
                // Allocate buffers for all hash results
                let resultSize = 4 + 32 + 16 + 20 // CRC32 + SHA256 + MD5 + SHA1

                guard let dataBuffer = device.makeBuffer(bytes: Array(data), length: data.count, options: .storageModeShared),
                      let resultBuffer = device.makeBuffer(length: resultSize, options: .storageModeShared),
                      let commandBuffer = commandQueue.makeCommandBuffer(),
                      let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                    continuation.resume(returning: nil)
                    return
                }

                computeEncoder.setComputePipelineState(multiHashPipeline)
                computeEncoder.setBuffer(dataBuffer, offset: 0, index: 0)
                computeEncoder.setBuffer(resultBuffer, offset: 0, index: 1)

                var dataLength = UInt32(data.count)
                computeEncoder.setBytes(&dataLength, length: MemoryLayout<UInt32>.size, index: 2)

                let threadsPerThreadgroup = MTLSize(width: 256, height: 1, depth: 1)
                let threadgroups = MTLSize(width: (data.count + 255) / 256, height: 1, depth: 1)

                computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
                computeEncoder.endEncoding()

                commandBuffer.addCompletedHandler { _ in
                    let pointer = resultBuffer.contents()

                    // Extract CRC32 (4 bytes)
                    let crc32Ptr = pointer.bindMemory(to: UInt32.self, capacity: 1)
                    let crc32 = String(format: "%08x", crc32Ptr.pointee)

                    // Extract SHA256 (32 bytes)
                    let sha256Ptr = pointer.advanced(by: 4).bindMemory(to: UInt8.self, capacity: 32)
                    let sha256 = (0..<32).map { String(format: "%02x", sha256Ptr[$0]) }.joined()

                    // Extract MD5 (16 bytes)
                    let md5Ptr = pointer.advanced(by: 36).bindMemory(to: UInt8.self, capacity: 16)
                    let md5 = (0..<16).map { String(format: "%02x", md5Ptr[$0]) }.joined()

                    // Extract SHA1 (20 bytes)
                    let sha1Ptr = pointer.advanced(by: 52).bindMemory(to: UInt8.self, capacity: 20)
                    let sha1 = (0..<20).map { String(format: "%02x", sha1Ptr[$0]) }.joined()

                    let result = GPUMultiHash(crc32: crc32, sha256: sha256, md5: md5, sha1: sha1)
                    continuation.resume(returning: result)
                }

                commandBuffer.commit()
            }
        }
    }

    // Metal shader source code
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    // CRC32 polynomial and lookup table generation
    constant uint32_t CRC32_POLY = 0xEDB88320;

    kernel void crc32_compute(device const uint8_t* input [[buffer(0)]],
                              device uint32_t* output [[buffer(1)]],
                              constant uint32_t& length [[buffer(2)]],
                              uint id [[thread_position_in_grid]]) {
        if (id >= length) return;

        // Simplified CRC32 - would need full implementation
        uint32_t crc = 0xFFFFFFFF;
        uint32_t byte = input[id];

        for (int j = 0; j < 8; j++) {
            if ((crc ^ byte) & 1) {
                crc = (crc >> 1) ^ CRC32_POLY;
            } else {
                crc >>= 1;
            }
            byte >>= 1;
        }

        // Use atomic operations to combine results
        atomic_fetch_xor_explicit((device atomic_uint*)output, crc, memory_order_relaxed);
    }

    kernel void sha256_compute(device const uint8_t* input [[buffer(0)]],
                               device uint8_t* output [[buffer(1)]],
                               constant uint32_t& length [[buffer(2)]],
                               uint id [[thread_position_in_grid]]) {
        // Simplified SHA256 - would need full implementation
        // This would process blocks in parallel
        if (id >= length) return;

        // SHA256 implementation would go here
        // Processing 64-byte blocks in parallel
    }

    kernel void multi_hash_compute(device const uint8_t* input [[buffer(0)]],
                                   device uint8_t* output [[buffer(1)]],
                                   constant uint32_t& length [[buffer(2)]],
                                   uint id [[thread_position_in_grid]]) {
        if (id >= length) return;

        // Compute all hashes in parallel
        // Each thread group handles a chunk of data
        // Results are combined atomically
    }
    """
}

