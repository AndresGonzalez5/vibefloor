// ABOUTME: Shared path utilities used across the app.
// ABOUTME: Replaces home directory prefix with ~ for display.

import Foundation

extension String {
    /// Replaces the home directory prefix with ~ for compact display.
    var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if hasPrefix(home) {
            return "~" + dropFirst(home.count)
        }
        return self
    }
}
