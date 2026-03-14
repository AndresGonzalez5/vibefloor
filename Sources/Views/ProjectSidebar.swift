// ABOUTME: SwiftUI sidebar showing projects as a collapsible tree with workstreams.
// ABOUTME: Supports adding projects via picker/drag-drop and workstreams inline.

import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let addProject = Notification.Name("ff2.addProject")
    static let addNew = Notification.Name("ff2.addNew")
}

/// Selection in the sidebar is a workstream ID.
/// From it we can find the parent project.
struct ProjectSidebar: View {
    @Binding var projects: [Project]
    @Binding var selectedWorkstreamID: UUID?
    let onProjectsChanged: () -> Void

    @State private var pendingDirectory: String?
    @State private var pendingName: String = ""
    @State private var isDropTargeted = false
    @State private var addingWorkstreamForProject: UUID?
    @State private var newWorkstreamName = ""
    @State private var projectToDelete: UUID?
    @State private var expandedProjects: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedWorkstreamID) {
                ForEach($projects) { $project in
                    let hasChildren = !project.workstreams.isEmpty
                    let label = ProjectRow(
                        project: project,
                        onAdd: { startAddingWorkstream(for: project.id) },
                        onDelete: { projectToDelete = project.id }
                    )

                    if hasChildren {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedProjects.contains(project.id) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedProjects.insert(project.id)
                                    } else {
                                        expandedProjects.remove(project.id)
                                    }
                                }
                            )
                        ) {
                            ForEach(project.workstreams) { workstream in
                                WorkstreamRow(
                                    name: workstream.name,
                                    onArchive: { archiveWorkstream(workstream.id, in: &$project.wrappedValue) }
                                )
                                .tag(workstream.id)
                            }
                        } label: {
                            label
                        }
                    } else {
                        label
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if projects.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("Drop a folder here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Divider()

            HStack {
                Button(action: openDirectoryPicker) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .padding(8)

                Spacer()
            }
        }
        .onChange(of: selectedWorkstreamID) { _, wsID in
            guard let wsID else { return }
            if let project = projects.first(where: { $0.workstreams.contains(where: { $0.id == wsID }) }) {
                expandedProjects.insert(project.id)
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .sheet(item: $pendingDirectory) { directory in
            ConfirmProjectSheet(
                directory: directory,
                name: $pendingName,
                onAdd: { addProject(name: pendingName, directory: directory) },
                onCancel: { pendingDirectory = nil }
            )
        }
        .sheet(item: $addingWorkstreamForProject) { projectID in
            AddWorkstreamSheet(
                name: $newWorkstreamName,
                onAdd: { commitWorkstream(forProjectID: projectID) },
                onCancel: { addingWorkstreamForProject = nil }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .addProject)) { _ in
            openDirectoryPicker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .addNew)) { _ in
            // If a workstream is selected, add to its project
            if let wsID = selectedWorkstreamID,
               let project = projects.first(where: { $0.workstreams.contains(where: { $0.id == wsID }) }) {
                startAddingWorkstream(for: project.id)
            }
            // If we have projects but nothing selected, add to the first project
            else if let first = projects.first {
                startAddingWorkstream(for: first.id)
            }
            // No projects at all, add a project
            else {
                openDirectoryPicker()
            }
        }
        .alert(
            "Remove Project",
            isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { projectToDelete = nil }
            Button("Remove", role: .destructive) {
                if let id = projectToDelete {
                    deleteProject(id: id)
                }
            }
        } message: {
            if let id = projectToDelete, let project = projects.first(where: { $0.id == id }) {
                Text("Remove \"\(project.name)\" from the list? Files in \(project.directory) will not be deleted.")
            }
        }
    }

    // MARK: - Workstream management

    private func startAddingWorkstream(for projectID: UUID) {
        newWorkstreamName = ""
        expandedProjects.insert(projectID)
        addingWorkstreamForProject = projectID
    }

    private func commitWorkstream(forProjectID projectID: UUID) {
        let name = newWorkstreamName.trimmingCharacters(in: .whitespaces)
        addingWorkstreamForProject = nil
        newWorkstreamName = ""
        guard !name.isEmpty else { return }
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        expandedProjects.insert(projectID)

        let workstream = Workstream(name: name)
        projects[index].workstreams.append(workstream)
        selectedWorkstreamID = workstream.id
        onProjectsChanged()
    }

    @EnvironmentObject private var surfaceCache: TerminalSurfaceCache

    private func archiveWorkstream(_ workstreamID: UUID, in project: inout Project) {
        surfaceCache.removeSurface(for: workstreamID)
        project.workstreams.removeAll { $0.id == workstreamID }
        if selectedWorkstreamID == workstreamID {
            selectedWorkstreamID = project.workstreams.first?.id
        }
        onProjectsChanged()
    }

    // MARK: - Project management

    private func deleteProject(id: UUID) {
        // Clean up all workstream surfaces for this project
        if let project = projects.first(where: { $0.id == id }) {
            for ws in project.workstreams {
                surfaceCache.removeSurface(for: ws.id)
            }
        }
        projects.removeAll { $0.id == id }
        if let selected = selectedWorkstreamID,
           !projects.contains(where: { $0.workstreams.contains(where: { $0.id == selected }) }) {
            selectedWorkstreamID = nil
        }
        projectToDelete = nil
        onProjectsChanged()
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.hasDirectoryPath || FileManager.default.isDirectory(at: url) else { return }

                DispatchQueue.main.async {
                    addProject(name: url.lastPathComponent, directory: url.path)
                }
            }
        }
        return true
    }

    private func openDirectoryPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a project directory"
        panel.prompt = "Select"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingName = url.lastPathComponent
        pendingDirectory = url.path
    }

    private func addProject(name: String, directory: String) {
        let projectName = name.isEmpty ? URL(fileURLWithPath: directory).lastPathComponent : name
        let project = Project(name: projectName, directory: directory)
        projects.append(project)
        pendingDirectory = nil
        pendingName = ""
        onProjectsChanged()
    }

}

// Make String and UUID work as Identifiable sheet items
extension String: @retroactive Identifiable {
    public var id: String { self }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

extension FileManager {
    func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}

private struct ProjectRow: View {
    let project: Project
    let onAdd: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.system(.body, weight: .medium))

                    if !project.workstreams.isEmpty {
                        Text("\(project.workstreams.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }

                Text(abbreviatePath(project.directory))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isHovering {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

private struct WorkstreamRow: View {
    let name: String
    let onArchive: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack {
            Label(name, systemImage: "terminal")
                .font(.system(.body))

            Spacer()

            if isHovering {
                Button(action: onArchive) {
                    Image(systemName: "archivebox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

private struct ConfirmProjectSheet: View {
    let directory: String
    @Binding var name: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Project")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Directory")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(directory)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("Project Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Project Name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add", action: onAdd)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

private struct AddWorkstreamSheet: View {
    @Binding var name: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Workstream")
                .font(.headline)

            TextField("Workstream Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty { onAdd() }
                }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add", action: onAdd)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}
