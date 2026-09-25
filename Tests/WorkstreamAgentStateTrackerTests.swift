// ABOUTME: Tests for the per-workstream agent roster and row-level state machine.
// ABOUTME: Covers run lifecycle, activity text, permission handling, and stall sweeping.

@testable import FactoryFloor
import XCTest

@MainActor
final class WorkstreamAgentStateTrackerTests: XCTestCase {
    private let wsID = UUID()
    private let projectDir = "/tmp/factoryfloor-test-worktree"

    private var tracker: WorkstreamAgentStateTracker { WorkstreamAgentStateTracker.shared }

    override func setUp() {
        super.setUp()
        tracker.resetForTesting()
    }

    override func tearDown() {
        tracker.resetForTesting()
        super.tearDown()
    }

    /// Routes an event through the tracker, installing the lookup mapping on first use.
    private func handle(_ event: AgentEvent) {
        if tracker.workstreamLookup == nil {
            let expected = WorkstreamAgentStateTracker.normalize(projectDir)
            let mapped = wsID
            tracker.workstreamLookup = { dir in
                WorkstreamAgentStateTracker.normalize(dir) == expected ? mapped : nil
            }
        }
        tracker.handle(projectDir: projectDir, event: event)
    }

    private func backdateMainRun(secondsAgo: TimeInterval) {
        tracker._backdateRun(
            agentId: "main",
            workstreamID: wsID,
            lastEventAt: Date().addingTimeInterval(-secondsAgo)
        )
    }

    // MARK: - Run lifecycle

    func testPromptSubmitCreatesMainRun() {
        handle(.waiting(agentId: "main"))
        let runs = tracker.runs(for: wsID)
        XCTAssertEqual(runs.count, 1)
        XCTAssertTrue(runs[0].isMain)
        XCTAssertEqual(runs[0].name, "Claude")
        XCTAssertEqual(tracker.activeRunCount(for: wsID), 1)
    }

    func testStopRemovesMainRun() {
        handle(.waiting(agentId: "main"))
        handle(.idle(agentId: "main"))
        XCTAssertEqual(tracker.activeRunCount(for: wsID), 0)
    }

    func testSubagentStartStopLifecycle() {
        handle(.created(agentId: "sub-1", name: "Explore", palette: 2))
        var runs = tracker.runs(for: wsID)
        XCTAssertEqual(runs.count, 1)
        XCTAssertFalse(runs[0].isMain)
        XCTAssertEqual(runs[0].name, "Explore")
        XCTAssertEqual(runs[0].palette, 2)

        handle(.removed(agentId: "sub-1"))
        runs = tracker.runs(for: wsID)
        XCTAssertTrue(runs.isEmpty)
    }

    func testDuplicateSubagentStartDoesNotDuplicateRun() {
        handle(.created(agentId: "sub-1", name: "Explore", palette: 1))
        handle(.created(agentId: "sub-1", name: "Explore", palette: 1))
        XCTAssertEqual(tracker.activeRunCount(for: wsID), 1)
    }

    func testMainRunSortsFirstAmongSubagents() {
        handle(.waiting(agentId: "main"))
        handle(.created(agentId: "sub-a", name: "Explore", palette: 1))
        handle(.created(agentId: "sub-b", name: "Plan", palette: 2))
        let runs = tracker.runs(for: wsID)
        XCTAssertEqual(runs.map(\.id), ["main", "sub-a", "sub-b"])
    }

    func testEventsOutsideTrackedWorkstreamsAreIgnored() {
        tracker.workstreamLookup = { _ in nil }
        handle(.waiting(agentId: "main"))
        handle(.created(agentId: "sub-1", name: "Explore", palette: 1))
        XCTAssertEqual(tracker.activeRunCount(for: wsID), 0)
    }

    // MARK: - Activity

    func testToolStartSetsActivityAndToolDoneClearsIt() {
        handle(.waiting(agentId: "main"))
        handle(.toolStart(agentId: "main", tool: "Edit", activity: "Editing Foo.swift"))
        XCTAssertEqual(tracker.runs(for: wsID).first?.activity, "Editing Foo.swift")

        handle(.toolDone(agentId: "main"))
        XCTAssertNil(tracker.runs(for: wsID).first?.activity)
    }

    func testSubagentActivityIsTrackedSeparately() {
        handle(.created(agentId: "sub-1", name: "Explore", palette: 1))
        handle(.toolStart(agentId: "sub-1", tool: "Grep", activity: "Searching"))
        let sub = tracker.runs(for: wsID).first(where: { $0.id == "sub-1" })
        XCTAssertEqual(sub?.activity, "Searching")
    }

    // MARK: - Row-level state

    func testPromptSubmitMarksRowWorking() {
        handle(.waiting(agentId: "main"))
        XCTAssertEqual(tracker.state(for: wsID), .working)
    }

    func testStopOnUnselectedWorkstreamNeedsAttention() {
        handle(.waiting(agentId: "main"))
        handle(.idle(agentId: "main"))
        XCTAssertEqual(tracker.state(for: wsID), .needsAttention(.justFinished))
    }

    func testStopOnSelectedWorkstreamGoesIdle() {
        tracker.currentSelection = wsID
        handle(.waiting(agentId: "main"))
        handle(.idle(agentId: "main"))
        XCTAssertEqual(tracker.state(for: wsID), .idle)
    }

    func testPermissionStatusThenToolActivityResumesWorking() {
        tracker.currentSelection = wsID
        handle(.status(agentId: "main", status: "permissionRequired"))
        XCTAssertEqual(tracker.state(for: wsID), .needsAttention(.permission))

        // Tool activity implies the user answered the prompt.
        handle(.toolStart(agentId: "main", tool: "Bash"))
        XCTAssertEqual(tracker.state(for: wsID), .working)
    }

    func testMarkSeenClearsJustFinishedButKeepsPermission() {
        handle(.idle(agentId: "main"))
        tracker.markSeen(workstreamID: wsID)
        XCTAssertEqual(tracker.state(for: wsID), .idle)

        handle(.status(agentId: "main", status: "permissionRequired"))
        tracker.markSeen(workstreamID: wsID)
        XCTAssertEqual(tracker.state(for: wsID), .needsAttention(.permission))
    }

    // MARK: - Stall detection

    func testStaleRunSweepsToStalled() {
        handle(.waiting(agentId: "main"))
        backdateMainRun(secondsAgo: WorkstreamAgentStateTracker.stallThreshold + 10)

        tracker.sweepForStalls(now: Date())
        XCTAssertEqual(tracker.runs(for: wsID)[0].state, .stalled)
        XCTAssertEqual(tracker.state(for: wsID), .stalled)
    }

    func testFreshRunDoesNotStall() {
        handle(.waiting(agentId: "main"))
        backdateMainRun(secondsAgo: 5)

        tracker.sweepForStalls(now: Date())
        XCTAssertEqual(tracker.runs(for: wsID)[0].state, .working)
        XCTAssertEqual(tracker.state(for: wsID), .working)
    }

    func testStalledSweepSkippedWhileAwaitingPermission() {
        tracker.currentSelection = wsID
        handle(.waiting(agentId: "main"))
        handle(.status(agentId: "main", status: "permissionRequired"))
        backdateMainRun(secondsAgo: WorkstreamAgentStateTracker.stallThreshold + 10)

        tracker.sweepForStalls(now: Date())
        // Waiting on the user is not stalling.
        XCTAssertEqual(tracker.runs(for: wsID)[0].state, .working)
    }

    func testToolStartUnstallsRunAndRow() {
        handle(.waiting(agentId: "main"))
        backdateMainRun(secondsAgo: WorkstreamAgentStateTracker.stallThreshold + 10)
        tracker.sweepForStalls(now: Date())
        XCTAssertEqual(tracker.state(for: wsID), .stalled)

        handle(.toolStart(agentId: "main", tool: "Read", activity: "Reading Bar.swift"))
        XCTAssertEqual(tracker.runs(for: wsID)[0].state, .working)
        XCTAssertEqual(tracker.state(for: wsID), .working)
    }

    /// A stale main run waiting on a live subagent is delegation, not a
    /// stall — the row keeps its Working state until the whole workstream
    /// goes quiet.
    func testFreshSubagentKeepsRowWorkingWhenMainGoesQuiet() {
        handle(.waiting(agentId: "main"))
        handle(.created(agentId: "ses_build", name: "build", palette: 1))
        backdateMainRun(secondsAgo: WorkstreamAgentStateTracker.stallThreshold + 10)

        tracker.sweepForStalls(now: Date())
        XCTAssertEqual(tracker.runs(for: wsID).first { $0.isMain }?.state, .stalled)
        XCTAssertEqual(tracker.state(for: wsID), .working)

        // Once the subagent goes quiet too, the row stalls.
        tracker._backdateRun(
            agentId: "ses_build",
            workstreamID: wsID,
            lastEventAt: Date().addingTimeInterval(-(WorkstreamAgentStateTracker.stallThreshold + 10))
        )
        tracker.sweepForStalls(now: Date())
        XCTAssertEqual(tracker.state(for: wsID), .stalled)
    }

    /// The main run's final context figures must outlive the roster clear
    /// at turn end so the row's context bar persists at Done/Idle.
    func testContextUsageSurvivesMainIdle() {
        handle(AgentEvent.info(
            agentId: "main",
            name: "OpenCode",
            model: "claude-sonnet-4-5",
            contextUsedTokens: 42_000
        ))
        XCTAssertNotNil(tracker.mainContextUsage(for: wsID))

        handle(.idle(agentId: "main"))
        XCTAssertTrue(tracker.runs(for: wsID).isEmpty)

        let usage = tracker.mainContextUsage(for: wsID)
        XCTAssertNotNil(usage)
        XCTAssertEqual(usage?.usedTokens, 42_000)
        XCTAssertEqual(usage?.limitTokens, 200_000)
    }

    // MARK: - Variant assignment

    func testVariantIndicesAssignedPerType() {
        handle(.created(agentId: "e1", name: "Explore", palette: 1))
        handle(.created(agentId: "e2", name: "Explore", palette: 2))
        handle(.created(agentId: "g1", name: "general-purpose", palette: 3))
        let runs = tracker.runs(for: wsID)
        XCTAssertEqual(runs.first(where: { $0.id == "e1" })?.variantIndex, 0)
        XCTAssertEqual(runs.first(where: { $0.id == "e2" })?.variantIndex, 1)
        // Independent sequence per type.
        XCTAssertEqual(runs.first(where: { $0.id == "g1" })?.variantIndex, 0)
    }

    func testFreedVariantIndexIsReused() {
        handle(.created(agentId: "e1", name: "Explore", palette: 1))
        handle(.created(agentId: "e2", name: "Explore", palette: 1))
        handle(.created(agentId: "e3", name: "Explore", palette: 1))
        handle(.removed(agentId: "e2"))
        handle(.created(agentId: "e4", name: "Explore", palette: 1))
        XCTAssertEqual(tracker.runs(for: wsID).first(where: { $0.id == "e4" })?.variantIndex, 1)
    }

    func testVariantIndicesKeepCountingWhenOverCapacity() {
        for i in 1...5 {
            handle(.created(agentId: "e\(i)", name: "Explore", palette: 1))
        }
        let variants = tracker.runs(for: wsID).map(\.variantIndex).sorted()
        // Raw indices keep counting; cycling to sprite 1 happens at render time.
        XCTAssertEqual(variants, [0, 1, 2, 3, 4])
    }

    func testVariantIndexIsStableForRunLifetime() {
        handle(.created(agentId: "e1", name: "Explore", palette: 1))
        handle(.toolStart(agentId: "e1", tool: "Grep", activity: "Searching"))
        XCTAssertEqual(tracker.runs(for: wsID).first?.variantIndex, 0)
    }

    func testMainAgentVariantIsZero() {
        handle(.waiting(agentId: "main"))
        XCTAssertEqual(tracker.runs(for: wsID).first?.variantIndex, 0)
    }

    func testNextVariantIndexMatchesNormalizedTypeNames() {
        var runs = tracker.runs(for: wsID)
        runs = [
            run(name: "Explore", variant: 0),
            run(name: "explore", variant: 2),
        ]
        XCTAssertEqual(WorkstreamAgentStateTracker.nextVariantIndex(for: "Explore", in: runs), 1)
        XCTAssertEqual(WorkstreamAgentStateTracker.nextVariantIndex(for: "general-purpose", in: runs), 0)
    }

    private func run(name: String, variant: Int) -> WorkstreamAgentStateTracker.AgentRun {
        WorkstreamAgentStateTracker.AgentRun(
            id: name + String(variant),
            name: name,
            palette: 1,
            isMain: false,
            variantIndex: variant,
            state: .working,
            activity: nil,
            startedAt: Date(),
            lastEventAt: Date()
        )
    }

    // MARK: - Cleanup

    func testClearRemovesAllStateForWorkstream() {
        handle(.waiting(agentId: "main"))
        handle(.created(agentId: "sub-1", name: "Explore", palette: 1))
        tracker.clear(workstreamID: wsID)
        XCTAssertEqual(tracker.activeRunCount(for: wsID), 0)
        XCTAssertEqual(tracker.state(for: wsID), .idle)
    }

    // MARK: - Activity description mapping

    func testActivityDescriptionMapping() {
        let filePathInput: [String: Any] = ["file_path": "/repo/Sources/Foo.swift"]
        XCTAssertEqual(HookEventReceiver.activityDescription(toolName: "Edit", toolInput: filePathInput), String(format: NSLocalizedString("Editing %@", comment: ""), "Foo.swift"))
        XCTAssertEqual(HookEventReceiver.activityDescription(toolName: "Read", toolInput: filePathInput), String(format: NSLocalizedString("Reading %@", comment: ""), "Foo.swift"))
        XCTAssertEqual(HookEventReceiver.activityDescription(toolName: "Grep", toolInput: nil), NSLocalizedString("Searching", comment: ""))
        XCTAssertEqual(HookEventReceiver.activityDescription(toolName: "Bash", toolInput: nil), NSLocalizedString("Running command", comment: ""))
        XCTAssertEqual(HookEventReceiver.activityDescription(toolName: "WebFetch", toolInput: nil), NSLocalizedString("Browsing", comment: ""))
        XCTAssertEqual(HookEventReceiver.activityDescription(toolName: "TodoWrite", toolInput: nil), NSLocalizedString("Planning", comment: ""))
        // Unknown tools surface verbatim so the row always says something specific.
        XCTAssertEqual(HookEventReceiver.activityDescription(toolName: "SomeCustomTool", toolInput: nil), "SomeCustomTool")
    }

    // MARK: - OpenCode (lowercase tool names, per-harness run names)

    func testActivityDescriptionMatchesLowercaseOpencodeTools() {
        let filePathInput: [String: Any] = ["file_path": "/repo/Sources/Foo.swift"]
        XCTAssertEqual(HookEventReceiver.activityDescription(toolName: "edit", toolInput: filePathInput), String(format: NSLocalizedString("Editing %@", comment: ""), "Foo.swift"))
        XCTAssertEqual(HookEventReceiver.activityDescription(toolName: "read", toolInput: filePathInput), String(format: NSLocalizedString("Reading %@", comment: ""), "Foo.swift"))
        XCTAssertEqual(HookEventReceiver.activityDescription(toolName: "grep", toolInput: nil), NSLocalizedString("Searching", comment: ""))
        XCTAssertEqual(HookEventReceiver.activityDescription(toolName: "bash", toolInput: nil), NSLocalizedString("Running command", comment: ""))
        XCTAssertEqual(HookEventReceiver.activityDescription(toolName: "todowrite", toolInput: nil), NSLocalizedString("Planning", comment: ""))
        XCTAssertEqual(HookEventReceiver.activityDescription(toolName: "task", toolInput: nil), NSLocalizedString("Delegating", comment: ""))
    }

    /// Unmapped custom/MCP tools surface verbatim so the row always shows
    /// something specific; an empty name still yields no activity.
    func testActivityDescriptionFallsBackToToolNameVerbatim() {
        XCTAssertEqual(HookEventReceiver.activityDescription(toolName: "mcp_custom_lookup", toolInput: nil), "mcp_custom_lookup")
        XCTAssertNil(HookEventReceiver.activityDescription(toolName: "", toolInput: nil))
    }

    func testOpencodeRunUsesProvidedHarnessName() {
        var event = AgentEvent.waiting(agentId: "main")
        event.name = "OpenCode"
        handle(event)
        XCTAssertEqual(tracker.runs(for: wsID).first?.name, "OpenCode")
    }

    /// OpenCode session_created payloads may carry the subtask description;
    /// it must land on the run as a separate field, not baked into the name
    /// (sprite selection keys off the type name).
    func testOpencodeSubagentCreatedCarriesTaskDescription() {
        handle(.created(
            agentId: "sub-1",
            name: "explore",
            palette: 1,
            parentAgentId: "main",
            taskDescription: "Map people/task completion code"
        ))
        let sub = tracker.runs(for: wsID).first(where: { $0.id == "sub-1" })
        XCTAssertEqual(sub?.name, "explore")
        XCTAssertEqual(sub?.taskDescription, "Map people/task completion code")
    }

    /// The plugin re-sends session_created when the subtask part arrives after
    /// the child was registered without a description; the duplicate must
    /// refine the existing run instead of recreating or resetting it.
    func testDuplicateCreatedRefinesNameAndTaskDescription() {
        handle(.created(agentId: "sub-1", name: "Sub-agent", palette: 3))
        let originalVariant = tracker.runs(for: wsID).first?.variantIndex

        handle(.created(
            agentId: "sub-1",
            name: "explore",
            palette: 1,
            parentAgentId: "main",
            taskDescription: "Map people/task completion code"
        ))

        let runs = tracker.runs(for: wsID)
        XCTAssertEqual(runs.count, 1)
        let sub = runs[0]
        XCTAssertEqual(sub.name, "explore")
        XCTAssertEqual(sub.taskDescription, "Map people/task completion code")
        XCTAssertEqual(sub.palette, 3)
        XCTAssertEqual(sub.variantIndex, originalVariant)

        // A later create without a description must not wipe the stored one.
        handle(.created(agentId: "sub-1", name: "explore", palette: 1))
        XCTAssertEqual(tracker.runs(for: wsID)[0].taskDescription, "Map people/task completion code")
    }

    /// Claude Code-style creates carry no description; runs stay unaffected.
    func testClaudeStyleCreateHasNoTaskDescription() {
        handle(.created(agentId: "sub-1", name: "Explore", palette: 2))
        XCTAssertNil(tracker.runs(for: wsID).first?.taskDescription)
    }

    // MARK: - Subtask description capping

    func testCappedTaskDescriptionTrimsAndCaps() {
        XCTAssertNil(HookEventReceiver.cappedTaskDescription(nil))
        XCTAssertNil(HookEventReceiver.cappedTaskDescription("   \n  "))
        XCTAssertEqual(HookEventReceiver.cappedTaskDescription("  Map people/task completion code  "), "Map people/task completion code")

        let long = String(repeating: "a", count: 200)
        XCTAssertEqual(HookEventReceiver.cappedTaskDescription(long), String(repeating: "a", count: 120))
    }

    /// OpenCode's message.updated can precede any tool/prompt event; the
    /// info-only event must still create the main run so its context
    /// figures land and the row's context bar can appear.
    func testAgentInfoCreatesMissingMainRunWithContext() {
        handle(AgentEvent.info(
            agentId: "main",
            name: "OpenCode",
            model: "claude-sonnet-4-5",
            contextUsedTokens: 42_000
        ))
        let runs = tracker.runs(for: wsID)
        XCTAssertEqual(runs.count, 1)
        XCTAssertTrue(runs[0].isMain)
        XCTAssertEqual(runs[0].name, "OpenCode")
        XCTAssertEqual(runs[0].model, "claude-sonnet-4-5")
        XCTAssertEqual(runs[0].contextUsedTokens, 42_000)
        XCTAssertEqual(runs[0].contextLimitTokens, 200_000)
        XCTAssertNotNil(tracker.mainContextUsage(for: wsID))
    }

    /// Subagents are never created from attribute-only events — that path
    /// must not produce ghost roster entries.
    func testAgentInfoDoesNotCreateSubagentRuns() {
        handle(AgentEvent.info(
            agentId: "ses_child",
            name: "Explore",
            model: "claude-sonnet-4-5",
            contextUsedTokens: 1_000
        ))
        XCTAssertTrue(tracker.runs(for: wsID).isEmpty)
    }

    func testChildIdleRemovesOnlyThatChild() {
        handle(.waiting(agentId: "main"))
        handle(.created(agentId: "ses_child", name: "Explore", palette: 1))
        handle(.idle(agentId: "ses_child"))
        XCTAssertEqual(tracker.runs(for: wsID).map(\.id), ["main"])
    }

    func testMainIdlePreservesLiveChildren() {
        handle(.waiting(agentId: "main"))
        handle(.created(agentId: "ses_a", name: "Explore", palette: 1))
        handle(.idle(agentId: "main"))
        XCTAssertEqual(tracker.runs(for: wsID).map(\.id), ["ses_a"])
    }

    /// Parent idling after delegating must not flip the row to idle or
    /// justFinished underneath live cards.
    func testMainIdleWithLiveChildrenKeepsRowWorking() {
        handle(.waiting(agentId: "main"))
        handle(.created(agentId: "ses_a", name: "Explore", palette: 1))
        handle(.idle(agentId: "main"))
        XCTAssertEqual(tracker.state(for: wsID), .working)
    }

    /// A live permission waiter still wins over working when main idles.
    func testMainIdleWithLiveChildrenPreservesPermission() {
        handle(.waiting(agentId: "main"))
        handle(.created(agentId: "ses_a", name: "Explore", palette: 1))
        handle(.status(agentId: "ses_a", status: "permissionRequired"))
        handle(.idle(agentId: "main"))
        XCTAssertEqual(tracker.state(for: wsID), .needsAttention(.permission))
    }

    func testMainIdleAloneClearsRoster() {
        handle(.waiting(agentId: "main"))
        handle(.idle(agentId: "main"))
        XCTAssertEqual(tracker.activeRunCount(for: wsID), 0)
    }

    /// Two parallel subagents each running one bash tool: both cards appear,
    /// each clears independently, main idle does not wipe the survivor.
    func testTwoParallelBashSubagents() {
        handle(.waiting(agentId: "main", sessionID: "ses_main"))
        handle(.created(agentId: "ses_a", name: "Explore", palette: 1, parentAgentId: "main", taskDescription: "First task"))
        handle(.created(agentId: "ses_b", name: "Plan", palette: 2, parentAgentId: "main", taskDescription: "Second task"))
        handle(.toolStart(agentId: "ses_a", tool: "bash", activity: "Running command", sessionID: "ses_a"))
        handle(.toolStart(agentId: "ses_b", tool: "bash", activity: "Running command", sessionID: "ses_b"))

        var subs = tracker.runs(for: wsID).filter { !$0.isMain }
        XCTAssertEqual(subs.map(\.id).sorted(), ["ses_a", "ses_b"])
        XCTAssertEqual(subs.first(where: { $0.id == "ses_a" })?.activity, "Running command")
        XCTAssertEqual(subs.first(where: { $0.id == "ses_b" })?.activity, "Running command")

        handle(.idle(agentId: "ses_a"))
        subs = tracker.runs(for: wsID).filter { !$0.isMain }
        XCTAssertEqual(subs.map(\.id), ["ses_b"])

        // Parent idling after delegating must not wipe the live child.
        handle(.idle(agentId: "main", sessionID: "ses_main"))
        subs = tracker.runs(for: wsID).filter { !$0.isMain }
        XCTAssertEqual(subs.map(\.id), ["ses_b"])

        handle(.idle(agentId: "ses_b"))
        XCTAssertTrue(tracker.runs(for: wsID).filter({ !$0.isMain }).isEmpty)
    }

    /// Implicit session switch with live subagents preserves the roster;
    /// explicit session_switched still performs the full reset.
    func testImplicitSwitchPreservesLiveSubagents() {
        handle(.waiting(agentId: "main", sessionID: "ses_1"))
        handle(.created(agentId: "ses_a", name: "Explore", palette: 1))
        handle(.waiting(agentId: "main", sessionID: "ses_2"))
        XCTAssertEqual(tracker.runs(for: wsID).filter({ !$0.isMain }).map(\.id), ["ses_a"])
        XCTAssertEqual(tracker.state(for: wsID), .working)
        // The tracked session repointed: a late idle from the old session
        // must not wipe the preserved roster.
        handle(.idle(agentId: "main", sessionID: "ses_1"))
        XCTAssertEqual(tracker.runs(for: wsID).filter({ !$0.isMain }).map(\.id), ["ses_a"])
        XCTAssertEqual(tracker.state(for: wsID), .working)
    }

    func testExplicitSwitchClearsLiveSubagents() {
        handle(.waiting(agentId: "main", sessionID: "ses_1"))
        handle(.created(agentId: "ses_a", name: "Explore", palette: 1))
        handle(.sessionSwitched(sessionID: "ses_2"))
        XCTAssertTrue(tracker.runs(for: wsID).isEmpty)
    }

    /// A switch target matching a live roster run is a misattributed child
    /// session (subagent prompt read as a conversation switch), never a new
    /// conversation — the roster must survive it.
    func testSessionSwitchedToLiveChildIsIgnored() {
        handle(.waiting(agentId: "main", sessionID: "ses_main"))
        handle(.created(agentId: "ses_a", name: "general", palette: 1))
        handle(.sessionSwitched(sessionID: "ses_a"))
        XCTAssertEqual(tracker.runs(for: wsID).filter({ !$0.isMain }).map(\.id), ["ses_a"])
    }

    /// A child's tool_start can precede its session_created (observed 8ms
    /// earlier in the live log). The provisional run must reclassify as a
    /// subagent once created lands — not stay a main-flagged ghost.
    func testToolStartBeforeCreatedStillYieldsSubagent() {
        handle(.waiting(agentId: "main", sessionID: "ses_main"))
        handle(.toolStart(agentId: "ses_a", tool: "bash", activity: "Running command", sessionID: "ses_a"))
        handle(.created(agentId: "ses_a", name: "general", palette: 1, parentAgentId: "main", taskDescription: "Run single bash"))
        let sub = tracker.runs(for: wsID).first(where: { $0.id == "ses_a" })
        XCTAssertNotNil(sub)
        XCTAssertFalse(sub?.isMain ?? true)
        XCTAssertEqual(sub?.taskDescription, "Run single bash")
    }

    /// A waiting event for a non-main id (e.g. a subagent prompt forwarded
    /// by the harness) must not mint a main-flagged ghost run.
    func testWaitingFromChildIdDoesNotCreateMainGhost() {
        handle(.waiting(agentId: "main", sessionID: "ses_main"))
        handle(.waiting(agentId: "ses_a", sessionID: "ses_a"))
        let mains = tracker.runs(for: wsID).filter(\.isMain)
        XCTAssertEqual(mains.map(\.id), ["main"])
        XCTAssertEqual(tracker.runs(for: wsID).first(where: { $0.id == "ses_a" })?.isMain, false)
    }

    // MARK: - Name and attribute refinement

    func testToolStartCreatesRunWithCarriedName() {
        var event = AgentEvent.toolStart(agentId: "ses_child", tool: "edit")
        event.name = "build"
        handle(event)
        XCTAssertEqual(tracker.runs(for: wsID).first?.name, "build")
    }

    func testSubsequentEventRefinesExistingRunName() {
        var first = AgentEvent.toolStart(agentId: "ses_child", tool: "bash")
        first.name = "OpenCode"
        handle(first)
        XCTAssertEqual(tracker.runs(for: wsID).first?.name, "OpenCode")

        // The plugin reports the real agent type once known.
        var second = AgentEvent.toolStart(agentId: "ses_child", tool: "read")
        second.name = "general"
        handle(second)
        XCTAssertEqual(tracker.runs(for: wsID).first?.name, "general")
    }

    func testAgentInfoStoresModelOnExistingRun() {
        handle(.waiting(agentId: "main"))
        handle(AgentEvent.info(agentId: "main", name: "OpenCode", model: "claude-sonnet-4-5"))
        let run = tracker.runs(for: wsID).first
        XCTAssertEqual(run?.name, "OpenCode")
        XCTAssertEqual(run?.model, "claude-sonnet-4-5")
        XCTAssertEqual(tracker.state(for: wsID), .working)
    }

    /// Attribute-only events may create the MAIN run (so OpenCode's early
    /// message.updated context lands) but never subagent runs.
    func testAgentInfoDoesNotCreateSubagentGhostRuns() {
        handle(AgentEvent.info(agentId: "main", name: "OpenCode", model: "m"))
        handle(AgentEvent.info(agentId: "ses_unknown", name: "build", model: "m"))
        XCTAssertEqual(tracker.runs(for: wsID).map(\.id), ["main"])
        XCTAssertTrue(tracker.runs(for: wsID)[0].isMain)
        XCTAssertEqual(tracker.state(for: wsID), .idle)
    }

    func testAgentInfoDoesNotClearPermissionState() {
        tracker.currentSelection = wsID
        handle(.waiting(agentId: "main"))
        handle(.status(agentId: "main", status: "permissionRequired"))
        handle(AgentEvent.info(agentId: "main", name: "OpenCode", model: "m"))
        XCTAssertEqual(tracker.state(for: wsID), .needsAttention(.permission))
    }

    func testAgentInfoRefreshesLastEventAt() {
        handle(.waiting(agentId: "main"))
        backdateMainRun(secondsAgo: 30)
        handle(AgentEvent.info(agentId: "main", name: "OpenCode", model: "m"))
        // If lastEventAt were not refreshed the next sweep would stall the run.
        let cutoff = Date().addingTimeInterval(-WorkstreamAgentStateTracker.stallThreshold)
        XCTAssertGreaterThan(tracker.runs(for: wsID)[0].lastEventAt, cutoff)
    }

    // MARK: - Live session presence

    func testHasLiveSessionIsFalseByDefault() {
        XCTAssertFalse(tracker.hasLiveSession(for: wsID))
        XCTAssertTrue(tracker.liveSessionIDs.isEmpty)
    }

    func testHandledEventMarksLiveSession() {
        handle(.waiting(agentId: "main"))
        XCTAssertTrue(tracker.hasLiveSession(for: wsID))
        XCTAssertTrue(tracker.liveSessionIDs.contains(wsID))
    }

    func testClearRemovesLiveSessionFlag() {
        handle(.waiting(agentId: "main"))
        tracker.clear(workstreamID: wsID)
        XCTAssertFalse(tracker.hasLiveSession(for: wsID))
    }

    // MARK: - Context-window usage

    private func tempTranscriptURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ff-tracker-tests-\(UUID().uuidString).jsonl")
    }

    private func writeTranscript(url: URL, usedTokens: Int, model: String = "claude-sonnet-4-5") throws {
        let line = "{\"type\":\"assistant\",\"message\":{\"model\":\"\(model)\",\"usage\":{\"input_tokens\":\(usedTokens),\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}}}"
        try line.write(to: url, atomically: true, encoding: .utf8)
    }

    func testTranscriptPathPopulatesContextUsage() throws {
        let url = tempTranscriptURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeTranscript(url: url, usedTokens: 1234)

        handle(.waiting(agentId: "main", transcriptPath: url.path))

        let usage = try XCTUnwrap(tracker.contextUsage[wsID])
        XCTAssertEqual(usage.usedTokens, 1234)
        XCTAssertEqual(usage.limitTokens, 200_000)
        XCTAssertEqual(usage.fraction, Double(1234) / 200_000, accuracy: 1e-12)
    }

    func testContextUsageReadIsThrottledWithinFiveSeconds() throws {
        let url = tempTranscriptURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeTranscript(url: url, usedTokens: 100)

        handle(.waiting(agentId: "main", transcriptPath: url.path))
        XCTAssertEqual(tracker.contextUsage[wsID]?.usedTokens, 100)

        // Rewrite the transcript; the throttle must skip the re-read.
        try writeTranscript(url: url, usedTokens: 9000)
        handle(.toolStart(agentId: "main", tool: "Bash", transcriptPath: url.path))
        XCTAssertEqual(tracker.contextUsage[wsID]?.usedTokens, 100)
    }

    func testAgentIdleAlwaysRereadsTranscript() throws {
        let url = tempTranscriptURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeTranscript(url: url, usedTokens: 100)
        handle(.waiting(agentId: "main", transcriptPath: url.path))

        try writeTranscript(url: url, usedTokens: 9000)
        handle(.idle(agentId: "main", transcriptPath: url.path))
        XCTAssertEqual(tracker.contextUsage[wsID]?.usedTokens, 9000)
    }

    func testFailedReadKeepsPreviousContextUsage() throws {
        let url = tempTranscriptURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeTranscript(url: url, usedTokens: 100)
        handle(.waiting(agentId: "main", transcriptPath: url.path))
        XCTAssertEqual(tracker.contextUsage[wsID]?.usedTokens, 100)

        // Remove the file so the forced idle re-read fails; the previous
        // value must stick.
        try FileManager.default.removeItem(at: url)
        handle(.idle(agentId: "main", transcriptPath: url.path))
        XCTAssertEqual(tracker.contextUsage[wsID]?.usedTokens, 100)
    }

    func testClearRemovesLiveSessionAndContextUsage() throws {
        let url = tempTranscriptURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeTranscript(url: url, usedTokens: 10)
        handle(.waiting(agentId: "main", transcriptPath: url.path))
        XCTAssertTrue(tracker.hasLiveSession(for: wsID))
        XCTAssertNotNil(tracker.contextUsage[wsID])

        tracker.clear(workstreamID: wsID)
        XCTAssertFalse(tracker.hasLiveSession(for: wsID))
        XCTAssertNil(tracker.contextUsage[wsID])
    }

    func testAgentInfoAppliesContextFieldsToRun() {
        handle(.waiting(agentId: "main"))
        handle(AgentEvent.info(
            agentId: "main",
            name: "OpenCode",
            model: "claude-sonnet-4-5",
            contextUsedTokens: 42_000
        ))
        let run = tracker.runs(for: wsID).first
        XCTAssertEqual(run?.contextUsedTokens, 42_000)
        XCTAssertEqual(run?.contextLimitTokens, 200_000)
    }

    func testMainContextUsageFallsBackToRunReportedTokens() {
        handle(.waiting(agentId: "main"))
        handle(AgentEvent.info(
            agentId: "main",
            name: "OpenCode",
            model: "claude-sonnet-4-5",
            contextUsedTokens: 42_000
        ))

        let usage = tracker.mainContextUsage(for: wsID)
        XCTAssertEqual(usage?.usedTokens, 42_000)
        XCTAssertEqual(usage?.limitTokens, 200_000)
    }

    func testMainContextUsagePrefersTranscriptOverRunTokens() throws {
        let url = tempTranscriptURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeTranscript(url: url, usedTokens: 100)
        handle(.waiting(agentId: "main", transcriptPath: url.path))
        handle(AgentEvent.info(
            agentId: "main",
            name: "OpenCode",
            model: "claude-sonnet-4-5",
            contextUsedTokens: 42_000
        ))

        XCTAssertEqual(tracker.mainContextUsage(for: wsID)?.usedTokens, 100)
    }

    /// Usage is nil until the harness has reported figures — but once it
    /// has, the last reading persists past turn end (the row's bar dims
    /// instead of vanishing at Done/Idle).
    func testMainContextUsageNilUntilReportedThenPersists() {
        XCTAssertNil(tracker.mainContextUsage(for: wsID))

        handle(.waiting(agentId: "main"))
        handle(AgentEvent.info(
            agentId: "main",
            name: "OpenCode",
            model: "claude-sonnet-4-5",
            contextUsedTokens: 42_000
        ))
        handle(.idle(agentId: "main"))

        let usage = tracker.mainContextUsage(for: wsID)
        XCTAssertEqual(usage?.usedTokens, 42_000)
    }

    // MARK: - Claude subagent description + context (hook receiver)

    /// Payload shapes and file layout captured from Claude Code 2.1.282:
    /// SubagentStart carries only agent_type; the meta file lands afterwards.
    func testClaudeSubagentGetsTaskDescriptionAndContextFromSessionFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ff-sub-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let transcript = root.appendingPathComponent("session.jsonl").path
        let prefix = HookEventReceiver.subagentFilePrefix(transcriptPath: transcript, agentId: "a1")
        XCTAssertEqual(prefix, root.appendingPathComponent("session/subagents/agent-a1").path)

        let receiver = HookEventReceiver.shared
        let dir = "\(projectDir)-\(UUID().uuidString)"
        let base: [String: Any] = ["transcript_path": transcript, "agent_id": "a1", "agent_type": "general-purpose"]
        func map(_ hook: String, _ extra: [String: Any] = [:]) {
            let input = base.merging(extra) { $1 }.merging(["hook_event_name": hook]) { $1 }
            receiver.mapHookEvent(hookEventName: hook, eventInput: input, projectDir: dir).forEach(handle)
        }

        map("SubagentStart")
        XCTAssertEqual(tracker.runs(for: wsID).first?.name, "general-purpose")
        XCTAssertNil(tracker.runs(for: wsID).first?.taskDescription)

        try FileManager.default.createDirectory(atPath: (prefix as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try #"{"agentType":"general-purpose","description":"Probe note reader"}"#
            .write(toFile: prefix + ".meta.json", atomically: true, encoding: .utf8)
        try #"{"type":"assistant","message":{"model":"claude-opus-5-5","usage":{"input_tokens":10,"cache_creation_input_tokens":2000,"cache_read_input_tokens":16000}}}"#
            .write(toFile: prefix + ".jsonl", atomically: true, encoding: .utf8)
        map("PreToolUse", ["tool_name": "Read", "tool_input": ["file_path": "/x/note.txt"]])

        let sub = try XCTUnwrap(tracker.runs(for: wsID).first(where: { $0.id == "a1" }))
        XCTAssertFalse(sub.isMain)
        XCTAssertEqual(sub.taskDescription, "Probe note reader")
        XCTAssertEqual(sub.contextUsedTokens, 18010)
        XCTAssertEqual(sub.contextLimitTokens, 200_000)
    }

    // MARK: - Session switching (multiple sessions, one worktree)

    /// An explicit session switch drops the old snapshot so the new
    /// conversation's live figures show immediately instead of lingering
    /// on the previous session's totals until its first turn ends.
    func testSessionSwitchResetsContextSnapshot() {
        handle(AgentEvent.info(
            agentId: "main",
            name: "OpenCode",
            model: "claude-sonnet-4-5",
            contextUsedTokens: 42_000,
            sessionID: "ses_A"
        ))
        handle(.idle(agentId: "main", sessionID: "ses_A"))
        XCTAssertEqual(tracker.mainContextUsage(for: wsID)?.usedTokens, 42_000)

        handle(.sessionSwitched(sessionID: "ses_B"))
        XCTAssertNil(tracker.mainContextUsage(for: wsID))
        XCTAssertTrue(tracker.runs(for: wsID).isEmpty)
        XCTAssertEqual(tracker.state(for: wsID), .working)

        handle(AgentEvent.info(
            agentId: "main",
            name: "OpenCode",
            model: "claude-sonnet-4-5",
            contextUsedTokens: 5_000,
            sessionID: "ses_B"
        ))
        XCTAssertEqual(tracker.mainContextUsage(for: wsID)?.usedTokens, 5_000)
    }

    /// A resumed session emits no session.created, so the first event
    /// carrying an unknown session id must implicitly reset.
    func testImplicitSwitchOnUnknownSessionID() {
        handle(.waiting(agentId: "main", sessionID: "ses_A"))
        handle(AgentEvent.info(
            agentId: "main",
            name: "OpenCode",
            model: "claude-sonnet-4-5",
            contextUsedTokens: 42_000,
            sessionID: "ses_A"
        ))
        handle(.idle(agentId: "main", sessionID: "ses_A"))
        XCTAssertEqual(tracker.mainContextUsage(for: wsID)?.usedTokens, 42_000)

        handle(.waiting(agentId: "main", sessionID: "ses_B"))
        XCTAssertNil(tracker.mainContextUsage(for: wsID))
        XCTAssertEqual(tracker.runs(for: wsID).map(\.id), ["main"])
    }

    /// A late idle from a superseded session must not wipe the new
    /// conversation's roster or row state.
    func testStaleIdleAfterSwitchIsIgnored() {
        tracker.currentSelection = wsID
        handle(.waiting(agentId: "main", sessionID: "ses_A"))
        handle(.sessionSwitched(sessionID: "ses_B"))
        handle(.waiting(agentId: "main", sessionID: "ses_B"))

        handle(.idle(agentId: "main", sessionID: "ses_A"))

        XCTAssertEqual(tracker.runs(for: wsID).map(\.id), ["main"])
        XCTAssertEqual(tracker.state(for: wsID), .working)
    }

    /// A different Claude transcript path mid-stream means another Claude
    /// session in the same worktree: the old snapshot is dropped instead of
    /// letting interleaved reads flicker the meter.
    func testClaudeTranscriptChangeResetsSnapshot() throws {
        let urlA = tempTranscriptURL()
        let urlB = tempTranscriptURL()
        defer {
            try? FileManager.default.removeItem(at: urlA)
            try? FileManager.default.removeItem(at: urlB)
        }
        try writeTranscript(url: urlA, usedTokens: 100)
        try writeTranscript(url: urlB, usedTokens: 9_000)

        handle(.waiting(agentId: "main", transcriptPath: urlA.path))
        XCTAssertEqual(tracker.contextUsage[wsID]?.usedTokens, 100)

        // A different transcript path means another Claude session in the
        // same worktree: the old snapshot is dropped (and the read throttle
        // cleared, so the new file is read immediately, not throttled).
        handle(.waiting(agentId: "main", transcriptPath: urlB.path))
        XCTAssertEqual(tracker.contextUsage[wsID]?.usedTokens, 9_000)
    }

    // MARK: - Question tool

    func testQuestionToolMapsToAskingActivity() {
        XCTAssertEqual(
            HookEventReceiver.activityDescription(toolName: "question", toolInput: nil),
            NSLocalizedString("Asking question", comment: "")
        )
        XCTAssertEqual(
            HookEventReceiver.activityDescription(toolName: "Question", toolInput: nil),
            NSLocalizedString("Asking question", comment: "")
        )
    }

    /// The question-tool permission signal must keep the row out of the
    /// stall sweep, like any other permission prompt.
    func testQuestionPermissionSkipsStallSweep() {
        tracker.currentSelection = wsID
        handle(.toolStart(agentId: "main", tool: "question", activity: "Asking question"))
        handle(.status(agentId: "main", status: "permissionRequired"))
        backdateMainRun(secondsAgo: WorkstreamAgentStateTracker.stallThreshold + 10)

        tracker.sweepForStalls(now: Date())
        XCTAssertEqual(tracker.runs(for: wsID)[0].state, .working)
        XCTAssertEqual(tracker.state(for: wsID), .needsAttention(.permission))
    }

    // MARK: - Question-tool variants and waiting semantics

    func testIsQuestionToolMatchesVariants() {
        XCTAssertTrue(HookEventReceiver.isQuestionTool("question"))
        XCTAssertTrue(HookEventReceiver.isQuestionTool("Question"))
        XCTAssertTrue(HookEventReceiver.isQuestionTool("askquestion"))
        XCTAssertTrue(HookEventReceiver.isQuestionTool("AskQuestion"))
        XCTAssertTrue(HookEventReceiver.isQuestionTool("AskUserQuestion"))
        XCTAssertTrue(HookEventReceiver.isQuestionTool("ask_user_question"))
        XCTAssertTrue(HookEventReceiver.isQuestionTool("ask-question"))
        XCTAssertFalse(HookEventReceiver.isQuestionTool("edit"))
        XCTAssertFalse(HookEventReceiver.isQuestionTool("questionnaire"))
        XCTAssertFalse(HookEventReceiver.isQuestionTool("faq_questions"))
        XCTAssertFalse(HookEventReceiver.isQuestionTool(""))
    }

    /// Working *on* question-related code must not look like asking the user:
    /// matching is exact-normalized, never substring or content-based.
    func testWorkingOnQuestionCodeDoesNotCountAsAsking() {
        XCTAssertFalse(HookEventReceiver.isQuestionTool("questionnaire"))
        let filePathInput: [String: Any] = ["file_path": "/repo/Sources/Question.swift"]
        XCTAssertEqual(
            HookEventReceiver.activityDescription(toolName: "edit", toolInput: filePathInput),
            String(format: NSLocalizedString("Editing %@", comment: ""), "Question.swift")
        )
        for tool in ["askquestion", "AskUserQuestion", "ask_user_question"] {
            XCTAssertEqual(
                HookEventReceiver.activityDescription(toolName: tool, toolInput: nil),
                NSLocalizedString("Asking question", comment: "")
            )
        }
    }

    /// The streaming heartbeat must keep the run alive without answering the
    /// prompt — this was the intermittent Working → Stalled flake.
    func testHeartbeatDoesNotClearPermission() {
        tracker.currentSelection = wsID
        handle(.waiting(agentId: "main"))
        handle(.status(agentId: "main", status: "permissionRequired"))
        XCTAssertEqual(tracker.state(for: wsID), .needsAttention(.permission))

        handle(.toolStart(agentId: "main", tool: "respond"))
        XCTAssertEqual(tracker.state(for: wsID), .needsAttention(.permission))
        XCTAssertEqual(tracker.runs(for: wsID)[0].activity, nil)
    }

    /// The explicit replied signal clears waiting immediately (distinct from
    /// the heartbeat) and drops the "Asking question" activity text.
    func testRepliedSignalClearsPermission() {
        tracker.currentSelection = wsID
        handle(.waiting(agentId: "main"))
        handle(.toolStart(agentId: "main", tool: "question", activity: "Asking question"))
        handle(.status(agentId: "main", status: "permissionRequired"))
        XCTAssertEqual(tracker.state(for: wsID), .needsAttention(.permission))

        handle(.toolStart(agentId: "main", tool: "reply"))
        XCTAssertEqual(tracker.state(for: wsID), .working)
        XCTAssertNil(tracker.runs(for: wsID)[0].activity)
    }

    /// A subagent waiting on input raises row-level attention too (the user
    /// must act for it to proceed) and suppresses the stall sweep.
    func testSubagentPermissionRaisesRowAttentionAndSkipsStall() {
        tracker.currentSelection = wsID
        handle(.waiting(agentId: "main"))
        handle(.created(agentId: "ses_child", name: "build", palette: 1))
        handle(.status(agentId: "ses_child", status: "permissionRequired"))
        XCTAssertEqual(tracker.state(for: wsID), .needsAttention(.permission))

        backdateMainRun(secondsAgo: WorkstreamAgentStateTracker.stallThreshold + 10)
        tracker._backdateRun(
            agentId: "ses_child",
            workstreamID: wsID,
            lastEventAt: Date().addingTimeInterval(-(WorkstreamAgentStateTracker.stallThreshold + 10))
        )
        tracker.sweepForStalls(now: Date())
        XCTAssertEqual(tracker.state(for: wsID), .needsAttention(.permission))
        XCTAssertTrue(tracker.runs(for: wsID).allSatisfy { $0.state == .working })
    }

    /// Clearing one waiter must not clear the row while another run still waits.
    func testRowStaysInPermissionUntilLastWaiterReplies() {
        tracker.currentSelection = wsID
        handle(.waiting(agentId: "main"))
        handle(.created(agentId: "ses_child", name: "build", palette: 1))
        handle(.status(agentId: "main", status: "permissionRequired"))
        handle(.status(agentId: "ses_child", status: "permissionRequired"))
        XCTAssertEqual(tracker.state(for: wsID), .needsAttention(.permission))

        handle(.toolStart(agentId: "ses_child", tool: "reply"))
        XCTAssertEqual(tracker.state(for: wsID), .needsAttention(.permission))

        handle(.toolStart(agentId: "main", tool: "reply"))
        XCTAssertEqual(tracker.state(for: wsID), .working)
    }
}
