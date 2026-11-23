// ABOUTME: Keeps the Mac awake while a Claude Code session in a workstream is busy.
// ABOUTME: Bridges the gap in Claude's own caffeinate restart (kill-then-spawn every 240s).

import Foundation
import os

private let logger = Logger(subsystem: "factoryfloor", category: "sleep-guard")

@MainActor
final class ClaudeSleepGuard {
    static let shared = ClaudeSleepGuard()

    // ponytail: polls instead of watching the directory — Claude rewrites the
    // files in place, which directory watchers miss. Start latency is covered
    // by Claude's own inhibitor (its first gap is 240s in); release lags <=10s.
    private static let pollInterval: TimeInterval = 10

    private var activity: NSObjectProtocol?
    private var timer: Timer?

    private init() {}

    nonisolated static var sessionsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        let lookup = WorkstreamAgentStateTracker.shared.workstreamLookup
        setHeld(Self.hasBusySession(in: Self.sessionsDirectory) { lookup?($0) != nil })
    }

    /// True when some live Claude session (per its `~/.claude/sessions/<pid>.json`)
    /// is busy in a tracked workstream. Only "busy" counts, matching Claude's own
    /// inhibitor: "shell" (idle with a background task such as a dev server) and
    /// "waiting" (permission prompt) would otherwise hold the Mac awake indefinitely.
    nonisolated static func hasBusySession(in dir: URL, isTracked: (String) -> Bool) -> Bool {
        (liveSessions(in: dir) ?? []).contains { entry in
            guard entry.status == "busy", let cwd = entry.cwd else { return false }
            return isTracked(cwd)
        }
    }

    /// `sessionId`s of the live Claude sessions in `dir`; nil when the
    /// directory can't be listed (unknown, as opposed to "none live").
    nonisolated static func liveSessionIDs(in dir: URL = sessionsDirectory) -> Set<String>? {
        liveSessions(in: dir).map { Set($0.compactMap(\.sessionId)) }
    }

    private struct SessionFile: Decodable {
        let pid: Int32
        let status: String?
        let cwd: String?
        let sessionId: String?
    }

    /// Session files whose process is alive; nil when `dir` can't be listed.
    /// Malformed files are skipped.
    private nonisolated static func liveSessions(in dir: URL) -> [SessionFile]? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        return files.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let entry = try? JSONDecoder().decode(SessionFile.self, from: data) else { return nil }
            // ponytail: kill(pid, 0) drops files left behind by a crashed Claude;
            // PID reuse isn't checked (compare `procStart` if that ever matters).
            return kill(entry.pid, 0) == 0 ? entry : nil
        }
    }

    private func setHeld(_ held: Bool) {
        guard held != (activity != nil) else { return }
        if held {
            // .userInitiated: no idle system sleep and no App Nap (keeps this poll
            // on time); the display is still allowed to sleep.
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Claude Code session busy")
            logger.info("Holding sleep assertion: Claude Code session busy")
        } else if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
            logger.info("Released sleep assertion: no busy Claude Code sessions")
        }
    }
}
