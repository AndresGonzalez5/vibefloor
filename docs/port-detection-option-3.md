# Port Detection, Option 3

## Summary

Option 3 is viable, but only if we scope it tightly.

Using `proc_pidinfo` and related `libproc` APIs is a good native
replacement for `lsof` once we already know which process tree to
inspect. It removes subprocess overhead and keeps the implementation in
Swift, but it does not solve the hardest part of the problem:
identifying the correct run-script process tree in a reliable way.

The right v1 scope is:

- support tmux-backed run sessions only
- poll `libproc` on a timer, because there is no event-driven socket bind API here
- detect listening TCP ports opened by the run session process tree
- update existing browser tabs only when they are still on the default URL or showing a connection error
- never auto-open a browser tab
- do not attempt non-tmux support yet
- do not attempt multi-port heuristics beyond a single clear winner

Anything larger than that pushes us into guesswork around Ghostty child
PIDs and browser behavior.

## Review Of Option 3

### What is good about it

- Native Swift implementation, no `lsof` subprocesses
- Lower overhead than shelling out every poll interval
- Better control over filtering and state tracking
- Easier to unit test than parsing command output

### What is not solved by it

- We still need polling. `libproc` lets us inspect process state, not subscribe to socket events.
- We still need a trustworthy root PID.
- We still need process-tree traversal because the server may be a child or grandchild of the shell in the pane.
- We still need a browser retargeting policy, otherwise we will navigate users away from pages they opened intentionally.

### Bottom line

Option 3 is a good implementation technique, not a complete product
strategy. It is better than option 1 only after we narrow the problem to
a process tree we can identify with confidence.

## Current Codebase Constraints

The current code structure points to a narrow and practical design:

- [`EnvironmentTabView.swift`](/Users/dpoblador/repos/ff2/Sources/Views/EnvironmentTabView.swift) starts and restarts the run script
- [`TerminalContainerView.swift`](/Users/dpoblador/repos/ff2/Sources/Views/TerminalContainerView.swift) owns browser tabs and the default `localhost:$FF_PORT` behavior
- [`BrowserView.swift`](/Users/dpoblador/repos/ff2/Sources/Views/BrowserView.swift) tracks connection errors and current URL state
- [`TmuxSession.swift`](/Users/dpoblador/repos/ff2/Sources/Models/TmuxSession.swift) already owns tmux session naming, but does not yet expose pane PID lookup

That means the missing technical seam is not browser code. It is a
tmux-aware way to resolve the run session to a root PID.

## Recommendation

Build option 3 as a tmux-only feature first.

This is the only version that is properly scoped for the current app
architecture. In tmux mode we already have a deterministic session name
for the run pane. That gives us a stable way to ask tmux for the pane
PID and then inspect that process tree with `libproc`.

Do not ship a non-tmux fallback in the same change. The app does not
currently expose a reliable child PID for plain Ghostty surfaces, so the
non-tmux path would immediately fall back to heuristics or process scans
by working directory. That is where this feature gets brittle.

## Proposed V1 Behavior

### Trigger

Start detection when the run script starts in the Environment tab.

Restart detection when the run script is rerun.

Stop detection when:

- the run session is restarted
- the Environment tab disappears for that workstream
- the run session exits
- a port is selected and stabilized
- a timeout is reached

### Candidate ports

Inspect the tmux run pane PID and all descendants for listening TCP
sockets.

Eligible candidate ports:

- TCP listen sockets only
- user-space ports only (`>= 1024`)
- ports opened by the run process tree after detection started

Ignored:

- UDP
- established outbound sockets
- ports that existed before the run command started

### Port selection

Auto-select only when there is one clear winner.

Rules:

1. If exactly one new listening port appears, use it.
2. If multiple new ports appear, prefer `FF_PORT` if it is one of them.
3. Otherwise, do not auto-switch.

That third rule is important. Picking between `3000`, `5173`, `8000`,
`8080`, and backend sidecars using guesswork will produce bad behavior.

### Browser behavior

When a port is selected:

- update browser tabs for the current workstream only
- only retarget a browser tab if it is still on the default URL derived from `FF_PORT`
- also retarget if the tab is showing the built-in connection error for that same default URL
- do not navigate tabs that the user has already pointed somewhere else
- do not create a new browser tab automatically

Also update the default URL used by:

- new embedded browser tabs
- “Open External Browser”

This keeps behavior coherent without surprising the user.

## Proposed Architecture

### 1. `TmuxSession` gains run pane PID lookup

Add a focused helper that asks tmux for the pane PID of the run session.

Responsibility:

- given project, workstream, and role
- resolve the tmux session name
- ask tmux for `#{pane_pid}`
- return `pid_t?`

This belongs in [`TmuxSession.swift`](/Users/dpoblador/repos/ff2/Sources/Models/TmuxSession.swift), because tmux session naming and interaction already live there.

### 2. New `PortDetector`

Add a native detector model, likely in
[`Sources/Models/PortDetector.swift`](/Users/dpoblador/repos/ff2/Sources/Models/PortDetector.swift).

Responsibilities:

- start and stop polling for a root PID
- walk the descendant process tree with `proc_listchildpids`
- inspect file descriptors with `proc_pidinfo(..., PROC_PIDLISTFDS, ...)`
- inspect socket details with `proc_pidinfo(..., PROC_PIDFDSOCKETINFO, ...)`
- return new listening TCP ports
- publish detection results back to the UI

This should be stateful, because it needs to remember:

- start time
- previously seen ports
- selected port
- timeout state

### 3. Workstream-level browser target state

`TerminalContainerView` needs one more piece of state:

- the current preferred browser port for the workstream

It should initialize to `FF_PORT` and switch only when detection
confidently finds a better port.

That state then feeds:

- the default URL for new `BrowserView` tabs
- the target for “Open External Browser”
- retarget decisions for existing browser tabs

### 4. `BrowserView` accepts controlled navigation

`BrowserView` currently owns its own URL state. For port detection to be
useful, it needs a way to accept “navigate to this URL if you are still
showing the default target or the matching error page.”

The smallest reasonable change is to give it:

- a stable `defaultURL`
- a lightweight external navigation trigger
- enough local logic to ignore retarget requests once the user has navigated away intentionally

## Detection Algorithm

### Root PID

1. Resolve the tmux run session name.
2. Ask tmux for the run pane PID.
3. Treat that PID as the root of the inspection tree.

### Process tree

On each poll:

1. Gather the root PID and all descendants recursively.
2. For each PID, list file descriptors.
3. For each socket FD, inspect socket info.
4. Keep only TCP listen sockets.
5. Collect local ports.
6. Subtract ports already seen before this run.
7. Feed the result into port selection rules.

### Poll cadence

Use a repeating timer on the main actor boundary with the actual work
offloaded from the view layer.

Recommended values:

- interval: 1 second
- initial grace period: none
- timeout: 30 seconds
- stabilization: require the same selected port on 2 consecutive polls before switching browser target

The stabilization step avoids switching on very short-lived ports during
tool startup.

## Why Tmux-Only First

Tmux mode gives us a stable identity for the run session:

- session name is deterministic
- pane PID can be queried directly
- persisted run sessions already exist in this flow

Plain terminal mode does not currently give us an equivalent hook. The
app launches terminal content through Ghostty, but this code does not
currently expose a reliable child PID for the shell or command running
inside the surface. Without that, option 3 becomes “scan the machine and
guess,” which is not a good feature.

If non-tmux support matters later, the right follow-up is to add child
PID visibility at the terminal integration boundary first.

## Non-Goals For V1

- non-tmux port detection
- automatically opening browser tabs
- guessing the “frontend” port when several ports appear
- scanning unrelated processes by cwd
- trying to infer HTTP readiness from TCP listen alone
- support for remote hosts or non-localhost bind addresses
- replacing `FF_PORT` as the configured contract between Factory Floor and the run script

That last point matters. `FF_PORT` should remain the default and the
recommended setup. Port detection is a recovery path for scripts that do
not honor it.

## Risks

### Process identity drift

The tmux pane PID may be the shell rather than the final server process.
That is acceptable only because this design walks descendants.

### Short-lived bootstrap ports

Tooling may briefly open a port before the real dev server binds. This is
why stabilization is needed before switching browser target.

### Multi-port servers

Some run commands start both frontend and backend services. A detector
that picks one arbitrarily will be wrong often enough to annoy users.
That is why v1 should refuse to auto-switch unless the winner is clear.

### Browser surprise

If we navigate a browser the user already repurposed, the feature will
feel broken. Retargeting must be conservative.

## Testing Plan

This repo already has XCTest coverage around environment behavior and
tmux command composition, so the new work should extend that pattern.

Add unit tests for:

- tmux pane PID command construction and parsing
- process-tree traversal from synthetic PID graphs
- socket filtering from synthetic fd snapshots
- port selection rules
- browser retarget policy

Do not try to unit test live OS sockets or real tmux sessions in the
initial test pass. The important logic can be isolated behind small
protocol seams and exercised deterministically.

## Suggested File Changes

- [`Sources/Models/TmuxSession.swift`](/Users/dpoblador/repos/ff2/Sources/Models/TmuxSession.swift)
  Add run-pane PID lookup.
- [`Sources/Models/PortDetector.swift`](/Users/dpoblador/repos/ff2/Sources/Models/PortDetector.swift)
  Add native polling and port selection.
- [`Sources/Views/EnvironmentTabView.swift`](/Users/dpoblador/repos/ff2/Sources/Views/EnvironmentTabView.swift)
  Start and stop detection alongside run lifecycle.
- [`Sources/Views/TerminalContainerView.swift`](/Users/dpoblador/repos/ff2/Sources/Views/TerminalContainerView.swift)
  Store detected browser target per workstream and coordinate tab updates.
- [`Sources/Views/BrowserView.swift`](/Users/dpoblador/repos/ff2/Sources/Views/BrowserView.swift)
  Accept conservative external retarget requests.
- [`Tests/EnvironmentTabViewTests.swift`](/Users/dpoblador/repos/ff2/Tests/EnvironmentTabViewTests.swift)
  Extend lifecycle tests.
- [`Tests/TmuxSessionTests.swift`](/Users/dpoblador/repos/ff2/Tests/TmuxSessionTests.swift)
  Extend tmux integration tests.
- new tests for detector and selection behavior

## Final Recommendation

Option 3 is worth doing, but only as a tightly scoped tmux-first
feature.

That gives Factory Floor a native implementation with reasonable
reliability, without pretending we can robustly discover run-script PIDs
in plain terminal mode. If we want broader support later, the next
architectural step is not a cleverer detector. It is exposing process
identity from the terminal layer.
