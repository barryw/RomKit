//
//  BaseXMLParser.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation

/// Base class for XML-based DAT parsers with common functionality
public class BaseXMLParser: NSObject {

    // Common parsing utilities

    /// Parse integer from string, handling hex values
    func parseInt(_ string: String?) -> Int? {
        guard let string = string else { return nil }

        if string.hasPrefix("0x") {
            return Int(string.dropFirst(2), radix: 16)
        } else {
            return Int(string)
        }
    }

    /// Parse UInt64 from string, handling hex values
    func parseSize(_ string: String?) -> UInt64? {
        guard let string = string else { return nil }

        if string.hasPrefix("0x") {
            return UInt64(string.dropFirst(2), radix: 16)
        } else {
            return UInt64(string)
        }
    }

    /// Parse boolean from various string representations
    func parseBool(_ string: String?) -> Bool {
        guard let string = string?.lowercased() else { return false }
        return string == "yes" || string == "true" || string == "1"
    }

    /// Create ROM checksums from attributes
    func parseChecksums(crc: String?, sha1: String?, md5: String? = nil, sha256: String? = nil) -> ROMChecksums {
        return ROMChecksums(
            crc32: crc,
            sha1: sha1,
            sha256: sha256,
            md5: md5
        )
    }

    /// Parse ROM status
    func parseStatus(_ string: String?) -> ROMStatus {
        guard let string = string?.lowercased() else { return .good }

        switch string {
        case "good": return .good
        case "bad", "baddump": return .baddump
        case "nodump": return .nodump
        case "verified": return .verified
        default: return .good
        }
    }

    /// Check if XML data appears to be a specific format
    func checkXMLFormat(data: Data, rootElement: String, requiredElements: [String] = []) -> Bool {
        guard let xmlString = String(data: data.prefix(4096), encoding: .utf8) else {
            return false
        }

        // Check for root element
        if !xmlString.contains("<\(rootElement)") && !xmlString.contains("<\(rootElement)>") {
            return false
        }

        // Check for required elements if specified
        for element in requiredElements where !xmlString.contains("<\(element)") {
            return false
        }

        return true
    }

    /// Common error types for parsers
    enum ParsingError: Error, LocalizedError {
        case invalidFormat
        case missingRequiredElement(String)
        case invalidData

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "Invalid DAT file format"
            case .missingRequiredElement(let element):
                return "Missing required element: \(element)"
            case .invalidData:
                return "Invalid or corrupted data"
            }
        }
    }
}
