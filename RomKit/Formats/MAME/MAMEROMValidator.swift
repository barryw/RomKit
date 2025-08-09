//
//  MAMEROMValidator.swift
//  RomKit
//
//  MAME ROM validation functionality
//

import Foundation
import CryptoKit

/// MAME ROM Validator
public class MAMEROMValidator: ROMValidator {
    public let supportsCRC32 = true
    public let supportsSHA1 = true

    public func validate(item: any ROMItem, against data: Data) -> ValidationResult {
        let isValid: Bool
        let failureReason: String?
        let checksums = item.checksums

        if let crc32 = checksums.crc32 {
            let actualCRC32 = HashUtilities.crc32(data: data)
            if actualCRC32.lowercased() != crc32.lowercased() {
                isValid = false
                failureReason = "CRC32 mismatch: expected \(crc32), got \(actualCRC32)"
            } else if let sha1 = checksums.sha1 {
                let actualSHA1 = HashUtilities.sha1(data: data)
                if actualSHA1.lowercased() != sha1.lowercased() {
                    isValid = false
                    failureReason = "SHA1 mismatch: expected \(sha1), got \(actualSHA1)"
                } else {
                    isValid = true
                    failureReason = nil
                }
            } else {
                isValid = true
                failureReason = nil
            }
        } else {
            isValid = false
            failureReason = "No CRC32 checksum available for validation"
        }

        let actualChecksums = ROMChecksums(
            crc32: HashUtilities.crc32(data: data),
            sha1: HashUtilities.sha1(data: data),
            md5: HashUtilities.md5(data: data)
        )

        return ValidationResult(
            isValid: isValid,
            actualChecksums: actualChecksums,
            expectedChecksums: checksums,
            sizeMismatch: item.size != UInt64(data.count),
            errors: failureReason.map { [$0] } ?? []
        )
    }

    public func validate(item: any ROMItem, at url: URL) throws -> ValidationResult {
        let data = try Data(contentsOf: url)
        return validate(item: item, against: data)
    }

    public func computeChecksums(for data: Data) -> ROMChecksums {
        return ROMChecksums(
            crc32: HashUtilities.crc32(data: data),
            sha1: HashUtilities.sha1(data: data),
            md5: HashUtilities.md5(data: data)
        )
    }

    public func batchValidate(
        items: [any ROMItem],
        against archives: [URL],
        progress: ((Int, Int) -> Void)?
    ) async throws -> [String: ValidationResult] {
        // TODO: Implement batch validation
        return [:]
    }
}
