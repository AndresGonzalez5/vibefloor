// ABOUTME: NSViewRepresentable that bridges a TerminalView into SwiftUI.
// ABOUTME: Manages the lifecycle of terminal surfaces per workstream, caching them for fast switching.

import SwiftUI

struct TerminalContainerView: NSViewRepresentable {
    let workstreamID: UUID
    let workingDirectory: String

    @EnvironmentObject var surfaceCache: TerminalSurfaceCache

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        // Remove all existing subviews
        container.subviews.forEach { $0.removeFromSuperview() }

        guard let app = TerminalApp.shared.app else { return }

        let terminalView = surfaceCache.surface(
            for: workstreamID,
            app: app,
            workingDirectory: workingDirectory
        )

        container.addSubview(terminalView)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: container.topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        DispatchQueue.main.async {
            terminalView.setFocused(true)
        }
    }
}

/// Caches terminal surfaces so switching workstreams doesn't destroy/recreate them.
final class TerminalSurfaceCache: ObservableObject {
    private var surfaces: [UUID: TerminalView] = [:]

    func surface(for workstreamID: UUID, app: ghostty_app_t, workingDirectory: String) -> TerminalView {
        if let existing = surfaces[workstreamID] {
            return existing
        }
        let view = TerminalView(app: app, workingDirectory: workingDirectory)
        surfaces[workstreamID] = view
        return view
    }

    func removeSurface(for workstreamID: UUID) {
        surfaces.removeValue(forKey: workstreamID)
    }
}
