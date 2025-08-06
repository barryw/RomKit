//
//  RomKitFormatRegistry.swift
//  RomKit
//
//  Created by Barry Walker on 8/5/25.
//

import Foundation

// MARK: - Format Registry

public class RomKitFormatRegistry {
    public static let shared = RomKitFormatRegistry()
    
    private var handlers: [String: any ROMFormatHandler] = [:]
    
    private init() {
        // Register default handlers
        // Logiqx is registered first as it's the industry standard
        register(LogiqxFormatHandler())
        register(MAMEFormatHandler())
        register(NoIntroFormatHandler())
        register(RedumpFormatHandler())
    }
    
    public func register(_ handler: any ROMFormatHandler) {
        handlers[handler.formatIdentifier] = handler
    }
    
    public func unregister(formatIdentifier: String) {
        handlers.removeValue(forKey: formatIdentifier)
    }
    
    public func handler(for formatIdentifier: String) -> (any ROMFormatHandler)? {
        return handlers[formatIdentifier]
    }
    
    public func detectFormat(from data: Data) -> (any ROMFormatHandler)? {
        // Check Logiqx first as it's the preferred format
        if let logiqxHandler = handlers["logiqx"] {
            let parser = logiqxHandler.createParser()
            if parser.canParse(data: data) {
                return logiqxHandler
            }
        }
        
        // Check other formats
        for (identifier, handler) in handlers where identifier != "logiqx" {
            let parser = handler.createParser()
            if parser.canParse(data: data) {
                return handler
            }
        }
        return nil
    }
    
    public func detectFormat(from url: URL) throws -> (any ROMFormatHandler)? {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return detectFormat(from: data)
    }
    
    public var availableFormats: [String] {
        return Array(handlers.keys).sorted()
    }
    
    public var availableHandlers: [any ROMFormatHandler] {
        return Array(handlers.values)
    }
}

// MARK: - Format Detection Result

public struct FormatDetectionResult {
    public let handler: any ROMFormatHandler
    public let confidence: Double
    public let formatName: String
    
    public init(handler: any ROMFormatHandler, confidence: Double = 1.0) {
        self.handler = handler
        self.confidence = confidence
        self.formatName = handler.formatName
    }
}