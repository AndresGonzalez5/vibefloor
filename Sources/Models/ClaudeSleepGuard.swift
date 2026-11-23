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
        (scanSessions(in: dir)?.live ?? []).contains { entry in
            guard entry.status == "busy", let cwd = entry.cwd else { return false }
            return isTracked(cwd)
        }
    }

    /// `sessionId`s of the live Claude sessions in `dir`. Nil means unknown, not
    /// "none live": the directory can't be listed, a live pid's file can't be
    /// read or decoded (Claude rewrites them in place, so it may be mid-write),
    /// or a live session lacks `sessionId`. Dead-pid files are excluded regardless.
    nonisolated static func liveSessionIDs(in dir: URL = sessionsDirectory) -> Set<String>? {
        guard let scan = scanSessions(in: dir), !scan.hasUnreadable else { return nil }
        let ids = scan.live.compactMap(\.sessionId)
        return ids.count == scan.live.count ? Set(ids) : nil
    }

    private struct SessionFile: Decodable {
        let status: String?
        let cwd: String?
        let sessionId: String?
    }

    /// Session files (`<pid>.json`) in `dir` whose process is alive, and whether
    /// one of them couldn't be read or decoded. Nil when `dir` can't be listed.
    private nonisolated static func scanSessions(in dir: URL) -> (live: [SessionFile], hasUnreadable: Bool)? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        var live: [SessionFile] = []
        var hasUnreadable = false
        for url in files where url.pathExtension == "json" {
            // The pid comes from the filename, so a dead session's torn file
            // never counts. Digits only: kill() on 0 or a negative pid
            // targets a process group.
            // ponytail: kill(pid, 0) drops files left behind by a crashed Claude;
            // PID reuse isn't checked (compare `procStart` if that ever matters).
            let stem = url.deletingPathExtension().lastPathComponent
            guard stem.allSatisfy({ $0.isASCII && $0.isNumber }), let pid = Int32(stem), pid > 0,
                  kill(pid, 0) == 0 else { continue }
            guard let data = try? Data(contentsOf: url),
                  let entry = try? JSONDecoder().decode(SessionFile.self, from: data)
            else {
                hasUnreadable = true
                continue
            }
            live.append(entry)
        }
        return (live, hasUnreadable)
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
