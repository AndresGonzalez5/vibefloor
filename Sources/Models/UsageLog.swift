// ABOUTME: Local-only append-only usage log of UI and agent-state events.
// ABOUTME: Writes JSON Lines to <cacheDirectory>/usage.jsonl; nothing is ever sent over the network.

import Foundation

enum UsageLog {
    static var fileURL: URL {
        AppConstants.cacheDirectory.appendingPathComponent("usage.jsonl")
    }

    static let queue = DispatchQueue(label: "factoryfloor.usage-log")

    /// Append one event. Callable from any thread.
    // ponytail: no rotation (about 100 bytes per event at human rates); add rotation if volume proves otherwise.
    static func record(_ event: String, _ data: [String: String] = [:]) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var object = data
        object["event"] = event
        object["ts"] = formatter.string(from: Date())
        guard let json = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        let line = json + Data("\n".utf8)

        queue.async {
            let url = fileURL
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(line)
                    handle.closeFile()
                }
            } else {
                try? line.write(to: url, options: .atomic)
            }
        }
    }
}
