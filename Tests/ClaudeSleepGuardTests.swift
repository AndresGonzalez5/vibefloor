// ABOUTME: Tests for detecting busy Claude Code sessions from ~/.claude/sessions files.
// ABOUTME: Covers status filtering, dead PIDs, untracked cwds, and malformed files.

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

    private func write(pid: Int32, status: String, cwd: String = "/tracked") {
        let json = #"{"pid":\#(pid),"status":"\#(status)","cwd":"\#(cwd)","kind":"interactive"}"#
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
}
