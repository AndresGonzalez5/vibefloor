// ABOUTME: Info panel for a workstream showing app branding, metadata, shortcuts, and docs.
// ABOUTME: Default view when opening a workstream, dismissible with Cmd+Return.

import SwiftUI

struct WorkstreamInfoView: View {
    let workstreamName: String
    let workingDirectory: String
    let projectName: String
    let projectDirectory: String
    var scriptConfig: ScriptConfig = .empty

    @EnvironmentObject var appEnv: AppEnvironment
    @AppStorage("factoryfloor.defaultTerminal") private var defaultTerminal: String = ""
    @State private var branchName: String?
    @State private var docFiles: [DocFile] = []
    @State private var selectedDoc: String?

    struct DocFile: Identifiable {
        let name: String
        let content: String
        var id: String { name }
    }

    private static let docFileNames = ["README.md", "CLAUDE.md", "AGENTS.md"]

    var body: some View {
        VStack(spacing: 0) {
            // Pinned header
            VStack(spacing: 4) {
                Text(projectName)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(workstreamName)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                if let branch = branchName {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption)
                        Text(branch)
                    }
                    .foregroundStyle(.secondary)
                }
                DirectoryRow(path: workingDirectory, defaultTerminal: defaultTerminal)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.bar)

            Divider()

            // Scrollable content: metadata + doc tabs + rendered docs
            ScrollView {
                VStack(spacing: 0) {
                    Form {
                        // GitHub PR
                        if appEnv.ghAvailable, let branch = branchName,
                           let pr = appEnv.githubPR(for: projectDirectory, branch: branch) {
                            Section("Pull Request") {
                                LabeledContent("#\(pr.number)") {
                                    Text(pr.title)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                LabeledContent("Status") {
                                    Text(pr.state)
                                        .foregroundStyle(pr.state == "OPEN" ? .green : .secondary)
                                }
                            }
                        }

                        // Scripts
                        if scriptConfig.hasAnyScript {
                            Section {
                                if let setup = scriptConfig.setup {
                                    LabeledContent("Setup") {
                                        Text(setup)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                if let run = scriptConfig.run {
                                    LabeledContent("Run") {
                                        Text(run)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                if let teardown = scriptConfig.teardown {
                                    LabeledContent("Teardown") {
                                        Text(teardown)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            } header: {
                                HStack {
                                    Text("Scripts")
                                    Spacer()
                                    if let source = scriptConfig.source {
                                        Text(source)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .scrollDisabled(true)

                    // Doc tabs + content
                    if !docFiles.isEmpty {
                        HStack(spacing: 0) {
                            ForEach(docFiles) { doc in
                                DocTabButton(
                                    name: doc.name,
                                    isActive: selectedDoc == doc.name,
                                    action: { selectedDoc = doc.name }
                                )
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)

                        Divider()
                            .padding(.horizontal, 16)

                        if let selected = selectedDoc,
                           let doc = docFiles.first(where: { $0.name == selected }) {
                            MarkdownContentView(markdown: doc.content)
                                .id(selected)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadInfo() }
    } // body

    private func loadInfo() {
        Task.detached {
            let branch = GitOperations.repoInfo(at: workingDirectory).branch
            await MainActor.run {
                branchName = branch
                appEnv.refreshGitHubInfo(for: projectDirectory, branch: branch)
            }
        }

        let dir = workingDirectory
        Task.detached {
            var found: [DocFile] = []
            for name in Self.docFileNames {
                let path = URL(fileURLWithPath: dir).appendingPathComponent(name).path
                if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                    found.append(DocFile(name: name, content: content))
                }
            }
            await MainActor.run {
                docFiles = found
                selectedDoc = found.first?.name
            }
        }
    }

}

// MARK: - Directory row with copy and open-in-terminal actions

struct DirectoryRow: View {
    let path: String
    var defaultTerminal: String = ""

    @State private var copied = false

    var body: some View {
        HStack(spacing: 4) {
            Text(abbreviatePath(path))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            DirectoryActionButton(
                icon: copied ? "checkmark" : "doc.on.doc",
                color: copied ? .green : nil,
                tooltip: "Copy path"
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }

            DirectoryActionButton(
                icon: "terminal",
                tooltip: "Open in external terminal"
            ) {
                openInTerminal()
            }
        }
    }

    private func openInTerminal() {
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")

        if !defaultTerminal.isEmpty {
            // Use AppleScript to tell the configured terminal to cd
            let appName: String
            switch defaultTerminal {
            case "com.mitchellh.ghostty": appName = "Ghostty"
            case "com.googlecode.iterm2": appName = "iTerm"
            case "dev.warp.Warp-Stable": appName = "Warp"
            case "org.alacritty": appName = "Alacritty"
            case "net.kovidgoyal.kitty": appName = "kitty"
            default: appName = "Terminal"
            }

            if appName == "iTerm" {
                let script = """
                tell application "iTerm"
                    activate
                    create window with default profile command "/bin/zsh"
                    tell current session of current window
                        write text "cd \(escaped) && clear"
                    end tell
                end tell
                """
                if let appleScript = NSAppleScript(source: script) {
                    appleScript.executeAndReturnError(nil)
                }
            } else {
                // Generic: open the app then use Terminal-style AppleScript
                let script = "tell application \"\(appName)\" to activate"
                if let appleScript = NSAppleScript(source: script) {
                    appleScript.executeAndReturnError(nil)
                }
                // Use open command with the directory
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-b", defaultTerminal, path]
                try? process.run()
            }
        } else {
            let script = "tell application \"Terminal\" to do script \"cd \(escaped) && clear\""
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(nil)
            }
        }
    }

    private func abbreviatePath(_ p: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if p.hasPrefix(home) {
            return "~" + p.dropFirst(home.count)
        }
        return p
    }
}

private struct DirectoryActionButton: View {
    let icon: String
    var color: Color? = nil
    let tooltip: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color ?? (isHovering ? Color.primary : Color.secondary))
                .frame(width: 16, height: 16)
                .background(isHovering ? Color.primary.opacity(0.1) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(tooltip)
    }
}

private struct DocTabButton: View {
    let name: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                Text(name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular, design: .monospaced))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isActive ? Color.accentColor.opacity(0.15) : (isHovering ? Color.primary.opacity(0.05) : .clear))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(isActive ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
