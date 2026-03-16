# TODO

## Pre-release
- [ ] Homebrew tap (alltuner/homebrew-tap) and cask formula
- [ ] Code signing and notarization for distribution
- [ ] All Tuner Labs logo image in help view (needs asset)
- [ ] Occlude non-visible terminal surfaces to save GPU (reverted, needs careful timing)
- [ ] Sidebar visual polish (custom styling beyond default SwiftUI)

## Future
- [ ] Split panes within a workstream
- [ ] External Chrome integration: launch with --remote-debugging-port for WebMCP/CDP
- [ ] PR management: create and manage PRs from workstreams (currently view-only)
- [ ] CommandBuilder withFallback quoting needs more testing with edge cases
- [ ] Auto-update mechanism (Sparkle or similar)
- [ ] Crash reporting
- [ ] Move persistence from UserDefaults to a proper file (for larger state)
- [ ] Add more translations (copy en.lproj to xx.lproj, translate strings)

## Done
- [x] Embedded Ghostty terminals (Metal GPU-rendered via libghostty)
- [x] Project and workstream management with sidebar tree
- [x] Git worktrees for workstreams (branch off default branch)
- [x] .env/.env.local symlinks in worktrees
- [x] Tmux mode for session persistence across app restarts (dedicated socket)
- [x] Claude session resume via --session-id/--resume
- [x] Auto-respawn on process exit (tmux pane-died hook)
- [x] Auto-rename branch via system prompt injection
- [x] Per-workstream permission mode (bypass prompts, context menu on +)
- [x] Agent Teams setting (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS)
- [x] --teammate-mode tmux flag
- [x] Deterministic port allocation per workstream (FF_PORT env var)
- [x] Four workstream tabs: Info, Coding Agent, Terminal, Browser
- [x] Embedded WKWebView browser with nav bar, home button
- [x] Info tab with rendered README.md and CLAUDE.md (MarkdownView SPM package)
- [x] GitHub integration: repo info, open PRs, branch PR status (via gh CLI)
- [x] Context-sensitive Cmd+0-9 shortcuts (project view: workstreams, workstream: tabs)
- [x] Cmd+Shift+[/] tab cycling
- [x] Cmd+Shift+O external browser, Cmd+Shift+E external terminal
- [x] Ctrl+Cmd+S sidebar toggle
- [x] Esc closes settings/help
- [x] Help view with grouped shortcuts, credits, Poblenou skyline
- [x] Settings: environment detection, tmux, bypass, teams, auto-rename, appearance, language, base dir, branch prefix, external apps, danger zone
- [x] Project overview with editable alias, git/GitHub info, workstream list
- [x] Drag-and-drop directories to sidebar
- [x] factoryfloor:// URL scheme for single-instance behavior
- [x] CLI launch with directory argument
- [x] Auto-generated workstream names (operation-adjective-component)
- [x] Async git repo info, path validity, GitHub data with periodic refresh
- [x] Auto-remove projects with missing directories
- [x] Worktree path validation with visual feedback (warning icon + strikethrough)
- [x] Localization: en, ca, es, sv
- [x] Performance: cached sorted IDs, O(1) lookups, debounced saves, deferred init, surface prewarm
- [x] Terminal resize flicker fix, async archive operations
- [x] CommandBuilder for clean shell command composition
- [x] Poblenou skyline as SwiftUI Shape in help and empty state
- [x] CLAUDE.md with comprehensive development workflow docs
- [x] Archive warning: warn if worktree has uncommitted changes before archiving
- [x] Workstream sorting in project view (by name or recent use toggle)
- [x] Sidebar shows branch name per workstream (refreshed periodically)
- [x] Sidebar toggle animation flicker fix
- [x] Git worktree list and prune in project overview
- [x] Fix auto-rename branch (--append-system-prompt instead of --system-prompt-file)
- [x] Extract env var injection logic to WorkstreamEnvironment module
- [x] Tmux mode limited to Coding Agent only (Terminal tab uses plain shell)
- [x] Tmux aggressive-resize and window-size latest to prevent size revert
- [x] Script config: .factoryfloor.json with fallback to emdash/conductor/superset formats
- [x] Setup tab (Cmd+5): auto-runs setup script on workstream creation
- [x] Run tab (Cmd+6): on-demand dev server via run script
- [x] Teardown script runs before worktree removal on archive
- [x] .env symlink guarded by setting (default on)
- [x] Script info displayed in workstream Info tab
- [x] App icon (factory floor + Poblenou skyline)
- [x] Landing page website with Tailwind CSS build
- [x] Rename to Factory Floor (bundle ID, URL scheme, config dir, all references)
- [x] Hugo website with asset versioning (MD5 query params)
- [x] GitHub Pages deploy workflow
- [x] Release-please for automated versioning
- [x] CLI launcher script (ff --install)
- [x] Distribution guide (Homebrew, notarization, Sparkle)
- [x] Umami analytics integration
- [x] GitHub repo at alltuner/factoryfloor

## Probably not needed
- [ ] Claude Agent SDK integration (TypeScript): CLI + tmux + session-id covers our needs
