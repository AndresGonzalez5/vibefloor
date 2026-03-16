# ff2 Project Instructions

## Development Workflow

### Build, Test, Run
```bash
./dev.sh build          # Debug build (xcodegen generate + xcodebuild)
./dev.sh build-release  # Release build (optimized)
./dev.sh test           # Run XCTest suite
./dev.sh br             # Build and run (debug)
./dev.sh br-release     # Build and run (release)
./dev.sh run [dir]      # Run existing build (uses ff2:// URL scheme)
./dev.sh clean          # Nuke build artifacts
```

### After code changes
1. Build: `xcodebuild -project ff2.xcodeproj -scheme ff2 -configuration Debug build`
   - If you added/removed files or changed `project.yml`: run `xcodegen generate` first
2. Kill and relaunch: `pkill -f "ff2.app/Contents/MacOS/ff2"; sleep 1; open "ff2:///path"`
3. If tmux mode was on, also kill the tmux server: `tmux -L ff2 kill-server`
4. If you changed the tmux config: `rm -f ~/.ff2/tmux.conf` (it regenerates on launch)

### When to regenerate the Xcode project
Run `xcodegen generate` when:
- Adding or removing Swift source files
- Adding or removing localization files (lproj)
- Changing `project.yml` (build settings, dependencies, targets)

Do NOT edit `ff2.xcodeproj` directly. It is generated from `project.yml`.

### Running tests
```bash
xcodebuild -project ff2.xcodeproj -scheme ff2Tests -configuration Debug test
```
Tests are in `Tests/`. The test target links against the app target.

## Architecture

- **SwiftUI sidebar** + **AppKit terminal views** (Metal GPU-rendered via libghostty)
- **XcodeGen** for project generation (`project.yml` -> xcodeproj)
- **Ghostty** as git submodule, xcframework built with `zig build`
- **Bridging header** approach for GhosttyKit (not module import)
- **Single-window** app via `Window` (not `WindowGroup`)
- **`ff2://`** URL scheme for single-instance behavior
- **AppConstants.appID** is the single place to change when renaming the app

### Key directories
- `Sources/Models/` - Data models, git operations, tmux, name generator, app constants
- `Sources/Terminal/` - Ghostty integration (TerminalApp singleton, TerminalView NSView)
- `Sources/Views/` - SwiftUI views (sidebar, settings, project overview, tabs, browser)
- `Localization/` - lproj directories with Localizable.strings
- `Resources/` - Info.plist, entitlements
- `ghostty/` - Git submodule (do not modify, rebuild xcframework with `./dev.sh build-ghostty`)

### Data flow
- **Projects/workstreams** stored in UserDefaults as JSON, accessed via `ProjectStore`
- **Settings** use `@AppStorage` (UserDefaults)
- **Terminal surfaces** cached in `TerminalSurfaceCache` (keyed by UUID)
- **Git repo info** cached in `AppEnvironment`, refreshed async every 15s
- **Tool detection** runs at startup in `AppEnvironment.refresh()`

### Workstream lifecycle
1. Creating a workstream: generates name, runs `git worktree add`, symlinks .env (if enabled), stores worktree path
2. Terminal tabs: Coding Agent runs claude (with session-id for resume), Terminal runs shell
3. Setup tab (Cmd+5): auto-runs setup script on creation (if configured)
4. Run tab (Cmd+6): starts dev server on demand (if configured)
5. Tmux mode: wraps Coding Agent and script commands in `tmux new-session -A` on a dedicated socket (`-L ff2`)
6. Archiving: runs teardown script, then `git worktree remove` + `tmux kill-session` in background

### Script configuration
Scripts are loaded from the project directory in priority order:
1. `.ff2.json` or `.ff2/config.json` - `{ "setup": "cmd", "run": "cmd", "teardown": "cmd" }`
2. `.emdash.json` - `{ "scripts": { "setup": "cmd", "run": "cmd", "teardown": "cmd" } }`
3. `conductor.json` - `{ "scripts": { "setup": "cmd", "run": "cmd", "archive": "cmd" } }`
4. `.superset/config.json` - `{ "setup": ["cmd1", "cmd2"], "teardown": ["cmd1"] }`

The config model is in `Sources/Models/ScriptConfig.swift`.

## Localization

All user-facing strings MUST use localization. Never hardcode strings directly in SwiftUI views or code.

### Rules
- **SwiftUI Text/Button/Label**: Use string literals directly (e.g., `Text("Cancel")`). SwiftUI automatically treats these as `LocalizedStringKey` and looks them up in `Localizable.strings`.
- **AppKit APIs** (NSOpenPanel, NSAlert, etc.): Use `NSLocalizedString("string", comment: "")`.
- **String interpolation with Images**: Split into `Text` concatenation, not inline interpolation. E.g., `(Text("Press ") + Text(Image(systemName: "command")) + Text(" N"))`.
- **Every new user-facing string** must be added to `Localization/en.lproj/Localizable.strings` and all other locale files.
- Current locales: English (en), Catalan (ca), Spanish (es), Swedish (sv).

### Adding a new string
1. Use the string in code as described above
2. Add the English key-value pair to `Localization/en.lproj/Localizable.strings`
3. Add translations to all other `Localization/xx.lproj/Localizable.strings` files

### Adding a new language
1. Copy `Localization/en.lproj` to `Localization/xx.lproj`
2. Translate all values in `Localizable.strings` (keep keys unchanged)
3. Add the new lproj path to `project.yml` under sources (with `buildPhase: resources`)
4. Run `xcodegen generate`

### Extracting strings
```bash
grep -rn 'Text("' Sources/ | grep -v '//'
grep -rn 'Button("' Sources/ | grep -v '//'
grep -rn 'Label("' Sources/ | grep -v '//'
```

## Task Tracking
- **TODO.md**: Track bugs, features, and future work. Add items when you discover issues or defer work.
- When you notice something that should be done later, add it to TODO.md immediately.

## Keyboard Shortcuts
When adding, removing, or changing keyboard shortcuts:
1. Update `FF2App.swift` (menu commands)
2. Update `TerminalContainerView.swift` (tab bar labels and handlers)
3. Update `HelpView.swift` (shortcut reference)
4. Update `README.md` (shortcut table)

Current shortcuts are context-sensitive via `switchByNumber`:
- **Cmd+0**: project view (from workstream)
- **Cmd+1-9**: in project view = jump to Nth workstream; in workstream view = switch tabs (1=info, 2=agent, 3=terminal, 4=browser, 5=setup, 6=run)
- **Cmd+Shift+[/]**: cycle tabs
- **Cmd+Shift+O**: external browser
- **Cmd+Shift+E**: external terminal
- **Cmd+Shift+/**: help

## Naming
- The app ID is `ff2` (working name, will change). Use `AppConstants.appID` not hardcoded strings.
- Use "directory" not "folder" in all user-facing text.
- Use "Coding Agent" for the claude terminal tab, not "Claude Code".
- Use "workstream" for the sub-units of a project.
