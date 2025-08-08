//
//  CallbackUsage.swift
//  RomKit Examples
//
//  Created by Barry Walker on 8/5/25.
//
//  Demonstrates various ways to use callbacks with RomKit

import Foundation
import RomKit

// MARK: - Example 1: Using Delegate Pattern

class RomKitController: RomKitDelegate {
    
    func scanWithDelegate() async throws {
        // Load DAT file
        let datURL = URL(fileURLWithPath: "/path/to/mame.dat")
        let datData = try Data(contentsOf: datURL)
        let parser = LogiqxDATParser()
        let datFile = try parser.parse(data: datData)
        
        // Create scanner with self as delegate
        let scanner = MAMEROMScanner(
            datFile: datFile,
            validator: MAMEROMValidator(),
            archiveHandlers: [ZIPArchiveHandler(), SevenZipArchiveHandler()],
            delegate: self
        )
        
        // Scan ROMs
        let romDirectory = URL(fileURLWithPath: "/path/to/roms")
        let results = try await scanner.scan(directory: romDirectory)
        
        print("Found \(results.foundGames.count) games")
    }
    
    // MARK: - RomKitDelegate Methods
    
    func romKit(didUpdateProgress progress: OperationProgress) {
        // Update UI progress bar
        let percentage = Int(progress.percentage * 100)
        print("[\(percentage)%] \(progress.message ?? "") - \(progress.currentItem ?? "")")
        
        if let eta = progress.estimatedTimeRemaining {
            print("ETA: \(formatTime(eta))")
        }
    }
    
    func romKit(didReceiveEvent event: RomKitEvent) {
        switch event {
        case .scanStarted(let path, let fileCount):
            print("📂 Scanning \(path) (\(fileCount) files)")
            
        case .gameFound(let name, let status):
            let statusIcon = status == .complete ? "✅" : status == .incomplete ? "⚠️" : "❌"
            print("\(statusIcon) \(name)")
            
        case .scanCompleted(let gamesFound, let duration):
            print("✨ Scan complete! Found \(gamesFound) games in \(formatTime(duration))")
            
        case .error(let error):
            print("❌ Error: \(error.localizedDescription)")
            
        case .warning(let message):
            print("⚠️ Warning: \(message)")
            
        default:
            break
        }
    }
    
    func romKitShouldCancel() -> Bool {
        // Check if user pressed cancel button
        return false // or check some cancellation flag
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "\(Int(seconds))s"
    }
}

// MARK: - Example 2: Using Closures

func scanWithClosures() async throws {
    // Load DAT file
    let datURL = URL(fileURLWithPath: "/path/to/mame.dat")
    let datData = try Data(contentsOf: datURL)
    let parser = LogiqxDATParser()
    let datFile = try parser.parse(data: datData)
    
    // Track progress for UI
    var progressBar: Double = 0.0
    var currentGame: String = ""
    
    // Create callbacks
    let callbacks = RomKitCallbacks(
        onProgress: { progress in
            progressBar = progress.percentage
            currentGame = progress.currentItem ?? ""
            
            // Update UI on main thread
            Task { @MainActor in
                updateProgressBar(progressBar)
                updateStatusLabel(currentGame)
            }
        },
        onEvent: { event in
            switch event {
            case .gameFound(let name, let status):
                print("Found: \(name) - \(status)")
                
            case .error(let error):
                Task { @MainActor in
                    showError(error.localizedDescription)
                }
                
            default:
                break
            }
        },
        shouldCancel: {
            // Return true if user cancelled
            return UserDefaults.standard.bool(forKey: "cancelOperation")
        },
        onCompletion: { result in
            switch result {
            case .success:
                print("✅ Operation completed successfully")
            case .failure(let error):
                print("❌ Operation failed: \(error)")
            }
        }
    )
    
    // Create scanner with callbacks
    let scanner = MAMEROMScanner(
        datFile: datFile,
        validator: MAMEROMValidator(),
        archiveHandlers: [ZIPArchiveHandler()],
        callbacks: callbacks
    )
    
    // Scan ROMs
    let romDirectory = URL(fileURLWithPath: "/path/to/roms")
    let results = try await scanner.scan(directory: romDirectory)
    
    print("Scan complete: \(results.foundGames.count) games found")
}

// MARK: - Example 3: Using Async Streams

func scanWithAsyncStreams() async throws {
    // Load DAT file
    let datURL = URL(fileURLWithPath: "/path/to/mame.dat")
    let datData = try Data(contentsOf: datURL)
    let parser = LogiqxDATParser()
    let datFile = try parser.parse(data: datData)
    
    // Create event stream
    let eventStream = RomKitEventStream()
    
    // Create scanner with event stream
    let scanner = MAMEROMScanner(
        datFile: datFile,
        validator: MAMEROMValidator(),
        archiveHandlers: [ZIPArchiveHandler()],
        eventStream: eventStream
    )
    
    // Process events concurrently
    Task { @MainActor in
        for await event in eventStream.events {
            await handleEvent(event)
        }
    }
    
    // Process progress concurrently
    Task {
        for await progress in eventStream.progress {
            await updateProgress(progress)
        }
    }
    
    // Scan ROMs
    let romDirectory = URL(fileURLWithPath: "/path/to/roms")
    let results = try await scanner.scan(directory: romDirectory)
    
    print("Found \(results.foundGames.count) games")
}

@MainActor
func handleEvent(_ event: RomKitEvent) async {
    switch event {
    case .scanStarted(let path, let fileCount):
        print("Starting scan of \(path) with \(fileCount) files")
        
    case .gameFound(let name, let status):
        addGameToList(name: name, status: status)
        
    case .scanCompleted(let gamesFound, let duration):
        showCompletionAlert(gamesFound: gamesFound, duration: duration)
        
    case .error(let error):
        showErrorAlert(error)
        
    default:
        break
    }
}

@MainActor
func updateProgress(_ progress: OperationProgress) async {
    // Update progress bar
    setProgressValue(progress.percentage)
    
    // Update status text
    if let message = progress.message {
        setStatusText(message)
    }
    
    // Update ETA
    if let eta = progress.estimatedTimeRemaining {
        setETAText("ETA: \(formatTime(eta))")
    }
}

// MARK: - Example 4: Rebuild with Progress

func rebuildWithProgress() async throws {
    // Load DAT file
    let datURL = URL(fileURLWithPath: "/path/to/mame.dat")
    let datData = try Data(contentsOf: datURL)
    let parser = LogiqxDATParser()
    let datFile = try parser.parse(data: datData)
    
    // Create progress tracking
    var rebuiltGames: [String] = []
    var failedGames: [String] = []
    
    let callbacks = RomKitCallbacks(
        onProgress: { progress in
            let percentage = Int(progress.percentage * 100)
            print("Rebuild Progress: \(percentage)% - \(progress.currentItem ?? "")")
        },
        onEvent: { event in
            switch event {
            case .rebuildStarted(let source, let destination):
                print("Starting rebuild from \(source) to \(destination)")
                
            case .rebuildingGame(let name, let index, let total):
                print("[\(index)/\(total)] Rebuilding \(name)...")
                
            case .gameRebuilt(let name, let success):
                if success {
                    rebuiltGames.append(name)
                    print("✅ \(name) rebuilt successfully")
                } else {
                    failedGames.append(name)
                    print("❌ \(name) failed to rebuild")
                }
                
            case .rebuildCompleted(let rebuilt, let failed, let duration):
                print("""
                
                Rebuild Complete!
                ================
                ✅ Rebuilt: \(rebuilt) games
                ❌ Failed: \(failed) games
                ⏱️ Duration: \(formatTime(duration))
                """)
                
            case .archiveCreating(let url):
                print("Creating archive: \(url.lastPathComponent)")
                
            case .archiveAdding(let fileName, let size):
                let sizeMB = Double(size) / 1024 / 1024
                print("  Adding \(fileName) (\(String(format: "%.2f", sizeMB)) MB)")
                
            default:
                break
            }
        }
    )
    
    // Create rebuilder
    let rebuilder = MAMEROMRebuilder(
        datFile: datFile,
        archiveHandlers: [ZIPArchiveHandler()],
        callbacks: callbacks
    )
    
    // Rebuild ROMs
    let sourceDir = URL(fileURLWithPath: "/path/to/source/roms")
    let destDir = URL(fileURLWithPath: "/path/to/rebuilt/roms")
    
    let results = try await rebuilder.rebuild(
        from: sourceDir,
        to: destDir,
        options: RebuildOptions(style: .split)
    )
    
    print("""
    
    Final Results:
    - Rebuilt: \(results.rebuilt)
    - Skipped: \(results.skipped)
    - Failed: \(results.failed)
    """)
}

// MARK: - Helper Functions (UI placeholders)

@MainActor func updateProgressBar(_ value: Double) {
    // Update your progress bar UI
}

@MainActor func updateStatusLabel(_ text: String) {
    // Update your status label
}

@MainActor func showError(_ message: String) {
    // Show error dialog
}

@MainActor func addGameToList(name: String, status: GameCompletionStatus) {
    // Add game to UI list
}

@MainActor func showCompletionAlert(gamesFound: Int, duration: TimeInterval) {
    // Show completion alert
}

@MainActor func showErrorAlert(_ error: RomKitCallbackError) {
    // Show error alert
}

@MainActor func setProgressValue(_ value: Double) {
    // Set progress bar value
}

@MainActor func setStatusText(_ text: String) {
    // Set status text
}

@MainActor func setETAText(_ text: String) {
    // Set ETA text
}

func formatTime(_ seconds: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: seconds) ?? "\(Int(seconds))s"
}