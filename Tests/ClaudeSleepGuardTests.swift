// ABOUTME: Tests for detecting busy Claude Code sessions from ~/.claude/sessions files.
// ABOUTME: Covers status filtering, dead PIDs, untracked cwds, malformed files, and live session ids.

@testable import FactoryFloor
import XCTest

final class ClaudeSleepGuardTests: XCTestCase {
    private var tmpDir: URL!
    private let alive = getpid()
    private let deadPid: Int32 = 99999

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func write(pid: Int32, status: String, cwd: String = "/tracked", sessionId: String? = nil) {
        let sid = sessionId.map { #","sessionId":"\#($0)""# } ?? ""
        let json = #"{"pid":\#(pid),"status":"\#(status)","cwd":"\#(cwd)","kind":"interactive"\#(sid)}"#
        try! json.write(to: tmpDir.appendingPathComponent("\(pid).json"), atomically: true, encoding: .utf8)
    }

    private func hasBusy(_ dir: URL? = nil) -> Bool {
        ClaudeSleepGuard.hasBusySession(in: dir ?? tmpDir) { $0 == "/tracked" }
    }

    func testBusyAliveTrackedSessionCounts() {
        write(pid: alive, status: "busy")
        XCTAssertTrue(hasBusy())
    }

    func testDeadPidIsIgnored() throws {
        try XCTSkipIf(kill(deadPid, 0) == 0, "pid \(deadPid) is alive on this machine")
        write(pid: deadPid, status: "busy")
        XCTAssertFalse(hasBusy())
    }

    func testNonBusyStatusesAreIgnored() {
        for status in ["idle", "waiting", "shell"] {
            write(pid: alive, status: status)
            XCTAssertFalse(hasBusy(), status)
        }
    }

    func testUntrackedCwdIsIgnored() {
        write(pid: alive, status: "busy", cwd: "/elsewhere")
        XCTAssertFalse(hasBusy())
    }

    func testMalformedFileDoesNotHideValidSession() throws {
        try "{not json".write(to: tmpDir.appendingPathComponent("1.json"), atomically: true, encoding: .utf8)
        write(pid: alive, status: "busy")
        XCTAssertTrue(hasBusy())
    }

    func testEmptyOrMissingDirectory() {
        XCTAssertFalse(hasBusy())
        XCTAssertFalse(hasBusy(tmpDir.appendingPathComponent("missing")))
    }

    // MARK: - liveSessionIDs

    func testLiveSessionIDsListsAlivePids() {
        write(pid: alive, status: "idle", sessionId: "abc")
        XCTAssertEqual(ClaudeSleepGuard.liveSessionIDs(in: tmpDir), ["abc"])
    }

    /// A dead pid is excluded even when its file lacks `sessionId`.
    func testLiveSessionIDsSkipsDeadPid() throws {
        try XCTSkipIf(kill(deadPid, 0) == 0, "pid \(deadPid) is alive on this machine")
        write(pid: deadPid, status: "idle")
        XCTAssertEqual(ClaudeSleepGuard.liveSessionIDs(in: tmpDir), [])
    }

    func testLiveSessionIDsIsNilWhenAliveSessionLacksSessionId() {
        write(pid: alive, status: "idle")
        XCTAssertNil(ClaudeSleepGuard.liveSessionIDs(in: tmpDir))
    }

    /// A live session's file caught mid-rewrite must read as "unknown", not as
    /// a gone session. hasBusySession keeps skipping it.
    func testUnreadableFileOfLivePidMakesLiveSessionIDsUnknown() throws {
        for contents in ["{not json", ""] {
            try contents.write(to: tmpDir.appendingPathComponent("\(alive).json"), atomically: true, encoding: .utf8)
            XCTAssertNil(ClaudeSleepGuard.liveSessionIDs(in: tmpDir), contents)
            XCTAssertFalse(hasBusy(), contents)
        }
    }

    /// The pid comes from the filename, so a crashed session's torn file can't block reaping.
    func testUnreadableFileOfDeadPidIsIgnored() throws {
        try XCTSkipIf(kill(deadPid, 0) == 0, "pid \(deadPid) is alive on this machine")
        write(pid: alive, status: "busy", sessionId: "abc")
        try "{not json".write(to: tmpDir.appendingPathComponent("\(deadPid).json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ClaudeSleepGuard.liveSessionIDs(in: tmpDir), ["abc"])
        XCTAssertTrue(hasBusy())
    }

    func testNonPidFilenamesAreIgnored() throws {
        write(pid: alive, status: "busy", sessionId: "abc")
        try "{not json".write(to: tmpDir.appendingPathComponent("notes.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ClaudeSleepGuard.liveSessionIDs(in: tmpDir), ["abc"])
        XCTAssertTrue(hasBusy())
    }

    func testLiveSessionIDsIsNilForMissingDirectory() {
        XCTAssertNil(ClaudeSleepGuard.liveSessionIDs(in: tmpDir.appendingPathComponent("missing")))
    }
}
