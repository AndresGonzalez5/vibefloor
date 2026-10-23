// ABOUTME: Circular pixel-art portrait of a workstream's main coding agent,
// ABOUTME: replacing the old status dot. Ring color and pulse convey state.

import SwiftUI

/// Sidebar portrait for a workstream's main agent: the harness's pixel
/// character inside a circular state ring. Presence tiers run from full color
/// while working down to near-transparent once dormant.
///
/// State palette (mirrored by the row's status word dot):
/// blue = working, yellow = stalled, orange = awaiting permission,
/// green = finished, gray = idle with a live session.
struct MainAgentPortrait: View {
    let state: WorkstreamAgentStateTracker.AgentRunState
    let isPathValid: Bool
    /// Whether any hook event was seen for this workstream this app launch.
    let hasLiveSession: Bool
    /// Agent type resolving the sprite ("Claude", "OpenCode", …).
    let portraitName: String
    var size: CGFloat = 38

    /// Ring/status-dot color for a state, mirroring the tiers below.
    /// Nil when the row is dormant (no live session).
    static func ringColor(
        for state: WorkstreamAgentStateTracker.AgentRunState,
        hasLiveSession: Bool
    ) -> Color? {
        switch state {
        case .working: .blue
        case .stalled: .yellow
        case .needsAttention(.permission): .orange
        case .needsAttention(.justFinished): .green
        case .idle where hasLiveSession: .secondary
        case .idle: nil
        }
    }

    var body: some View {
        Group {
            if !isPathValid {
                missingPathPortrait
            } else {
                statefulPortrait
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - State tiers

    @ViewBuilder
    private var statefulPortrait: some View {
        switch state {
        case .working:
            ringedPortrait(color: .blue)
                .shadow(color: .blue.opacity(0.35), radius: 3)
                .accessibilityLabel(Text("Agent is working"))

        case .stalled:
            ringedPortrait(color: .yellow)
                .accessibilityLabel(Text("Agent may be stalled"))

        case .needsAttention(.permission):
            ringedPortrait(color: .orange)
                .overlay(alignment: .topTrailing) { permissionBadge }
                .accessibilityLabel(Text("Agent is awaiting permission"))

        case .needsAttention(.justFinished):
            ringedPortrait(color: .green)
                .accessibilityLabel(Text("Agent finished — needs review"))

        case .idle where hasLiveSession:
            ringedPortrait(color: .secondary, lineWidth: 1)
                .saturation(0.3)
                .opacity(0.8)
                .accessibilityLabel(Text("Agent is idle"))

        case .idle:
            portrait
                .opacity(0.2)
                .accessibilityLabel(Text("Agent is idle"))
        }
    }

    /// Portrait with a state ring that pulses while the agent is active.
    private func ringedPortrait(color: Color, lineWidth: CGFloat = 1.5) -> some View {
        ZStack {
            PulsingRing(color: color, lineWidth: lineWidth, period: pulsePeriod)

            portrait
                .padding(1)
        }
    }

    private var missingPathPortrait: some View {
        portrait
            .saturation(0.2)
            .opacity(0.5)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .offset(x: 3, y: -3)
            }
            .accessibilityLabel(Text("Worktree path missing"))
    }

    private var permissionBadge: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 11))
            .foregroundStyle(.orange)
            .background(Circle().fill(Color.white))
            .offset(x: 4, y: -3)
            .accessibilityHidden(true)
    }

    // MARK: - Pieces

    private var portrait: some View {
        Group {
            if let image = AgentSpriteStore.shared.avatar(name: portraitName, palette: 0, variant: 0) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipShape(Circle())
    }

    /// Full pulse cycle for the current state, nil when the ring is static.
    private var pulsePeriod: TimeInterval? {
        switch state {
        case .working: 1.6
        case .stalled: 2.8
        case .needsAttention, .idle: nil
        }
    }
}

/// Ring whose opacity follows the clock; nil period = static ring. No implicit
/// animation, so a layout move during a List re-measure can never be captured
/// into a repeating animation (the ring used to bounce after a space switch).
struct PulsingRing: View {
    let color: Color
    var lineWidth: CGFloat = 1.5
    /// Full bright→dim→bright cycle length; nil draws a static ring.
    var period: TimeInterval?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: period == nil)) { context in
            Circle().strokeBorder(color.opacity(opacity(at: context.date)), lineWidth: lineWidth)
        }
    }

    private func opacity(at date: Date) -> Double {
        guard let period else { return 1 }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return 0.675 + 0.325 * cos(2 * .pi * phase)   // 1.0 → 0.35 → 1.0
    }
}
