// ABOUTME: Tests for UsageLog, the local append-only JSON Lines usage log.
// ABOUTME: Validates one valid JSON object per line with event, data fields and timestamp.

@testable import FactoryFloor
import XCTest

final class UsageLogTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UsageLog.queue.sync {}
        try? FileManager.default.removeItem(at: UsageLog.fileURL)
    }

    override func tearDown() {
        UsageLog.queue.sync {}
        try? FileManager.default.removeItem(at: UsageLog.fileURL)
        super.tearDown()
    }

    func testRecordAppendsOneJSONLinePerEvent() throws {
        let suffix = UUID().uuidString
        let first = "first-\(suffix)", second = "second-\(suffix)"
        UsageLog.record(first, ["ws": "abc"])
        UsageLog.record(second, ["kind": "agent"])
        UsageLog.queue.sync {}

        // Other tests may append unrelated events to the same file; keep only ours.
        let text = try String(contentsOf: UsageLog.fileURL, encoding: .utf8)
        let objects = try text.split(separator: "\n")
            .map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: String]) }
            .filter { [first, second].contains($0["event"] ?? "") }
        XCTAssertEqual(objects.count, 2)
        XCTAssertEqual(objects[0]["event"], first)
        XCTAssertEqual(objects[0]["ws"], "abc")
        XCTAssertEqual(objects[1]["event"], second)
        XCTAssertEqual(objects[1]["kind"], "agent")
        for object in objects {
            XCTAssertFalse(object["ts"]?.isEmpty ?? true)
        }
    }
}
