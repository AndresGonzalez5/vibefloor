# Pixel Agents — Architecture

The pixel agents panel shows animated pixel art characters that reflect what Claude Code is doing in real-time. Each workstream gets its own pixel office, and each Claude Code agent (main + subagents) appears as a separate character.

## How it works

Claude Code fires **hooks** at lifecycle events (tool use, session stop, subagent spawn). A shell script bundled in the app forwards these events to a local HTTP listener in the Swift app, which routes them to the correct workstream's WKWebView panel.

```
Claude Code hooks (settings.json)
  → ff-hook (shell script, reads stdin JSON + CLAUDE_PROJECT_DIR env var)
  → curl POST http://127.0.0.1:{port}/hook
  → HookEventReceiver (NWListener, Swift)
  → HookEventRouter (routes by project_dir to correct workstream)
  → PixelAgentsPanelView.Coordinator (evaluateJavaScript)
  → AgentManager → AgentStateMachine → Canvas animation
```

## Hook registration

On app launch, `HookInstaller` writes entries into `~/.claude/settings.json` for these events:

| Hook Event | What it means | AgentEvent | Animation |
|---|---|---|---|
| `PreToolUse` | Agent is about to use a tool | `agentToolStart` | type or read (by tool name) |
| `PostToolUse` | Tool execution finished | `agentToolDone` | idle |
| `Stop` | Agent finished responding | `agentIdle` | idle |
| `UserPromptSubmit` | User sent a message | `agentWaiting` | wait (fidget) |
| `SubagentStart` | Subagent spawned | `agentCreated` | new character appears |
| `SubagentStop` | Subagent finished | `agentRemoved` | character disappears |

Each hook entry uses `type: "command"` pointing to the bundled `ff-hook` script:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "/path/to/VibeFloor.app/.../ff-hook", "timeout": 5 }] }
    ]
  }
}
```

## Port discovery

The HTTP listener binds to `127.0.0.1` on a dynamic port (OS-assigned via port 0). The actual port is written to `~/Library/Caches/factoryfloor/hook-port`. The `ff-hook` script reads this file to know where to POST. If the file doesn't exist (app not running), the script exits silently.

## Multi-workstream routing (Model C)

There is a **single** HTTP listener shared across all workstreams. Each `PixelAgentsPanelView.Coordinator` registers its worktree path with `HookEventRouter`. When an event arrives, the router normalizes the `project_dir` from the hook payload and dispatches to the matching Coordinator.

```
HookEventReceiver (one listener, one port)
  ├── /Users/.../.factoryfloor/worktrees/proj-a/foo → Coordinator A
  ├── /Users/.../.factoryfloor/worktrees/proj-b/bar → Coordinator B
  └── unknown project_dir → silently discarded
```

Path normalization uses `URL(fileURLWithPath:).standardized.path` to handle trailing slashes and symlinks.

## Key files

| File | Role |
|---|---|
| `Resources/Scripts/ff-hook` | Shell script invoked by Claude Code hooks. Reads stdin JSON, wraps with `CLAUDE_PROJECT_DIR`, POSTs to localhost. |
| `Sources/PixelAgents/HookEventReceiver.swift` | NWListener singleton. Parses HTTP POST, maps hook events to `AgentEvent`, tracks per-project subagent palettes. |
| `Sources/PixelAgents/HookEventRouter.swift` | Singleton registry. Routes events to the correct workstream's Coordinator by normalized path. |
| `Sources/PixelAgents/HookInstaller.swift` | Idempotent install/uninstall of hook entries in `~/.claude/settings.json`. |
| `Sources/PixelAgents/AgentEvent.swift` | Event types sent from Swift to JS: `agentCreated`, `agentRemoved`, `agentToolStart`, `agentToolDone`, `agentIdle`, `agentWaiting`. |
| `Sources/Views/PixelAgentsPanelView.swift` | WKWebView host. Coordinator registers with router, creates main agent on ready, forwards events to JS. |
| `pixel-agents/src/engine/AgentStateMachine.ts` | Animation states: `idle`, `type`, `read`, `walk`, `wait`. Frame sequences and timing per state. |
| `pixel-agents/src/engine/AgentManager.ts` | Agent registry. Routes events to state machines, auto-creates agents on first event, 30s safety timeout. |

## Animation states

| State | Frames | Duration | Trigger |
|---|---|---|---|
| `idle` | `[1]` | 1.0s | PostToolUse, Stop |
| `type` | `[3, 4]` | 0.3s | PreToolUse with Edit, Write, Bash |
| `read` | `[5, 6]` | 0.3s | PreToolUse with Read, Grep, Glob, WebFetch |
| `walk` | `[0, 1, 2, 1]` | 0.15s | Status update |
| `wait` | `[1, 1, 0, 1]` | 0.8s | UserPromptSubmit |

## Testing

```bash
# Full lifecycle test (requires app running with a workstream open)
bash scripts/test-hook-tracer.sh /path/to/worktree

# HookInstaller idempotency test
bash scripts/test-hook-installer.sh
```

## Troubleshooting

**Agents don't animate:** Check that hooks are installed:
```bash
cat ~/.claude/settings.json | python3 -m json.tool | grep ff-hook
```

**Port file missing:** The app writes `~/Library/Caches/factoryfloor/hook-port` on startup. If it's missing, the receiver failed to bind — check Console.app for `factoryfloor:hook-receiver` logs.

**Wrong workstream:** The hook's `CLAUDE_PROJECT_DIR` must match the worktree path registered by the Coordinator (e.g. `~/.factoryfloor/worktrees/project/workstream-name`). Watch routing logs:
```bash
log stream --predicate 'subsystem == "factoryfloor"' --info | grep -i hook
```
