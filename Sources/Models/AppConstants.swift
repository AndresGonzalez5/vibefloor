// ABOUTME: Central place for app-wide constants.
// ABOUTME: Debug builds use separate IDs so they can run alongside release builds.

import Foundation

enum AppConstants {
    #if DEBUG
    static let appID = "factoryfloor-debug"
    static let appName = "Factory Floor Debug"
    #else
    static let appID = "factoryfloor"
    static let appName = "Factory Floor"
    #endif

    /// Config directory: ~/.config/factoryfloor[-debug]/ (respects XDG_CONFIG_HOME).
    /// Falls back to the release config directory if the debug one doesn't exist.
    static var configDirectory: URL {
        let configBase: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            configBase = URL(fileURLWithPath: xdg)
        } else {
            configBase = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }
        let dir = configBase.appendingPathComponent(appID)
        #if DEBUG
        if !FileManager.default.fileExists(atPath: dir.path) {
            let releaseDir = configBase.appendingPathComponent("factoryfloor")
            if FileManager.default.fileExists(atPath: releaseDir.path) {
                return releaseDir
            }
        }
        #endif
        return dir
    }

    /// Worktrees are always shared between debug and release builds.
    static var worktreesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".factoryfloor")
            .appendingPathComponent("worktrees")
    }
}
