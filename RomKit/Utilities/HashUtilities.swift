//
//  HashUtilities.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation
import CryptoKit
import zlib

public struct HashUtilities {
    
    public static func crc32(data: Data) -> String {
        let crc = data.withUnsafeBytes { bytes in
            return zlib.crc32(0, bytes.bindMemory(to: UInt8.self).baseAddress, uInt(data.count))
        }
        return String(format: "%08x", crc)
    }
    
    public static func sha1(data: Data) -> String {
        let digest = Insecure.SHA1.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    public static func sha256(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    public static func md5(data: Data) -> String {
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
}