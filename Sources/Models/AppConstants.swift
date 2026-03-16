// ABOUTME: Central place for app-wide constants.
// ABOUTME: Change appID/appName here when the app is renamed.

import Foundation

enum AppConstants {
    static let appID = "factoryfloor"
    static let appName = "Factory Floor"

    static var appSupportDirectory: URL {
        let configBase: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            configBase = URL(fileURLWithPath: xdg)
        } else {
            configBase = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }
        return configBase.appendingPathComponent(appID)
    }

    static var worktreesDirectory: URL {
        appSupportDirectory.appendingPathComponent("worktrees")
    }
}
