// ABOUTME: Extracts context-window usage from harness transcripts and payloads.
// ABOUTME: Claude Code transcripts are append-only JSONL; only the file tail is read.

import Foundation

enum TranscriptContextReader {
    /// Usage lines are appended to the transcript as turns progress, so the
    /// newest assistant entry is always near the end. Parsing only the last
    /// ~256KB keeps huge sessions cheap to poll.
    private static let tailByteCount = 256 * 1024
    /// Fallback when the tail holds no usable line: right after compaction
    /// Claude Code writes the summary and re-attached files (seen up to
    /// ~550KB) after the boundary line.
    private static let compactTailByteCount = 2 * 1024 * 1024

    /// Reads the tail of a Claude Code transcript and extracts context usage.
    /// Returns nil when the file is missing, unreadable, or has no usable line.
    static func usage(transcriptPath: String) -> (usedTokens: Int, limitTokens: Int)? {
        guard let handle = FileHandle(forReadingAtPath: transcriptPath) else { return nil }
        defer { try? handle.close() }
        do {
            let size = try handle.seekToEnd()
            for count in [tailByteCount, compactTailByteCount] {
                let start = size > UInt64(count) ? size - UInt64(count) : 0
                try handle.seek(toOffset: start)
                // Lossy decode: a seek landing mid-character must not drop the whole tail.
                let data = try handle.read(upToCount: count) ?? Data()
                if let usage = usage(contents: String(decoding: data, as: UTF8.self)) { return usage }
                if start == 0 { break }
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Pure variant over JSONL contents: finds the LAST usable line and returns
    /// its usage. Assistant lines carrying `message.usage` sum their input-side
    /// token counts (missing → 0); a `compact_boundary` system line reports its
    /// `compactMetadata.postTokens`, so the meter drops right after compaction.
    /// Malformed lines are skipped; never throws. Returns nil when no usable line.
    static func usage(contents: String) -> (usedTokens: Int, limitTokens: Int)? {
        var latest: (usedTokens: Int, limitTokens: Int)?
        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if entry["type"] as? String == "system", entry["subtype"] as? String == "compact_boundary",
               let postTokens = (entry["compactMetadata"] as? [String: Any])?["postTokens"] as? Int
            {
                // ponytail: boundary lines carry no model; with no earlier
                // assistant line in the tail the limit falls back to 200k until
                // the next turn. Read the model from the session if that matters.
                latest = (postTokens, latest?.limitTokens ?? ContextLimits.limitTokens(forModel: nil))
                continue
            }
            guard entry["type"] as? String == "assistant",
                  let message = entry["message"] as? [String: Any],
                  let usageDict = message["usage"] as? [String: Any]
            else { continue }
            let used = int(usageDict, "input_tokens")
                + int(usageDict, "cache_creation_input_tokens")
                + int(usageDict, "cache_read_input_tokens")
            latest = (used, ContextLimits.limitTokens(forModel: message["model"] as? String))
        }
        return latest
    }

    /// Sums an OpenCode tokens payload (`{ input, output, cache: { read, write } }`)
    /// into context-used tokens. Missing or non-numeric fields count as zero.
    static func usedTokens(fromOpencodeTokens tokens: [String: Any]) -> Int {
        guard let cache = tokens["cache"] as? [String: Any] else {
            return int(tokens, "input")
        }
        return int(tokens, "input") + int(cache, "read") + int(cache, "write")
    }

    private static func int(_ dict: [String: Any], _ key: String) -> Int {
        (dict[key] as? Int) ?? 0
    }
}
