// ABOUTME: Central place for app-wide constants.
// ABOUTME: Change appID here when the app is renamed.

import Foundation

enum AppConstants {
    static let appID = "ff2"

    static var appSupportDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".\(appID)")
    }

    static var worktreesDirectory: URL {
        appSupportDirectory.appendingPathComponent("worktrees")
    }
}
