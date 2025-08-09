import Foundation
import RomKit

@main
struct TestIndex {
    static func main() async {
        do {
            // Create a test ZIP file
            let testDir = URL(fileURLWithPath: "/tmp/test_roms")
            try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
            
            // Create a sample ZIP with multiple entries
            let zipPath = testDir.appendingPathComponent("test.zip")
            let handler = FastZIPArchiveHandler()
            
            // Create test ROM data
            let entries: [(name: String, data: Data)] = [
                ("rom1.bin", Data(repeating: 0x01, count: 1024)),
                ("rom2.bin", Data(repeating: 0x02, count: 1024)),
                ("rom3.bin", Data(repeating: 0x03, count: 1024))
            ]
            
            try handler.create(at: zipPath, with: entries)
            
            // Now test indexing
            let dbPath = testDir.appendingPathComponent("test_index.db")
            let manager = try await ROMIndexManager(databasePath: dbPath)
            
            print("Adding source: \(testDir.path)")
            try await manager.addSource(testDir, showProgress: true)
            
            // Check statistics
            let stats = await manager.getStatistics()
            print("\nIndex Statistics:")
            print("  Total ROMs: \(stats.totalROMs)")
            print("  Unique ROMs: \(stats.uniqueCRCs)")
            
            // List entries
            let sources = await manager.listSources()
            for source in sources {
                print("\nSource: \(source.path)")
                print("  ROMs: \(source.romCount)")
                print("  Size: \(source.totalSize)")
            }
            
        } catch {
            print("Error: \(error)")
        }
    }
}
