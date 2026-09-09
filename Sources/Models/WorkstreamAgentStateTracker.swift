// ABOUTME: Per-workstream Claude agent roster derived from lifecycle hook events.
// ABOUTME: Tracks main + subagent runs (activity, stalls) and drives the sidebar UI.

import Foundation
import os

private let logger = Logger(subsystem: "factoryfloor", category: "agent-state")

/// Tracks the live agent runs in each workstream.
///
/// State transitions are driven by hook events (`UserPromptSubmit` / `Stop`,
/// `PreToolUse` / `PostToolUse`, `SubagentStart` / `SubagentStop`). A run is
/// created when its agent spawns and removed when its stop hook arrives, so
/// the roster mirrors exactly what Claude Code reports — no artificial timers
/// govern visibility. The only timer is the stall sweep: a run that stops
/// emitting events while supposedly working flips to `.stalled`.
///
/// The high-level `AgentRunState` (driving the sidebar row dot) is kept in
/// sync alongside the roster.
@MainActor
final class WorkstreamAgentStateTracker: ObservableObject {
    static let shared = WorkstreamAgentStateTracker()

    enum NeedsReason: Equatable {
        case justFinished
        case permission
    }

    enum AgentRunState: Equatable {
        case idle
        case working
        /// No hook events for a while although the turn hasn't ended.
        case stalled
        case needsAttention(NeedsReason)
    }

    /// One live agent (main or subagent) inside a workstream.
    struct AgentRun: Identifiable, Equatable {
        enum RunState: Equatable {
            case working
            case stalled
        }

        /// Claude's agent id ("main" or a subagent id).
        let id: String
        /// Display name ("Claude"/"OpenCode" or the subagent type). Mutable:
        /// later events may refine it once the harness reports the agent type.
        var name: String
        let palette: Int
        /// False for delegated subagents. Var, not let: a child's first event
        /// can be a tool_start (creating a provisional main-flagged run)
        /// before its session_created lands and reclassifies it.
        var isMain: Bool
        /// Per-type occurrence slot: the lowest index not held by a live
        /// same-type run at creation. Drives sprite-set cycling in the roster
        /// (sprite shown is `variantIndex % setCount`).
        let variantIndex: Int
        var state: RunState
        /// What the agent is doing right now, e.g. "Editing Foo.swift".
        var activity: String?
        /// Model backing the run when the harness reports one.
        var model: String?
        /// Per-run context figures when the harness reports them directly
        /// (e.g. OpenCode child sessions via agent_info).
        var contextUsedTokens: Int?
        var contextLimitTokens: Int?
        /// Short task description the harness attaches to delegated subagents
        /// (OpenCode subtask parts); rendered as a roster subtitle. Kept out of
        /// `name` so sprite selection keeps keying off the agent type.
        var taskDescription: String?
        /// True while this run blocks on user input (permission prompt or
        /// question tool). Waiting runs never sweep to stalled, and any live
        /// waiter suppresses the row-level stall promotion.
        var isWaitingForUser: Bool = false
        let startedAt: Date
        var lastEventAt: Date
    }

    /// Context-window consumption of a workstream's main session.
    struct ContextUsage: Equatable {
        let usedTokens: Int
        let limitTokens: Int
        var fraction: Double {
            limitTokens > 0 ? Double(usedTokens) / Double(limitTokens) : 0
        }
    }

    static let stallThreshold: TimeInterval = 45
    private static let sweepInterval: TimeInterval = 15
    private static let contextReadInterval: TimeInterval = 5

    @Published private(set) var states: [UUID: AgentRunState] = [:]
    @Published private(set) var rosters: [UUID: [AgentRun]] = [:]
    /// Workstreams that have seen harness activity during this app launch.
    /// In-memory only by design ("part of my work today").
    @Published private(set) var liveSessionIDs: Set<UUID> = []
    /// Latest known context-window usage for each workstream's MAIN session.
    @Published private(set) var contextUsage: [UUID: ContextUsage] = [:]

    private var lastContextReadAt: [UUID: Date] = [:]
    /// Harness session currently tracked per workstream (OpenCode `session_id`).
    /// A new conversation in the same worktree must reset roster and context
    /// instead of mixing with the previous session's figures.
    private var currentSessionIDs: [UUID: String] = [:]
    /// Claude transcript path currently tracked per workstream. A different
    /// path mid-stream means a second Claude session in the same worktree.
    private var currentTranscriptPaths: [UUID: String] = [:]

    /// Resolves a Claude `project_dir` payload to the matching workstream UUID.
    /// Set by `ContentView` whenever the project list changes.
    var workstreamLookup: ((String) -> UUID?)?

    /// Currently selected workstream — `Stop` while selected goes straight to
    /// `.idle` because the user is already looking at it.
    var currentSelection: UUID?

    private var sweepTimer: Timer?

    private init() {}

    // MARK: - Public API

    func state(for id: UUID) -> AgentRunState {
        states[id] ?? .idle
    }

    /// Live agent runs for a workstream, main agent first.
    func runs(for id: UUID) -> [AgentRun] {
        rosters[id] ?? []
    }

    /// Number of live agent runs (main + subagents).
    func activeRunCount(for id: UUID) -> Int {
        rosters[id]?.count ?? 0
    }

    /// Clears the `.justFinished` blue state. Permission state is preserved
    /// because it still blocks Claude even after the user has looked at the row.
    func markSeen(workstreamID: UUID) {
        if case .needsAttention(.justFinished) = states[workstreamID] {
            states[workstreamID] = .idle
        }
    }

    /// True while the workstream has seen harness activity this app launch.
    func hasLiveSession(for id: UUID) -> Bool {
        liveSessionIDs.contains(id)
    }

    /// Context usage of the workstream's main session, regardless of harness:
    /// prefers the transcript-derived figure (Claude Code), falling back to
    /// the per-run totals the harness reported (OpenCode `agent_info`).
    /// Returns nil while no main run is live or nothing has been reported yet.
    func mainContextUsage(for id: UUID) -> ContextUsage? {
        if let rowLevel = contextUsage[id] { return rowLevel }
        guard let main = rosters[id]?.first(where: { $0.isMain }),
              let used = main.contextUsedTokens,
              let limit = main.contextLimitTokens,
              limit > 0 else { return nil }
        return ContextUsage(usedTokens: used, limitTokens: limit)
    }

    /// Drops all tracked state for a workstream (called when it is removed).
    func clear(workstreamID: UUID) {
        states.removeValue(forKey: workstreamID)
        rosters.removeValue(forKey: workstreamID)
        liveSessionIDs.remove(workstreamID)
        contextUsage.removeValue(forKey: workstreamID)
        lastContextReadAt.removeValue(forKey: workstreamID)
        currentSessionIDs.removeValue(forKey: workstreamID)
        currentTranscriptPaths.removeValue(forKey: workstreamID)
    }

    /// Clears every tracked state. Used by tests to isolate cases.
    func resetForTesting() {
        states.removeAll()
        rosters.removeAll()
        liveSessionIDs.removeAll()
        contextUsage.removeAll()
        lastContextReadAt.removeAll()
        currentSessionIDs.removeAll()
        currentTranscriptPaths.removeAll()
        workstreamLookup = nil
        currentSelection = nil
    }

    /// Backdates a run's last-event timestamp. Used by stall sweep unit tests.
    func _backdateRun(agentId: String, workstreamID: UUID, lastEventAt: Date) {
        guard var list = rosters[workstreamID],
              let idx = list.firstIndex(where: { $0.id == agentId }) else { return }
        list[idx].lastEventAt = lastEventAt
        rosters[workstreamID] = list
    }

    /// Aggressive path normalization: resolves symlinks (e.g. `/private/var` ↔ `/var`)
    /// in addition to the `.standardized` collapse. Hook payloads and stored
    /// `worktreePath`s have come through different code paths and may differ in
    /// symlink form.
    static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardized.path
    }

    // MARK: - Event Handling

    func handle(projectDir: String, event: AgentEvent) {
        guard let lookup = workstreamLookup, let wsID = lookup(projectDir) else {
            // Common: Claude sessions running outside any tracked workstream.
            logger.debug("No workstream match for projectDir: \(projectDir, privacy: .public)")
            return
        }

        ensureSweepTimer()
        liveSessionIDs.insert(wsID)
        detectSessionSwitch(wsID: wsID, event: event)
        updateRoster(wsID: wsID, event: event)
        // Permission/question prompts block forward progress no matter which
        // run asked — a subagent waiting on input still needs the user to act,
        // so any live waiter raises row-level attention (decision: option A).
        if event.type == .agentStatus, event.status == "permissionRequired" {
            states[wsID] = .needsAttention(.permission)
        }
        if event.agentId == "main" {
            updateMainState(wsID: wsID, event: event)
            if let transcriptPath = event.transcriptPath {
                refreshContextUsage(wsID: wsID, transcriptPath: transcriptPath, force: event.type == .agentIdle)
            }
        } else if event.type == .agentToolStart, event.tool != "respond" {
            // A subagent resuming real tool activity clears row attention only
            // once no live run still waits on the user.
            clearPermissionIfNoWaiters(wsID: wsID, event: event)
        }
    }

    /// Clears row-level permission attention after tool activity, unless some
    /// other live run is still waiting on the user.
    private func clearPermissionIfNoWaiters(wsID: UUID, event: AgentEvent) {
        guard case .needsAttention(.permission) = states[wsID] else { return }
        let stillWaiting = rosters[wsID]?.contains(where: { $0.isWaitingForUser }) ?? false
        if !stillWaiting {
            states[wsID] = .working
        }
    }

    /// Detects that the workstream's tracked conversation was replaced and
    /// resets to the new session so stale roster runs and context snapshots
    /// don't leak across sessions sharing one worktree.
    private func detectSessionSwitch(wsID: UUID, event: AgentEvent) {
        // Explicit harness signal (opencode `session_switched`) always wins.
        if event.type == .agentSessionSwitched, let sid = event.sessionID, !sid.isEmpty {
            // A switch target matching a live roster run is a misattributed
            // child session (e.g. a subagent prompt misread as a conversation
            // switch), never a new conversation — ignore it, don't wipe.
            if (rosters[wsID]?.contains(where: { $0.id == sid })) == true {
                logger.info("Session switch to live run \(sid, privacy: .public) in workstream \(wsID) — ignoring")
                return
            }
            if currentSessionIDs[wsID] != sid {
                logger.info("Session switched in workstream \(wsID) — resetting to new session")
                resetToNewSession(wsID: wsID, sessionID: sid)
                currentTranscriptPaths.removeValue(forKey: wsID)
            }
            return
        }
        // Implicit: a new user prompt carrying an unknown session id (e.g. a
        // resumed opencode session, which emits no session.created). Only
        // turn-start events trigger this — late stragglers from the previous
        // session (idle, tool_done, info) must never rewind the reset; the
        // scoped idle guard below drops those instead. Subagent runs carry
        // their own ids and must not trigger this either.
        if event.type == .agentWaiting, event.agentId == "main",
           let sid = event.sessionID, !sid.isEmpty {
            if let current = currentSessionIDs[wsID] {
                if current != sid {
                    // A new prompt on an unknown session usually means a
                    // resumed/switched conversation — but with live subagents
                    // it is more likely a misattributed straggler than a real
                    // switch, so preserve the roster and only repoint the
                    // tracked session + context. Explicit session_switched
                    // still performs the full reset above.
                    if (rosters[wsID]?.contains(where: { !$0.isMain })) == true {
                        logger.info("New harness session with live subagents in workstream \(wsID) — preserving roster")
                        currentSessionIDs[wsID] = sid
                        contextUsage.removeValue(forKey: wsID)
                        lastContextReadAt.removeValue(forKey: wsID)
                        currentTranscriptPaths.removeValue(forKey: wsID)
                    } else {
                        logger.info("New harness session in workstream \(wsID) — resetting to new session")
                        resetToNewSession(wsID: wsID, sessionID: sid)
                        currentTranscriptPaths.removeValue(forKey: wsID)
                    }
                }
            } else {
                currentSessionIDs[wsID] = sid
            }
        }
        // Claude side: a different transcript path mid-stream means another
        // Claude session in the same worktree. Drop the old snapshot (and the
        // read throttle, so the new file is read immediately) rather than
        // letting interleaved reads flicker the meter. The roster is left
        // alone — concurrent Claudes share the main run and can't be split.
        if event.agentId == "main", let path = event.transcriptPath, !path.isEmpty {
            if let current = currentTranscriptPaths[wsID] {
                if current != path {
                    currentTranscriptPaths[wsID] = path
                    contextUsage.removeValue(forKey: wsID)
                    lastContextReadAt.removeValue(forKey: wsID)
                }
            } else {
                currentTranscriptPaths[wsID] = path
            }
        }
    }

    /// Resets a workstream's tracked conversation to a new session: the old
    /// roster, its context snapshot, and the read throttle are dropped so the
    /// new session's live figures show immediately.
    private func resetToNewSession(wsID: UUID, sessionID: String) {
        rosters.removeValue(forKey: wsID)
        contextUsage.removeValue(forKey: wsID)
        lastContextReadAt.removeValue(forKey: wsID)
        currentSessionIDs[wsID] = sessionID
        states[wsID] = .working
    }

    private func updateRoster(wsID: UUID, event: AgentEvent) {
        let now = Date()
        var list = rosters[wsID] ?? []

        func upsert(_ agentId: String, name: String? = nil, palette: Int = 0, isMain: Bool = true, variantIndex: Int = 0, mutate: (inout AgentRun) -> Void = { _ in }) {
            if let idx = list.firstIndex(where: { $0.id == agentId }) {
                mutate(&list[idx])
                // Harnesses may report the display name after a run's first
                // event (e.g. OpenCode child sessions); apply refinements.
                if let name, !name.isEmpty, name != list[idx].name {
                    list[idx].name = name
                }
                list[idx].lastEventAt = now
            } else {
                var run = AgentRun(
                    id: agentId,
                    name: name ?? "Claude",
                    palette: palette,
                    isMain: isMain,
                    variantIndex: variantIndex,
                    state: .working,
                    activity: nil,
                    model: nil,
                    startedAt: now,
                    lastEventAt: now
                )
                mutate(&run)
                list.append(run)
            }
        }

        switch event.type {
        case .agentCreated:
            // A duplicate create (OpenCode re-forwards the subtask part to
            // enrich an already-registered child) refines the existing run's
            // attributes instead of recreating it.
            let fallbackName = NSLocalizedString("Sub-agent", comment: "Fallback name for an unnamed subagent")
            let name = event.name ?? fallbackName
            if let idx = list.firstIndex(where: { $0.id == event.agentId }) {
                // session_created is authoritative: this id is a subagent, even
                // if its first-seen event (e.g. an early tool_start) provisionally
                // created it as main.
                list[idx].isMain = false
                if !name.isEmpty, name != list[idx].name {
                    list[idx].name = name
                }
                if let description = event.taskDescription, !description.isEmpty {
                    list[idx].taskDescription = description
                }
                list[idx].lastEventAt = now
            } else {
                upsert(
                    event.agentId,
                    name: name,
                    palette: event.palette ?? 1,
                    isMain: false,
                    variantIndex: Self.nextVariantIndex(for: name, in: list)
                ) { run in
                    if let description = event.taskDescription, !description.isEmpty {
                        run.taskDescription = description
                    }
                }
            }

        case .agentRemoved:
            list.removeAll { $0.id == event.agentId }

        case .agentToolStart:
            // Tool kinds: "respond" is the streaming heartbeat (keeps the run
            // alive but never answers a prompt); "reply" is an explicit
            // user-answered signal from the plugin; anything else is real tool
            // activity. A new user turn (agentWaiting) also clears waiting.
            // Only the "main" id is the main run — a child's early tool_start
            // (before its session_created) must not mint a main-flagged ghost.
            upsert(event.agentId, name: event.name, isMain: event.agentId == "main") { run in
                if event.tool == "reply" {
                    run.activity = nil
                    run.isWaitingForUser = false
                } else if event.tool == "respond" {
                    // Heartbeat only — keep activity text and waiting flag.
                } else {
                    run.activity = event.activity ?? run.activity
                    run.isWaitingForUser = false
                }
                if run.state == .stalled, !run.isWaitingForUser { run.state = .working }
            }
            if event.agentId == "main", state(for: wsID) == .stalled, event.tool != "respond" {
                states[wsID] = .working
            }

        case .agentToolDone:
            if let idx = list.firstIndex(where: { $0.id == event.agentId }) {
                list[idx].activity = nil
                list[idx].lastEventAt = now
            }

        case .agentWaiting:
            upsert(event.agentId, name: event.name, isMain: event.agentId == "main") { run in
                run.isWaitingForUser = false
            }

        case .agentInfo:
            // Attribute-only refresh: update an existing run's name/model
            // without touching state. Info can also arrive before any tool
            // or prompt event (OpenCode streams message.updated early); in
            // that case create the MAIN run so its context figures land —
            // subagents are still never created from info alone.
            if event.agentId == "main", !list.contains(where: { $0.id == "main" }) {
                upsert("main", name: event.name) { run in
                    run.model = event.model ?? run.model
                    run.contextUsedTokens = event.contextUsedTokens ?? run.contextUsedTokens
                    run.contextLimitTokens = event.contextLimitTokens ?? run.contextLimitTokens
                }
            } else if let idx = list.firstIndex(where: { $0.id == event.agentId }) {
                if let name = event.name, !name.isEmpty, name != list[idx].name {
                    list[idx].name = name
                }
                if let model = event.model {
                    list[idx].model = model
                }
                if let used = event.contextUsedTokens {
                    list[idx].contextUsedTokens = used
                }
                if let limit = event.contextLimitTokens {
                    list[idx].contextLimitTokens = limit
                }
                list[idx].lastEventAt = now
            }

        case .agentIdle:
            // Main going idle ends its own run; live subagents keep working
            // (the parent often idles right after delegating). Snapshot the
            // main run's last known context figures first — OpenCode reports
            // them per-run only, and the row keeps showing usage until the
            // next turn.
            if event.agentId == "main" {
                // A late idle from a superseded session must not wipe the
                // new conversation's live roster or re-snapshot stale figures.
                if let sid = event.sessionID,
                   let current = currentSessionIDs[wsID],
                   sid != current {
                    break
                }
                if let main = list.first(where: \.isMain),
                   let used = main.contextUsedTokens,
                   let limit = main.contextLimitTokens,
                   limit > 0 {
                    contextUsage[wsID] = ContextUsage(usedTokens: used, limitTokens: limit)
                }
                // ponytail: main idle removes only main while children live;
                // children leave via their own idle. Full clear only when alone.
                if list.contains(where: { !$0.isMain }) {
                    list.removeAll { $0.isMain }
                } else {
                    list.removeAll()
                }
            } else {
                list.removeAll { $0.id == event.agentId }
            }

        case .agentSessionSwitched:
            // Reset already performed in detectSessionSwitch before this ran;
            // no roster mutation here.
            break

        case .agentStatus:
            // A permission/question prompt marks that run as waiting on the
            // user (row-level attention is raised in handle(), for any agent).
            // Other statuses (e.g. idle nudges) just prove liveness.
            // Waiting is keyed off tool identity and structured bus events,
            // never off code content — editing files about questions or
            // permissions does not land here.
            if event.status == "permissionRequired" {
                upsert(event.agentId, name: event.name, isMain: event.agentId == "main") { run in
                    run.isWaitingForUser = true
                }
            } else if let idx = list.firstIndex(where: { $0.id == event.agentId }) {
                list[idx].lastEventAt = now
            }
            break
        }

        if list.isEmpty {
            rosters.removeValue(forKey: wsID)
        } else {
            // Main agent first so the sidebar reads top-down.
            list.sort { ($0.isMain ? 0 : 1, $0.startedAt) < ($1.isMain ? 0 : 1, $1.startedAt) }
            rosters[wsID] = list
        }
    }

    /// Reads context usage from the transcript tail. Throttled to one read per
    /// `contextReadInterval` — except at turn end (idle), where the final
    /// totals must land even if a read just happened. A failed read keeps any
    /// previous value.
    private func refreshContextUsage(wsID: UUID, transcriptPath: String, force: Bool) {
        let now = Date()
        if !force, let last = lastContextReadAt[wsID], now.timeIntervalSince(last) < Self.contextReadInterval {
            return
        }
        lastContextReadAt[wsID] = now
        guard let parsed = TranscriptContextReader.usage(transcriptPath: transcriptPath) else { return }
        contextUsage[wsID] = ContextUsage(usedTokens: parsed.usedTokens, limitTokens: parsed.limitTokens)
    }

    private func updateMainState(wsID: UUID, event: AgentEvent) {
        switch event.type {
        case .agentWaiting, .agentSessionSwitched:
            states[wsID] = .working

        case .agentIdle:
            // Ignore a late idle from a superseded session.
            if let sid = event.sessionID,
               let current = currentSessionIDs[wsID],
               sid != current {
                return
            }
            if currentSelection == wsID {
                states[wsID] = .idle
            } else {
                states[wsID] = .needsAttention(.justFinished)
            }

        case .agentStatus:
            if event.status == "permissionRequired" {
                states[wsID] = .needsAttention(.permission)
            }

        case .agentToolStart, .agentToolDone:
            // Real tool activity while awaiting permission means the user
            // answered the prompt (there's no explicit "granted" hook).
            // The "respond" streaming heartbeat must never clear it — that's
            // what used to flip question-waits back to Working right before
            // they decayed into Stalled. Otherwise no state change — prevents
            // flicker between tools. Only clears when no other live run still
            // waits (a sibling may still block on the user).
            if event.tool == "respond" { break }
            if case .needsAttention(.permission) = states[wsID] {
                let stillWaiting = rosters[wsID]?.contains(where: {
                    $0.isWaitingForUser && $0.id != event.agentId
                }) ?? false
                if !stillWaiting {
                    states[wsID] = .working
                }
            }

        case .agentCreated, .agentRemoved, .agentInfo:
            break
        }
    }

    // MARK: - Variant Assignment

    /// Lowest variant index not held by a live run of the same type. Cycling
    /// happens at render time (`variantIndex % setCount`), so indices beyond
    /// the sprite count wrap back to the first sprite.
    static func nextVariantIndex(for name: String, in runs: [AgentRun]) -> Int {
        let key = AgentSpriteStore.normalizeTypeName(name)
        let used = Set(runs.filter { AgentSpriteStore.normalizeTypeName($0.name) == key }.map(\.variantIndex))
        var index = 0
        while used.contains(index) { index += 1 }
        return index
    }

    // MARK: - Stall Detection

    private func ensureSweepTimer() {
        guard sweepTimer == nil else { return }
        let timer = Timer(timeInterval: Self.sweepInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sweepForStalls()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sweepTimer = timer
    }

    /// Marks runs stalled when they haven't emitted an event since `now - stallThreshold`.
    /// Internal (not private) so tests can sweep with backdated timestamps.
    func sweepForStalls(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.stallThreshold)
        for (wsID, list) in rosters {
            var updated = list
            var changed = false
            let rowState = states[wsID] ?? .idle
            // Any live waiter (main or subagent) suppresses stalling: waiting
            // on the user isn't stalling, even if row state hasn't caught up.
            let anyWaiting = updated.contains(where: { $0.isWaitingForUser })
            for idx in updated.indices {
                guard updated[idx].state == .working, updated[idx].lastEventAt < cutoff else { continue }
                if updated[idx].isWaitingForUser { continue }
                if anyWaiting { continue }
                if case .needsAttention(.permission) = rowState { continue }
                updated[idx].state = .stalled
                changed = true
            }
            guard changed else { continue }
            rosters[wsID] = updated
            // Surface a stalled main run at row level unless something more
            // important already needs attention there. A fresh sibling run
            // (a live subagent) means the workstream is still actively
            // working through it — keep the row Working.
            let hasFreshActivity = updated.contains { run in
                run.state == .working && run.lastEventAt >= cutoff
            }
            if updated.contains(where: { $0.isMain && $0.state == .stalled }),
               !hasFreshActivity,
               case .working = rowState
            {
                states[wsID] = .stalled
            }
        }
    }
}
