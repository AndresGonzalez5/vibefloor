// ABOUTME: Handles atomic file writes for JSON persistence.
// ABOUTME: Ensures the config directory exists and writes via temp file for crash safety.

import Foundation
import OSLog

private let logger = Logger(subsystem: "factoryfloor", category: "file-persistence")

enum FilePersistence {
    /// Write data atomically to a file, creating parent directories if needed.
    /// Writes to a temporary file first, then renames for crash safety.
    static func writeAtomically(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let tempURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: tempURL, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            // Clean up temp file on failure
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }
}
