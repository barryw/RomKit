//
//  FormatHandlersTests.swift
//  RomKitTests
//
//  Tests for Format Handlers to improve code coverage
//

import Testing
import Foundation
@testable import RomKit

struct FormatHandlersTests {
    
    @Test func testNoIntroFormatHandler() {
        let handler = NoIntroFormatHandler()
        
        #expect(handler.formatIdentifier == "no-intro")
        #expect(handler.formatName == "No-Intro")
        #expect(handler.supportedExtensions.contains("dat"))
        #expect(handler.supportedExtensions.contains("xml"))
    }
    
    @Test func testRedumpFormatHandler() {
        let handler = RedumpFormatHandler()
        
        #expect(handler.formatIdentifier == "redump")
        #expect(handler.formatName == "Redump")
        #expect(handler.supportedExtensions.contains("dat"))
        #expect(handler.supportedExtensions.contains("xml"))
    }
    
    @Test func testLogiqxFormatHandler() {
        let handler = LogiqxFormatHandler()
        
        #expect(handler.formatIdentifier == "logiqx")
        #expect(handler.formatName == "Logiqx DAT")
        #expect(handler.supportedExtensions.contains("dat"))
        #expect(handler.supportedExtensions.contains("xml"))
    }
}