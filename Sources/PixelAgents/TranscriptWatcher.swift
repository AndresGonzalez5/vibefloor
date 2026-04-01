// ABOUTME: Monitors Claude Code JSONL transcript files for agent activity.
// ABOUTME: Tails .jsonl files in ~/.claude/projects/ and emits AgentEvent for each tool use.

import Foundation
import os

private let logger = Logger(subsystem: "factoryfloor", category: "transcript-watcher")

/// Watches Claude Code JSONL transcripts and emits pixel agent events.
///
/// Given a project working directory, it resolves the Claude project hash path,
/// finds the most recent active session .jsonl file, and tails it for tool_use / tool_result
/// records. Subagent transcripts are discovered dynamically — only new subagent files that
/// appear after watching starts will create pixel agent characters.
final class TranscriptWatcher: @unchecked Sendable {

    /// Callback invoked on the main queue whenever an agent event is detected.
    var onEvent: ((AgentEvent) -> Void)?

    private let projectDir: String
    private let claudeProjectPath: URL
    private let queue = DispatchQueue(label: "factoryfloor.transcript-watcher", qos: .utility)

    // MARK: - Thread Safety
    //
    // This class is `@unchecked Sendable` because all mutable state below is
    // accessed exclusively on `self.queue` (a serial DispatchQueue). Public
    // entry points (`start`, `stop`) dispatch onto the queue, and the
    // `onEvent` callback is forwarded to the main queue.
    //
    // DispatchSource cancel handlers (which close file descriptors) fire
    // reliably when sources are deallocated, so `deinit` calling `stop()`
    // with `[weak self]` guards is safe — the sources will still clean up
    // even if the async block finds `self` already nil.

    // Tracking state for each watched file
    private var watchedFiles: [URL: WatchedFile] = [:]
    private var directorySource: DispatchSourceFileSystemObject?
    private var pollTimer: DispatchSourceTimer?

    // The active session we're tracking (most recently modified .jsonl)
    private var activeSessionId: String?
    private var activeSessionDir: URL?

    // Known subagent files at start — we only create pixel agents for NEW ones
    private var initialSubagentFiles: Set<String> = []
    private var hasRecordedInitialSubagents = false

    // Palette assignment for agents
    private var nextPalette = 0
    private var agentPalettes: [String: Int] = [:]

    // Track active tools per agent to emit toolDone
    private var activeTools: [String: String] = [:]

    // Track last event time per agent for idle timeout
    private var lastEventTime: [String: Date] = [:]
    private let idleTimeout: TimeInterval = 3.0

    // Whether we've emitted the main Claude agent
    private var mainAgentCreated = false

    private struct WatchedFile {
        var offset: UInt64
        var agentId: String
        var fileSource: DispatchSourceFileSystemObject?
    }

    init(projectDir: String) {
        self.projectDir = projectDir
        self.claudeProjectPath = Self.resolveClaudeProjectPath(for: projectDir)
        logger.info("TranscriptWatcher init for: \(self.claudeProjectPath.path)")
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    func start() {
        queue.async { [weak self] in
            self?.setupWatching()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pollTimer?.cancel()
            self.pollTimer = nil
            self.directorySource?.cancel()
            self.directorySource = nil
            for (url, watched) in self.watchedFiles {
                watched.fileSource?.cancel()
                self.watchedFiles[url] = nil
            }
        }
    }

    // MARK: - Claude Project Path Resolution

    /// Converts a working directory path to the Claude project hash directory.
    /// Claude Code replaces both `/` and `.` with `-` in the path.
    /// e.g. /Users/foo/.factoryfloor/worktrees/bar → ~/.claude/projects/-Users-foo--factoryfloor-worktrees-bar/
    static func resolveClaudeProjectPath(for directory: String) -> URL {
        let sanitized = directory
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
            .appendingPathComponent(sanitized)
        return claudeDir
    }

    // MARK: - Watching Setup

    private func setupWatching() {
        // Always show the main Claude agent — even before a session exists
        emitMainAgentCreated()

        let dirPath = claudeProjectPath.path
        logger.info("Looking for Claude transcripts at: \(dirPath)")

        if FileManager.default.fileExists(atPath: dirPath) {
            findAndWatchActiveSession()
        } else {
            logger.info("Claude project path does not exist yet — will poll until it appears.")
        }

        startPollTimer()
    }

    /// Poll timer serves three purposes:
    /// 1. Re-discover active session if a newer one appears
    /// 2. Discover new subagent files
    /// 3. Poll watched files for new content (DispatchSource doesn't always fire)
    private func startPollTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            // Re-check for newer session (handles session starts after app launch)
            self.checkForNewerSession()
            // Poll all watched files for new content
            self.pollAllFiles()
            // Check for new subagent files
            self.scanForNewSubagents()
            // Return idle agents that haven't had activity
            self.checkIdleTimeouts()
        }
        pollTimer = timer
        timer.resume()
    }

    // MARK: - Active Session Discovery

    /// Checks if a newer session .jsonl has appeared and switches to it.
    /// Also handles the case where the Claude project dir didn't exist at startup.
    private func checkForNewerSession() {
        let fm = FileManager.default
        let dirPath = claudeProjectPath.path
        guard fm.fileExists(atPath: dirPath) else {
            // Directory might appear once Claude Code starts in this worktree
            return
        }
        guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { return }

        var latestDate: Date = .distantPast
        var latestSessionId: String?

        for entry in entries where entry.hasSuffix(".jsonl") {
            let filePath = claudeProjectPath.appendingPathComponent(entry)
            guard let attrs = try? fm.attributesOfItem(atPath: filePath.path),
                  let modDate = attrs[.modificationDate] as? Date else { continue }
            if modDate > latestDate {
                latestDate = modDate
                latestSessionId = String(entry.dropLast(6))
            }
        }

        guard let newSessionId = latestSessionId else { return }

        // If this is a different session than what we're watching, switch
        if newSessionId != activeSessionId {
            logger.info("Switching to newer session: \(newSessionId)")
            // Stop watching old files (but keep the main Claude agent)
            for (url, watched) in watchedFiles {
                watched.fileSource?.cancel()
                watchedFiles[url] = nil
            }
            // Reset subagent state
            initialSubagentFiles.removeAll()
            hasRecordedInitialSubagents = false
            activeTools.removeAll()
            // Remove any subagent pixel agents (keep main)
            for (agentId, _) in agentPalettes where agentId != "main" {
                emit(.removed(agentId: agentId))
            }
            agentPalettes = agentPalettes.filter { $0.key == "main" }

            findAndWatchActiveSession()
        }
    }

    /// Finds the most recently modified .jsonl file and watches it.
    private func findAndWatchActiveSession() {
        let fm = FileManager.default
        let dirPath = claudeProjectPath.path
        guard fm.fileExists(atPath: dirPath) else { return }
        guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { return }

        // Find the most recently modified .jsonl file
        var latestDate: Date = .distantPast
        var latestFile: URL?
        var latestSessionId: String?

        for entry in entries {
            guard entry.hasSuffix(".jsonl") else { continue }
            let filePath = claudeProjectPath.appendingPathComponent(entry)
            guard let attrs = try? fm.attributesOfItem(atPath: filePath.path),
                  let modDate = attrs[.modificationDate] as? Date else { continue }

            if modDate > latestDate {
                latestDate = modDate
                latestFile = filePath
                // Session ID is the filename without .jsonl
                latestSessionId = String(entry.dropLast(6))
            }
        }

        guard let sessionFile = latestFile, let sessionId = latestSessionId else {
            logger.info("No JSONL session files found")
            return
        }

        activeSessionId = sessionId
        activeSessionDir = claudeProjectPath.appendingPathComponent(sessionId)

        logger.info("Active session: \(sessionId) (modified: \(latestDate))")

        // Record existing subagent files so we don't create pixel agents for them
        recordInitialSubagents()

        // Watch the main session file
        watchFileIfNew(sessionFile, agentId: "main")
    }

    /// Record which subagent files already exist — we only animate NEW ones
    private func recordInitialSubagents() {
        guard let sessionDir = activeSessionDir else { return }
        let subagentsDir = sessionDir.appendingPathComponent("subagents")
        let fm = FileManager.default

        guard fm.fileExists(atPath: subagentsDir.path),
              let files = try? fm.contentsOfDirectory(atPath: subagentsDir.path) else {
            hasRecordedInitialSubagents = true
            return
        }

        for file in files where file.hasSuffix(".jsonl") {
            initialSubagentFiles.insert(file)
        }
        hasRecordedInitialSubagents = true
        logger.info("Recorded \(self.initialSubagentFiles.count) existing subagent files (will ignore)")
    }

    // MARK: - Subagent Discovery

    /// Check for new subagent .jsonl files that appeared since we started watching
    private func scanForNewSubagents() {
        guard hasRecordedInitialSubagents, let sessionDir = activeSessionDir else { return }

        let subagentsDir = sessionDir.appendingPathComponent("subagents")
        let fm = FileManager.default
        guard fm.fileExists(atPath: subagentsDir.path),
              let files = try? fm.contentsOfDirectory(atPath: subagentsDir.path) else { return }

        for file in files where file.hasSuffix(".jsonl") {
            // Skip files that existed before we started
            guard !initialSubagentFiles.contains(file) else { continue }

            let agentId = String(file.dropLast(6)) // remove .jsonl
            let filePath = subagentsDir.appendingPathComponent(file)

            // Only process if we haven't seen this file before
            guard watchedFiles[filePath] == nil else { continue }

            // This is a NEW subagent — create a pixel agent for it
            let metaFile = file.replacingOccurrences(of: ".jsonl", with: ".meta.json")
            let metaPath = subagentsDir.appendingPathComponent(metaFile)
            emitSubagentCreated(agentId: agentId, metaPath: metaPath)

            // Watch its transcript
            watchFileIfNew(filePath, agentId: agentId)

            logger.info("New subagent discovered: \(agentId)")
        }
    }

    // MARK: - File Watching

    private func watchFileIfNew(_ url: URL, agentId: String) {
        guard watchedFiles[url] == nil else { return }

        // Start from end of file (only watch new activity)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0

        var watched = WatchedFile(offset: fileSize, agentId: agentId, fileSource: nil)

        // Attach FS event source as primary notification
        let descriptor = open(url.path, O_EVTONLY)
        if descriptor >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.extend, .write],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.readNewLines(from: url)
            }
            source.setCancelHandler {
                close(descriptor)
            }
            watched.fileSource = source
            source.resume()
        }

        watchedFiles[url] = watched
        logger.info("Watching transcript: \(url.lastPathComponent) as \(agentId)")
    }

    // MARK: - Reading New Lines

    /// Poll all watched files for new content — fallback when DispatchSource doesn't fire
    private func pollAllFiles() {
        for url in watchedFiles.keys {
            readNewLines(from: url)
        }
    }

    private func readNewLines(from url: URL) {
        guard var watched = watchedFiles[url] else { return }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        // Check if file has grown
        handle.seekToEndOfFile()
        let currentSize = handle.offsetInFile
        guard currentSize > watched.offset else { return }

        // Read new data
        handle.seek(toFileOffset: watched.offset)
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return }

        watched.offset += UInt64(data.count)
        watchedFiles[url] = watched

        guard let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.components(separatedBy: "\n")
        for line in lines where !line.isEmpty {
            parseLine(line, agentId: watched.agentId)
        }
    }

    // MARK: - JSONL Parsing

    private func parseLine(_ line: String, agentId: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        guard let message = json["message"] as? [String: Any],
              let role = message["role"] as? String else { return }

        if role == "assistant" {
            parseAssistantMessage(message, agentId: agentId)
        } else if role == "user" {
            parseUserMessage(message, agentId: agentId)
        }
    }

    private func parseAssistantMessage(_ message: [String: Any], agentId: String) {
        guard let content = message["content"] as? [[String: Any]] else { return }

        for block in content {
            guard let blockType = block["type"] as? String else { continue }

            if blockType == "tool_use" {
                guard let toolName = block["name"] as? String else { continue }
                // Skip internal/meta tools
                guard !toolName.hasPrefix("mcp__") && toolName != "Skill" && toolName != "ToolSearch" else { continue }

                activeTools[agentId] = toolName
                lastEventTime[agentId] = Date()
                emit(.toolStart(agentId: agentId, tool: toolName))
            }
        }
    }

    private func parseUserMessage(_ message: [String: Any], agentId: String) {
        guard let content = message["content"] as? [[String: Any]] else { return }

        for block in content {
            guard let blockType = block["type"] as? String, blockType == "tool_result" else { continue }
            // A tool_result means the previous tool finished
            if activeTools[agentId] != nil {
                activeTools[agentId] = nil
                lastEventTime[agentId] = Date()
                emit(.toolDone(agentId: agentId))
            }
        }
    }

    // MARK: - Idle Timeout

    /// If an agent has been active (tool running) for longer than idleTimeout
    /// with no new events, emit toolDone to return it to idle.
    private func checkIdleTimeouts() {
        let now = Date()
        for (agentId, tool) in activeTools {
            guard let lastTime = lastEventTime[agentId] else { continue }
            if now.timeIntervalSince(lastTime) > idleTimeout {
                activeTools[agentId] = nil
                lastEventTime[agentId] = nil
                logger.debug("Idle timeout for \(agentId), was using \(tool)")
                emit(.toolDone(agentId: agentId))
            }
        }
    }

    // MARK: - Agent Creation

    private func emitMainAgentCreated() {
        guard !mainAgentCreated else { return }
        mainAgentCreated = true
        let palette = assignPalette(for: "main")
        emit(.created(agentId: "main", name: "Claude", palette: palette))
    }

    private func emitSubagentCreated(agentId: String, metaPath: URL) {
        guard agentPalettes[agentId] == nil else { return }

        var name = "Sub-agent"
        if let data = try? Data(contentsOf: metaPath),
           let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let desc = meta["description"] as? String {
            name = String(desc.prefix(20))
        }

        let palette = assignPalette(for: agentId)
        emit(.created(agentId: agentId, name: name, palette: palette))
    }

    private func assignPalette(for agentId: String) -> Int {
        if let existing = agentPalettes[agentId] { return existing }
        let palette = nextPalette % 6
        nextPalette += 1
        agentPalettes[agentId] = palette
        return palette
    }

    // MARK: - Emit Events

    private func emit(_ event: AgentEvent) {
        logger.debug("Agent event: \(event.type.rawValue) agent=\(event.agentId) tool=\(event.tool ?? "-")")
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }
}
