// ABOUTME: Derives a deterministic port number from a workstream path.
// ABOUTME: Port range 40001-49999, unique per worktree to avoid collisions.

import Foundation

enum PortAllocator {
    static let rangeStart = 40001
    static let rangeEnd = 49999

    /// Derive a deterministic port from the working directory path.
    /// Uses DJB2 hash (stable across processes, unlike Swift's Hasher).
    static func port(for path: String) -> Int {
        var hash: UInt64 = 5381
        for byte in path.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        let range = rangeEnd - rangeStart + 1
        return rangeStart + Int(hash % UInt64(range))
    }
}
