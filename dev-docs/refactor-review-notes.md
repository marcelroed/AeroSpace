# Refactor review notes: suspected bugs

These are the suspected bugs found while refactoring on branch `refactor-cleanup`. The branch starts from base `812da7fa` (2026-10-26).

The refactor was meant to preserve behavior, so **none of the production bugs below are fixed**. Some problems were fixed along the way: several test-suite problems, one build warning and one wrong test expectation. They are listed under [Resolved by the refactor](#resolved-by-the-refactor).

Every open entry is marked `needs review`. For each one, either confirm it and fix it in a separate behavior-change commit (upstream if possible), or close it with a reason.

**Severity** is about user impact:
- **High:** a crash or hang that can happen in normal use.
- **Medium:** one of the following:
  - wrong behavior that users can hit;
  - a crash or hang that needs unusual conditions.
- **Low:** cosmetic problems, diagnostics, non-deterministic output, and test-suite quality.

**Confidence:**
- **Likely:** the code clearly does the wrong thing, and the trigger is clear. Some of these were confirmed by running the code.
- **Possible:** the code looks wrong, but the trigger is uncertain or hard to reach.
- **Speculative:** one of the following:
  - the problem is theoretical;
  - the code path can't be reached today;
  - it depends on undocumented API behavior.

**Locations:**
- **Original** is the code at `812da7fa`.
- **Current** is `refactor-cleanup` at `c394622e`.
- Paths are relative to the repository root.

**IDs are stable.** A gap in the summary table is an entry that moved to [Resolved by the refactor](#resolved-by-the-refactor) or [Dropped entries](#dropped-entries).

## Summary

| ID | Severity | Confidence | Area | Title |
|----|----------|------------|------|-------|
| [RB-01](#rb-01-with-no-screens-monitorapproximation-crashes-and-mainmonitorinfo-returns-a-fake-monitor) | high | possible | Core model | With no screens, `monitorApproximation` crashes and `mainMonitorInfo` returns a fake monitor |
| [RB-02](#rb-02-termination-helpers-can-block-the-main-thread-forever) | high | possible | Core model | Termination helpers can block the main thread forever |
| [RB-03](#rb-03-reading-a-special-container-creates-it-and-makes-it-the-most-recent-child) | medium | likely | Core model | Reading a special container creates it and makes it the most-recent child |
| [RB-04](#rb-04-config-auto-reload-stops-after-an-atomic-save-with-a-syntax-error) | medium | likely | Config, shell and UI | Config auto-reload stops after an atomic save with a syntax error |
| [RB-05](#rb-05-int32exitcodesucc-is-2) | medium | likely | Commands and CLI | `Int32ExitCode.succ` is 2 |
| [RB-06](#rb-06-dying-recurses-forever-when-tmpbobkoaerospace-isnt-writable) | medium | likely | Shared utilities | Dying recurses forever when `/tmp/bobko.aerospace` isn't writable |
| [RB-07](#rb-07-ax-size-and-position-getters-crash-on-unexpected-values-and-can-deadlock-on-quit) | medium | possible | Shared utilities | AX size and position getters crash on unexpected values and can deadlock on quit |
| [RB-08](#rb-08-readbytes-busy-loops-when-the-peer-closes-early) | medium | possible | Shared utilities | `read(bytes:)` busy-loops when the peer closes early |
| [RB-09](#rb-09-on-quit-windows-are-centered-without-the-monitors-origin) | medium | possible | Shared utilities | On quit, windows are centered without the monitor's origin |
| [RB-10](#rb-10-config-reload-crashes-if-librarylaunchagents-cant-be-created) | medium | possible | Config, shell and UI | Config reload crashes if `~/Library/LaunchAgents` can't be created |
| [RB-11](#rb-11-test-not---help-prints-the-test-usage) | low | likely | Commands and CLI | `test-not --help` prints the `test` usage |
| [RB-12](#rb-12-the-move-workspace-to-display-alias-skips-post-parse-validation) | low | likely | Commands and CLI | The `move-workspace-to-display` alias skips post-parse validation |
| [RB-13](#rb-13-output-and-error-order-depends-on-dictionary-and-set-iteration) | low | likely | Commands and CLI | Output and error order depends on Dictionary and Set iteration |
| [RB-14](#rb-14-subscribe-adds-a-bogus-error-after-a-duplicate-event) | low | likely | Commands and CLI | `subscribe` adds a bogus error after a duplicate event |
| [RB-15](#rb-15-exec-and-forget-description-has-a-double-space) | low | likely | Commands and CLI | `exec-and-forget` description has a double space |
| [RB-16](#rb-16-post-parse-validation-errors-lack-the-error-prefix) | low | likely | Commands and CLI | Post-parse validation errors lack the `ERROR:` prefix |
| [RB-17](#rb-17-error-text-names---wraparound-instead-of---wrap-around) | low | likely | Commands and CLI | Error text names `--wrapAround` instead of `--wrap-around` |
| [RB-18](#rb-18-rached-typo-and-inconsistent---fail-if-noop-tip-wording) | low | likely | Commands and CLI | "Rached" typo and inconsistent `--fail-if-noop` tip wording |
| [RB-19](#rb-19-config---get----keys-error-shows-string) | low | likely | Commands and CLI | `config --get … --keys` error shows `string("…")` |
| [RB-67](#rb-67-resize-fails-silently-when-the-window-is-its-parents-only-tiling-child) | low | likely | Commands and CLI | `resize` fails silently when the window is its parent's only tiling child |
| [RB-20](#rb-20-dragging-a-floating-window-rebinds-it-on-every-mouse-event) | low | likely | Core model | Dragging a floating window rebinds it on every mouse event |
| [RB-21](#rb-21-crash-messages-print-the-type-name-instead-of-the-node) | low | likely | Core model | Crash messages print the type name instead of the node |
| [RB-22](#rb-22-the-splitflatten-conflict-error-says-disabled-instead-of-enabled) | low | likely | Config, shell and UI | The split/flatten conflict error says "disabled" instead of "enabled" |
| [RB-23](#rb-23-wrong-expected-type-in-the-execenv-vars-error) | low | likely | Config, shell and UI | Wrong expected type in the `exec.env-vars` error |
| [RB-24](#rb-24-the-shell-parser-rejects-input-that-is-only-newlines-or-comments) | low | likely | Config, shell and UI | The shell parser rejects input that is only newlines or comments |
| [RB-25](#rb-25-finding-the-project-root-loops-forever-without-a-git-directory) | low | likely | Config, shell and UI | Finding the project root loops forever without a `.git` directory |
| [RB-26](#rb-26-the-unrecognized-flag-error-names-the-wrong-flag) | low | likely | Shared utilities | The unrecognized-flag error names the wrong flag |
| [RB-27](#rb-27-interceptterminationsigkill-does-nothing) | low | likely | Shared utilities | `interceptTermination(SIGKILL)` does nothing |
| [RB-28](#rb-28-activationpolicyprohibited-prints-with-a-leading-space) | low | likely | Shared utilities | `ActivationPolicy.prohibited` prints with a leading space |
| [RB-29](#rb-29-jointruncating-adds-an-ellipsis-when-nothing-was-cut) | low | likely | Shared utilities | `joinTruncating` adds an ellipsis when nothing was cut |
| [RB-30](#rb-30-kaxtrustedcheckoptionprompt-is-taken-as-retained) | low | likely | Shared utilities | `kAXTrustedCheckOptionPrompt` is taken as retained |
| [RB-31](#rb-31-workspace-back-and-forth-ignores-whether-focusing-succeeded) | low | possible | Commands and CLI | `workspace-back-and-forth` ignores whether focusing succeeded |
| [RB-32](#rb-32-run-callback---for-every-window-differs-from-real-window-detection) | low | possible | Commands and CLI | `run-callback --for-every-window` differs from real window detection |
| [RB-33](#rb-33-resize-accepts-doubled-signs) | low | possible | Commands and CLI | `resize` accepts doubled signs |
| [RB-34](#rb-34-debug-windows-state-machine-quirks) | low | possible | Commands and CLI | `debug-windows` state machine quirks |
| [RB-35](#rb-35-the-window-level-cache-misses-on-every-lookup-for-off-screen-windows) | low | possible | Core model | The window-level cache misses on every lookup for off-screen windows |
| [RB-36](#rb-36-virtual-rects-shrink-by-inner-gaps-in-nested-containers) | low | possible | Core model | Virtual rects shrink by inner gaps in nested containers |
| [RB-37](#rb-37-tray-symbols-for-workspace-names-that-only-look-like-numbers) | low | possible | Config, shell and UI | Tray symbols for workspace names that only look like numbers |
| [RB-38](#rb-38-open-config-and-reload-use-the-wrong-file-if-the---config-path-file-is-deleted) | low | possible | Config, shell and UI | "Open config" and reload use the wrong file if the `--config-path` file is deleted |
| [RB-39](#rb-39-the-debug-build-signal-handler-isnt-async-signal-safe) | low | possible | Shared utilities | The debug-build signal handler isn't async-signal-safe |
| [RB-40](#rb-40-inconsistent-reporting-of-impossible-paths) | low | speculative | Commands and CLI | Inconsistent reporting of "impossible" paths |
| [RB-41](#rb-41-workspace-gc-evaluates-focus-inside-its-filter) | low | speculative | Core model | Workspace GC evaluates `focus` inside its filter |
| [RB-42](#rb-42-hotkey-events-can-report-another-modes-key-notation) | low | speculative | Config, shell and UI | Hotkey events can report another mode's key notation |
| [RB-43](#rb-43-on-window-detected-warnings-are-dropped-when-there-are-no-errors) | low | speculative | Config, shell and UI | `on-window-detected` warnings are dropped when there are no errors |
| [RB-44](#rb-44-implicit-persistent-workspace-order-depends-on-dictionary-iteration) | low | speculative | Config, shell and UI | Implicit persistent-workspace order depends on Dictionary iteration |
| [RB-68](#rb-68-toml-syntax-errors-are-reported-verbatim-from-tomlkit) | low | speculative | Config, shell and UI | TOML syntax errors are reported verbatim from TOMLKit |
| [RB-45](#rb-45-unchecked-as-axuielement-casts) | low | speculative | Shared utilities | Unchecked `as! AXUIElement` casts |
| [RB-46](#rb-46-initconnection-hangs-if-the-connection-is-cancelled-before-it-is-ready) | low | speculative | Shared utilities | `initConnection` hangs if the connection is cancelled before it is ready |
| [RB-47](#rb-47-bugprompt-reads-nsscreen-from-whatever-thread-is-dying) | low | speculative | Shared utilities | `bugPrompt` reads `NSScreen` from whatever thread is dying |
| [RB-48](#rb-48-topaddingtable-mixes-character-and-utf-16-counts) | low | speculative | Shared utilities | `toPaddingTable` mixes Character and UTF-16 counts |
| [RB-49](#rb-49-transposed-assumes-a-rectangular-table) | low | speculative | Shared utilities | `transposed()` assumes a rectangular table |
| [RB-69](#rb-69-isunittest-depends-on-xctest-being-loaded) | low | speculative | Shared utilities | `isUnitTest` depends on XCTest being loaded |
| [RB-61](#rb-61-tests-cant-reset-two-private-focus-globals) | low | possible | Tests | Tests can't reset two private focus globals |
| [RB-64](#rb-64-all-ax-dumps-run-in-one-test-that-crashes-on-a-malformed-dump) | low | possible | Tests | All AX dumps run in one test that crashes on a malformed dump |
| [RB-70](#rb-70-testservereventdecoding-checks-only-the-event-type) | low | possible | Tests | `testServerEventDecoding` checks only the event type |

**Totals:** 55 open entries: 2 high, 8 medium and 45 low. Of these, 52 are in production code and 3 are in tests. A further 18 entries were resolved by the refactor, and 3 were dropped.

## Core model

### RB-01: With no screens, `monitorApproximation` crashes and `mainMonitorInfo` returns a fake monitor

- **Status:** needs review
- **Severity:** high · **Confidence:** possible
- **Original location:** `Sources/AppBundle/util/appBundleUtil.swift:102 @812da7fa`, `Sources/AppBundle/model/MonitorInfo.swift:97-111 @812da7fa`
- **Current location:** `Sources/AppBundle/util/appBundleUtil.swift:102`, `Sources/AppBundle/model/MonitorInfo.swift:62-85`. The bug is unchanged: CM-12 turned `MonitorInfo` into a struct but kept both fallbacks.
- **Description:** During display reconfiguration, `NSScreen.screens` can briefly be empty. In that state:
  - `monitorInfos` returns `[]`, and `CGPoint.monitorApproximation` calls `minByOrDie` on it, which dies with "Empty sequence".
  - `mainMonitorInfo` silently returns the 1920x1080 unit-test monitor, so its callers lay out windows against a monitor that doesn't exist.
- **How it shows up:** a crash on display wake, or when connecting or disconnecting displays. This is the same window as the known stack-overflow crash in `activeWorkspace` on display wake. These callers can hit it during a refresh:
  - `Workspace.workspaceMonitor` (`Workspace.swift:103-106`)
  - `layoutFloatingWindow` (`layoutRecursive.swift:74`)
  - `MacWindow.hideInCorner` (`MacWindow.swift:115`)
  - `makeAllWindowsVisibleAndRestoreSize` on quit
  - the mouse handlers

  It's hard to reproduce on demand. Look for "Empty sequence" crash reports around display wake.
- **Fix direction:** skip refresh and layout while there are no screens. Alternatively, make `monitorApproximation` optional and handle nil at the call sites. Use the fake monitor only in unit tests.

### RB-02: Termination helpers can block the main thread forever

- **Status:** needs review
- **Severity:** high · **Confidence:** possible
- **Original location:** `Sources/AppBundle/tree/MacApp.swift:159-171` (`setAxFrameForTermination`), `:186-195` (`getAxRectForTermination`) and `:354-359` (`withWindowAsync`) `@812da7fa`
- **Current location:** `Sources/AppBundle/tree/MacApp.swift:159-171`, `:186-195` and `:354-359`. Unchanged.
- **Description:** Both helpers schedule work on the app's AX thread with `withWindowAsync`, then block the main thread on a semaphore or a `CompletableFuture`. The scheduled body starts with `guard let window = windows.threadGuarded[windowId] else { return }`. If the window is no longer in the app's `windows` map, the body returns before `semaphore.signal()` or `future.complete(...)` runs, and the main thread waits forever.
- **How it shows up:** AeroSpace hangs on quit (or on Ctrl-C in debug builds) instead of restoring windows and exiting. The race:
  1. `refreshAndGetAliveWindowIds` has already dropped a dead window from `windows`.
  2. `refresh()` hasn't garbage-collected the `MacWindow` yet.
  3. Quit arrives.

  Repro idea: close a window and quit AeroSpace at the same moment, or add a debug-only delay between the two refresh steps.
- **Fix direction:** signal or complete in a `defer` inside the body, or have `withWindowAsync` report a missing window to its caller. Consider a timed wait on termination paths.

### RB-03: Reading a special container creates it and makes it the most-recent child

- **Status:** needs review
- **Severity:** medium · **Confidence:** likely
- **Original location:** `Sources/AppBundle/tree/WorkspaceEx.swift:27-52 @812da7fa`, `Sources/AppBundle/tree/TreeNode.swift:95 @812da7fa`
- **Current location:** `Sources/AppBundle/tree/WorkspaceEx.swift:19-35` (the shared `singleChild` helper from CM-6 is at `:38-54`) and `Sources/AppBundle/tree/TreeNode.swift:97`. Behavior is unchanged.
- **Description:**
  1. The getters `floatingWindowsContainer`, `macOsNativeFullscreenWindowsContainer` and `macOsNativeHiddenAppsWindowsContainer` create and bind their container when it's missing.
  2. `bind` always calls `markAsMostRecentChild()`, so a plain read makes the new, empty container the workspace's most-recent child.
  3. `Workspace.toLiveFocus()` then gets nil from `mostRecentWindowRecursive`.
  4. It falls back to `anyLeafWindowRecursive`, which returns the first window in the tree, not the last-focused one.
- **How it shows up:** after a window closes, switching to another workspace can focus that workspace's first window instead of the one that was focused last. It happens once per container, because after that the container exists. Triggers:
  - Every window close runs `cacheClosedWindowIfNeeded` (`Sources/AppBundle/tree/frozen/closedWindowsCache.swift:40-50`). That builds a `FrozenWorkspace` for every workspace, which reads these getters (`closedWindowsCache.swift:33-36`).
  - Layout reads `floatingWindowsContainer` (`Sources/AppBundle/layout/layoutRecursive.swift:24` in both versions).

  The `todo` in `toLiveFocus` describes this symptom (`Sources/AppBundle/focus.swift:94 @812da7fa`, now `:96`).

  Repro idea: write a unit test that creates windows A and B, focuses B, reads `workspace.floatingWindowsContainer`, and then asserts that `workspace.toLiveFocus()` still points at B.
- **Fix direction:** bind auto-created containers without marking them most-recent, or create them when the workspace is created. Read-only callers could also use a lookup that doesn't create.

### RB-20: Dragging a floating window rebinds it on every mouse event

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/mouse/moveWithMouse.swift:44 @812da7fa`
- **Current location:** `Sources/AppBundle/mouse/moveWithMouse.swift:28`. The rebind is still there. CM-1 removed the stack-trace symbolication from each rebind, which was the expensive part.
- **Description:** `moveFloatingWindow` checks `targetWorkspace != parent`. Since upstream 5e37ec0a, a floating window's parent is the workspace's `FloatingWindowsContainer`, never the workspace itself. So the check is always true, and every drag event unbinds and rebinds the window.
- **How it shows up:**
  - During a drag, the window moves to the end of the floating children on every event.
  - The MRU order churns.
  - Before CM-1, each event also symbolicated a stack trace, which cost CPU.
- **Fix direction:** compare against `window.nodeWorkspace`.

### RB-21: Crash messages print the type name instead of the node

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location (`@812da7fa`) → current location:**
  - `Sources/AppBundle/tree/Workspace.swift:97` → `:94`
  - `Sources/AppBundle/tree/TreeNode.swift:122` → `:126`
  - `Sources/AppBundle/tree/TreeNodeCases.swift:185` → `:184`
  - `Sources/AppBundle/tree/Workspace.swift:200-201` → `:195-196`
  - `Sources/AppBundle/command/impl/MoveWorkspaceToMonitorCommand.swift:22` → `:22`
  - `Sources/AppBundle/command/impl/SummonWorkspaceCommand.swift:24` → `:20`
- **Description:** These `die` and `check` messages interpolate `\(workspace)`, `\(self)` or `\(stubWorkspace)`. `Workspace` and `TreeNode` don't conform to `CustomStringConvertible`: `Workspace.description` is a plain `@MainActor` property. So the messages print only the type name, such as "AppBundle.Workspace". The three "getStubWorkspace generated incompatible stub workspace" messages are also missing their closing parenthesis.
- **How it shows up:** crash reports don't identify the node involved.
- **Fix direction:** interpolate `.name` or `prettyDescription` explicitly, and close the parenthesis.

### RB-35: The window-level cache misses on every lookup for off-screen windows

- **Status:** needs review
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/AppBundle/windowLevelCache.swift:8-26 @812da7fa`
- **Current location:** `Sources/AppBundle/windowLevelCache.swift:8-26`. Unchanged.
- **Description:** On a miss, `getWindowLevel` queries `CGWindowListCopyWindowInfo` with `.optionOnScreenOnly`, then replaces the whole cache with the result. Off-screen windows never appear in that result: minimized windows, windows of hidden apps, and windows on other Spaces. So every lookup for one of them repeats the full query. A window whose level changes keeps its stale cached level until some other miss replaces the cache.
- **How it shows up:** extra CPU work during refresh when many windows are off-screen. Rarely, a window has the wrong level, which affects how it is classified.
- **Fix direction:** cache negative results for the duration of a refresh, and invalidate the cache once per refresh instead of on misses.

### RB-36: Virtual rects shrink by inner gaps in nested containers

- **Status:** needs review
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/AppBundle/layout/layoutRecursive.swift:126-137 @812da7fa` (virtual rect at 130-135; the `height - 1` workaround at `:11`)
- **Current location:** `Sources/AppBundle/layout/layoutRecursive.swift:121-133` (virtual rect at 128-133; `height - 1` at `:12`). Unchanged.
- **Description:** Virtual rects are documented as the layout "as if inner gaps were always zero". In `layoutTiles`, though, the cross-axis size of a child's virtual rect is the physical `width` or `height`, not the parent's virtual size. The physical size has already been reduced by inner gaps and by the `height - 1` workaround.
- **How it shows up:** in nested containers, virtual rects are a few pixels too small. For example, a v-container with virtual width 1250 gives its children a virtual width of 1240. This affects resize-with-mouse and floating-as-tiling focus decisions by a few pixels.
- **Fix direction:** use `virtual.width` or `virtual.height` for the cross axis.

### RB-41: Workspace GC evaluates `focus` inside its filter

- **Status:** needs review
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/AppBundle/tree/Workspace.swift:84-94 @812da7fa`
- **Current location:** `Sources/AppBundle/tree/Workspace.swift:81-91`. Unchanged. The CM-11 plan was to hoist `focus` out of the filter, but only the `setFocus` part of CM-11 landed.
- **Description:** `garbageCollectUnusedWorkspaces` reads `focus` inside the `filter` closure over `workspaceNameToWorkspace`. `focus` goes through `FrozenFocus.live`, which calls `Workspace.get(byName:)`, and that can insert a new workspace into the same dictionary. The insertion is lost when the filtered copy is assigned back.
- **How it shows up:** in theory, two `Workspace` objects end up with the same name, which trips the `check` in `Workspace.==` (`:94`). This has not been observed.
- **Fix direction:** read `focus.workspace.name` once, before the filter.

## Commands and CLI

### RB-05: `Int32ExitCode.succ` is 2

- **Status:** needs review
- **Severity:** medium · **Confidence:** likely
- **Original location:** `Sources/Common/cmdArgs/ExitCode.swift:17 @812da7fa`. It is used at `Sources/AppBundle/tree/MacWindow.swift:274` and `Sources/AppBundle/command/impl/RunCallbackCommand.swift:12`.
- **Current location:** `Sources/Common/cmdArgs/ExitCode.swift:17`. It is used at `Sources/AppBundle/tree/MacWindow.swift:255` and `Sources/AppBundle/command/impl/RunCallbackCommand.swift:12`. Unchanged.
- **Description:** `public static let succ = Int32ExitCode(rawValue: EXIT_CODE_TWO)` has the same value as `.fail`. It came in with upstream 59b181c9 ("Implement RunCallbackCommand"), apparently copied from the `fail` line above it. It is used as the default when no callback runs.
- **How it shows up:**
  - `aerospace run-callback on-window-detected` exits 2 when no `on-window-detected` callback matches or none is configured.
  - `run-callback --for-every-window on-window-detected` exits 2 when there are no windows.
  - By contrast, `run-callback on-focus-changed` with no callbacks exits 0, because an empty `Shell` returns 0 (`Sources/AppBundle/shell/Shell.swift:107 @812da7fa`, now `:91`).
  - The docs (`docs/aerospace-run-callback.adoc`) say the command forwards the callback's exit code.
  - Real window detection discards the value, so only the CLI is affected.
- **Fix direction:** set it to `EXIT_CODE_ZERO`. This changes a CLI exit code, so mention it in the changelog.

### RB-11: `test-not --help` prints the `test` usage

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/Common/cmdArgs/impl/TestNotCmdArgs.swift:15-19 @812da7fa`
- **Current location:** `Sources/Common/cmdArgs/impl/TestNotCmdArgs.swift:15-19`. Unchanged.
- **Description:** `parseTestNotCmdArgs` parses with `TestCmdArgs`. For `--help`, the result is `TestCmdArgs.info.help`, which is `test_help_generated`. `test_not_help_generated` is never shown.
- **How it shows up:** `aerospace test-not --help` prints `USAGE: test …`.
- **Fix direction:** map a `.help` result to `TestNotCmdArgs.info.help`.

### RB-12: The `move-workspace-to-display` alias skips post-parse validation

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/Common/cmdArgs/cmdArgsManifest.swift:124 @812da7fa`. The validator is at `Sources/Common/cmdArgs/impl/MoveWorkpsaceToMonitorCmdArgs.swift:21-26`.
- **Current location:** `Sources/Common/cmdArgs/cmdArgsManifest.swift:124`. The validator is `parseMoveWorkspaceToMonitorCmdArgs` at `Sources/Common/cmdArgs/impl/MoveWorkspaceToMonitorCmdArgs.swift:21-26`; the file was renamed to fix its typo. Behavior is unchanged.
- **Description:** The deprecated alias registers `MoveWorkspaceToMonitorCmdArgs.init`. `SubCommandParser(_ raw:)` then runs only `parseSpecificCmdArgs` and skips the validator that the real command uses.
- **How it shows up:** `aerospace move-workspace-to-display --wrap-around 2` is accepted, but `aerospace move-workspace-to-monitor --wrap-around 2` is rejected.
- **Fix direction:** register the alias with `parseMoveWorkspaceToMonitorCmdArgs`.

### RB-13: Output and error order depends on Dictionary and Set iteration

- **Status:** needs review
- **Severity:** low · **Confidence:** likely (possible for `list-apps`)
- **Original and current location:** the lines are the same in both versions.

  | Location | Affected output |
  |---|---|
  | `Sources/Common/cmdArgs/impl/ConfigCmdArgs.swift:42-50` | "Conflicting flags are specified: …", which joins a `Set`. The test works around it with `hasPrefix` (`ConfigCommandTest.swift:39 @812da7fa`, now `:40`). |
  | `Sources/AppBundle/command/impl/ConfigCommand.swift:16` | `config --major-keys`, which lists `config.modes.keys`. |
  | `Sources/AppBundle/command/impl/ConfigCommand.swift:48` | `config --get <map> --keys --json`. The array isn't sorted, while the plain-text path is sorted at `:74`. |
  | `Sources/AppBundle/command/impl/ConfigCommand.swift:112` | `config --all-keys`, which walks dictionaries recursively. |
  | `Sources/AppBundle/command/impl/TriggerBindingCommand.swift:18` | "Available modes: …" |
  | `Sources/AppBundle/command/impl/ListExecEnvVarsCommand.swift:9` | `list-exec-env-vars` |
  | `Sources/AppBundle/command/impl/ListAppsCommand.swift:9` | `list-apps`, from `MacApp.allAppsMap.values`. It is never sorted, unlike `list-windows`. Maybe acceptable. |
- **Description:** Swift seeds Dictionary and Set hashing per process, so iteration order changes from run to run. These paths print in iteration order.
- **How it shows up:** the same command prints its lines in a different order on different runs, which breaks scripts that diff the output and makes tests fragile.
- **Fix direction:** sort before printing. Sort `list-apps` the same way as `list-windows`.

### RB-14: `subscribe` adds a bogus error after a duplicate event

- **Status:** needs review
- **Severity:** low · **Confidence:** likely (confirmed by running it)
- **Original location:** `Sources/Common/cmdArgs/impl/SubscribeCmdArgs.swift:46 @812da7fa`
- **Current location:** `Sources/Common/cmdArgs/impl/SubscribeCmdArgs.swift:46`. Unchanged.
- **Description:** On a parse failure, the parser returns `advanceBy: events.count + 1`. `events` is the de-duplicated set, not the number of arguments consumed.
- **How it shows up:** `aerospace subscribe focus-changed focus-changed bogus` advances too little, reads `bogus` again, and prints an extra "Unknown argument 'bogus'" error.
- **Fix direction:** count consumed arguments with `enumerated()`.

### RB-15: `exec-and-forget` description has a double space

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/Common/cmdArgs/parseCmdArgs.swift:56` and `Sources/AppBundle/command/parseCommand.swift:8-9` `@812da7fa`. Pinned by `Sources/AppBundleTests/command/ExecCommandTest.swift:10`.
- **Current location:** same files and lines, including the test. Unchanged.
- **Description:** `parseCommand` keeps the text after `exec-and-forget` untrimmed, so `bashScript` starts with a space, and `description` adds another one. A related, speculative problem: `raw.starts(with: "exec-and-forget")` also matches `exec-and-forgetfoo`.
- **How it shows up:** `aerospace config --get mode.main.binding.<key>` prints `exec-and-forget  open …`, through `shellOfCommandsDescription` (`ConfigCommand.swift:126`).
- **Fix direction:** trim the script once in `parseCommand` and update `ExecCommandTest`. Require a space or the end of input after the command name.

### RB-16: Post-parse validation errors lack the `ERROR:` prefix

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/Common/cmdArgs/ParsedCmd.swift:29-37 @812da7fa`. `joinErrors` is at `Sources/Common/util/StringEx.swift:26`.
- **Current location:** same lines. Unchanged.
- **Description:** Arg-parser errors are joined with `joinErrors()`, which prefixes each one with `ERROR: `. Post-parse validation failures (`.filter`, `.filterNot`, `.failure(String)`) are printed without the prefix.
- **How it shows up:** `aerospace focus --dfs-index 0 left` prints a bare message, while `aerospace focus foo` prints `ERROR: …`.
- **Fix direction:** format validation failures the same way as parser errors.

### RB-17: Error text names `--wrapAround` instead of `--wrap-around`

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/Common/cmdArgs/impl/WorkspaceCmdArgs.swift:32` and `Sources/Common/cmdArgs/impl/MoveNodeToWorkspaceCmdArgs.swift:41` `@812da7fa`. Pinned by `Sources/AppBundleTests/command/WorkspaceCommandTest.swift:18`.
- **Current location:** same production lines. Unchanged. The test is now at `WorkspaceCommandTest.swift:15`.
- **Description:** The messages say "--wrapAround requires using (next|prev) argument", but the flag is `--wrap-around`. Also, the `move-node-to-workspace` message hard-codes `(prev|next)`, while `workspace` uses `NextPrev.unionLiteral`, which is `(next|prev)`.
- **How it shows up:** `aerospace workspace --wrap-around 1` tells the user about a flag that doesn't exist.
- **Fix direction:** use the real flag name and `NextPrev.unionLiteral` in both messages, and update the test.

### RB-18: "Rached" typo and inconsistent `--fail-if-noop` tip wording

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/command/impl/WorkspaceCommand.swift:67`, `Sources/AppBundle/command/impl/LayoutCommand.swift:47` and `Sources/AppBundle/command/impl/MacosNativeFullscreenCommand.swift:29` `@812da7fa`
- **Current location:** `WorkspaceCommand.swift:62`, `LayoutCommand.swift:44` and `MacosNativeFullscreenCommand.swift:22`. Pinned by `Sources/AppBundleTests/command/MoveNodeToWorkspaceCommandTest.swift:159` and by `Sources/AppBundleTests/command/LayoutCommandTest.swift:205, 238, 257, 459`. TS-4 added the last three when it fixed RB-53. At `812da7fa` only line 255 pinned the wording.
- **Description:** "Rached the beginning of the supplied workspaces list" should say "Reached". Most noop messages end with "Tip: use --fail-if-noop to exit with non-zero code", but `layout` and `macos-native-fullscreen` say "non-zero exit code".
- **How it shows up:** user-visible stderr text.
- **Fix direction:** fix the spelling, pick one wording for the tip, and update both tests.

### RB-19: `config --get … --keys` error shows `string("…")`

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/command/impl/ConfigCommand.swift:46 @812da7fa`. Pinned by `Sources/AppBundleTests/command/ConfigCommandTest.swift:154`.
- **Current location:** `ConfigCommand.swift:46`. Unchanged. The test is now at `ConfigCommandTest.swift:165`.
- **Description:** The message interpolates the `ConfigScalarValue` enum directly, which produces Swift's default case representation. Other messages in the same file use `scalar.describe` (`:61`, `:86`).
- **How it shows up:** `aerospace config --get mode.main.binding.alt-h --keys` prints `--keys flag cannot be applied to scalar object 'string("focus left")'`.
- **Fix direction:** use `scalar.describe` and update the test.

### RB-67: `resize` fails silently when the window is its parent's only tiling child

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/command/impl/ResizeCommand.swift:47 @812da7fa`. The `orientation` and `node` guards at `:39-40` also return a bare `.fail`.
- **Current location:** `Sources/AppBundle/command/impl/ResizeCommand.swift:34`, with the guards at `:26-27`. Pinned by `testSingleChildParent_failsCleanly` (`Sources/AppBundleTests/command/ResizeCommandTest.swift:157-165`). That test checks the exit code and that the weight is unchanged, but not that a message is printed.
- **Description:** if the target node is the only child of its tiling parent, `diff.div(parent.children.count - 1)` returns nil. The command then returns a bare `.fail`, which means exit code 2 and nothing on stderr.
- **How it shows up:** in a workspace with a single tiled window, `aerospace resize width +50` exits with code 2 and doesn't say why.
- **Fix direction:** print a message, for example that the window has no siblings to take space from, and assert it in the test.

### RB-31: `workspace-back-and-forth` ignores whether focusing succeeded

- **Status:** needs review
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/AppBundle/command/impl/WorkspaceBackAndForthCommand.swift:9 @812da7fa`
- **Current location:** same line. Unchanged.
- **Description:** `prevFocusedWorkspace?.focusWorkspace() != nil` compares an `Optional<Bool>` with nil, so the `Bool` result is ignored.
- **How it shows up:** the command exits 0 whenever a previous workspace exists, even if focusing it failed. It exits 2 with no message when there is no previous workspace. Compare `FocusBackAndForthCommand.swift:9-12`, which uses the result and prints a message.
- **Fix direction:** follow `FocusBackAndForthCommand`.

### RB-32: `run-callback --for-every-window` differs from real window detection

- **Status:** needs review
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/AppBundle/command/impl/RunCallbackCommand.swift:11-16 @812da7fa`. Real detection is `runOnWindowDetected` at `Sources/AppBundle/tree/MacWindow.swift:244`.
- **Current location:** `RunCallbackCommand.swift:11-16`. `runOnWindowDetected` is at `MacWindow.swift:226`. Unchanged.
- **Description:** The command iterates `MacWindow.allWindows` and calls `onWindowDetected` directly.
- **How it shows up:**
  - Callbacks also run for popups and unbound windows, which real detection skips.
  - Windows are processed in dictionary order.
  - The exit code is the last window's.
- **Fix direction:** share the filter with `runOnWindowDetected`, sort by window id, and combine the exit codes.

### RB-33: `resize` accepts doubled signs

- **Status:** needs review
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/Common/cmdArgs/impl/ResizeCmdArgs.swift:49 @812da7fa`
- **Current location:** `Sources/Common/cmdArgs/impl/ResizeCmdArgs.swift:47`. Unchanged.
- **Description:** The amount is parsed with `removePrefix("+").removePrefix("-")` and then `UInt(...)`, and `UInt(...)` itself accepts a leading `+`. So:
  - `+-5` and `++5` both mean "add 5".
  - `-+5` is rejected as an unknown flag, because the negative-number check needs a digit after `-`. That check was `isResizeNegativeUnitsArg` in `parseSpecificCmdArgs.swift:80-83 @812da7fa`; it is now `isNegativeNumber` at `parseSpecificCmdArgs.swift:80`, used together with `negativeNumbersArePositional`.
- **How it shows up:** `aerospace resize width +-50` grows the window instead of failing.
- **Fix direction:** accept exactly one optional sign followed by digits.

### RB-34: `debug-windows` state machine quirks

- **Status:** needs review
- **Severity:** low · **Confidence:** possible (the last point is speculative)
- **Original location:** `Sources/AppBundle/command/impl/DebugWindowsCommand.swift:45-55` and `:122-129` `@812da7fa`
- **Current location:** same lines. Unchanged.
- **Description:**
  - `count > debugWindowsLimit` lets 11 windows in, but the message says 10.
  - After setting `.recordingAborted`, the code doesn't return, so it still logs the current window.
  - The state is set to `.recording` and the "started" banner is printed before `resolveTargetOrReportError`. If target resolution fails, the command exits 2 and may leave recording on.
- **How it shows up:** an off-by-one in the window limit, and an extra entry after an abort.
- **Fix direction:** use `>=`, return after aborting, and resolve the target before changing the state.

### RB-40: Inconsistent reporting of "impossible" paths

- **Status:** needs review
- **Severity:** low · **Confidence:** speculative (unreachable today)
- **Original location (`@812da7fa`):**
  - `Sources/AppBundle/command/impl/FocusCommand.swift:81` returns a plain "Must be discarded by args parser", while `:61` wraps the same text in `bugPrompt(...)`.
  - `Sources/AppBundle/command/impl/MoveCommand.swift:67` returns a plain "Can't find the current monitor", while `FocusCommand.swift:86` uses `bugPrompt`.
- **Current location:** `FocusCommand.swift:78` vs `:58`, and `MoveCommand.swift:61` vs `FocusCommand.swift:83`.
- **Description:** the same impossible conditions are reported in two different ways.
- **How it shows up:** it doesn't today. If one of these paths is ever reached, the plain variants won't ask for a bug report.
- **Fix direction:** use `bugPrompt` in all of them.

## Config, shell and UI

### RB-04: Config auto-reload stops after an atomic save with a syntax error

- **Status:** needs review
- **Severity:** medium · **Confidence:** likely
- **Original location:** `Sources/AppBundle/config/ConfigFileWatcher.swift:31-45` and `Sources/AppBundle/command/impl/ReloadConfigCommand.swift:51-60` `@812da7fa`
- **Current location:** same lines. Unchanged.
- **Description:** The watcher is a `DispatchSource` on an `O_EVTONLY` file descriptor, so it follows the inode, not the path. Only `syncConfigFileWatcher()` re-arms it, and `ReloadConfigCommand` calls that only when the reload is allowed. A TOML syntax error is a `preventConfigReload` error, so `allowReloadConfig` is false (`parseConfig.swift:236 @812da7fa`, now `:257`), and the watcher isn't re-armed.
- **How it shows up:** editors that save atomically write a temporary file and rename it over the config, which replaces the inode. If such a save contains a syntax error, the watcher stays bound to the old, deleted file. Fixing the error and saving again does nothing. Auto-reload silently stops until the user runs `aerospace reload-config`.

  Repro: in an editor that saves atomically, save the config with a stray `[`, fix it, and save again. The fix isn't picked up.
- **Fix direction:** call `syncConfigFileWatcher()` after every reload attempt, or re-arm the watcher on delete and rename events whatever the reload result.

### RB-10: Config reload crashes if `~/Library/LaunchAgents` can't be created

- **Status:** needs review
- **Severity:** medium · **Confidence:** possible
- **Original location:** `Sources/AppBundle/config/startAtLogin.swift:16-21 @812da7fa`
- **Current location:** `Sources/AppBundle/config/startAtLogin.swift:16-21`. Unchanged.
- **Description:** `syncStartAtLogin` runs on startup and on every successful reload. It calls `cleanupPlistFromPrevVersions`, which creates `~/Library/LaunchAgents` with `getOrDie` only so that it can delete a legacy plist from it. The delete doesn't need the directory to exist.
- **How it shows up:** with a read-only or unusual home directory, such as on a managed Mac, AeroSpace crashes at startup and on every reload. Repro idea: point `HOME` at a read-only directory in a debug build.
- **Fix direction:** don't create the directory. Remove the plist with `try?` only if it exists.

### RB-22: The split/flatten conflict error says "disabled" instead of "enabled"

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/config/parseConfig.swift:302 @812da7fa`
- **Current location:** `Sources/AppBundle/config/parseConfig.swift:324` (`splitAndFlattenConflictError`). Pinned by `Sources/AppBundleTests/config/ConfigTest.swift:280`.
- **Description:** The error fires when `enable-normalization-flatten-containers` is enabled and a binding uses `split`. The text says "'split' command has no effect when enable-normalization-flatten-containers is disabled".
- **How it shows up:** a misleading config diagnostic.
- **Fix direction:** change "disabled" to "enabled" and update the test.

### RB-23: Wrong expected type in the `exec.env-vars` error

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/config/parseExecEnvVariables.swift:37 @812da7fa`
- **Current location:** `Sources/AppBundle/config/parseExecEnvVariables.swift:37`. Unchanged.
- **Description:** if `exec.env-vars` isn't a table, the error says "Expected type is 'Array'".
- **How it shows up:** `[exec]` with `env-vars = 1` produces a message that asks for an array.
- **Fix direction:** pass `expected: .table` (`TomlType.table` exists).

### RB-24: The shell parser rejects input that is only newlines or comments

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/shell/shellParser.swift:91-99` and `Sources/AppBundle/shell/shellLexer.swift:32-33` `@812da7fa`
- **Current location:** `shellParser.swift:90-98` and `shellLexer.swift:32-33`. Unchanged.
- **Description:** The lexer emits a `.newline` token after a comment that ends in a newline. The parser then finds a newline where it expects a word. So `"\n"` and `"# c\n"` fail with "Expected at least one word. Got: \n", while `"# c"` parses as empty. `ShellParserTest.swift:16 @812da7fa` (now `:18`) shows the message.
- **How it shows up:** a multi-line TOML command string that contains only comments, for example a binding that was temporarily commented out, is reported as a config error.
- **Fix direction:** skip newline tokens before requiring a word, and treat input that is only whitespace or comments as empty.

### RB-25: Finding the project root loops forever without a `.git` directory

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/config/Config.swift:9-11` and `Sources/AppBundleTests/testUtil.swift:10` `@812da7fa`
- **Current location:** `Sources/AppBundle/config/Config.swift:9-11`. Unchanged. The test half is fixed: TS-3 (f7e5b183) changed `projectRoot` (`Sources/AppBundleTests/testUtil.swift:6-14`) to look for `Package.swift` and to stop at `/`.
- **Description:** `getDefaultConfigUrlFromProject` walks up from `#filePath` until it finds `.git`. `deleteLastPathComponent` never fails, so the loop never ends when no ancestor has a `.git` directory. This happens with a source tarball or a copied tree.
- **How it shows up:** a debug build that isn't run as an app bundle hangs at startup, and so do unit tests, because `defaultConfigUrl` falls back to this function.
- **Fix direction:** stop at the filesystem root and fail with a clear message.

### RB-37: Tray symbols for workspace names that only look like numbers

- **Status:** needs review
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/AppBundle/ui/TrayMenuModel.swift:94-106 @812da7fa`
- **Current location:** `Sources/AppBundle/ui/TrayMenuModel.swift:111-125`, rendered by `MenuBarLabel.swift`. Unchanged.
- **Description:** `Int(name)` accepts names such as `+5`, `-0` and `005`. The symbol name is then built from the raw name, for example `+5.square`, and SF Symbols has no such symbol. `05` is probably fine.
- **How it shows up:** in the squares and i3 menu-bar styles, such a workspace shows a blank item instead of the text fallback.
- **Fix direction:** use the symbol only when `String(number) == name`, or when the name is all digits and has the canonical form.

### RB-38: "Open config" and reload use the wrong file if the `--config-path` file is deleted

- **Status:** needs review
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/AppBundle/config/ConfigFile.swift:5-23` and `Sources/AppBundle/ui/MenuBar.swift:95-103` `@812da7fa`
- **Current location:** `ConfigFile.swift:5-22` and `MenuBar.swift:116-127` (`openConfigButton`). Unchanged.
- **Description:** `findCustomConfigUrl` returns `.noCustomConfigExists` when the file given by `--config-path` doesn't exist. Startup rejects a missing path (`initAppBundle.swift:108-110`), but the file can be deleted after launch.
- **How it shows up:** after the file is deleted, "Open config" copies the default config to `~/.aerospace.toml` instead of the configured path, and reloading silently falls back to the default config.
- **Fix direction:** when `--config-path` is set, always use it, and report a missing file as an error.

### RB-42: Hotkey events can report another mode's key notation

- **Status:** needs review
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/AppBundle/config/HotkeyBinding.swift:31-45 @812da7fa`
- **Current location:** `Sources/AppBundle/config/HotkeyBinding.swift:31-45` (the event is built at `:35-38`). Unchanged.
- **Description:** A `HotKey` is registered once per key code. When a later mode binds the same key code, the existing registration stays. Its handler correctly looks up the active mode's command, but it still broadcasts the first mode's `binding.descriptionWithKeyNotation`.
- **How it shows up:** if two modes reach the same key code through different notations (for example key-mapping aliases), `bindingTriggered` events report the other mode's notation. The right command still runs.
- **Fix direction:** take the notation from the active mode's binding when building the event.

### RB-43: `on-window-detected` warnings are dropped when there are no errors

- **Status:** needs review
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/AppBundle/config/parseOnWindowDetected.swift:130-134 @812da7fa`
- **Current location:** `Sources/AppBundle/config/parseOnWindowDetected.swift:127-131`. Unchanged.
- **Description:** `myContext.warnings` reaches `c.warnings` only when the callback also has errors.
- **How it shows up:** nothing today, because only the top-level `config-version` check emits warnings.
- **Fix direction:** always append the warnings.

### RB-44: Implicit persistent-workspace order depends on Dictionary iteration

- **Status:** needs review
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/AppBundle/config/parseConfig.swift:280-288 @812da7fa`
- **Current location:** `Sources/AppBundle/config/parseConfig.swift:286` and `:299-310` (`implicitPersistentWorkspaces`). Unchanged.
- **Description:** For `config-version = 1`, the implicit `persistentWorkspaces` order comes from iterating `[String: Mode]` and `[String: HotkeyBinding]`, so it changes from process to process.
- **How it shows up:** no visible effect was found. `Workspace.all` sorts, and the order isn't shown in any output. It would matter if something started relying on the `OrderedSet` order.
- **Fix direction:** sort the names before inserting them.

### RB-68: TOML syntax errors are reported verbatim from TOMLKit

- **Status:** needs review
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/AppBundle/config/parseConfig.swift:254 @812da7fa`
- **Current location:** `Sources/AppBundle/config/parseConfig.swift:212`. Unchanged. Pinned by `testMissingValueIsSyntaxErrorThatPreventsReload` (`Sources/AppBundleTests/config/ConfigTest.swift:680-685`).
- **Description:** TOML parse errors are passed on unchanged as `error.description`. For `a = `, the message is "[ERROR] (Line 1) Syntax error: syntax error.", which doesn't say what is wrong.
- **How it shows up:** an unhelpful config error for common TOML mistakes.
- **Fix direction:** wrap TOMLKit's error and add context, such as the offending line, where TOMLKit provides it.

## Shared utilities and app entry point

### RB-06: Dying recurses forever when `/tmp/bobko.aerospace` isn't writable

- **Status:** needs review
- **Severity:** medium · **Confidence:** likely (when the directory isn't writable)
- **Original location:** `Sources/Common/util/showMessageInGui.swift:9-12` and `Sources/Common/util/commonUtil.swift:59-66` `@812da7fa`
- **Current location:** same lines. Unchanged.
- **Description:** `dieT` calls `showMessageInGui`, which creates and writes `/tmp/bobko.aerospace/` with `getOrDie`. If that fails, `getOrDie` calls `die` → `dieT` → `showMessageInGui` again, forever. The directory is in the shared `/tmp` and isn't per-user, so it may belong to another macOS user on the same machine.
- **How it shows up:** any crash turns into a stack overflow. The error report is never shown, and the termination handler never runs, so hidden windows are not restored.

  Repro: create `/tmp/bobko.aerospace` as another user (or as root) with mode 755, then trigger any `die` in a debug build.
- **Fix direction:** use a per-user directory (for example `FileManager.default.temporaryDirectory`), and use `try?` there instead of `getOrDie`.

### RB-07: AX size and position getters crash on unexpected values and can deadlock on quit

- **Status:** needs review
- **Severity:** medium · **Confidence:** possible for the crash, speculative for the deadlock
- **Original location:** `Sources/AppBundle/util/accessibility.swift:252,264 @812da7fa`
- **Current location:** `Sources/AppBundle/util/accessibility.swift:85,97`. Unchanged in substance.
- **Description:** The size and position getters do `check(AXValueGetValue($0 as! AXValue, …))`. An app that returns something that isn't an `AXValue`, or an `AXValue` of the wrong type, kills AeroSpace. During termination it can be worse:
  1. `getAxRectForTermination` blocks the main thread while it waits for the AX thread.
  2. A `die` on the AX thread calls `MainActor.runSync`, which is `DispatchQueue.main.asyncAndWait`.
  3. The main thread is blocked, so this deadlocks.
- **How it shows up:** one misbehaving app crashes the window manager. During quit it hangs instead of producing a crash report. No such app is known.
- **Fix direction:** check `CFGetTypeID` and `AXValueGetType` before reading, and return nil on a mismatch, as the other attribute getters do.

### RB-08: `read(bytes:)` busy-loops when the peer closes early

- **Status:** needs review
- **Severity:** medium · **Confidence:** possible
- **Original location:** `Sources/Common/util/NWConnectionEx.swift:65-81 @812da7fa`
- **Current location:** `Sources/Common/util/NWConnectionEx.swift:66-82`. Unchanged in behavior.
- **Description:** `read(bytes:)` loops while `data.count < size`. When the peer closes before sending enough bytes, `receive` reports `isComplete == true` with nil data and no error. The loop then appends an empty `Data()` and asks again, forever. `readTillError` handles this case, but `read(bytes:)` doesn't.
- **How it shows up:** the CLI spins at 100% CPU if the server dies in the middle of an answer. A server task does the same if a client disconnects in the middle of a request.

  Repro: run a small Unix-socket server at the AeroSpace socket path that accepts a connection and closes it without answering, then run any `aerospace` command.
- **Fix direction:** when `isComplete` is true and fewer bytes than requested have arrived, throw a "connection closed" error.

### RB-09: On quit, windows are centered without the monitor's origin

- **Status:** needs review
- **Severity:** medium · **Confidence:** possible
- **Original location:** `Sources/AppBundle/util/appBundleUtil.swift:33-40 @812da7fa`
- **Current location:** `Sources/AppBundle/util/appBundleUtil.swift:33-40`. Unchanged.
- **Description:** When AeroSpace quits, it moves every window back on screen. Each window is centered at `((visibleRect.width - w) / 2, (visibleRect.height - h) / 2)` on its approximate monitor. The monitor's `topLeftX` and `topLeftY` are never added, so the position is relative to the main monitor's origin.
- **How it shows up:** with several monitors, windows that belonged to a secondary monitor end up on the main monitor after AeroSpace quits. The code has been like this since at least late 2023 (db226755), so it may be intentional.
- **Fix direction:** add `visibleRect.topLeftX` and `topLeftY`, or confirm with upstream that placing windows on the main monitor is intended, and document it.

### RB-26: The unrecognized-flag error names the wrong flag

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/initAppBundle.swift:105 @812da7fa`
- **Current location:** `Sources/AppBundle/initAppBundle.swift:105`. Unchanged.
- **Description:** the message prints `args.first` instead of `current`, which is the flag that was actually rejected.
- **How it shows up:** `AeroSpace --read-only --bogus` reports "Unrecognized flag '--read-only'".
- **Fix direction:** print `current`.

### RB-27: `interceptTermination(SIGKILL)` does nothing

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/initAppBundle.swift:14 @812da7fa`
- **Current location:** `Sources/AppBundle/initAppBundle.swift:14`. Unchanged.
- **Description:** SIGKILL can't be caught, so `signal()` returns `SIG_ERR` and the call has no effect.
- **How it shows up:** nothing visible. It is misleading, because it suggests that `kill -9` restores windows.
- **Fix direction:** remove the call.

### RB-28: `ActivationPolicy.prohibited` prints with a leading space

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/util/NsApplicationEx.swift:7 @812da7fa`. Used by `DebugWindowsCommand.swift:96`.
- **Current location:** same lines. Unchanged.
- **Description:** The string for `.prohibited` is `" prohibited"`.
- **How it shows up:**
  - The leading space appears in `debug-windows` output.
  - The test helper `ActivationPolicy.from(string:)` (`AxUiElementWindowTypeTest.swift:62-69 @812da7fa`, now `:69-78`) would `die` on a dump that contains this value.
- **Fix direction:** remove the space.

### RB-29: `joinTruncating` adds an ellipsis when nothing was cut

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/Common/util/StringEx.swift:39-60 @812da7fa`. Used by `Sources/AppBundle/ui/TrayMenuModel.swift:41`.
- **Current location:** `StringEx.swift:39-60`. Used by `TrayMenuModel.swift:52`. Pinned by `Sources/AppBundleTests/util/CommonUtilTest.swift:75`.
- **Description:** The first element is never counted against `length`, and the check is `elemCount < remainingLen` where `<=` is meant. For example, `["aaa", "bbb", "ccc"]` with length 10 gives `"aaa, bbb, ccc…"` even though nothing was cut.
- **How it shows up:** the app list in the tray menu can show a spurious "…" or run past 25 characters.
- **Fix direction:** count every element, use `<=`, and update the test.

### RB-30: `kAXTrustedCheckOptionPrompt` is taken as retained

- **Status:** needs review
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/util/axTrustedCheckOptionPrompt.swift:3 @812da7fa`
- **Current location:** `Sources/AppBundle/util/axTrustedCheckOptionPrompt.swift:3`. Unchanged.
- **Description:** `kAXTrustedCheckOptionPrompt.takeRetainedValue()` over-releases a global CFString constant.
- **How it shows up:** nothing in practice, because CFSTR constants are never freed. The ownership is still wrong.
- **Fix direction:** use `takeUnretainedValue()`.

### RB-39: The debug-build signal handler isn't async-signal-safe

- **Status:** needs review
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/AppBundle/util/appBundleUtil.swift:11-19 @812da7fa`
- **Current location:** `Sources/AppBundle/util/appBundleUtil.swift:11-19`. Unchanged.
- **Description:** The handler allocates, spawns a `Task`, and calls `check`, which can `die` and show a GUI. None of that is safe in a signal handler. The signal can also arrive on any thread, so `check(Thread.current.isMainThread)` can fail.
- **How it shows up:** debug builds only. Ctrl-C can crash or deadlock instead of restoring windows.
- **Fix direction:** use `DispatchSource.makeSignalSource(signal:queue: .main)` together with `signal(sig, SIG_IGN)`.

### RB-45: Unchecked `as! AXUIElement` casts

- **Status:** needs review
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/AppBundle/util/accessibility.swift:191, 328` and `Sources/AppBundle/util/dumpAxRecursive.swift:59` `@812da7fa`
- **Current location:** `accessibility.swift:69, 126`, plus a new site at `:143` (`axWindowOrNil`), and `dumpAxRecursive.swift:61`
- **Description:** `as!` to a CoreFoundation type isn't checked at runtime. A value that isn't an AX element would be passed straight to the AX functions. `dumpAxRecursive` does this for every attribute value that isn't a string, number or bool.
- **How it shows up:** nothing so far. The code relies on the AX APIs rejecting wrong types gracefully, and `debug-windows` already sends many attribute values through these casts without crashing.
- **Fix direction:** check `CFGetTypeID(value) == AXUIElementGetTypeID()` before casting.

### RB-46: `initConnection` hangs if the connection is cancelled before it is ready

- **Status:** needs review
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/Common/util/NWConnectionEx.swift:24 @812da7fa`
- **Current location:** `Sources/Common/util/NWConnectionEx.swift:24`. UT-7 kept the behavior.
- **Description:** The state handler resumes the continuation on `.ready`, `.failed` and `.waiting`, but not on `.cancelled`.
- **How it shows up:** the CLI would hang instead of reporting an error. Nothing currently cancels a connection before it is ready.
- **Fix direction:** resume with an error on `.cancelled`.

### RB-47: `bugPrompt` reads `NSScreen` from whatever thread is dying

- **Status:** needs review
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/Common/util/commonUtil.swift:43-44 @812da7fa`
- **Current location:** `Sources/Common/util/commonUtil.swift:43-44`. Unchanged.
- **Description:** `bugPrompt` reads `NSScreen.screens` and `NSScreen.screensHaveSeparateSpaces` on the thread that is dying, which is often an AX thread. AppKit doesn't document these as thread-safe.
- **How it shows up:** the crash reporter itself could crash.
- **Fix direction:** read these values only on the main thread, and skip them elsewhere.

### RB-48: `toPaddingTable` mixes Character and UTF-16 counts

- **Status:** needs review
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/Common/util/StringEx.swift:64-73 @812da7fa`
- **Current location:** `Sources/Common/util/StringEx.swift:64-73`. Unchanged.
- **Description:** Column widths are measured in `Character`s, but padding uses `NSString.padding(toLength:)`, which counts UTF-16 code units.
- **How it shows up:** columns with non-BMP or decomposed characters come out misaligned or truncated. All current inputs (the CLI help) are ASCII.
- **Fix direction:** pad by appending spaces based on `count`.

### RB-49: `transposed()` assumes a rectangular table

- **Status:** needs review
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/Common/util/ArrayEx.swift:2-15 @812da7fa`
- **Current location:** `Sources/Common/util/ArrayEx.swift:2-5`. It was rewritten with the same behavior.
- **Description:** The column count comes from the first row. Extra cells in longer rows are silently dropped, and shorter rows cause a `die`.
- **How it shows up:** nothing today, because the callers in `format.swift` build rectangular tables.
- **Fix direction:** document the precondition, or check it with a clear message.

### RB-69: `isUnitTest` depends on XCTest being loaded

- **Status:** needs review
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/Common/util/commonUtil.swift:151 @812da7fa`
- **Current location:** `Sources/Common/util/commonUtil.swift:149`. It is now a `let` instead of a computed property, with the same check.
- **Description:** `isUnitTest` is `NSClassFromString("XCTestCase") != nil`. Swift Testing runs, such as `--filter` on a migrated suite or `--disable-xctest`, see it as true only because the SwiftPM testing helper happens to link and load XCTest.
- **How it shows up:** if a future toolchain stops loading XCTest for Swift Testing runs, `isUnitTest` becomes false, and the tests drive the real accessibility API and monitors. Two checks added by the test-suite cleanup would make such a run fail loudly:
  - `SwiftTestingSupportTest.swift:41`
  - a `check(isUnitTest)` in the global-state trait (`SwiftTestingSupport.swift:34`)
- **Fix direction:** detect test runs explicitly, for example with an environment variable or a flag set by the test target. This is TS-11 in the test plan.

## Test suite

Test-suite issues are all low severity: they hide regressions but don't affect users. Since the base commit, the test-suite cleanup (TS-1 to TS-8) has landed and many suites now use Swift Testing. That work fixed most of the original test entries, which are now listed under [Resolved by the refactor](#resolved-by-the-refactor).

### RB-61: Tests can't reset two private focus globals

- **Status:** needs review
- **Severity:** low · **Confidence:** possible
- **Original location (`@812da7fa`):**
  - the test suites `Sources/AppBundleTests/command/FormatTest.swift:200, 206`, `Sources/AppBundleTests/command/ListModesTest.swift:5, 20` and `Sources/AppBundleTests/command/WorkspaceCommandTest.swift:9`
  - the globals `Sources/AppBundle/focus.swift:116` and `Sources/AppBundle/focusCache.swift:1`
- **Current location:**
  - `_prevFocus` at `Sources/AppBundle/focus.swift:118`
  - `lastKnownNativeFocusedWindowId` at `Sources/AppBundle/focusCache.swift:1`
  - the reset function, `setUpWorkspacesForTests` (`Sources/AppBundleTests/testUtil.swift:16-53`)

  TS-3 (f7e5b183) fixed the rest of the original entry:
  - `setUpWorkspacesForTests` now empties the global minimized and popup containers.
  - It also resets `_prevFocusedWorkspaceName`, `activeMode` and other globals.
  - `ListModesTest` has the standard `setUp`.
- **Description:** `_prevFocus` and `lastKnownNativeFocusedWindowId` are `private` globals, so the test setup can't reset them.
- **How it shows up:** a test whose result depends on the previous focus or on the native-focus cache also depends on the order the tests run in. No test is affected today.
- **Fix direction:** add a test-only reset hook. This is a small production change.

### RB-64: All AX dumps run in one test that crashes on a malformed dump

- **Status:** needs review
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/AppBundleTests/AxUiElementWindowTypeTest.swift:5, 19-30 @812da7fa`
- **Current location:** `Sources/AppBundleTests/AxUiElementWindowTypeTest.swift:8-12` and `:16-44`. The `as!` casts are at `:26` and `:31`, and the `dieT()` calls at `:30`, `:34` and `:39`. Two parts of the original entry are fixed:
  - TS-5 (3a7f30d2) renamed the class to match its file.
  - TS-4 added a check that at least one dump was read.
- **Description:** a single test checks every dump in `axDumps/`. A malformed dump hits `as!` or `dieT()` and aborts the whole test process instead of failing one case.
- **Fix direction:** parameterize the test over the dump files (Swift Testing `arguments:`), and report parse problems as test failures. The test-suite cleanup deferred this because it changes the test count.

### RB-70: `testServerEventDecoding` checks only the event type

- **Status:** needs review
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/AppBundleTests/model/ClientServerTest.swift:96-110 @812da7fa`
- **Current location:** `Sources/AppBundleTests/model/ClientServerTest.swift:106-120`. Unchanged.
- **Description:** the test decodes six events but compares only `eventType`. It never checks the payload fields (`windowId`, `workspace`, `monitorId`, `prevWorkspace`, `mode`, `binding`). The encoding test covers only the opposite direction.
- **How it shows up:** a decoder that drops or swaps fields still passes.
- **Fix direction:** compare each decoded event with a complete expected `ServerEvent`.

## Resolved by the refactor

These entries were fixed on `refactor-cleanup`. Locations are at `c394622e` unless noted.

- **RS-1: `Lateinit ==` treated any two initialized values as equal.**
  - Original location: `Sources/Common/util/Lateinit.swift:22-25 @812da7fa`.
  - Cause: `a && b && c || d` parses as `(a && b && c) || d`. So `CmdArgs` equality ignored every mandatory positional argument in the parse and config tests. Production code never compared these values, so users saw no effect.
  - Fixed in bed216c1, which replaced the custom `==` with the synthesized `extension Lateinit: Equatable where T: Equatable {}` (`Lateinit.swift:14`).
- **RS-2: data race on `RunLoopJob._isCancelled`.**
  - Original location: `Sources/AppBundle/runLoop.swift:65-71 @812da7fa`.
  - Cause: the AX thread read the flag non-atomically while the main thread wrote it with `OSAtomicCompareAndSwapInt`.
  - CM-10 (a8b6b7c5) puts the flag behind an `OSAllocatedUnfairLock` (`runLoop.swift:62-69`).
- **RS-3: `ConfigTest.testParseKeyMapping` expected the wrong workspace.**
  - Original location: `Sources/AppBundleTests/config/ConfigTest.swift:704-705 @812da7fa`.
  - Cause: the test expected `workspace unicorn`, but the config under test binds `workspace wonderland`. The old `Lateinit ==` bug hid the mismatch.
  - bed216c1 marked the assertion as an expected failure.
  - R-1 (1ec122fa) corrected it to expect `wonderland` (`ConfigTest.swift:703`). It is no longer an expected failure.
- **RS-4: misaligned load in `NWConnectionEx`.**
  - Original location: `Sources/Common/util/NWConnectionEx.swift:96 @812da7fa`.
  - Cause: `load(as: UInt32.self)` requires 4-byte alignment, which a small inline `Data` doesn't guarantee.
  - UT-7 (d27f42e9) switched to `loadUnaligned` (`:97`). It gives the same result whenever the old code worked.
- **RS-5: `SecureInputView` passed the icon width as the height.**
  - Original location: `Sources/AppBundle/ui/SecureInputView.swift:27 @812da7fa`.
  - This was harmless, since both dimensions are 50.
  - UI-4 (61c4c27a) uses the size correctly (`SecureInputView.swift:34, 73-74`).
- **RB-50: new `SendableMetatypes` warning in `enumArgParsers.swift`.**
  - This warning came from CMD-3 and wasn't in `812da7fa`.
  - R-5 (660b8835) constrains both helpers to `T: SendableMetatype` (`Sources/Common/cmdArgs/enumArgParsers.swift:2, 8`), so the build is warning-free.
- **RB-51: the keep-last-value JSON test couldn't tell first from last.**
  - Original location: `FormatTest.swift:445 @812da7fa`.
  - TS-4 (327dff90) renamed it to `testFormatToJsonRepeatedVariableIsOutputOnce` and added a comment that says what it checks (`Sources/AppBundleTests/command/FormatTest.swift:452-453`).
- **RB-52: the first-failure JSON test didn't check which failure.**
  - Original location: `FormatTest.swift:430 @812da7fa`.
  - TS-4 (327dff90) made the two objects fail differently (a workspace and a monitor) and asserts the workspace's exact error (`FormatTest.swift:439-451`).
- **RB-53: `LayoutCommandTest` `…_fails` tests asserted success.**
  - Original location: `LayoutCommandTest.swift:197, 230, 250, 448 @812da7fa`.
  - TS-4 (327dff90) renamed them to `…_isNoop`, and all four assert the "Tip: use --fail-if-noop" message on stderr (`Sources/AppBundleTests/command/LayoutCommandTest.swift:197, 231, 252, 450`).
- **RB-54: duplicate and misnamed config tests.**
  - Original location: `ConfigTest.swift:660, 680 @812da7fa`.
  - TS-4 (327dff90) renamed the `:680` test to `testMissingValueIsSyntaxErrorThatPreventsReload` and pinned its message. It also made the `:660` test use `ConfigVersion.max` (`Sources/AppBundleTests/config/ConfigTest.swift:660-685`).
  - The overlap with the tests at `:42` and `:57` was kept on purpose so that the test count doesn't drop.
- **RB-55: expected and actual were swapped.**
  - Original location: `ConfigTest.swift:318, 322` and `TreeNodeTest.swift:57` `@812da7fa`.
  - Fixed in TS-4 (327dff90). The current locations are `ConfigTest.swift:318, 322` and `TreeNodeTest.swift:60-63`.
- **RB-56: stale test comments.**
  - Original location: `MoveNodeToWorkspaceCommandTest.swift:150` and `WorkspaceCommandTest.swift:157` `@812da7fa`.
  - Fixed in TS-4 (327dff90). The current locations are `MoveNodeToWorkspaceCommandTest.swift:150` and `WorkspaceCommandTest.swift:154`.
- **RB-57: the `ListAppsTest` assertion couldn't fail.**
  - Original location: `ListAppsTest.swift:7-10 @812da7fa`.
  - TS-4 (327dff90) checks `cmdOrNil` instead (`Sources/AppBundleTests/command/ListAppsTest.swift:9-12`).
- **RB-58: the latch tests didn't check that awaiters were suspended.**
  - Original location: `AwaitableOneTimeBroadcastLatchTest.swift:16, 21 @812da7fa`.
  - TS-4 (327dff90) counts the awaiters that have returned. The count must be 0 before the signal and N after it (`Sources/AppBundleTests/AwaitableOneTimeBroadcastLatchTest.swift:16-46`).
- **RB-60: `msg.contains("workspace")` was nearly vacuous.**
  - Original location: `FormatTest.swift:305 @812da7fa`.
  - TS-4 (327dff90) matches the `workspace` entry on a line of its own (`FormatTest.swift:305`).
- **RB-62: `BalanceSizesCommandTest` could pass vacuously.**
  - Original location: `BalanceSizesCommandTest.swift:21 @812da7fa`.
  - TS-4 (327dff90) asserts the child count first (`Sources/AppBundleTests/command/BalanceSizesCommandTest.swift:21`).
- **RB-63: `testParseCommandFail` crashed on a help result.**
  - Original location: `testUtil.swift:60 @812da7fa`.
  - TS-1 (672a05ff) records a test failure instead (`Sources/AppBundleTests/testUtil.swift:84`).
- **RB-65: `ListWindowsTest.testFormat` created duplicate window ids.**
  - Original location: `ListWindowsTest.swift:51 @812da7fa`.
  - TS-4 (327dff90) uses a fresh id for every window (`Sources/AppBundleTests/command/ListWindowsTest.swift:54-71`).

Two entries are only partly resolved:
- **RB-25:** TS-3 (f7e5b183) fixed the test half. The production half is still open.
- **RB-61** and **RB-64:** the parts that are still open are listed in the [Test suite](#test-suite) section.

## Dropped entries

- **"`list-windows` turns a transient title-fetch error into a bug prompt"**
  - Sources: the commands bug log and the commands plan (B-14). It pointed at `Sources/AppBundle/command/impl/ListWindowsCommand.swift:48`, `EchoCommand.swift:11` and `TestCommand.swift:14` (`@812da7fa`).
  - Why it was dropped: the title is fetched with `.nonCancellable`, so `getTitle` can't throw.
    - `runInLoop` skips the cancellation check for non-cancellable jobs.
    - A throwing body would `die()` rather than throw.
    - A missing window returns nil, which becomes `""`.

    So the `try?`/`bugPrompt` branch can't be reached.
- **RB-59: "The memory-leak test checks nothing"** (`Sources/AppBundleTests/tree/TreeNodeTest.swift:8 @812da7fa`; test plan B22). This is a false positive.
  - `TreeNode.parent` is `weak` (`Sources/AppBundle/tree/TreeNode.swift:10`).
  - After the root container is unbound from the workspace, nothing else holds it. So `window.parent == nil` can only be true if the root was deallocated, which means the test does detect a retain cycle.
  - TS-4 added a comment that explains this (`TreeNodeTest.swift:14`).
- **RB-66: "`ClientServerTest` copies are no-ops"** (`Sources/AppBundleTests/model/ClientServerTest.swift:11, 21 @812da7fa`; test plan B21). This is a false positive.
  - `ClientRequest.windowId` and `ClientRequest.workspace` are double optionals (`Sources/Common/model/clientServer.swift:32-33`).
  - The init stores `.some(windowId)`, so passing `nil` produces an explicit JSON null.
  - `.copy(\.windowId, nil)` instead sets the outer optional to nil, which is what decoding a request without the key produces. So the copies matter.
  - TS-4 added a comment that explains this.
