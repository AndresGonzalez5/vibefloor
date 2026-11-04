// ABOUTME: Tests for transcript context-usage parsing, OpenCode token sums,
// ABOUTME: and model-based context limit lookup.

@testable import FactoryFloor
import XCTest

final class TranscriptContextReaderTests: XCTestCase {
    private let userLine = #"{"type":"user","message":{"role":"user","content":"hello"}}"#
    private let sonnetLine =
        #"{"type":"assistant","message":{"model":"claude-sonnet-4-5","usage":{"input_tokens":4,"cache_creation_input_tokens":123,"cache_read_input_tokens":45000,"output_tokens":99}}}"#
    private let opusOneMLine =
        #"{"type":"assistant","message":{"model":"claude-opus-4-1[1m]","usage":{"input_tokens":10,"cache_read_input_tokens":2000000}}}"#

    // MARK: - JSONL parsing

    func testSumsInputAndCacheFields() {
        let usage = TranscriptContextReader.usage(contents: sonnetLine)
        XCTAssertEqual(usage?.usedTokens, 4 + 123 + 45000)
        XCTAssertEqual(usage?.limitTokens, 200_000)
    }

    func testLastAssistantEntryWins() {
        let contents = [userLine, sonnetLine, "not json at all", opusOneMLine].joined(separator: "\n")
        let usage = TranscriptContextReader.usage(contents: contents)
        XCTAssertEqual(usage?.usedTokens, 10 + 2_000_000)
        XCTAssertEqual(usage?.limitTokens, 1_000_000)
    }

    /// A compact boundary drops the meter to the post-compact size, keeping
    /// the earlier limit; the next assistant line takes over again.
    func testCompactBoundaryReportsPostTokens() {
        let boundary = #"{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"manual","preTokens":180000,"postTokens":29293}}"#
        let compacted = TranscriptContextReader.usage(contents: [opusOneMLine, boundary].joined(separator: "\n"))
        XCTAssertEqual(compacted?.usedTokens, 29293)
        XCTAssertEqual(compacted?.limitTokens, 1_000_000)

        let resumed = TranscriptContextReader.usage(contents: [opusOneMLine, boundary, sonnetLine].joined(separator: "\n"))
        XCTAssertEqual(resumed?.usedTokens, 4 + 123 + 45000)
    }

    /// Claude Code writes the summary and re-attached files after the boundary
    /// in one batch, often past the 256KB tail; the reader must still find it.
    func testCompactBoundaryFoundPastLargePostCompactBatch() throws {
        let boundary = #"{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"manual","postTokens":29293}}"#
        let attachment = #"{"type":"attachment","content":""# + String(repeating: "x", count: 300 * 1024) + #""}"#
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jsonl")
        try [opusOneMLine, boundary, attachment].joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let usage = TranscriptContextReader.usage(transcriptPath: url.path)
        XCTAssertEqual(usage?.usedTokens, 29293)
        XCTAssertEqual(usage?.limitTokens, 1_000_000)
    }

    func testMissingCacheFieldsDefaultToZero() {
        let line = #"{"type":"assistant","message":{"model":"claude-sonnet-4-5","usage":{"input_tokens":42}}}"#
        let usage = TranscriptContextReader.usage(contents: line)
        XCTAssertEqual(usage?.usedTokens, 42)
    }

    func testSkipsMalformedAndUserLines() {
        let contents = [
            "{\"type\":\"assistant\",", // truncated
            userLine,
            "",
            sonnetLine,
        ].joined(separator: "\n")
        let usage = TranscriptContextReader.usage(contents: contents)
        XCTAssertEqual(usage?.usedTokens, 45127)
    }

    func testReturnsNilWithoutAssistantUsage() {
        XCTAssertNil(TranscriptContextReader.usage(contents: ""))
        XCTAssertNil(TranscriptContextReader.usage(contents: userLine))
        XCTAssertNil(TranscriptContextReader.usage(contents: "garbage\nmore garbage"))
        let noUsage = #"{"type":"assistant","message":{"model":"claude-sonnet-4-5"}}"#
        XCTAssertNil(TranscriptContextReader.usage(contents: noUsage))
    }

    func testLimitComesFromEntryModel() {
        let usage = TranscriptContextReader.usage(contents: opusOneMLine)
        XCTAssertEqual(usage?.limitTokens, 1_000_000)
    }

    // MARK: - OpenCode tokens dict

    func testOpencodeTokenSumIncludesCacheReadAndWrite() {
        let tokens: [String: Any] = [
            "input": 100,
            "output": 500,
            "cache": ["read": 50, "write": 25],
        ]
        XCTAssertEqual(TranscriptContextReader.usedTokens(fromOpencodeTokens: tokens), 175)
    }

    func testOpencodeTokenSumHandlesMissingAndNonNumericFields() {
        XCTAssertEqual(
            TranscriptContextReader.usedTokens(fromOpencodeTokens: ["input": 7]),
            7
        )
        XCTAssertEqual(
            TranscriptContextReader.usedTokens(fromOpencodeTokens: [:]),
            0
        )
        XCTAssertEqual(
            TranscriptContextReader.usedTokens(fromOpencodeTokens: ["input": "nope", "cache": ["read": true]]),
            0
        )
    }

    // MARK: - File tail reading

    func testReadsUsageFromTempFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ff-reader-tests-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try [userLine, sonnetLine].joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)

        let usage = try XCTUnwrap(TranscriptContextReader.usage(transcriptPath: url.path))
        XCTAssertEqual(usage.usedTokens, 45127)
    }

    func testMissingFileReturnsNil() {
        XCTAssertNil(TranscriptContextReader.usage(transcriptPath: "/nonexistent/transcript.jsonl"))
    }
}

final class ContextLimitsTests: XCTestCase {
    func testDefaultLimitIs200k() {
        XCTAssertEqual(ContextLimits.limitTokens(forModel: nil), 200_000)
        XCTAssertEqual(ContextLimits.limitTokens(forModel: ""), 200_000)
        XCTAssertEqual(ContextLimits.limitTokens(forModel: "claude-sonnet-4-5"), 200_000)
    }

    func testExtendedMarkersYieldOneMillion() {
        XCTAssertEqual(ContextLimits.limitTokens(forModel: "claude-sonnet-4-5[1m]"), 1_000_000)
        XCTAssertEqual(ContextLimits.limitTokens(forModel: "claude-sonnet-4-5-1m"), 1_000_000)
    }

    func testMarkerMatchIsCaseInsensitive() {
        XCTAssertEqual(ContextLimits.limitTokens(forModel: "claude-sonnet-4-5[1M]"), 1_000_000)
        XCTAssertEqual(ContextLimits.limitTokens(forModel: "CLAUDE-SONNET-4-5-1M"), 1_000_000)
    }
}
