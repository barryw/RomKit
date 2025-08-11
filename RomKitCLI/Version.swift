//
//  Version.swift
//  RomKit CLI - Version Management
//
//  Provides version information for the CLI tool
//

import Foundation

/// Version information for RomKit CLI
public struct Version {
    /// The version string to display
    public static var current: String {
        // Check for version override from build environment
        if let envVersion = ProcessInfo.processInfo.environment["ROMKIT_VERSION"] {
            return envVersion
        }
        
        // For release builds, check if we have a hardcoded version
        #if RELEASE
        return "1.0.0"  // This will be replaced by CI/CD
        #else
        // For debug/local builds, use git SHA
        return gitVersion ?? "dev"
        #endif
    }
    
    /// Get the git SHA for local builds
    private static var gitVersion: String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["rev-parse", "--short=8", "HEAD"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()  // Suppress error output
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    return output
                }
            }
        } catch {
            // Git not available or not in a git repo
        }
        
        return nil
    }
}