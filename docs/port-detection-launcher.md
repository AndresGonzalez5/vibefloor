# Port Detection Via Run Launcher

## Summary

Yes, there is a cleaner way to solve port detection for both tmux and
plain terminal sessions: stop launching run scripts directly, and route
them through a dedicated Factory Floor launcher.

The launcher becomes the parent process for the run script, keeps the
terminal attached, watches the child process tree for listening TCP
ports, and reports the result back to the app.

That is a better architecture than app-side PID discovery because it
works the same way in both modes:

- tmux mode
- plain Ghostty terminal mode

The launcher does not eliminate all ambiguity, but it does eliminate the
hardest current problem: figuring out which process tree belongs to the
run script.

## Why This Is Better Than Tmux-Specific Detection

The current tmux-first design works because tmux can tell us the pane
PID. That is useful, but it is still a special case.

A launcher is better because:

- it owns the child PID directly
- it works the same way with or without tmux
- it localizes process management and port detection in one place
- it avoids Ghostty-specific child PID discovery work
- it keeps the app focused on UI state instead of OS process inspection

This is the first version of the feature that has a credible path to
cross-mode parity.

## Core Idea

Instead of sending the run script directly to the shell, Factory Floor
launches a helper process and gives that helper the run command.

Conceptually:

```text
Factory Floor -> launcher -> shell -> run script -> dev server(s)
```

The launcher:

1. starts the shell command as a child process
2. keeps stdin/stdout/stderr attached to the terminal
3. tracks the child process tree
4. polls for listening TCP ports with `libproc`
5. reports selected ports back to the app
6. forwards signals and exits with the same status as the child

That means the app no longer has to discover the run-script PID from the
outside. The launcher already knows it.

## Recommendation

If the goal is reliable support for both tmux and non-tmux modes, the
launcher approach is the better long-term design.

I would still keep the first shipped version narrow:

- wrap only the Environment tab run script
- do not wrap setup scripts yet
- use native `libproc` polling inside the launcher
- auto-switch only on a clear port winner
- do not auto-open browser tabs
- keep `FF_PORT` as the default contract

That gives us one well-bounded feature instead of turning the launcher
into a general-purpose shell supervisor on day one.

## What The Launcher Must Actually Do

This cannot be a thin bash wrapper if we want it to behave properly.

It needs to be a real executable with process control.

### Requirements

- launch the requested shell command in the foreground
- preserve interactive terminal behavior
- create or manage a child process group
- handle `Ctrl+C` and forward signals correctly
- detect listening ports from the child process tree
- report port updates to the app
- exit with the same code or signal outcome as the run command

Shell glue can fake parts of this, but it gets brittle fast once signal
forwarding and descendant inspection matter.

## Why Not Extend The Existing `ff` Shell Script

The current bundled script at
[`Resources/Scripts/ff`](/Users/dpoblador/repos/ff2/Resources/Scripts/ff)
is a simple URL-scheme launcher for opening directories in the app.

It is not the right place to grow process supervision because:

- it is written as a lightweight convenience script
- shell signal semantics are easy to get subtly wrong
- child-process and process-group handling will get messy
- `libproc` port inspection is easier and safer from Swift

So the right shape is a small helper binary, bundled with the app, not
an increasingly clever shell script.

## Proposed Architecture

### 1. New bundled launcher binary

Add a small executable target, for example `ff-run`.

Responsibility:

- parse launcher arguments
- start the actual run command
- monitor the child tree
- write port status updates
- forward signals
- mirror child exit status

This helper should be the only place that knows how to supervise the run
script process tree.

### 2. Environment run command always goes through the launcher

`EnvironmentTabView` currently builds the run command and sends it to the
terminal directly.

Instead, it should invoke something conceptually like:

```sh
ff-run \
  --workstream-id <uuid> \
  --expected-port <ff_port> \
  --state-file <path> \
  -- sh -lc "<run script>"
```

That wrapper can be used:

- inside tmux sessions
- in plain terminal sessions

The terminal still shows the real script output because the launcher
keeps stdio attached.

### 3. App reads launcher status

The launcher needs to report port discoveries back to the app.

The cleanest first version is a small state file keyed by workstream ID.

Example location:

- `~/.config/factoryfloor/run-state/<workstream-id>.json`

Example contents:

```json
{
  "workstreamID": "UUID",
  "pid": 12345,
  "status": "running",
  "detectedPorts": [5173],
  "selectedPort": 5173
}
```

Why a state file is better than URL callbacks for v1:

- simpler to debug
- no focus-stealing side effects
- no URL-scheme routing edge cases
- easier to test deterministically

The app can poll or watch these files and update browser targets for the
matching workstream.

### 4. App still owns browser policy

The launcher should report facts, not make UI decisions.

It should report:

- child PID
- detected listening ports
- selected port, if any
- lifecycle state

The app should decide:

- whether to retarget an embedded browser tab
- whether the current tab is still on the default URL
- whether the tab is showing a connection error
- what to do when multiple tabs exist

This keeps UI behavior in the app and process behavior in the helper.

## Detection Model

The launcher can use the same `libproc` mechanics discussed in option 3,
but it no longer has to discover the root PID from the outside.

### Root process

The launcher starts the shell command and gets the child PID directly.

That PID becomes the inspection root.

### Child tree

On each poll:

1. gather the child PID and descendants
2. inspect file descriptors with `PROC_PIDLISTFDS`
3. inspect socket details with `PROC_PIDFDSOCKETINFO`
4. keep only TCP listen sockets
5. collect local ports
6. compare against the baseline taken at launcher start

### Port selection

Keep the same conservative rules:

1. if exactly one new listening port appears, use it
2. if several appear and `FF_PORT` is among them, use `FF_PORT`
3. otherwise, report ambiguity and do not auto-switch

That avoids pretending we can always tell frontend from backend.

## Terminal And Signal Behavior

This is the part that makes or breaks the launcher.

The helper must preserve the feel of running the command directly in the
terminal.

That means:

- child stdout and stderr stream directly into the terminal
- stdin remains interactive
- `Ctrl+C` reaches the run command
- if the child forks workers, signals still reach the relevant process group
- the helper exits when the command exits

If we get this wrong, port detection is irrelevant because the run
experience itself will feel broken.

## Communication Options

There are three realistic ways for the launcher to tell the app about
detected ports.

### Option 1: State file

Recommended for v1.

Pros:

- simple
- robust
- easy to inspect manually
- works whether the app is foregrounded or not

Cons:

- requires cleanup
- app needs polling or file watching

### Option 2: Distributed notifications

Possible, but less attractive for the first pass.

Pros:

- event-driven
- no file cleanup

Cons:

- harder to debug
- delivery timing is less transparent
- still needs state recovery if the app misses an event

### Option 3: URL-scheme callbacks

Not recommended.

Pros:

- already available

Cons:

- awkward message channel
- likely to create activation/focus side effects
- poor fit for repeated state updates

## Suggested Scope For V1

The launcher design can sprawl if we let it. The smallest useful slice
is:

- add a bundled helper executable
- use it only for Environment run scripts
- use state-file reporting
- support both tmux and non-tmux modes
- detect ports for the child process tree
- update browser target only on a clear winner

Not in v1:

- wrapping setup scripts
- HTTP readiness probing
- remote host detection
- daemonized background services
- browser auto-open
- choosing among multiple non-`FF_PORT` candidates

## Risks

### Daemonizing scripts

If the run script intentionally detaches and exits, the launcher loses
the clean parent-child lifecycle model. We can support that later if it
turns out to matter, but it should not shape v1.

### Process group bugs

TTY and signal bugs are easy to introduce and annoying to diagnose. This
is the strongest argument for a real helper binary instead of shell
glue.

### State cleanup

If the helper crashes or the app quits unexpectedly, stale state files
can remain. The file format should include enough lifecycle metadata for
the app to ignore dead entries.

### Ambiguous multi-port services

The launcher knows more than the app about the process tree, but it
still does not know which port is the “right” browser target unless the
signal is obvious.

## Suggested File Changes

- new executable target in [`project.yml`](/Users/dpoblador/repos/ff2/project.yml)
  for the launcher binary
- new launcher source files under `Sources/`
- [`Sources/Views/EnvironmentTabView.swift`](/Users/dpoblador/repos/ff2/Sources/Views/EnvironmentTabView.swift)
  to route run commands through the launcher
- [`Sources/Views/TerminalContainerView.swift`](/Users/dpoblador/repos/ff2/Sources/Views/TerminalContainerView.swift)
  to react to reported selected ports
- [`Sources/Views/BrowserView.swift`](/Users/dpoblador/repos/ff2/Sources/Views/BrowserView.swift)
  for conservative retargeting
- new tests for launcher argument building, port selection, and app-side
  browser retarget policy

## Recommendation

If you want one feature that behaves consistently in both terminal
modes, build the launcher.

The tmux-only approach is simpler as a narrow tactical fix. The launcher
approach is the better system design because it moves run-script
ownership to a place where process identity is explicit instead of
inferred.
