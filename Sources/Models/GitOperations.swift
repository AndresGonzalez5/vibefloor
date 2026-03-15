// ABOUTME: Git operations for project and workstream management.
// ABOUTME: Handles repo detection, init, worktree create/remove, and repo info.

import Foundation

struct GitRepoInfo {
    let isRepo: Bool
    let branch: String?
    let remoteURL: String?
    let commitCount: Int?
    let isDirty: Bool
}

enum GitOperations {
    /// Check if a directory is a git repository.
    static func isGitRepo(at path: String) -> Bool {
        let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")
        return FileManager.default.fileExists(atPath: gitDir.path)
    }

    /// Initialize a git repo at the given path.
    static func initRepo(at path: String) -> Bool {
        return run("git", args: ["init"], in: path) != nil
    }

    /// Get repo information for display.
    static func repoInfo(at path: String) -> GitRepoInfo {
        guard isGitRepo(at: path) else {
            return GitRepoInfo(isRepo: false, branch: nil, remoteURL: nil, commitCount: nil, isDirty: false)
        }

        let branch = run("git", args: ["rev-parse", "--abbrev-ref", "HEAD"], in: path)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let remote = run("git", args: ["remote", "get-url", "origin"], in: path)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let countStr = run("git", args: ["rev-list", "--count", "HEAD"], in: path)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let commitCount = countStr.flatMap(Int.init)

        let status = run("git", args: ["status", "--porcelain"], in: path)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let isDirty = status.map { !$0.isEmpty } ?? false

        return GitRepoInfo(
            isRepo: true,
            branch: branch,
            remoteURL: remote,
            commitCount: commitCount,
            isDirty: isDirty
        )
    }

    /// Create a git worktree for a workstream.
    /// Returns the worktree path on success, nil on failure.
    static func createWorktree(projectPath: String, projectName: String, workstreamName: String, branchPrefix: String = "ff2") -> String? {
        let worktreeDir = AppConstants.worktreesDirectory
            .appendingPathComponent(sanitize(projectName))
            .appendingPathComponent(sanitize(workstreamName))

        let branchName = branchPrefix.isEmpty
            ? workstreamName
            : "\(branchPrefix)/\(workstreamName)"

        // Create parent directories
        try? FileManager.default.createDirectory(
            at: worktreeDir.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let result = run(
            "git",
            args: ["worktree", "add", "-b", branchName, worktreeDir.path],
            in: projectPath
        )

        if result != nil {
            return worktreeDir.path
        }

        // Branch might already exist, try without -b
        let fallback = run(
            "git",
            args: ["worktree", "add", worktreeDir.path, branchName],
            in: projectPath
        )

        return fallback != nil ? worktreeDir.path : nil
    }

    /// Remove a git worktree.
    static func removeWorktree(projectPath: String, workstreamName: String, projectName: String) {
        let worktreeDir = AppConstants.worktreesDirectory
            .appendingPathComponent(sanitize(projectName))
            .appendingPathComponent(sanitize(workstreamName))

        _ = run("git", args: ["worktree", "remove", "--force", worktreeDir.path], in: projectPath)

        // Clean up empty directories
        try? FileManager.default.removeItem(at: worktreeDir)
        let projectWorktreeDir = AppConstants.worktreesDirectory.appendingPathComponent(sanitize(projectName))
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: projectWorktreeDir.path), contents.isEmpty {
            try? FileManager.default.removeItem(at: projectWorktreeDir)
        }
    }

    /// List existing worktrees for a project.
    static func listWorktrees(at projectPath: String) -> [String] {
        guard let output = run("git", args: ["worktree", "list", "--porcelain"], in: projectPath) else {
            return []
        }
        return output.components(separatedBy: "\n")
            .filter { $0.hasPrefix("worktree ") }
            .map { String($0.dropFirst("worktree ".count)) }
    }

    // MARK: - Private

    private static func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    private static func run(_ command: String, args: [String], in directory: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
