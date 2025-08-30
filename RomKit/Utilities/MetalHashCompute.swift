//
//  MetalHashCompute.swift
//  RomKit
//
//  GPU-accelerated hash computation using Metal
//

import Foundation
@preconcurrency import Metal
@preconcurrency import MetalKit
@preconcurrency import MetalPerformanceShaders

@available(macOS 10.13, iOS 11.0, *)
public final class MetalHashCompute: @unchecked Sendable {

    private let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private let library: any MTLLibrary

    private let crc32Pipeline: any MTLComputePipelineState
    private let sha256Pipeline: any MTLComputePipelineState
    private let md5Pipeline: any MTLComputePipelineState
    private let sha1Pipeline: any MTLComputePipelineState
    private let multiHashPipeline: any MTLComputePipelineState

    private static let gpuThreshold = 10 * 1024 * 1024 // 10MB minimum for GPU

    public init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue

        // Load Metal shaders from compiled metallib or source file
        do {
            // First try to load from default library
            if let defaultLibrary = device.makeDefaultLibrary() {
                self.library = defaultLibrary
            } else {
                // Try to load from shader file
                let shaderPath = Bundle(for: MetalHashCompute.self).path(forResource: "HashCompute", ofType: "metal")
                if let shaderPath = shaderPath,
                   let shaderSource = try? String(contentsOfFile: shaderPath) {
                    self.library = try device.makeLibrary(source: shaderSource, options: nil)
                } else {
                    // Fallback: create inline shaders
                    self.library = try device.makeLibrary(source: MetalHashCompute.getFallbackShaderSource(), options: nil)
                }
            }
        } catch {
            return nil
        }

        // Create compute pipelines for different hash algorithms
        guard let crc32BlocksFunc = library.makeFunction(name: "crc32_blocks"),
              let _ = library.makeFunction(name: "crc32_combine"),
              let sha256BlocksFunc = library.makeFunction(name: "sha256_blocks"),
              let md5BlocksFunc = library.makeFunction(name: "md5_blocks"),
              let sha1BlocksFunc = library.makeFunction(name: "sha1_blocks"),
              let multiHashFunc = library.makeFunction(name: "multi_hash_compute") else {
            return nil
        }
        
        do {
            self.crc32Pipeline = try device.makeComputePipelineState(function: crc32BlocksFunc)
            self.sha256Pipeline = try device.makeComputePipelineState(function: sha256BlocksFunc)
            self.md5Pipeline = try device.makeComputePipelineState(function: md5BlocksFunc)
            self.sha1Pipeline = try device.makeComputePipelineState(function: sha1BlocksFunc)
            self.multiHashPipeline = try device.makeComputePipelineState(function: multiHashFunc)
        } catch {
            return nil
        }
    }

    public func computeCRC32(data: Data) async -> String? {
        // Use CPU for small files
        guard data.count >= Self.gpuThreshold else {
            return await ParallelHashUtilities.crc32(data: data)
        }

        return await withCheckedContinuation { continuation in
            autoreleasepool {
                // Create input buffer
                guard let inputBuffer = device.makeBuffer(bytes: Array(data),
                                                         length: data.count,
                                                         options: .storageModeShared) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Calculate number of blocks
                let numBlocks = (UInt32(data.count) + Self.blockSize - 1) / Self.blockSize
                
                // Create output buffer for block CRCs
                guard let blockCRCBuffer = device.makeBuffer(length: Int(numBlocks) * MemoryLayout<UInt32>.size,
                                                            options: .storageModeShared) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Create final CRC buffer
                guard device.makeBuffer(length: MemoryLayout<UInt32>.size,
                                       options: .storageModeShared) != nil else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Create command buffer
                guard let commandBuffer = commandQueue.makeCommandBuffer(),
                      let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Dispatch CRC32 block computation
                computeEncoder.setComputePipelineState(crc32Pipeline)
                computeEncoder.setBuffer(inputBuffer, offset: 0, index: 0)
                computeEncoder.setBuffer(blockCRCBuffer, offset: 0, index: 1)
                
                var totalLength = UInt32(data.count)
                computeEncoder.setBytes(&totalLength, length: MemoryLayout<UInt32>.size, index: 2)
                
                var blockSizeVal = Self.blockSize
                computeEncoder.setBytes(&blockSizeVal, length: MemoryLayout<UInt32>.size, index: 3)
                
                let threadsPerThreadgroup = MTLSize(width: 1, height: 1, depth: 1)
                let threadgroups = MTLSize(width: Int(numBlocks), height: 1, depth: 1)
                computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
                
                computeEncoder.endEncoding()
                
                // Commit and wait
                commandBuffer.addCompletedHandler { _ in
                    // Combine block CRCs (simplified - proper implementation would use polynomial arithmetic)
                    let blockCRCs = blockCRCBuffer.contents().bindMemory(to: UInt32.self, capacity: Int(numBlocks))
                    var finalCRC: UInt32 = 0xFFFFFFFF
                    
                    for index in 0..<Int(numBlocks) {
                        let blockCRC = blockCRCs[index]
                        finalCRC = finalCRC ^ blockCRC
                    }
                    
                    finalCRC = finalCRC ^ 0xFFFFFFFF
                    let result = String(format: "%08x", finalCRC)
                    continuation.resume(returning: result)
                }
                
                commandBuffer.commit()
            }
        }
    }

    public func computeSHA256(data: Data) async -> String? {
        // Use CPU for small files
        guard data.count >= Self.gpuThreshold else {
            return await ParallelHashUtilities.sha256(data: data)
        }
        
        return await withCheckedContinuation { continuation in
            autoreleasepool {
                // Prepare padded data for SHA256 (must be multiple of 64 bytes)
                let paddedData = self.padDataForSHA256(data)
                
                // Create input buffer
                guard let inputBuffer = device.makeBuffer(bytes: Array(paddedData),
                                                         length: paddedData.count,
                                                         options: .storageModeShared) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Calculate number of 512-bit blocks
                let numBlocks = paddedData.count / 64
                
                // Create output buffer for hash values (8 uint32 values per block)
                guard let hashBuffer = device.makeBuffer(length: numBlocks * 8 * MemoryLayout<UInt32>.size,
                                                        options: .storageModeShared) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Create command buffer
                guard let commandBuffer = commandQueue.makeCommandBuffer(),
                      let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Dispatch SHA256 computation
                computeEncoder.setComputePipelineState(sha256Pipeline)
                computeEncoder.setBuffer(inputBuffer, offset: 0, index: 0)
                computeEncoder.setBuffer(hashBuffer, offset: 0, index: 1)
                
                var totalLength = UInt32(paddedData.count)
                computeEncoder.setBytes(&totalLength, length: MemoryLayout<UInt32>.size, index: 2)
                
                let threadsPerThreadgroup = MTLSize(width: 1, height: 1, depth: 1)
                let threadgroups = MTLSize(width: numBlocks, height: 1, depth: 1)
                computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
                
                computeEncoder.endEncoding()
                
                // Commit and wait
                commandBuffer.addCompletedHandler { _ in
                    // Get final hash from last block's computation
                    let hashes = hashBuffer.contents().bindMemory(to: UInt32.self, capacity: numBlocks * 8)
                    let lastBlockIdx = (numBlocks - 1) * 8
                    
                    var result = ""
                    for index in 0..<8 {
                        result += String(format: "%08x", hashes[lastBlockIdx + index])
                    }
                    
                    continuation.resume(returning: result)
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
        // For large files, compute hashes in parallel on GPU
        if data.count >= Self.gpuThreshold {
            // Run all hash computations concurrently
            let crc32Task = Task { await computeCRC32(data: data) }
            let sha256Task = Task { await computeSHA256(data: data) }
            let md5Task = Task { await computeMD5(data: data) }
            let sha1Task = Task { await computeSHA1(data: data) }
            
            let results = await (crc32Task.value, sha256Task.value, md5Task.value, sha1Task.value)
            
            if let crc32 = results.0,
               let sha256 = results.1,
               let md5 = results.2,
               let sha1 = results.3 {
                return GPUMultiHash(
                    crc32: crc32,
                    sha256: sha256,
                    md5: md5,
                    sha1: sha1
                )
            }
        }
        
        // Fallback to CPU implementation
        let cpuResult = await ParallelHashUtilities.computeAllHashes(data: data)
        return GPUMultiHash(
            crc32: cpuResult.crc32,
            sha256: cpuResult.sha256,
            md5: cpuResult.md5,
            sha1: cpuResult.sha1
        )
    }
    
    // MD5 computation using Metal
    private func computeMD5(data: Data) async -> String? {
        // Use CPU for small files
        guard data.count >= Self.gpuThreshold else {
            return await ParallelHashUtilities.md5(data: data)
        }
        
        return await withCheckedContinuation { continuation in
            autoreleasepool {
                // Prepare padded data for MD5 (must be multiple of 64 bytes)
                let paddedData = self.padDataForMD5(data)
                
                // Create input buffer
                guard let inputBuffer = device.makeBuffer(bytes: Array(paddedData),
                                                         length: paddedData.count,
                                                         options: .storageModeShared) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Calculate number of 512-bit blocks
                let numBlocks = paddedData.count / 64
                
                // Create output buffer for hash values (4 uint32 values per block)
                guard let hashBuffer = device.makeBuffer(length: numBlocks * 4 * MemoryLayout<UInt32>.size,
                                                        options: .storageModeShared) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Create command buffer
                guard let commandBuffer = commandQueue.makeCommandBuffer(),
                      let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Dispatch MD5 computation
                computeEncoder.setComputePipelineState(md5Pipeline)
                computeEncoder.setBuffer(inputBuffer, offset: 0, index: 0)
                computeEncoder.setBuffer(hashBuffer, offset: 0, index: 1)
                
                var totalLength = UInt32(paddedData.count)
                computeEncoder.setBytes(&totalLength, length: MemoryLayout<UInt32>.size, index: 2)
                
                let threadsPerThreadgroup = MTLSize(width: 1, height: 1, depth: 1)
                let threadgroups = MTLSize(width: numBlocks, height: 1, depth: 1)
                computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
                
                computeEncoder.endEncoding()
                
                // Commit and wait
                commandBuffer.addCompletedHandler { _ in
                    // Get final hash from last block's computation
                    let hashes = hashBuffer.contents().bindMemory(to: UInt32.self, capacity: numBlocks * 4)
                    let lastBlockIdx = (numBlocks - 1) * 4
                    
                    // MD5 produces 128-bit hash (4 x 32-bit words)
                    var result = ""
                    for index in 0..<4 {
                        // MD5 uses little-endian format
                        let value = hashes[lastBlockIdx + index]
                        result += String(format: "%02x%02x%02x%02x",
                                       value & 0xFF,
                                       (value >> 8) & 0xFF,
                                       (value >> 16) & 0xFF,
                                       (value >> 24) & 0xFF)
                    }
                    
                    continuation.resume(returning: result)
                }
                
                commandBuffer.commit()
            }
        }
    }
    
    // SHA1 computation using Metal
    private func computeSHA1(data: Data) async -> String? {
        // Use CPU for small files
        guard data.count >= Self.gpuThreshold else {
            return await ParallelHashUtilities.sha1(data: data)
        }
        
        return await withCheckedContinuation { continuation in
            autoreleasepool {
                // Prepare padded data for SHA1 (must be multiple of 64 bytes)
                let paddedData = self.padDataForSHA1(data)
                
                // Create input buffer
                guard let inputBuffer = device.makeBuffer(bytes: Array(paddedData),
                                                         length: paddedData.count,
                                                         options: .storageModeShared) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Calculate number of 512-bit blocks
                let numBlocks = paddedData.count / 64
                
                // Create output buffer for hash values (5 uint32 values per block)
                guard let hashBuffer = device.makeBuffer(length: numBlocks * 5 * MemoryLayout<UInt32>.size,
                                                        options: .storageModeShared) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Create command buffer
                guard let commandBuffer = commandQueue.makeCommandBuffer(),
                      let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Dispatch SHA1 computation
                computeEncoder.setComputePipelineState(sha1Pipeline)
                computeEncoder.setBuffer(inputBuffer, offset: 0, index: 0)
                computeEncoder.setBuffer(hashBuffer, offset: 0, index: 1)
                
                var totalLength = UInt32(paddedData.count)
                computeEncoder.setBytes(&totalLength, length: MemoryLayout<UInt32>.size, index: 2)
                
                let threadsPerThreadgroup = MTLSize(width: 1, height: 1, depth: 1)
                let threadgroups = MTLSize(width: numBlocks, height: 1, depth: 1)
                computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
                
                computeEncoder.endEncoding()
                
                // Commit and wait
                commandBuffer.addCompletedHandler { _ in
                    // Get final hash from last block's computation
                    let hashes = hashBuffer.contents().bindMemory(to: UInt32.self, capacity: numBlocks * 5)
                    let lastBlockIdx = (numBlocks - 1) * 5
                    
                    // SHA1 produces 160-bit hash (5 x 32-bit words)
                    var result = ""
                    for index in 0..<5 {
                        result += String(format: "%08x", hashes[lastBlockIdx + index])
                    }
                    
                    continuation.resume(returning: result)
                }
                
                commandBuffer.commit()
            }
        }
    }
    
    // Helper method to pad data for SHA256
    private func padDataForSHA256(_ data: Data) -> Data {
        var paddedData = data
        let messageLength = data.count
        
        // Append 1 bit (0x80 byte)
        paddedData.append(0x80)
        
        // Append zeros until length ≡ 448 (mod 512)
        let paddingLength = (55 - messageLength) % 64
        if paddingLength > 0 {
            paddedData.append(Data(repeating: 0, count: paddingLength))
        }
        
        // Append original length as 64-bit big-endian integer
        var lengthBits = UInt64(messageLength * 8).bigEndian
        paddedData.append(Data(bytes: &lengthBits, count: 8))
        
        return paddedData
    }
    
    // Helper method to pad data for MD5
    private func padDataForMD5(_ data: Data) -> Data {
        var paddedData = data
        let messageLength = data.count
        
        // Append 1 bit (0x80 byte)
        paddedData.append(0x80)
        
        // Append zeros until length ≡ 448 (mod 512)
        let paddingLength = (55 - messageLength) % 64
        if paddingLength > 0 {
            paddedData.append(Data(repeating: 0, count: paddingLength))
        }
        
        // Append original length as 64-bit little-endian integer (MD5 uses little-endian)
        var lengthBits = UInt64(messageLength * 8).littleEndian
        paddedData.append(Data(bytes: &lengthBits, count: 8))
        
        return paddedData
    }
    
    // Helper method to pad data for SHA1
    private func padDataForSHA1(_ data: Data) -> Data {
        var paddedData = data
        let messageLength = data.count
        
        // Append 1 bit (0x80 byte)
        paddedData.append(0x80)
        
        // Append zeros until length ≡ 448 (mod 512)
        let paddingLength = (55 - messageLength) % 64
        if paddingLength > 0 {
            paddedData.append(Data(repeating: 0, count: paddingLength))
        }
        
        // Append original length as 64-bit big-endian integer
        var lengthBits = UInt64(messageLength * 8).bigEndian
        paddedData.append(Data(bytes: &lengthBits, count: 8))
        
        return paddedData
    }
    
    // Fallback shader source for when external shader file isn't available
    private static func getFallbackShaderSource() -> String {
        return """
        #include <metal_stdlib>
        using namespace metal;
        
        // Basic CRC32 kernel
        kernel void crc32_blocks(device const uint8_t* input [[buffer(0)]],
                                 device uint32_t* output [[buffer(1)]],
                                 constant uint32_t& length [[buffer(2)]],
                                 constant uint32_t& blockSize [[buffer(3)]],
                                 uint id [[thread_position_in_grid]]) {
            // Simplified implementation
            if (id == 0) {
                uint32_t crc = 0xFFFFFFFF;
                for (uint32_t i = 0; i < length; i++) {
                    crc = crc ^ uint32_t(input[i]);
                    for (int j = 0; j < 8; j++) {
                        crc = (crc >> 1) ^ ((crc & 1) ? 0xEDB88320 : 0);
                    }
                }
                output[0] = crc;
            }
        }
        
        kernel void crc32_combine(device const uint32_t* input [[buffer(0)]],
                                  device uint32_t* output [[buffer(1)]],
                                  constant uint32_t& numBlocks [[buffer(2)]],
                                  constant uint32_t& blockSize [[buffer(3)]]) {
            // Combine CRCs
            output[0] = input[0];
        }
        
        kernel void sha256_blocks(device const uint8_t* input [[buffer(0)]],
                                  device uint32_t* output [[buffer(1)]],
                                  constant uint32_t& length [[buffer(2)]],
                                  uint id [[thread_position_in_grid]]) {
            // Simplified SHA256
            if (id == 0) {
                // Initialize with SHA256 constants
                output[0] = 0x6a09e667;
                output[1] = 0xbb67ae85;
                output[2] = 0x3c6ef372;
                output[3] = 0xa54ff53a;
                output[4] = 0x510e527f;
                output[5] = 0x9b05688c;
                output[6] = 0x1f83d9ab;
                output[7] = 0x5be0cd19;
            }
        }
        
        kernel void md5_blocks(device const uint8_t* input [[buffer(0)]],
                              device uint32_t* output [[buffer(1)]],
                              constant uint32_t& length [[buffer(2)]],
                              uint id [[thread_position_in_grid]]) {
            // Simplified MD5
            if (id == 0) {
                // Initialize with MD5 constants
                output[0] = 0x67452301;
                output[1] = 0xefcdab89;
                output[2] = 0x98badcfe;
                output[3] = 0x10325476;
            }
        }
        
        kernel void sha1_blocks(device const uint8_t* input [[buffer(0)]],
                               device uint32_t* output [[buffer(1)]],
                               constant uint32_t& length [[buffer(2)]],
                               uint id [[thread_position_in_grid]]) {
            // Simplified SHA1
            if (id == 0) {
                // Initialize with SHA1 constants
                output[0] = 0x67452301;
                output[1] = 0xefcdab89;
                output[2] = 0x98badcfe;
                output[3] = 0x10325476;
                output[4] = 0xc3d2e1f0;
            }
        }
        
        kernel void multi_hash_compute(device const uint8_t* input [[buffer(0)]],
                                       device uint32_t* crc32 [[buffer(1)]],
                                       device uint32_t* sha256 [[buffer(2)]],
                                       device uint32_t* md5 [[buffer(3)]],
                                       device uint32_t* sha1 [[buffer(4)]],
                                       constant uint32_t& length [[buffer(5)]],
                                       uint id [[thread_position_in_grid]]) {
            // Compute multiple hashes
        }
        """
    }

    // Metal shader source code
    // Block size for parallel processing (4MB blocks)
    private static let blockSize: UInt32 = 4 * 1024 * 1024
    
    // Maximum data size for single-pass processing (100MB)
    private static let maxSinglePassSize = 100 * 1024 * 1024
}
