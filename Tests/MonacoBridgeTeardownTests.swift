// ABOUTME: Tests that Monaco bridges are released once torn down.
// ABOUTME: Guards the userContentController → Coordinator → bridge retain cycle.

@testable import FactoryFloor
import XCTest

@MainActor
final class MonacoBridgeTeardownTests: XCTestCase {
    func testEditorBridgeIsReleasedAfterTeardown() {
        weak var weakBridge: MonacoEditorBridge?
        autoreleasepool {
            let bridge = MonacoEditorBridge()
            _ = bridge.ensureWebView()
            // Callbacks capture their owner in production (the workspace view).
            bridge.onContentChanged = { _, _ in _ = bridge }
            bridge.teardown()
            weakBridge = bridge
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNil(weakBridge, "MonacoEditorBridge leaked after teardown")
    }

    func testDiffBridgeIsReleasedAfterTeardown() {
        weak var weakBridge: MonacoDiffBridge?
        autoreleasepool {
            let bridge = MonacoDiffBridge()
            _ = bridge.ensureWebView()
            bridge.onSaveFile = { _ in _ = bridge }
            bridge.teardown()
            weakBridge = bridge
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNil(weakBridge, "MonacoDiffBridge leaked after teardown")
    }
}
