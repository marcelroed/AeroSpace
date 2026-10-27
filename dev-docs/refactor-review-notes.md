# Refactor review notes: suspected bugs

These are the suspected bugs found while refactoring on branch `refactor-cleanup`. The branch starts from base `812da7fa` (2026-10-26).

The refactor was meant to preserve behavior, so it fixed none of the production bugs below. Some problems were fixed along the way: several test-suite problems, one build warning and one wrong test expectation. They are listed under [Resolved by the refactor](#resolved-by-the-refactor).

The entries were then worked through on branch `fix-review-bugs`, which starts from `refactor-cleanup` at `4a4ab116`. Each fix is a separate commit, so it can be sent upstream on its own. The **Status** line of every entry says the outcome:
- **Fixed in `<commit>`:** the bug was confirmed and fixed. The status names the regression test, which fails without the fix, or says why there is none and how the fix was verified.
- **Closed:** not a bug, unreachable or intended. The status gives the reason.
- **Needs decision:** a real problem whose fix changes user-visible behavior. The status lists the options and a recommendation.
- **Open:** found while fixing the other entries (RB-71 to RB-92) or on `simplify` (RB-93 and up), and not worked on yet.

An independent reviewer checked every fix: that the regression test fails with the production change reverted, that the fix handles the paths the entry describes, and that it changes nothing else. Problems found in review were fixed in follow-up commits, which the status lists too.

Branch `integrate` merges three branches into `9897aeed`: `simplify` (behavior-preserving refactors), `perf` (6 performance commits) and `fix-review-bugs`. Entries RB-93 and up were found on `simplify`, which logged its suspected bugs at about `9897aeed`. Each one was checked against `integrate` at `99679420`. The bug list of the `perf` stream wasn't available, so no entries come from it. These `simplify` items got no ID, because they duplicate an entry, were already fixed or aren't bugs:
- The order of the conflicting flags in `ConfigCmdArgs`: RB-13.
- The dead `Bool` and `UInt32` arms in `dumpAxRecursive`: removed by 69998dd6, which also documents that AX booleans are dumped as 0 and 1.
- `OrderedJson.encode` writes a dict as an array of keys and values: fixed by 697113b6.
- The unused `ClientRequest.command`, documented as kept for old servers: removed by fb7c811a.
- Without screens, `MonitorInfo.activeWorkspace` re-enters the `_focus` initializer: fixed by b072e731 (RB-01).
- Dying recurses when `/tmp/bobko.aerospace` isn't writable: RB-06.
- `initConnection` ignores `.cancelled`: RB-46.
- `format.sh` formats nothing inside a `.claude/worktrees` worktree: fixed by 9897aeed.
- The `move-workspace-to-display` alias skips validation: RB-12.
- `list-windows --count` counts before the `isBound` filter: not a bug. Every counted window is bound; the filter only drops windows that close while the titles are fetched, and `--count` fetches none.
- The `subscribe` `advanceBy` after a duplicate event: RB-14.
- `--wrapAround` and `(prev|next)` in the error texts: RB-17, which covers both.
- `ConfigCommandTest` compares the output with the function that produced it: `shellOfCommandsDescription` is now pinned to literals by `ConfigCharacterizationTest` (91d1dcb1) and `ExecCommandTest` (36920fc3).
- `testParseCommandHelp` doesn't check the help text: `SubcommandHelpTest` (7b660b61) pins every help text.
- `layout` doesn't accept `--`: not a bug. Only commands with a free-form positional argument accept `--`, and the `layout` synopsis doesn't list it.
- The `debug-windows` abort count and the entry logged after the abort: RB-34.
- `Int32ExitCode.succ` is 2: RB-05.
- The unrecognized-flag error names the wrong flag: RB-26.
- The expected type in the `exec.env-vars` error: RB-23.
- The termination helpers can block forever: RB-02 and RB-76.
- `.prohibited` prints with a leading space: RB-28.
- "Rached": RB-18.

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
- Entries RB-71 and up give a single **Location**. For a fixed entry, it is on `fix-review-bugs`, before the fix.
- Open entries give their **Location** at `integrate` `99679420`.
- RB-19 and RB-67 also have an **At integrate** line, because `simplify` rewrote the code they point at.

**IDs are stable.** A gap in the summary table is an entry that moved to [Resolved by the refactor](#resolved-by-the-refactor) or [Dropped entries](#dropped-entries).

## Summary

| ID | Severity | Confidence | Area | Title | Status |
|----|----------|------------|------|-------|--------|
| [RB-01](#rb-01-with-no-screens-monitorapproximation-crashes-and-mainmonitorinfo-returns-a-fake-monitor) | high | possible | Core model | With no screens, `monitorApproximation` crashes and `mainMonitorInfo` returns a fake monitor | fixed |
| [RB-02](#rb-02-termination-helpers-can-block-the-main-thread-forever) | high | possible | Core model | Termination helpers can block the main thread forever | fixed |
| [RB-03](#rb-03-reading-a-special-container-creates-it-and-makes-it-the-most-recent-child) | medium | likely | Core model | Reading a special container creates it and makes it the most-recent child | fixed |
| [RB-04](#rb-04-config-auto-reload-stops-after-an-atomic-save-with-a-syntax-error) | medium | likely | Config, shell and UI | Config auto-reload stops after an atomic save with a syntax error | fixed |
| [RB-05](#rb-05-int32exitcodesucc-is-2) | medium | likely | Commands and CLI | `Int32ExitCode.succ` is 2 | fixed |
| [RB-06](#rb-06-dying-recurses-forever-when-tmpbobkoaerospace-isnt-writable) | medium | likely | Shared utilities | Dying recurses forever when `/tmp/bobko.aerospace` isn't writable | fixed |
| [RB-71](#rb-71-a-die-on-an-ax-thread-deadlocks-termination) | medium | likely | Core model | A die on an AX thread deadlocks termination | fixed |
| [RB-07](#rb-07-ax-size-and-position-getters-crash-on-unexpected-values-and-can-deadlock-on-quit) | medium | possible | Shared utilities | AX size and position getters crash on unexpected values and can deadlock on quit | fixed |
| [RB-08](#rb-08-readbytes-busy-loops-when-the-peer-closes-early) | medium | possible | Shared utilities | `read(bytes:)` busy-loops when the peer closes early | closed |
| [RB-09](#rb-09-on-quit-windows-are-centered-without-the-monitors-origin) | medium | possible | Shared utilities | On quit, windows are centered without the monitor's origin | fixed |
| [RB-10](#rb-10-config-reload-crashes-if-librarylaunchagents-cant-be-created) | medium | possible | Config, shell and UI | Config reload crashes if `~/Library/LaunchAgents` can't be created | fixed |
| [RB-108](#rb-108-swap---wrap-around-on-a-floating-window-swaps-it-into-the-tiling-tree) | medium | possible | Commands and CLI | `swap --wrap-around` on a floating window swaps it into the tiling tree | open |
| [RB-11](#rb-11-test-not---help-prints-the-test-usage) | low | likely | Commands and CLI | `test-not --help` prints the `test` usage | fixed |
| [RB-12](#rb-12-the-move-workspace-to-display-alias-skips-post-parse-validation) | low | likely | Commands and CLI | The `move-workspace-to-display` alias skips post-parse validation | fixed |
| [RB-13](#rb-13-output-and-error-order-depends-on-dictionary-and-set-iteration) | low | likely | Commands and CLI | Output and error order depends on Dictionary and Set iteration | fixed |
| [RB-14](#rb-14-subscribe-adds-a-bogus-error-after-a-duplicate-event) | low | likely | Commands and CLI | `subscribe` adds a bogus error after a duplicate event | fixed |
| [RB-15](#rb-15-exec-and-forget-description-has-a-double-space) | low | likely | Commands and CLI | `exec-and-forget` description has a double space | fixed |
| [RB-16](#rb-16-post-parse-validation-errors-lack-the-error-prefix) | low | likely | Commands and CLI | Post-parse validation errors lack the `ERROR:` prefix | fixed |
| [RB-17](#rb-17-error-text-names---wraparound-instead-of---wrap-around) | low | likely | Commands and CLI | Error text names `--wrapAround` instead of `--wrap-around` | fixed |
| [RB-18](#rb-18-rached-typo-and-inconsistent---fail-if-noop-tip-wording) | low | likely | Commands and CLI | "Rached" typo and inconsistent `--fail-if-noop` tip wording | fixed |
| [RB-19](#rb-19-config---get----keys-error-shows-string) | low | likely | Commands and CLI | `config --get … --keys` error shows `string("…")` | fixed |
| [RB-67](#rb-67-resize-fails-silently-when-the-window-is-its-parents-only-tiling-child) | low | likely | Commands and CLI | `resize` fails silently when the window is its parent's only tiling child | fixed |
| [RB-20](#rb-20-dragging-a-floating-window-rebinds-it-on-every-mouse-event) | low | likely | Core model | Dragging a floating window rebinds it on every mouse event | fixed |
| [RB-21](#rb-21-crash-messages-print-the-type-name-instead-of-the-node) | low | likely | Core model | Crash messages print the type name instead of the node | fixed |
| [RB-22](#rb-22-the-splitflatten-conflict-error-says-disabled-instead-of-enabled) | low | likely | Config, shell and UI | The split/flatten conflict error says "disabled" instead of "enabled" | fixed |
| [RB-23](#rb-23-wrong-expected-type-in-the-execenv-vars-error) | low | likely | Config, shell and UI | Wrong expected type in the `exec.env-vars` error | fixed |
| [RB-24](#rb-24-the-shell-parser-rejects-input-that-is-only-newlines-or-comments) | low | likely | Config, shell and UI | The shell parser rejects input that is only newlines or comments | fixed |
| [RB-25](#rb-25-finding-the-project-root-loops-forever-without-a-git-directory) | low | likely | Config, shell and UI | Finding the project root loops forever without a `.git` directory | fixed |
| [RB-26](#rb-26-the-unrecognized-flag-error-names-the-wrong-flag) | low | likely | Shared utilities | The unrecognized-flag error names the wrong flag | fixed |
| [RB-27](#rb-27-interceptterminationsigkill-does-nothing) | low | likely | Shared utilities | `interceptTermination(SIGKILL)` does nothing | fixed |
| [RB-28](#rb-28-activationpolicyprohibited-prints-with-a-leading-space) | low | likely | Shared utilities | `ActivationPolicy.prohibited` prints with a leading space | fixed |
| [RB-29](#rb-29-jointruncating-adds-an-ellipsis-when-nothing-was-cut) | low | likely | Shared utilities | `joinTruncating` adds an ellipsis when nothing was cut | fixed |
| [RB-30](#rb-30-kaxtrustedcheckoptionprompt-is-taken-as-retained) | low | likely | Shared utilities | `kAXTrustedCheckOptionPrompt` is taken as retained | fixed |
| [RB-72](#rb-72-resize-blames-floating-windows-when-a-tiled-window-has-no-ancestor-of-the-right-orientation) | low | likely | Commands and CLI | `resize` blames floating windows when a tiled window has no ancestor of the right orientation | fixed |
| [RB-77](#rb-77-an-empty-root-container-stays-the-most-recent-child-after-the-last-tiling-window-closes) | low | likely | Core model | An empty root container stays the most recent child after the last tiling window closes | open |
| [RB-89](#rb-89-config-errors-for-binding-commands-show-the-error-prefix-twice) | low | likely | Config, shell and UI | Config errors for binding commands show the `ERROR:` prefix twice | open |
| [RB-96](#rb-96-config-errors-with-several-expected-types-print-lowercase-type-names) | low | likely | Config, shell and UI | Config errors with several expected types print lowercase type names | open |
| [RB-97](#rb-97-an-invalid-key-notation-is-reported-at-the-tables-path) | low | likely | Config, shell and UI | An invalid key notation is reported at the table's path | open |
| [RB-103](#rb-103-clean-xcodesh-deletes-paths-that-moved-to-xcode) | low | likely | Scripts | `clean-xcode.sh` deletes paths that moved to `xcode/` | open |
| [RB-109](#rb-109-typo-in-the-layout-error-for-minimized-fullscreen-and-hidden-app-windows) | low | likely | Commands and CLI | Typo in the `layout` error for minimized, fullscreen and hidden-app windows | open |
| [RB-31](#rb-31-workspace-back-and-forth-ignores-whether-focusing-succeeded) | low | possible | Commands and CLI | `workspace-back-and-forth` ignores whether focusing succeeded | fixed |
| [RB-32](#rb-32-run-callback---for-every-window-differs-from-real-window-detection) | low | possible | Commands and CLI | `run-callback --for-every-window` differs from real window detection | fixed |
| [RB-33](#rb-33-resize-accepts-doubled-signs) | low | possible | Commands and CLI | `resize` accepts doubled signs | fixed |
| [RB-34](#rb-34-debug-windows-state-machine-quirks) | low | possible | Commands and CLI | `debug-windows` state machine quirks | fixed |
| [RB-35](#rb-35-the-window-level-cache-misses-on-every-lookup-for-off-screen-windows) | low | possible | Core model | The window-level cache misses on every lookup for off-screen windows | fixed |
| [RB-36](#rb-36-virtual-rects-shrink-by-inner-gaps-in-nested-containers) | low | possible | Core model | Virtual rects shrink by inner gaps in nested containers | fixed |
| [RB-37](#rb-37-tray-symbols-for-workspace-names-that-only-look-like-numbers) | low | possible | Config, shell and UI | Tray symbols for workspace names that only look like numbers | fixed |
| [RB-38](#rb-38-open-config-and-reload-use-the-wrong-file-if-the---config-path-file-is-deleted) | low | possible | Config, shell and UI | "Open config" and reload use the wrong file if the `--config-path` file is deleted | fixed |
| [RB-39](#rb-39-the-debug-build-signal-handler-isnt-async-signal-safe) | low | possible | Shared utilities | The debug-build signal handler isn't async-signal-safe | fixed |
| [RB-73](#rb-73-the-shell-parser-rejects-a-newline-right-after-an-opening-parenthesis) | low | possible | Config, shell and UI | The shell parser rejects a newline right after an opening parenthesis | fixed |
| [RB-74](#rb-74-focus-dfs-next-and-dfs-prev-fail-silently) | low | possible | Commands and CLI | `focus dfs-next` and `dfs-prev` fail silently | fixed |
| [RB-75](#rb-75-the-config-watcher-isnt-armed-after-the-config-fails-to-parse-at-startup) | low | possible | Config, shell and UI | The config watcher isn't armed after the config fails to parse at startup | open |
| [RB-76](#rb-76-termination-helpers-still-wait-without-a-bound) | low | possible | Core model | Termination helpers still wait without a bound | needs decision |
| [RB-80](#rb-80-exec-and-forget-with-leading-whitespace-is-an-unknown-command) | low | possible | Commands and CLI | `exec-and-forget` with leading whitespace is an unknown command | open |
| [RB-84](#rb-84-the-main-axis-of-virtual-rects-uses-the-physical-size) | low | possible | Core model | The main axis of virtual rects uses the physical size | open |
| [RB-85](#rb-85-a-window-first-seen-off-screen-is-classified-as-a-popup) | low | possible | Core model | A window first seen off-screen is classified as a popup | open |
| [RB-88](#rb-88-a-monitor-that-disappears-briefly-loses-its-visible-workspace) | low | possible | Core model | A monitor that disappears briefly loses its visible workspace | open |
| [RB-90](#rb-90-parse-errors-with-an-explicit-exit-code-have-no-error-prefix) | low | possible | Commands and CLI | Parse errors with an explicit exit code have no `ERROR:` prefix | open |
| [RB-91](#rb-91-the-list-windows-order-depends-on-the-format) | low | possible | Commands and CLI | The `list-windows` order depends on the format | open |
| [RB-92](#rb-92-workspace-names-that-differ-only-in-leading-zeros-have-no-stable-order) | low | possible | Core model | Workspace names that differ only in leading zeros have no stable order | fixed |
| [RB-93](#rb-93-focus-follows-mouse-can-stop-scanning-the-floating-windows-early) | low | possible | Core model | Focus follows mouse can stop scanning the floating windows early | open |
| [RB-100](#rb-100-a-wrong-type-if-also-reports-that-if-was-omitted) | low | possible | Config, shell and UI | A wrong-type `if` also reports that `if` was omitted | open |
| [RB-101](#rb-101-a-binding-whose-command-fails-to-parse-stays-bound-and-does-nothing) | low | possible | Config, shell and UI | A binding whose command fails to parse stays bound and does nothing | open |
| [RB-104](#rb-104-slicen-traps-instead-of-returning-nil-when-n-is-past-the-end) | low | possible | Shared utilities | `slice(n...)` traps instead of returning nil when `n` is past the end | open |
| [RB-111](#rb-111-test-rejects-an-empty-right-hand-side) | low | possible | Commands and CLI | `test` rejects an empty right-hand side | open |
| [RB-40](#rb-40-inconsistent-reporting-of-impossible-paths) | low | speculative | Commands and CLI | Inconsistent reporting of "impossible" paths | fixed |
| [RB-41](#rb-41-workspace-gc-evaluates-focus-inside-its-filter) | low | speculative | Core model | Workspace GC evaluates `focus` inside its filter | fixed |
| [RB-42](#rb-42-hotkey-events-can-report-another-modes-key-notation) | low | speculative | Config, shell and UI | Hotkey events can report another mode's key notation | fixed |
| [RB-43](#rb-43-on-window-detected-warnings-are-dropped-when-there-are-no-errors) | low | speculative | Config, shell and UI | `on-window-detected` warnings are dropped when there are no errors | closed |
| [RB-44](#rb-44-implicit-persistent-workspace-order-depends-on-dictionary-iteration) | low | speculative | Config, shell and UI | Implicit persistent-workspace order depends on Dictionary iteration | closed |
| [RB-68](#rb-68-toml-syntax-errors-are-reported-verbatim-from-tomlkit) | low | speculative | Config, shell and UI | TOML syntax errors are reported verbatim from TOMLKit | closed |
| [RB-45](#rb-45-unchecked-as-axuielement-casts) | low | speculative | Shared utilities | Unchecked `as! AXUIElement` casts | fixed |
| [RB-46](#rb-46-initconnection-hangs-if-the-connection-is-cancelled-before-it-is-ready) | low | speculative | Shared utilities | `initConnection` hangs if the connection is cancelled before it is ready | fixed |
| [RB-47](#rb-47-bugprompt-reads-nsscreen-from-whatever-thread-is-dying) | low | speculative | Shared utilities | `bugPrompt` reads `NSScreen` from whatever thread is dying | fixed |
| [RB-48](#rb-48-topaddingtable-mixes-character-and-utf-16-counts) | low | speculative | Shared utilities | `toPaddingTable` mixes Character and UTF-16 counts | fixed |
| [RB-49](#rb-49-transposed-assumes-a-rectangular-table) | low | speculative | Shared utilities | `transposed()` assumes a rectangular table | fixed |
| [RB-69](#rb-69-isunittest-depends-on-xctest-being-loaded) | low | speculative | Shared utilities | `isUnitTest` depends on XCTest being loaded | fixed |
| [RB-78](#rb-78-debug-windows-stays-recording-after-a-failed-first-dump) | low | speculative | Commands and CLI | `debug-windows` stays recording after a failed first dump | open |
| [RB-79](#rb-79-the-server-writes-an-error-into-a-connection-the-client-closed) | low | speculative | Shared utilities | The server writes an error into a connection the client closed | open |
| [RB-81](#rb-81-subscribe-drops-the-duplicate-event-error-when-an-unknown-event-follows) | low | speculative | Commands and CLI | `subscribe` drops the duplicate-event error when an unknown event follows | open |
| [RB-82](#rb-82-the-workspace-back-and-forth-docs-say-it-always-succeeds) | low | speculative | Commands and CLI | The `workspace-back-and-forth` docs say it always succeeds | fixed |
| [RB-86](#rb-86-getorregister-can-bind-a-new-window-into-a-workspace-that-was-garbage-collected) | low | speculative | Core model | `getOrRegister` can bind a new window into a workspace that was garbage-collected | open |
| [RB-87](#rb-87-dragging-can-make-a-window-floating-again-after-it-became-tiling) | low | speculative | Core model | Dragging can make a window floating again after it became tiling | open |
| [RB-95](#rb-95-subscribe-works-while-the-server-is-disabled) | low | speculative | Shared utilities | `subscribe` works while the server is disabled | open |
| [RB-98](#rb-98-config-error-paths-dont-quote-keys-with-dots-or-spaces) | low | speculative | Config, shell and UI | Config error paths don't quote keys with dots or spaces | open |
| [RB-99](#rb-99-the-on-window-detected-debug-json-omits-check-further-callbacks-and-doesnt-escape-values) | low | speculative | Config, shell and UI | The `on-window-detected` debug JSON omits `check-further-callbacks` and doesn't escape values | open |
| [RB-105](#rb-105-the-accessibility-reset-script-uses-the-wrong-case-in-the-bundle-id) | low | speculative | Scripts | The accessibility reset script uses the wrong case in the bundle ID | open |
| [RB-106](#rb-106-setupsh-rejects-bash-6-and-later) | low | speculative | Scripts | `setup.sh` rejects bash 6 and later | open |
| [RB-107](#rb-107-the-generated-command-help-doesnt-escape-the-docs-text) | low | speculative | Scripts | The generated command help doesn't escape the docs text | open |
| [RB-110](#rb-110-debug-windows-can-log-a-window-after-its-session-ended) | low | speculative | Commands and CLI | `debug-windows` can log a window after its session ended | open |
| [RB-112](#rb-112-the-initial-focused-workspace-changed-event-names-the-current-workspace-as-the-previous-one) | low | speculative | Commands and CLI | The initial `focused-workspace-changed` event names the current workspace as the previous one | open |
| [RB-61](#rb-61-tests-cant-reset-two-private-focus-globals) | low | possible | Tests | Tests can't reset two private focus globals | fixed |
| [RB-64](#rb-64-all-ax-dumps-run-in-one-test-that-crashes-on-a-malformed-dump) | low | possible | Tests | All AX dumps run in one test that crashes on a malformed dump | fixed |
| [RB-70](#rb-70-testservereventdecoding-checks-only-the-event-type) | low | possible | Tests | `testServerEventDecoding` checks only the event type | fixed |
| [RB-83](#rb-83-converting-a-test-ax-dump-can-still-crash-the-test-run) | low | speculative | Tests | Converting a test AX dump can still crash the test run | fixed |
| [RB-94](#rb-94-newscalarornil-reads-json-booleans-as-integers) | low | speculative | Tests | `newScalarOrNil` reads JSON booleans as integers | open |
| [RB-102](#rb-102-syncfocusfrommacos-crashes-on-test-windows) | low | speculative | Tests | `syncFocusFromMacOs` crashes on test windows | open |

**Totals:** 55 entries were open before `fix-review-bugs`: 2 high, 8 medium and 45 low. Of these, 51 fixed and 4 closed. The fixes turned up 22 new entries (RB-71 to RB-92; 1 medium and 21 low): 7 fixed, 1 needs decision and 14 open. A further 18 entries were resolved by the refactor, and 3 were dropped. The `simplify` stream added 20 entries (RB-93 to RB-112; 1 medium and 19 low), all open.

## Core model

### RB-01: With no screens, `monitorApproximation` crashes and `mainMonitorInfo` returns a fake monitor

- **Status:** Fixed in d39e1278, with follow-ups c9207efc, b072e731, cbc19651, 436c5da0, 106ed563, 7127e77c, e60908ed, 52a6c618, 4304f1d0 and 41e22f0c. While there are no screens:
  - `monitorApproximation` falls back to the main monitor instead of dying, and the visible-workspace arrangement is kept.
  - Heavy refresh sessions, the layout and hiding windows in corners are skipped. The layout and `refresh()` check again after their suspension points, so the window GC (and with it the closed-windows cache) and window registration don't run against the fake monitor.
  - Light sessions don't move workspaces between monitors and don't fire focus callbacks. `summon-workspace` and `enable off` fail with a message, and nothing is laid out while AeroSpace is disabled.
  - Startup waits for the screens.

  Regression tests: `NoScreensTest`, `WorkspaceBackAndForthCommandTest.testFailsWhenFocusingPrevWorkspaceFails` and the no-screens tests of RB-40, which use the `noScreensForTests` task-local. The paths where the screens vanish during an await have no test, because a task-local can't simulate that; they were verified by reading the code.

  Remaining gaps:
  - The screens can still vanish during an await after the last check, for example while windows are registered or laid out. Those races are narrower now, but not closed.
  - If the screens vanish between the check in `enable off` and its layout, AeroSpace is disabled while the windows of hidden workspaces stay in the corners. They keep their remembered positions, and the next `enable off` with screens, or `enable on`, restores them.
  - If the screens vanish again between the startup wait and the startup session, that session is still skipped.
  - A monitor that disappears only briefly still loses its visible workspace: see RB-88.
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

- **Status:** Fixed in 2afad54e. No regression test: the helpers block on a real app's AX thread. Verified by reading every path of the new job (window missing, body throws). Unbounded waits for a hung app remain: see RB-76.
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

- **Status:** Fixed in a9c1685f. Regression tests in `TreeNodeTest`. The empty root container can still become the most recent child in another way: see RB-77.
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

- **Status:** Fixed in d80a7106. Regression tests in `MoveWithMouseTest`. A related race is RB-87.
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

- **Status:** Fixed in 98016063. No regression test: the messages are only printed when AeroSpace dies. Verified by reading every changed message.
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

- **Status:** Fixed in c2c0fe59 and reworked in 4f530915. After one query in a refresh session, a known window that is missing from the cache is taken as off-screen without another query. The cache is kept across sessions, as before, so an on-screen popup such as a browser picture-in-picture window costs no query. No regression test: the query is the real `CGWindowListCopyWindowInfo`, and known windows must be real `MacWindow`s. Verified by reading every lookup sequence: unless the set of on-screen windows changes during a session, it never queries more than the original code. If the set does change, it can make one more query, which returns fresher data. A cached level is still refreshed only when a miss causes a query, as in the original code. A related case is RB-85.
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/AppBundle/windowLevelCache.swift:8-26 @812da7fa`
- **Current location:** `Sources/AppBundle/windowLevelCache.swift:8-26`. Unchanged.
- **Description:** On a miss, `getWindowLevel` queries `CGWindowListCopyWindowInfo` with `.optionOnScreenOnly`, then replaces the whole cache with the result. Off-screen windows never appear in that result: minimized windows, windows of hidden apps, and windows on other Spaces. So every lookup for one of them repeats the full query. A window whose level changes keeps its stale cached level until some other miss replaces the cache.
- **How it shows up:** extra CPU work during refresh when many windows are off-screen. Rarely, a window has the wrong level, which affects how it is classified.
- **Fix direction:** cache negative results for the duration of a refresh, and invalidate the cache once per refresh instead of on misses.

### RB-36: Virtual rects shrink by inner gaps in nested containers

- **Status:** Fixed in 84ce3fb9. The `LayoutTest` expectations that pinned the bug now expect the full cross-axis size. The main axis has a similar problem: see RB-84.
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/AppBundle/layout/layoutRecursive.swift:126-137 @812da7fa` (virtual rect at 130-135; the `height - 1` workaround at `:11`)
- **Current location:** `Sources/AppBundle/layout/layoutRecursive.swift:121-133` (virtual rect at 128-133; `height - 1` at `:12`). Unchanged.
- **Description:** Virtual rects are documented as the layout "as if inner gaps were always zero". In `layoutTiles`, though, the cross-axis size of a child's virtual rect is the physical `width` or `height`, not the parent's virtual size. The physical size has already been reduced by inner gaps and by the `height - 1` workaround.
- **How it shows up:** in nested containers, virtual rects are a few pixels too small. For example, a v-container with virtual width 1250 gives its children a virtual width of 1240. This affects resize-with-mouse and floating-as-tiling focus decisions by a few pixels.
- **Fix direction:** use `virtual.width` or `virtual.height` for the cross axis.

### RB-41: Workspace GC evaluates `focus` inside its filter

- **Status:** Fixed in 8717ff8c: unused workspaces are removed in place. Hoisting `focus` out of the filter would have initialized it before the first `focusWorkspace()` at startup. No regression test: verified by reading the code.
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/AppBundle/tree/Workspace.swift:84-94 @812da7fa`
- **Current location:** `Sources/AppBundle/tree/Workspace.swift:81-91`. Unchanged. The CM-11 plan was to hoist `focus` out of the filter, but only the `setFocus` part of CM-11 landed.
- **Description:** `garbageCollectUnusedWorkspaces` reads `focus` inside the `filter` closure over `workspaceNameToWorkspace`. `focus` goes through `FrozenFocus.live`, which calls `Workspace.get(byName:)`, and that can insert a new workspace into the same dictionary. The insertion is lost when the filtered copy is assigned back.
- **How it shows up:** in theory, two `Workspace` objects end up with the same name, which trips the `check` in `Workspace.==` (`:94`). This has not been observed.
- **Fix direction:** read `focus.workspace.name` once, before the filter.

### RB-71: A die on an AX thread deadlocks termination

- **Status:** Fixed in f91a5d30: `dieT` records the dying thread first, and the termination helpers skip it. No regression test: needs a real AX thread that dies during termination. Verified by reading the termination paths. The remaining unbounded waits are RB-76.
- **Severity:** medium · **Confidence:** likely
- **Location:** `Sources/AppBundle/tree/MacApp.swift:159-195` and `dieT` in `Sources/Common/util/commonUtil.swift`
- **Description:** A die on an app's AX thread blocks that thread in `MainActor.runSync` while the main thread runs `beforeTermination`. That schedules `getAxRect` and `setFrame` jobs on the same AX thread and waits for them forever.
- **How it shows up:** AeroSpace freezes instead of crashing, so there is no crash report and the windows aren't restored.
- **Fix direction:** have `dieT` record the dying thread so the helpers skip it, or use timed waits on termination paths.

### RB-76: Termination helpers still wait without a bound

- **Status:** Needs decision: whether to use timed waits on termination paths, and how long. Options: (a) keep the unbounded waits; (b) wait about 1–2 s per app and skip the rest of an app's windows after its first timeout; (c) one overall deadline for restoring all windows. Recommendation: (b), together with RB-02's "consider a timed wait". A timeout means some windows of a hung app stay where AeroSpace hid them.
- **Severity:** low · **Confidence:** possible
- **Location:** `Sources/AppBundle/tree/MacApp.swift:159-195`
- **Description:** After RB-02 and RB-71, the termination helpers still wait forever if the target AX thread starts dying after main has scheduled the job (a die inside the termination job, or a second thread dying at the same time). For a hung app they wait for about 9 AX calls × 6 s per window.
- **How it shows up:** AeroSpace freezes on quit or on a crash instead of exiting.
- **Fix direction:** timed waits in `setAxFrameForTermination` and `getAxRectForTermination`.

### RB-77: An empty root container stays the most recent child after the last tiling window closes

- **Status:** Open.
- **Severity:** low · **Confidence:** likely
- **Location:** `Sources/AppBundle/focus.swift:86-88`, the `todo` in `toLiveFocus`
- **Description:** After a workspace's last tiling window closes, its empty root tiling container stays the workspace's most recent child. `toLiveFocus()` then picks the first floating or unconventional window, not the last focused one. The existing `todo` describes this; RB-03 only removed the "created on read" trigger.
- **How it shows up:** close the last tiling window on a workspace with floating windows: focus goes to the first floating window instead of the most recently used one.
- **Fix direction:** skip empty containers in `mostRecentWindowRecursive`, or stop marking the root as most recent when it becomes empty.

### RB-84: The main axis of virtual rects uses the physical size

- **Status:** Open.
- **Severity:** low · **Confidence:** possible
- **Location:** `Sources/AppBundle/layout/layoutRecursive.swift:112-140`
- **Description:** The main axis of virtual rects still uses weights normalized to the physical main size. With same-orientation nesting (h in v in h, inner gap 20), the children's virtual rects end 10 px before the container's virtual edge. In v-containers, the `height - 1` workaround leaves a 1 px gap.
- **How it shows up:** points in the gap match no child in `findWindowRecursively(virtual: true)`, which resize with mouse and floating-as-tiling focus use.
- **Fix direction:** scale the main-axis virtual size by virtual/physical.

### RB-85: A window first seen off-screen is classified as a popup

- **Status:** Open.
- **Severity:** low · **Confidence:** possible
- **Location:** `Sources/AppBundle/model/AxUiElementWindowType.swift:107-111` and `Sources/AppBundle/windowLevelCache.swift:18-41`
- **Description:** The window-level cache holds on-screen windows only. A window first detected while off-screen (minimized at startup, or of a hidden app) gets a nil level. For Slack, Chrome, Firefox, iTerm2 and the other listed apps, `windowLevel != .normalWindow` then holds, so it is classified as a popup.
- **How it shows up:** the window isn't tiled. It is fixed only when it comes on screen and `validateStillPopups` lays it out, on `focus.workspace` rather than its original workspace.
- **Fix direction:** treat an unknown level as unknown rather than as not normal, or query off-screen windows too.

### RB-86: `getOrRegister` can bind a new window into a workspace that was garbage-collected

- **Status:** Open.
- **Severity:** low · **Confidence:** speculative
- **Location:** `Sources/AppBundle/tree/MacWindow.swift:17-28` and `:186-193`
- **Description:** `getOrRegister` reads `focus.workspace` before its AX awaits and binds the new window into it afterwards. If a concurrent light session changed focus and garbage-collected that empty, now invisible workspace in between, the window lands in a workspace that is no longer registered.
- **How it shows up:** the window isn't laid out. A later `Workspace.get(byName:)` creates a duplicate workspace, and the `Workspace.==` check dies.
- **Fix direction:** read `focus.workspace` after the awaits.

### RB-87: Dragging can make a window floating again after it became tiling

- **Status:** Open.
- **Severity:** low · **Confidence:** speculative
- **Location:** `Sources/AppBundle/mouse/moveWithMouse.swift:21-27`
- **Description:** If the window became tiling during the `getCenter` await (for example, `layout tiling` ran in between), `bindAsFloatingWindow` makes it floating again when the target workspace differs. This was already the case before RB-20.
- **How it shows up:** a `layout tiling` that races with a drag is silently undone.
- **Fix direction:** re-check that the window is still floating after the await.

### RB-88: A monitor that disappears briefly loses its visible workspace

- **Status:** Open.
- **Severity:** low · **Confidence:** possible
- **Location:** `Sources/AppBundle/tree/Workspace.swift:182-213` (`rearrangeWorkspacesOnMonitors`)
- **Description:** RB-01 keeps the arrangement while there are no screens at all. When only some screens are missing for a moment, for example while monitors wake one after another, `rearrangeWorkspacesOnMonitors` maps the visible workspaces to the remaining screens and forgets the others. When the missing monitor comes back, it gets a stub workspace.
- **How it shows up:** after waking a multi-monitor setup, a secondary monitor can show a different workspace than before sleep.
- **Fix direction:** remember the visible workspace of a monitor that disappeared, and restore it if a monitor comes back at the same position. Unplugging a monitor takes the same path, so this is a design choice.

### RB-92: Workspace names that differ only in leading zeros have no stable order

- **Status:** Fixed in 5709dac8; 422757f8 compares the names in a single pass, so sorting is no slower than before. Regression test: `ListWorkspacesTest.testRunAll_namesThatDifferOnlyInLeadingZerosAreOrderedByName`.
- **Severity:** low · **Confidence:** possible
- **Location:** `Sources/AppBundle/tree/Workspace.swift:45` (`Workspace.all`) and `:59` (`<`)
- **Description:** Workspaces compare by their logical segments, so "1" and "01" are equal. `Workspace.all` sorts the values of a dictionary, so the order of such workspaces changes from run to run.
- **How it shows up:** `list-workspaces --all` and the order of tied windows in `list-windows` change between runs when two workspace names differ only in leading zeros.
- **Fix direction:** break ties by the name in `<`.

### RB-93: Focus follows mouse can stop scanning the floating windows early

- **Status:** Open.
- **Severity:** low · **Confidence:** possible
- **Location:** `Sources/AppBundle/util/MruStack.swift:28` and `Sources/AppBundle/mouse/focusFollowsMouse.swift:31-39`
- **Description:** Focus follows mouse iterates the live `mruChildren` stack of the floating container and awaits `getAxRect` for each window. `MruStack.remove` sets `next` to nil on the node it unlinks, and raising a window removes it first. If the window that the iterator returns next is raised or unbound during an await, the iterator returns it and then stops.
- **How it shows up:** the floating windows after it are never checked. If the mouse is over one of them, focus follows mouse falls through to the tiling tree and can focus the tiling window behind the floating one.
- **Fix direction:** iterate over a copy, such as `Array(mruChildren)`, or don't clear `next` in `remove`.

## Commands and CLI

### RB-05: `Int32ExitCode.succ` is 2

- **Status:** Fixed in 5749afae. Regression test: `RunCallbackCommandTest.testOnWindowDetectedWithoutCallbacksSucceeds`.
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

- **Status:** Fixed in 99fb52c8. Regression test: `TestCommandTest.testParseHelpPrintsOwnUsage`.
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/Common/cmdArgs/impl/TestNotCmdArgs.swift:15-19 @812da7fa`
- **Current location:** `Sources/Common/cmdArgs/impl/TestNotCmdArgs.swift:15-19`. Unchanged.
- **Description:** `parseTestNotCmdArgs` parses with `TestCmdArgs`. For `--help`, the result is `TestCmdArgs.info.help`, which is `test_help_generated`. `test_not_help_generated` is never shown.
- **How it shows up:** `aerospace test-not --help` prints `USAGE: test …`.
- **Fix direction:** map a `.help` result to `TestNotCmdArgs.info.help`.

### RB-12: The `move-workspace-to-display` alias skips post-parse validation

- **Status:** Fixed in c6ed54b7. Regression test: `MoveWorkspaceToMonitorCommandTest.testParseDeprecatedAliasIsValidatedLikeTheCommand`.
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/Common/cmdArgs/cmdArgsManifest.swift:124 @812da7fa`. The validator is at `Sources/Common/cmdArgs/impl/MoveWorkpsaceToMonitorCmdArgs.swift:21-26`.
- **Current location:** `Sources/Common/cmdArgs/cmdArgsManifest.swift:124`. The validator is `parseMoveWorkspaceToMonitorCmdArgs` at `Sources/Common/cmdArgs/impl/MoveWorkspaceToMonitorCmdArgs.swift:21-26`; the file was renamed to fix its typo. Behavior is unchanged.
- **Description:** The deprecated alias registers `MoveWorkspaceToMonitorCmdArgs.init`. `SubCommandParser(_ raw:)` then runs only `parseSpecificCmdArgs` and skips the validator that the real command uses.
- **How it shows up:** `aerospace move-workspace-to-display --wrap-around 2` is accepted, but `aerospace move-workspace-to-monitor --wrap-around 2` is rejected.
- **Fix direction:** register the alias with `parseMoveWorkspaceToMonitorCmdArgs`.

### RB-13: Output and error order depends on Dictionary and Set iteration

- **Status:** Fixed in f06618d6 and bcf1997d. The keys are sorted before printing, and `list-apps` sorts by app name and then pid. `list-windows` visits the workspaces in `list-workspaces` order, so tied windows are listed by workspace and then in tree order. be4f1289 broke ties by window ID; bcf1997d replaced that, because it changed the already deterministic order within one workspace. Regression tests in `ConfigCommandTest`, `TriggerBindingCommandTest`, `ListExecEnvVarsCommandTest` and `ListWindowsTest`. `list-apps` has no test: it lists the real running apps. Related cases are RB-91 and RB-92.
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

- **Status:** Fixed in 9316d8c5. Regression test: `SubscribeCmdArgsTest.testParseUnknownEventAfterDuplicateEventIsReportedOnce`. A related cosmetic case is RB-81.
- **Severity:** low · **Confidence:** likely (confirmed by running it)
- **Original location:** `Sources/Common/cmdArgs/impl/SubscribeCmdArgs.swift:46 @812da7fa`
- **Current location:** `Sources/Common/cmdArgs/impl/SubscribeCmdArgs.swift:46`. Unchanged.
- **Description:** On a parse failure, the parser returns `advanceBy: events.count + 1`. `events` is the de-duplicated set, not the number of arguments consumed.
- **How it shows up:** `aerospace subscribe focus-changed focus-changed bogus` advances too little, reads `bogus` again, and prints an extra "Unknown argument 'bogus'" error.
- **Fix direction:** count consumed arguments with `enumerated()`.

### RB-15: `exec-and-forget` description has a double space

- **Status:** Fixed in 36920fc3: the description no longer adds a second space, and the name must be followed by whitespace, so `exec-and-forgetfoo` is now an unknown command instead of running `foo`. The script itself keeps its leading whitespace, as documented. Regression tests in `ExecCommandTest`. A related case is RB-80.
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/Common/cmdArgs/parseCmdArgs.swift:56` and `Sources/AppBundle/command/parseCommand.swift:8-9` `@812da7fa`. Pinned by `Sources/AppBundleTests/command/ExecCommandTest.swift:10`.
- **Current location:** same files and lines, including the test. Unchanged.
- **Description:** `parseCommand` keeps the text after `exec-and-forget` untrimmed, so `bashScript` starts with a space, and `description` adds another one. A related, speculative problem: `raw.starts(with: "exec-and-forget")` also matches `exec-and-forgetfoo`.
- **How it shows up:** `aerospace config --get mode.main.binding.<key>` prints `exec-and-forget  open …`, through `shellOfCommandsDescription` (`ConfigCommand.swift:126`).
- **Fix direction:** trim the script once in `parseCommand` and update `ExecCommandTest`. Require a space or the end of input after the command name.

### RB-16: Post-parse validation errors lack the `ERROR:` prefix

- **Status:** Fixed in 4739987d: post-parse validation errors are formatted like the arg-parser errors. The 45 test expectations that pinned the old messages now expect the prefix. Related: errors with an explicit exit code still have no prefix (RB-90), and config errors show the prefix twice (RB-89).
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/Common/cmdArgs/ParsedCmd.swift:29-37 @812da7fa`. `joinErrors` is at `Sources/Common/util/StringEx.swift:26`.
- **Current location:** same lines. Unchanged.
- **Description:** Arg-parser errors are joined with `joinErrors()`, which prefixes each one with `ERROR: `. Post-parse validation failures (`.filter`, `.filterNot`, `.failure(String)`) are printed without the prefix.
- **How it shows up:** `aerospace focus --dfs-index 0 left` prints a bare message, while `aerospace focus foo` prints `ERROR: …`.
- **Fix direction:** format validation failures the same way as parser errors.

### RB-17: Error text names `--wrapAround` instead of `--wrap-around`

- **Status:** Fixed in 92a3297f. Regression tests: `WorkspaceCommandTest.testParseWorkspaceCommand` and `MoveNodeToWorkspaceCommandTest.testParse`.
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/Common/cmdArgs/impl/WorkspaceCmdArgs.swift:32` and `Sources/Common/cmdArgs/impl/MoveNodeToWorkspaceCmdArgs.swift:41` `@812da7fa`. Pinned by `Sources/AppBundleTests/command/WorkspaceCommandTest.swift:18`.
- **Current location:** same production lines. Unchanged. The test is now at `WorkspaceCommandTest.swift:15`.
- **Description:** The messages say "--wrapAround requires using (next|prev) argument", but the flag is `--wrap-around`. Also, the `move-node-to-workspace` message hard-codes `(prev|next)`, while `workspace` uses `NextPrev.unionLiteral`, which is `(next|prev)`.
- **How it shows up:** `aerospace workspace --wrap-around 1` tells the user about a flag that doesn't exist.
- **Fix direction:** use the real flag name and `NextPrev.unionLiteral` in both messages, and update the test.

### RB-18: "Rached" typo and inconsistent `--fail-if-noop` tip wording

- **Status:** Fixed in 15179fca. The tests that pinned the old messages now expect the new ones.
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/command/impl/WorkspaceCommand.swift:67`, `Sources/AppBundle/command/impl/LayoutCommand.swift:47` and `Sources/AppBundle/command/impl/MacosNativeFullscreenCommand.swift:29` `@812da7fa`
- **Current location:** `WorkspaceCommand.swift:62`, `LayoutCommand.swift:44` and `MacosNativeFullscreenCommand.swift:22`. Pinned by `Sources/AppBundleTests/command/MoveNodeToWorkspaceCommandTest.swift:159` and by `Sources/AppBundleTests/command/LayoutCommandTest.swift:205, 238, 257, 459`. TS-4 added the last three when it fixed RB-53. At `812da7fa` only line 255 pinned the wording.
- **Description:** "Rached the beginning of the supplied workspaces list" should say "Reached". Most noop messages end with "Tip: use --fail-if-noop to exit with non-zero code", but `layout` and `macos-native-fullscreen` say "non-zero exit code".
- **How it shows up:** user-visible stderr text.
- **Fix direction:** fix the spelling, pick one wording for the tip, and update both tests.

### RB-19: `config --get … --keys` error shows `string("…")`

- **Status:** Fixed in 9b6ac6d3. Regression test: `ConfigCommandTest.testGetScalar_keys_fails`.
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/command/impl/ConfigCommand.swift:46 @812da7fa`. Pinned by `Sources/AppBundleTests/command/ConfigCommandTest.swift:154`.
- **Current location:** `ConfigCommand.swift:46`. Unchanged. The test is now at `ConfigCommandTest.swift:165`.
- **At integrate:** `simplify` replaced `ConfigMapValue` with `OrderedJson`. The fix is at `Sources/AppBundle/command/impl/ConfigCommand.swift:46`, which prints `scalarDescription` (`:80-88`) in place of `scalar.describe`. The regression test is at `Sources/AppBundleTests/command/ConfigCommandTest.swift:164-173`.
- **Description:** The message interpolates the `ConfigScalarValue` enum directly, which produces Swift's default case representation. Other messages in the same file use `scalar.describe` (`:61`, `:86`).
- **How it shows up:** `aerospace config --get mode.main.binding.alt-h --keys` prints `--keys flag cannot be applied to scalar object 'string("focus left")'`.
- **Fix direction:** use `scalar.describe` and update the test.

### RB-67: `resize` fails silently when the window is its parent's only tiling child

- **Status:** Fixed in 94a0f00d. Regression test: `ResizeCommandTest.testSingleChildParent_failsCleanly`.
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/command/impl/ResizeCommand.swift:47 @812da7fa`. The `orientation` and `node` guards at `:39-40` also return a bare `.fail`.
- **Current location:** `Sources/AppBundle/command/impl/ResizeCommand.swift:34`, with the guards at `:26-27`. Pinned by `testSingleChildParent_failsCleanly` (`Sources/AppBundleTests/command/ResizeCommandTest.swift:157-165`). That test checks the exit code and that the weight is unchanged, but not that a message is printed.
- **At integrate:** `simplify` restructured `ResizeCommand`. The fix is at `Sources/AppBundle/command/impl/ResizeCommand.swift:42-44`. The `orientation` and `node` guards became one guard at `:24-35`, which also holds the RB-72 message. The regression test is at `Sources/AppBundleTests/command/ResizeCommandTest.swift:167-174`, and it asserts the message too.
- **Description:** if the target node is the only child of its tiling parent, `diff.div(parent.children.count - 1)` returns nil. The command then returns a bare `.fail`, which means exit code 2 and nothing on stderr.
- **How it shows up:** in a workspace with a single tiled window, `aerospace resize width +50` exits with code 2 and doesn't say why.
- **Fix direction:** print a message, for example that the window has no siblings to take space from, and assert it in the test.

### RB-31: `workspace-back-and-forth` ignores whether focusing succeeded

- **Status:** Fixed in 212dd3a3: the command forwards the result of focusing and explains a missing previous workspace, also for `workspace --auto-back-and-forth`. Exit codes are unchanged. Regression tests: `WorkspaceBackAndForthCommandTest.testNoPrevWorkspace_failsWithMessage` and `testFailsWhenFocusingPrevWorkspaceFails` (added in 42399acc), which covers the ignored result. RB-82 corrects the docs.
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/AppBundle/command/impl/WorkspaceBackAndForthCommand.swift:9 @812da7fa`
- **Current location:** same line. Unchanged.
- **Description:** `prevFocusedWorkspace?.focusWorkspace() != nil` compares an `Optional<Bool>` with nil, so the `Bool` result is ignored.
- **How it shows up:** the command exits 0 whenever a previous workspace exists, even if focusing it failed. It exits 2 with no message when there is no previous workspace. Compare `FocusBackAndForthCommand.swift:9-12`, which uses the result and prints a message.
- **Fix direction:** follow `FocusBackAndForthCommand`.

### RB-32: `run-callback --for-every-window` differs from real window detection

- **Status:** Fixed in 797a99f5. Regression test: `RunCallbackCommandTest.testForEveryWindowFollowsWindowDetection`.
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

- **Status:** Fixed in 428e1f02. Regression test: `ResizeCommandTest.testParseCommand_acceptsAtMostOneSign`.
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/Common/cmdArgs/impl/ResizeCmdArgs.swift:49 @812da7fa`
- **Current location:** `Sources/Common/cmdArgs/impl/ResizeCmdArgs.swift:47`. Unchanged.
- **Description:** The amount is parsed with `removePrefix("+").removePrefix("-")` and then `UInt(...)`, and `UInt(...)` itself accepts a leading `+`. So:
  - `+-5` and `++5` both mean "add 5".
  - `-+5` is rejected as an unknown flag, because the negative-number check needs a digit after `-`. That check was `isResizeNegativeUnitsArg` in `parseSpecificCmdArgs.swift:80-83 @812da7fa`; it is now `isNegativeNumber` at `parseSpecificCmdArgs.swift:80`, used together with `negativeNumbersArePositional`.
- **How it shows up:** `aerospace resize width +-50` grows the window instead of failing.
- **Fix direction:** accept exactly one optional sign followed by digits.

### RB-34: `debug-windows` state machine quirks

- **Status:** Fixed in 8147e772. Regression test: `DebugWindowsCommandTest.testFailedTargetResolutionDoesntStartRecording`. A related case is RB-78.
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

- **Status:** Fixed in 26c00d67, 2c072a79 and eaaf3800. The impossible paths of `focus` and `move` ask for a bug report. When `move`, `focus`, `focus-monitor`, `move-node-to-monitor` or `move-workspace-to-monitor` can't find a monitor because there are no screens (RB-01), they print a plain message instead. Exit codes are unchanged. Regression tests: the `noScreens` tests in `MoveCommandTest`, `FocusCommandTest`, `FocusMonitorCommandTest` and `MoveWorkspaceToMonitorCommandTest`. The bug-prompt paths themselves can't be reached in a test. Without screens, the `main` pattern still resolves to the fake monitor and succeeds; the fake monitor is the current monitor in that state.
- **Severity:** low · **Confidence:** speculative (unreachable today)
- **Original location (`@812da7fa`):**
  - `Sources/AppBundle/command/impl/FocusCommand.swift:81` returns a plain "Must be discarded by args parser", while `:61` wraps the same text in `bugPrompt(...)`.
  - `Sources/AppBundle/command/impl/MoveCommand.swift:67` returns a plain "Can't find the current monitor", while `FocusCommand.swift:86` uses `bugPrompt`.
- **Current location:** `FocusCommand.swift:78` vs `:58`, and `MoveCommand.swift:61` vs `FocusCommand.swift:83`.
- **Description:** the same impossible conditions are reported in two different ways.
- **How it shows up:** it doesn't today. If one of these paths is ever reached, the plain variants won't ask for a bug report.
- **Fix direction:** use `bugPrompt` in all of them.

### RB-72: `resize` blames floating windows when a tiled window has no ancestor of the right orientation

- **Status:** Fixed in a7f5c795. Regression tests in `ResizeCommandTest`.
- **Severity:** low · **Confidence:** likely
- **Location:** `Sources/AppBundle/command/impl/ResizeCommand.swift:23-25`
- **Description:** When no tiling ancestor has the requested orientation, `resize` says "resize command doesn't support floating windows yet", even for a tiled window.
- **How it shows up:** `resize height` in a tree with only horizontal containers fails with a message about floating windows (`ResizeCommandTest.testHeight_noVerticalAncestor_returnsFail` reaches this path).
- **Fix direction:** keep the floating-window message for floating windows and say what happened for tiled ones.

### RB-74: `focus dfs-next` and `dfs-prev` fail silently

- **Status:** Fixed in 6ad194af. Regression tests: `FocusCommandTest.testFocusDfsRelative_noWindow_failsWithMessage` and `testFocusDfsRelative_ignoredFloatingWindow_failsWithMessage`.
- **Severity:** low · **Confidence:** possible
- **Location:** `Sources/AppBundle/command/impl/FocusCommand.swift:49-51`
- **Description:** With no focused window, or with a floating window focused, `focus dfs-next` and `focus dfs-prev` exit 2 without a message.
- **How it shows up:** a CLI user gets exit code 2 and no explanation.
- **Fix direction:** print a short message, like the neighboring paths.

### RB-78: `debug-windows` stays recording after a failed first dump

- **Status:** Open.
- **Severity:** low · **Confidence:** speculative
- **Location:** `Sources/AppBundle/command/impl/DebugWindowsCommand.swift:44-63`
- **Description:** The state is set to `.recording` before the starting window is dumped. If that dump throws, the command exits 2 with a bug prompt but stays in `.recording`.
- **How it shows up:** the next `debug-windows` finishes a session that the user thinks failed.
- **Fix direction:** reset the state when the first dump fails.

### RB-80: `exec-and-forget` with leading whitespace is an unknown command

- **Status:** Open.
- **Severity:** low · **Confidence:** possible
- **Location:** `Sources/AppBundle/command/parseCommand.swift:8`
- **Description:** `raw` isn't trimmed before the `exec-and-forget` check, so `' exec-and-forget open …'` goes to the shell parser, which fails with "Unrecognized subcommand 'exec-and-forget'". The friendlier message in `cmdManifest.swift:16` can't be reached, because `parseCmdArgs` rejects the name first.
- **How it shows up:** a binding with a leading space fails at config load with a confusing error.
- **Fix direction:** trim leading whitespace before the check.

### RB-81: `subscribe` drops the duplicate-event error when an unknown event follows

- **Status:** Open.
- **Severity:** low · **Confidence:** speculative
- **Location:** `Sources/Common/cmdArgs/impl/SubscribeCmdArgs.swift:35-50`
- **Description:** When a duplicate event comes before an unknown one, only the unknown-event error is reported. This was already the case before RB-14.
- **How it shows up:** `subscribe a a bogus` reports only the unknown event.
- **Fix direction:** collect both errors.

### RB-82: The `workspace-back-and-forth` docs say it always succeeds

- **Status:** Fixed in f435248e. Documentation only; the generated files don't change.
- **Severity:** low · **Confidence:** speculative
- **Location:** `docs/aerospace-workspace-back-and-forth.adoc:22`
- **Description:** The docs say the command "always succeeds", but it exits 2 when there is no previous workspace, for example right after startup. Since RB-31 it also prints a message then.
- **How it shows up:** scripts that rely on the documented behavior get exit code 2.
- **Fix direction:** correct the sentence.

### RB-90: Parse errors with an explicit exit code have no `ERROR:` prefix

- **Status:** Open.
- **Severity:** low · **Confidence:** possible
- **Location:** `Sources/Common/cmdArgs/parseCmdArgs.swift:4, 9`, `Sources/AppBundle/command/parseCommand.swift:18, 21`, `Sources/AppBundle/command/cmdManifest.swift:16, 42`
- **Description:** Errors created with `failure(_:_:)` (empty command, unrecognized subcommand, illegal eval, shell syntax errors) have no `ERROR: ` prefix, unlike the arg-parser and, since RB-16, the validation errors.
- **How it shows up:** `aerospace bogus` prints `Unrecognized subcommand 'bogus'`, while `aerospace focus --bogus` prints `ERROR: …`.
- **Fix direction:** format these through `joinErrors()` too, together with RB-89.

### RB-91: The `list-windows` order depends on the format

- **Status:** Open.
- **Severity:** low · **Confidence:** possible
- **Location:** `Sources/AppBundle/command/impl/ListWindowsCommand.swift:47-55`
- **Description:** The windows are sorted by app name, title and window ID, but the title is fetched only when the format uses `%{window-title}`. Otherwise every title is empty for the sort.
- **How it shows up:** `list-windows --all --format '%{window-id}'` orders one app's windows by ID, while the default format orders them by title.
- **Fix direction:** document it, or always fetch the title for sorting. Fetching it costs an AX call per window.

### RB-108: `swap --wrap-around` on a floating window swaps it into the tiling tree

- **Status:** Open.
- **Severity:** medium · **Confidence:** possible
- **Location:** `Sources/AppBundle/command/impl/SwapCommand.swift:15-21`
- **Description:** For a floating or macOS-native window, `closestParent` returns nil, because the window's parent isn't a tiling container. With `--wrap-around`, the command then takes a tiling window of the workspace as the target. `swapWindows` exchanges the parents of the two windows.
- **How it shows up:** `swap left --wrap-around` with a floating window focused moves the floating window into the tiling tree and a tiling window into the floating container. Without `--wrap-around`, the command exits 2 without a message.
- **Fix direction:** fail with a message for windows that aren't tiled, before looking for a target.

### RB-109: Typo in the `layout` error for minimized, fullscreen and hidden-app windows

- **Status:** Open.
- **Severity:** low · **Confidence:** likely
- **Location:** `Sources/AppBundle/command/impl/LayoutCommand.swift:30`
- **Description:** The message says "Can't change layout for macOS minimized, fullscreen windows or windows or hidden apps". It should say "windows of hidden apps".
- **How it shows up:** user-visible stderr text when `layout` runs on a minimized, macOS fullscreen or hidden-app window. `WindowParentTest.swift:66` pins it.
- **Fix direction:** fix the wording and update the test.

### RB-110: `debug-windows` can log a window after its session ended

- **Status:** Open.
- **Severity:** low · **Confidence:** speculative
- **Location:** `Sources/AppBundle/command/impl/DebugWindowsCommand.swift:117-126`
- **Description:** `debugWindowsIfRecording` checks the state, then writes the result of `await dumpWindowDebugInfo(...)` into `debugWindowsLog` at `:125` without checking the state again. A related case is RB-78.
- **How it shows up:** if `debug-windows` ends the session during the await, the entry lands in the cleared log. The next session start clears it, unless that session started during the await too; then the entry shows up in the new session's output.
- **Fix direction:** check the state again after the await, and drop the result if the session changed.

### RB-111: `test` rejects an empty right-hand side

- **Status:** Open.
- **Severity:** low · **Confidence:** possible
- **Location:** `Sources/Common/cmdArgs/impl/TestCmdArgs.swift:25-33`. Empty literals are dropped at `Sources/Common/util/StringEx.swift:144`.
- **Description:** `rawInterpolationTokens` drops empty literals, so an empty right-hand side has no tokens at all. `parseTestRhs` then falls to the default arm.
- **How it shows up:** `test %{window-title} = ''` fails with "Right hand side doesn't allow interpolation variables" instead of comparing the title with the empty string.
- **Fix direction:** treat an empty token list as the empty literal.

### RB-112: The initial `focused-workspace-changed` event names the current workspace as the previous one

- **Status:** Open.
- **Severity:** low · **Confidence:** speculative
- **Location:** `Sources/AppBundle/subscriptions.swift:25`
- **Description:** Unless `--no-send-initial` is given, `subscribe` sends an initial event for each subscribed type. The initial `focused-workspace-changed` event sets `prevWorkspace` to the current workspace.
- **How it shows up:** the initial event looks like a change from the current workspace to itself, and nothing marks it as initial. A subscriber that tracks the previous workspace gets a wrong value.
- **Fix direction:** send the real previous workspace (`_prevFocusedWorkspaceName`), or document the initial value.

## Config, shell and UI

### RB-04: Config auto-reload stops after an atomic save with a syntax error

- **Status:** Fixed in db5c420f: the watcher is re-armed after every non-dry-run reload. No regression test: the watcher reloads the real config. Verified by reading the reload paths. A related startup case is RB-75.
- **Severity:** medium · **Confidence:** likely
- **Original location:** `Sources/AppBundle/config/ConfigFileWatcher.swift:31-45` and `Sources/AppBundle/command/impl/ReloadConfigCommand.swift:51-60` `@812da7fa`
- **Current location:** same lines. Unchanged.
- **Description:** The watcher is a `DispatchSource` on an `O_EVTONLY` file descriptor, so it follows the inode, not the path. Only `syncConfigFileWatcher()` re-arms it, and `ReloadConfigCommand` calls that only when the reload is allowed. A TOML syntax error is a `preventConfigReload` error, so `allowReloadConfig` is false (`parseConfig.swift:236 @812da7fa`, now `:257`), and the watcher isn't re-armed.
- **How it shows up:** editors that save atomically write a temporary file and rename it over the config, which replaces the inode. If such a save contains a syntax error, the watcher stays bound to the old, deleted file. Fixing the error and saving again does nothing. Auto-reload silently stops until the user runs `aerospace reload-config`.

  Repro: in an editor that saves atomically, save the config with a stray `[`, fix it, and save again. The fix isn't picked up.
- **Fix direction:** call `syncConfigFileWatcher()` after every reload attempt, or re-arm the watcher on delete and rename events whatever the reload result.

### RB-10: Config reload crashes if `~/Library/LaunchAgents` can't be created

- **Status:** Fixed in c843e5c3: the directory is no longer created. No regression test: the code works on the real home directory. Verified by reading the code.
- **Severity:** medium · **Confidence:** possible
- **Original location:** `Sources/AppBundle/config/startAtLogin.swift:16-21 @812da7fa`
- **Current location:** `Sources/AppBundle/config/startAtLogin.swift:16-21`. Unchanged.
- **Description:** `syncStartAtLogin` runs on startup and on every successful reload. It calls `cleanupPlistFromPrevVersions`, which creates `~/Library/LaunchAgents` with `getOrDie` only so that it can delete a legacy plist from it. The delete doesn't need the directory to exist.
- **How it shows up:** with a read-only or unusual home directory, such as on a managed Mac, AeroSpace crashes at startup and on every reload. Repro idea: point `HOME` at a read-only directory in a debug build.
- **Fix direction:** don't create the directory. Remove the plist with `try?` only if it exists.

### RB-22: The split/flatten conflict error says "disabled" instead of "enabled"

- **Status:** Fixed in 293561c8. Regression test: `ConfigTest.testSplitCommandAndFlattenContainersNormalization`.
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/config/parseConfig.swift:302 @812da7fa`
- **Current location:** `Sources/AppBundle/config/parseConfig.swift:324` (`splitAndFlattenConflictError`). Pinned by `Sources/AppBundleTests/config/ConfigTest.swift:280`.
- **Description:** The error fires when `enable-normalization-flatten-containers` is enabled and a binding uses `split`. The text says "'split' command has no effect when enable-normalization-flatten-containers is disabled".
- **How it shows up:** a misleading config diagnostic.
- **Fix direction:** change "disabled" to "enabled" and update the test.

### RB-23: Wrong expected type in the `exec.env-vars` error

- **Status:** Fixed in 12dc9cae. Regression test: `ParseEnvVariablesTest.testEnvVarsOfWrongType`.
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/config/parseExecEnvVariables.swift:37 @812da7fa`
- **Current location:** `Sources/AppBundle/config/parseExecEnvVariables.swift:37`. Unchanged.
- **Description:** if `exec.env-vars` isn't a table, the error says "Expected type is 'Array'".
- **How it shows up:** `[exec]` with `env-vars = 1` produces a message that asks for an array.
- **Fix direction:** pass `expected: .table` (`TomlType.table` exists).

### RB-24: The shell parser rejects input that is only newlines or comments

- **Status:** Fixed in 91d1dcb1. Regression tests: `ShellParserTest.testParserOnlyNewlinesAndComments` and `ConfigCharacterizationTest.testBindingWithCommentedOutCommands`. The same problem after an opening parenthesis is RB-73.
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/shell/shellParser.swift:91-99` and `Sources/AppBundle/shell/shellLexer.swift:32-33` `@812da7fa`
- **Current location:** `shellParser.swift:90-98` and `shellLexer.swift:32-33`. Unchanged.
- **Description:** The lexer emits a `.newline` token after a comment that ends in a newline. The parser then finds a newline where it expects a word. So `"\n"` and `"# c\n"` fail with "Expected at least one word. Got: \n", while `"# c"` parses as empty. `ShellParserTest.swift:16 @812da7fa` (now `:18`) shows the message.
- **How it shows up:** a multi-line TOML command string that contains only comments, for example a binding that was temporarily commented out, is reported as a config error.
- **Fix direction:** skip newline tokens before requiring a word, and treat input that is only whitespace or comments as empty.

### RB-25: Finding the project root loops forever without a `.git` directory

- **Status:** Fixed in e5b98f27 and 2627f966: the walk looks for `Package.swift`, like `projectRoot` in the tests, and stops with a clear message at `/`. No regression test: the walk starts at `#filePath`, and the old code hangs. Verified with a throwaway copy of the walk on scratch trees: a tarball, sources inside another git repository, and a worktree.
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/config/Config.swift:9-11` and `Sources/AppBundleTests/testUtil.swift:10` `@812da7fa`
- **Current location:** `Sources/AppBundle/config/Config.swift:9-11`. Unchanged. The test half is fixed: TS-3 (f7e5b183) changed `projectRoot` (`Sources/AppBundleTests/testUtil.swift:6-14`) to look for `Package.swift` and to stop at `/`.
- **Description:** `getDefaultConfigUrlFromProject` walks up from `#filePath` until it finds `.git`. `deleteLastPathComponent` never fails, so the loop never ends when no ancestor has a `.git` directory. This happens with a source tarball or a copied tree.
- **How it shows up:** a debug build that isn't run as an app bundle hangs at startup, and so do unit tests, because `defaultConfigUrl` falls back to this function.
- **Fix direction:** stop at the filesystem root and fail with a clear message.

### RB-37: Tray symbols for workspace names that only look like numbers

- **Status:** Fixed in 3233d6f3. Regression tests in `TrayMenuModelTest`.
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/AppBundle/ui/TrayMenuModel.swift:94-106 @812da7fa`
- **Current location:** `Sources/AppBundle/ui/TrayMenuModel.swift:111-125`, rendered by `MenuBarLabel.swift`. Unchanged.
- **Description:** `Int(name)` accepts names such as `+5`, `-0` and `005`. The symbol name is then built from the raw name, for example `+5.square`, and SF Symbols has no such symbol. `05` is probably fine.
- **How it shows up:** in the squares and i3 menu-bar styles, such a workspace shows a blank item instead of the text fallback.
- **Fix direction:** use the symbol only when `String(number) == name`, or when the name is all digits and has the canonical form.

### RB-38: "Open config" and reload use the wrong file if the `--config-path` file is deleted

- **Status:** Fixed in a83cbf47 and 257a547d. A reload with a missing `--config-path` file now reports the missing file and keeps the current config. "Open config" recreates the configured file from the default config and opens it in the editor for `.toml` files. Regression test: `ConfigFileTest.testConfigPathIsUsedEvenIfTheFileIsMissing`. The editor lookup has no test, because it depends on LaunchServices; verified with a throwaway probe.
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/AppBundle/config/ConfigFile.swift:5-23` and `Sources/AppBundle/ui/MenuBar.swift:95-103` `@812da7fa`
- **Current location:** `ConfigFile.swift:5-22` and `MenuBar.swift:116-127` (`openConfigButton`). Unchanged.
- **Description:** `findCustomConfigUrl` returns `.noCustomConfigExists` when the file given by `--config-path` doesn't exist. Startup rejects a missing path (`initAppBundle.swift:108-110`), but the file can be deleted after launch.
- **How it shows up:** after the file is deleted, "Open config" copies the default config to `~/.aerospace.toml` instead of the configured path, and reloading silently falls back to the default config.
- **Fix direction:** when `--config-path` is set, always use it, and report a missing file as an error.

### RB-42: Hotkey events can report another mode's key notation

- **Status:** Fixed in 1495d958. No regression test: needs a real HotKey event. Verified by reading the code.
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/AppBundle/config/HotkeyBinding.swift:31-45 @812da7fa`
- **Current location:** `Sources/AppBundle/config/HotkeyBinding.swift:31-45` (the event is built at `:35-38`). Unchanged.
- **Description:** A `HotKey` is registered once per key code. When a later mode binds the same key code, the existing registration stays. Its handler correctly looks up the active mode's command, but it still broadcasts the first mode's `binding.descriptionWithKeyNotation`.
- **How it shows up:** if two modes reach the same key code through different notations (for example key-mapping aliases), `bindingTriggered` events report the other mode's notation. The right command still runs.
- **Fix direction:** take the notation from the active mode's binding when building the event.

### RB-43: `on-window-detected` warnings are dropped when there are no errors

- **Status:** Closed: the only warning is the outdated-config-version warning, which is added at the root after parsing. `on-window-detected` produces no warnings that could be dropped.
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/AppBundle/config/parseOnWindowDetected.swift:130-134 @812da7fa`
- **Current location:** `Sources/AppBundle/config/parseOnWindowDetected.swift:127-131`. Unchanged.
- **Description:** `myContext.warnings` reaches `c.warnings` only when the callback also has errors.
- **How it shows up:** nothing today, because only the top-level `config-version` check emits warnings.
- **Fix direction:** always append the warnings.

### RB-44: Implicit persistent-workspace order depends on Dictionary iteration

- **Status:** Closed: the implicit persistent workspaces are only used through `contains` and the workspace GC loop, which don't depend on the order, and they are never displayed.
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/AppBundle/config/parseConfig.swift:280-288 @812da7fa`
- **Current location:** `Sources/AppBundle/config/parseConfig.swift:286` and `:299-310` (`implicitPersistentWorkspaces`). Unchanged.
- **Description:** For `config-version = 1`, the implicit `persistentWorkspaces` order comes from iterating `[String: Mode]` and `[String: HotkeyBinding]`, so it changes from process to process.
- **How it shows up:** no visible effect was found. `Workspace.all` sorts, and the order isn't shown in any output. It would matter if something started relying on the `OrderedSet` order.
- **Fix direction:** sort the names before inserting them.

### RB-68: TOML syntax errors are reported verbatim from TOMLKit

- **Status:** Closed: the messages come from TOMLKit and TOMLDecoder, so the fix belongs upstream. TOMLDecoder also reports "Internal error." for an unclosed bracket.
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/AppBundle/config/parseConfig.swift:254 @812da7fa`
- **Current location:** `Sources/AppBundle/config/parseConfig.swift:212`. Unchanged. Pinned by `testMissingValueIsSyntaxErrorThatPreventsReload` (`Sources/AppBundleTests/config/ConfigTest.swift:680-685`).
- **Description:** TOML parse errors are passed on unchanged as `error.description`. For `a = `, the message is "[ERROR] (Line 1) Syntax error: syntax error.", which doesn't say what is wrong.
- **How it shows up:** an unhelpful config error for common TOML mistakes.
- **Fix direction:** wrap TOMLKit's error and add context, such as the offending line, where TOMLKit provides it.

### RB-73: The shell parser rejects a newline right after an opening parenthesis

- **Status:** Fixed in c1494c07. Regression test: `ShellParserTest.testParserParensStartingWithNewlines`.
- **Severity:** low · **Confidence:** possible
- **Location:** `Sources/AppBundle/shell/shellParser.swift:77-80`
- **Description:** A parenthesized group that starts with a newline or a comment line fails with "Expected at least one word. Got: \n". It has the same cause as RB-24, which fixed only the top level.
- **How it shows up:** a multi-line binding such as `(\n  foo\n)` is a config error.
- **Fix direction:** skip newline tokens after `(` as at the top level.

### RB-75: The config watcher isn't armed after the config fails to parse at startup

- **Status:** Open. Whether a config that fails to parse should be watched is a design choice: the setting that enables watching is in that config.
- **Severity:** low · **Confidence:** possible
- **Location:** `Sources/AppBundle/config/ConfigFileWatcher.swift:31-33`, `Sources/AppBundle/initAppBundle.swift:21`
- **Description:** If the user's config fails to parse at startup, the default config stays active, and it has `auto-reload-config = false`. So no watcher is armed, and fixing the file isn't picked up until a manual `reload-config`.
- **How it shows up:** a user starts AeroSpace with a typo in the config, fixes the typo, and nothing happens.
- **Fix direction:** arm the watcher on the user's config file after a failed parse, or tell the user to run `reload-config` in the parse-error message.

### RB-89: Config errors for binding commands show the `ERROR:` prefix twice

- **Status:** Open.
- **Severity:** low · **Confidence:** likely
- **Location:** `Sources/AppBundle/config/parseConfig.swift:190-202` (`parseCommandForConfig`, which replaced `ParsedCmd.toResult`)
- **Description:** Config parsing reports a bad binding command with the command parser's message, which already starts with `ERROR: `, inside its own `[ERROR] <key>: ` line. This was already the case for arg-parser errors. Since RB-16, post-parse validation errors look the same.
- **How it shows up:** the config-error window and `reload-config` show `[ERROR] mode.main.binding.alt-a: ERROR: Can't parse 'foo'.`
- **Fix direction:** strip the per-error prefix in `parseCommandForConfig`, or have `CmdParsingFailure` keep the raw error list.

### RB-96: Config errors with several expected types print lowercase type names

- **Status:** Open.
- **Severity:** low · **Confidence:** likely
- **Location:** `Sources/AppBundle/config/parseConfig.swift:471-474` (the `[TomlType]` overload of `expectedActualTypeDiagnostic`) and `Sources/AppBundle/config/DynamicConfigValue.swift:52, 73`
- **Description:** The single-type message prints the raw values of `TomlType`, such as `'String'`. The multi-type message and the two messages in `DynamicConfigValue.swift` interpolate the enum cases, which print in lowercase. A doc comment at `:471` notes the difference.
- **How it shows up:** `after-startup-command = true` reports "Expected types are 'string' or 'array'. But actual type is 'bool'", while `accordion-padding = true` reports "Expected type is 'Int'. But actual type is 'Bool'". A per-monitor gap with a wrong value even mixes both: "Expected type is 'Int'. But actual type is 'bool'". `ConfigCharacterizationTest` and `ConfigTest` pin these messages.
- **Fix direction:** use `rawValue` everywhere and update the tests.

### RB-97: An invalid key notation is reported at the table's path

- **Status:** Open.
- **Severity:** low · **Confidence:** likely
- **Location:** `Sources/AppBundle/config/parseKeyMapping.swift:51`. The key-code error is at `:47`.
- **Description:** An invalid key notation is reported at the path of the `key-notation-to-key-code` table. An invalid key code is reported at the path of its key.
- **How it shows up:** `key-mapping.key-notation-to-key-code: ' f' is invalid key notation`, but `key-mapping.key-notation-to-key-code.q: 'qw' is invalid key code`. `ConfigTest.swift:630` pins the first.
- **Fix direction:** report the notation error at `backtrace + .key(key)` and update the test.

### RB-98: Config error paths don't quote keys with dots or spaces

- **Status:** Open.
- **Severity:** low · **Confidence:** speculative
- **Location:** `Sources/AppBundle/config/parseConfig.swift:435-445` (`ConfigBacktrace.description`)
- **Description:** The path joins keys with `.` and never quotes them.
- **How it shows up:** in error messages, `monitor."test monitor"` prints as `monitor.test monitor`, and a quoted key `"a.b"` looks like the nested path `a.b`.
- **Fix direction:** quote keys that aren't valid bare TOML keys.

### RB-99: The `on-window-detected` debug JSON omits `check-further-callbacks` and doesn't escape values

- **Status:** Open.
- **Severity:** low · **Confidence:** speculative
- **Location:** `Sources/AppBundle/config/parseOnWindowDetected.swift:8-16` (`WindowDetectedCallback.debugJson`) and `:37-46` (`LegacyWindowDetectedCallbackMatcher.debugJson`)
- **Description:** The debug JSON of a callback has `matcher` and `commands`, but not `check-further-callbacks`. The legacy matcher text wraps values in `"…"` without escaping them.
- **How it shows up:** in `debug-windows` output, `Aero.on-window-detected` doesn't show whether later callbacks run too. An app ID or regex that contains a `"` makes the matcher text ambiguous.
- **Fix direction:** add `check-further-callbacks`, and escape the quoted values.

### RB-100: A wrong-type `if` also reports that `if` was omitted

- **Status:** Open.
- **Severity:** low · **Confidence:** possible
- **Location:** `Sources/AppBundle/config/parseOnWindowDetected.swift:97-100` and `:108-112`
- **Description:** For an `if` of the wrong type, `parseMatcher` reports the type error and returns the empty matcher. An omitted `if` gives the same empty matcher, so the callback also gets "Omitting 'if' is error prone". An `if` command that fails to parse does the same, because `parseCommandForConfig` returns an empty shell.
- **How it shows up:** `on-window-detected = [{ if = 1, run = '' }]` reports the type error and a second error that says `if` was omitted. `ConfigCharacterizationTest.testOnWindowDetectedMatcherErrors` pins both.
- **Fix direction:** track whether `if` was given, separately from its parsed value.

### RB-101: A binding whose command fails to parse stays bound and does nothing

- **Status:** Open.
- **Severity:** low · **Confidence:** possible
- **Location:** `Sources/AppBundle/config/HotkeyBinding.swift:89-102` and `Sources/AppBundle/config/parseConfig.swift:190-202` (`parseCommandForConfig`)
- **Description:** When a binding's command fails to parse, `parseCommandForConfig` reports the error and returns an empty shell, and `parseBindings` still adds the binding. Only severe errors such as TOML syntax errors stop a reload (`allowReloadConfig`), so the config is applied with the empty binding.
- **How it shows up:** after a reload that reports the error, the hotkey is registered but does nothing. It still takes the key, and the binding of the previous config is gone. This may be intended.
- **Fix direction:** skip bindings whose command fails to parse, or keep the previous config's binding for that key.

## Shared utilities and app entry point

### RB-06: Dying recurses forever when `/tmp/bobko.aerospace` isn't writable

- **Status:** Fixed in f7721310: the report goes to a per-user temporary directory, and a failed write skips opening Console instead of dying. No regression test: the path opens Console. Verified by reading the code.
- **Severity:** medium · **Confidence:** likely (when the directory isn't writable)
- **Original location:** `Sources/Common/util/showMessageInGui.swift:9-12` and `Sources/Common/util/commonUtil.swift:59-66` `@812da7fa`
- **Current location:** same lines. Unchanged.
- **Description:** `dieT` calls `showMessageInGui`, which creates and writes `/tmp/bobko.aerospace/` with `getOrDie`. If that fails, `getOrDie` calls `die` → `dieT` → `showMessageInGui` again, forever. The directory is in the shared `/tmp` and isn't per-user, so it may belong to another macOS user on the same machine.
- **How it shows up:** any crash turns into a stack overflow. The error report is never shown, and the termination handler never runs, so hidden windows are not restored.

  Repro: create `/tmp/bobko.aerospace` as another user (or as root) with mode 755, then trigger any `die` in a debug build.
- **Fix direction:** use a per-user directory (for example `FileManager.default.temporaryDirectory`), and use `try?` there instead of `getOrDie`.

### RB-07: AX size and position getters crash on unexpected values and can deadlock on quit

- **Status:** Fixed in df0c4dac. Regression test: `AccessibilityTest.testSizeAndPositionGettersReturnNilForUnexpectedValues`.
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

- **Status:** Closed: not a bug. Network.framework fails the receive that follows the end of the stream (ENOTCONN after a close, ENODATA after a half-close), so the loop ends after one extra receive. 3696767e pins this with a test that is bounded by a timeout.
- **Severity:** medium · **Confidence:** possible
- **Original location:** `Sources/Common/util/NWConnectionEx.swift:65-81 @812da7fa`
- **Current location:** `Sources/Common/util/NWConnectionEx.swift:66-82`. Unchanged in behavior.
- **Description:** `read(bytes:)` loops while `data.count < size`. When the peer closes before sending enough bytes, `receive` reports `isComplete == true` with nil data and no error. The loop then appends an empty `Data()` and asks again, forever. `readTillError` handles this case, but `read(bytes:)` doesn't.
- **How it shows up:** the CLI spins at 100% CPU if the server dies in the middle of an answer. A server task does the same if a client disconnects in the middle of a request.

  Repro: run a small Unix-socket server at the AeroSpace socket path that accepts a connection and closes it without answering, then run any `aerospace` command.
- **Fix direction:** when `isComplete` is true and fewer bytes than requested have arrived, throw a "connection closed" error.

### RB-09: On quit, windows are centered without the monitor's origin

- **Status:** Fixed in 3366b949. No regression test: the code runs only on quit, with real windows. Verified by reading the code; before db226755 windows were placed relative to their own monitor too.
- **Severity:** medium · **Confidence:** possible
- **Original location:** `Sources/AppBundle/util/appBundleUtil.swift:33-40 @812da7fa`
- **Current location:** `Sources/AppBundle/util/appBundleUtil.swift:33-40`. Unchanged.
- **Description:** When AeroSpace quits, it moves every window back on screen. Each window is centered at `((visibleRect.width - w) / 2, (visibleRect.height - h) / 2)` on its approximate monitor. The monitor's `topLeftX` and `topLeftY` are never added, so the position is relative to the main monitor's origin.
- **How it shows up:** with several monitors, windows that belonged to a secondary monitor end up on the main monitor after AeroSpace quits. The code has been like this since at least late 2023 (db226755), so it may be intentional.
- **Fix direction:** add `visibleRect.topLeftX` and `topLeftY`, or confirm with upstream that placing windows on the main monitor is intended, and document it.

### RB-26: The unrecognized-flag error names the wrong flag

- **Status:** Fixed in d5f8cedb. No regression test: `initServerArgs` reads the process arguments and exits. Verified by reading the code.
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/initAppBundle.swift:105 @812da7fa`
- **Current location:** `Sources/AppBundle/initAppBundle.swift:105`. Unchanged.
- **Description:** the message prints `args.first` instead of `current`, which is the flag that was actually rejected.
- **How it shows up:** `AeroSpace --read-only --bogus` reports "Unrecognized flag '--read-only'".
- **Fix direction:** print `current`.

### RB-27: `interceptTermination(SIGKILL)` does nothing

- **Status:** Fixed in 988c85f1: the call is removed. No test: the call had no effect.
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/initAppBundle.swift:14 @812da7fa`
- **Current location:** `Sources/AppBundle/initAppBundle.swift:14`. Unchanged.
- **Description:** SIGKILL can't be caught, so `signal()` returns `SIG_ERR` and the call has no effect.
- **How it shows up:** nothing visible. It is misleading, because it suggests that `kill -9` restores windows.
- **Fix direction:** remove the call.

### RB-28: `ActivationPolicy.prohibited` prints with a leading space

- **Status:** Fixed in ab7b57ac. Regression test: `AxUiElementWindowTypeTest.testActivationPolicyRoundTrip`.
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/util/NsApplicationEx.swift:7 @812da7fa`. Used by `DebugWindowsCommand.swift:96`.
- **Current location:** same lines. Unchanged.
- **Description:** The string for `.prohibited` is `" prohibited"`.
- **How it shows up:**
  - The leading space appears in `debug-windows` output.
  - The test helper `ActivationPolicy.from(string:)` (`AxUiElementWindowTypeTest.swift:62-69 @812da7fa`, now `:69-78`) would `die` on a dump that contains this value.
- **Fix direction:** remove the space.

### RB-29: `joinTruncating` adds an ellipsis when nothing was cut

- **Status:** Fixed in 249ddde0: every element counts against the length, including the first, which is cut if it is too long, and an exact fit isn't cut. Regression test: `CommonUtilTest.testJoinTruncating`. Visible change: the tray menu's app list is now really limited to 25 characters, so a long first app name is cut too. When the next element doesn't fit, the `…` marker can still exceed the length by the separator; that is intended.
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/Common/util/StringEx.swift:39-60 @812da7fa`. Used by `Sources/AppBundle/ui/TrayMenuModel.swift:41`.
- **Current location:** `StringEx.swift:39-60`. Used by `TrayMenuModel.swift:52`. Pinned by `Sources/AppBundleTests/util/CommonUtilTest.swift:75`.
- **Description:** The first element is never counted against `length`, and the check is `elemCount < remainingLen` where `<=` is meant. For example, `["aaa", "bbb", "ccc"]` with length 10 gives `"aaa, bbb, ccc…"` even though nothing was cut.
- **How it shows up:** the app list in the tray menu can show a spurious "…" or run past 25 characters.
- **Fix direction:** count every element, use `<=`, and update the test.

### RB-30: `kAXTrustedCheckOptionPrompt` is taken as retained

- **Status:** Fixed in a1745022. No test: the over-release of a CF constant has no observable effect. Verified against the Core Foundation ownership rules.
- **Severity:** low · **Confidence:** likely
- **Original location:** `Sources/AppBundle/util/axTrustedCheckOptionPrompt.swift:3 @812da7fa`
- **Current location:** `Sources/AppBundle/util/axTrustedCheckOptionPrompt.swift:3`. Unchanged.
- **Description:** `kAXTrustedCheckOptionPrompt.takeRetainedValue()` over-releases a global CFString constant.
- **How it shows up:** nothing in practice, because CFSTR constants are never freed. The ownership is still wrong.
- **Fix direction:** use `takeUnretainedValue()`.

### RB-39: The debug-build signal handler isn't async-signal-safe

- **Status:** Fixed in 68f337e1: SIGINT is ignored and handled by a dispatch source on the main queue. No regression test: signal handling of a debug build. Verified with a throwaway experiment. Children started through `Process` don't inherit the ignored SIGINT; AeroSpace starts no children in any other way.
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/AppBundle/util/appBundleUtil.swift:11-19 @812da7fa`
- **Current location:** `Sources/AppBundle/util/appBundleUtil.swift:11-19`. Unchanged.
- **Description:** The handler allocates, spawns a `Task`, and calls `check`, which can `die` and show a GUI. None of that is safe in a signal handler. The signal can also arrive on any thread, so `check(Thread.current.isMainThread)` can fail.
- **How it shows up:** debug builds only. Ctrl-C can crash or deadlock instead of restoring windows.
- **Fix direction:** use `DispatchSource.makeSignalSource(signal:queue: .main)` together with `signal(sig, SIG_IGN)`.

### RB-45: Unchecked `as! AXUIElement` casts

- **Status:** Fixed in 20b69c08. Regression test: `AccessibilityTest.testAxElementGettersSkipValuesThatAreNotAxElements`. Its `parentWindowRecursive` assertion fails without the fix. The `windowsAttr` assertion passes either way, and dd19763f adds a comment that says so.
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/AppBundle/util/accessibility.swift:191, 328` and `Sources/AppBundle/util/dumpAxRecursive.swift:59` `@812da7fa`
- **Current location:** `accessibility.swift:69, 126`, plus a new site at `:143` (`axWindowOrNil`), and `dumpAxRecursive.swift:61`
- **Description:** `as!` to a CoreFoundation type isn't checked at runtime. A value that isn't an AX element would be passed straight to the AX functions. `dumpAxRecursive` does this for every attribute value that isn't a string, number or bool.
- **How it shows up:** nothing so far. The code relies on the AX APIs rejecting wrong types gracefully, and `debug-windows` already sends many attribute values through these casts without crashing.
- **Fix direction:** check `CFGetTypeID(value) == AXUIElementGetTypeID()` before casting.

### RB-46: `initConnection` hangs if the connection is cancelled before it is ready

- **Status:** Fixed in 52f11a2e: a cancel resumes the handshake with ECANCELED, which the CLI reports as "Can't connect to AeroSpace server". Regression test: `NWConnectionExTest.testHandshakeFailsWhenCancelledBeforeReady`. A connection that is cancelled before `initConnection()` is called still hangs; no caller does that.
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/Common/util/NWConnectionEx.swift:24 @812da7fa`
- **Current location:** `Sources/Common/util/NWConnectionEx.swift:24`. UT-7 kept the behavior.
- **Description:** The state handler resumes the continuation on `.ready`, `.failed` and `.waiting`, but not on `.cancelled`.
- **How it shows up:** the CLI would hang instead of reporting an error. Nothing currently cancels a connection before it is ready.
- **Fix direction:** resume with an error on `.cancelled`.

### RB-47: `bugPrompt` reads `NSScreen` from whatever thread is dying

- **Status:** Fixed in 4e25181c. Regression tests in `BugPromptTest`.
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/Common/util/commonUtil.swift:43-44 @812da7fa`
- **Current location:** `Sources/Common/util/commonUtil.swift:43-44`. Unchanged.
- **Description:** `bugPrompt` reads `NSScreen.screens` and `NSScreen.screensHaveSeparateSpaces` on the thread that is dying, which is often an AX thread. AppKit doesn't document these as thread-safe.
- **How it shows up:** the crash reporter itself could crash.
- **Fix direction:** read these values only on the main thread, and skip them elsewhere.

### RB-48: `toPaddingTable` mixes Character and UTF-16 counts

- **Status:** Fixed in ba1b6987. Regression test: a new case in `CommonUtilTest.testToPaddingTable`. The generated CLI help is ASCII-only, so it doesn't change.
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/Common/util/StringEx.swift:64-73 @812da7fa`
- **Current location:** `Sources/Common/util/StringEx.swift:64-73`. Unchanged.
- **Description:** Column widths are measured in `Character`s, but padding uses `NSString.padding(toLength:)`, which counts UTF-16 code units.
- **How it shows up:** columns with non-BMP or decomposed characters come out misaligned or truncated. All current inputs (the CLI help) are ASCII.
- **Fix direction:** pad by appending spaces based on `count`.

### RB-49: `transposed()` assumes a rectangular table

- **Status:** Fixed in a5dcae9c: `transposed()` documents and checks that the table is rectangular. All callers build rectangular tables. No test for the new check, because it dies and the suite has no exit tests. The test assertion that pinned the silent dropping was removed.
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/Common/util/ArrayEx.swift:2-15 @812da7fa`
- **Current location:** `Sources/Common/util/ArrayEx.swift:2-5`. It was rewritten with the same behavior.
- **Description:** The column count comes from the first row. Extra cells in longer rows are silently dropped, and shorter rows cause a `die`.
- **How it shows up:** nothing today, because the callers in `format.swift` build rectangular tables.
- **Fix direction:** document the precondition, or check it with a clear message.

### RB-69: `isUnitTest` depends on XCTest being loaded

- **Status:** Fixed in 9515ab00: test runs are detected with a class that the test target defines. Verified in every test run mode (Swift Testing only, XCTest only, both).
- **Severity:** low · **Confidence:** speculative
- **Original location:** `Sources/Common/util/commonUtil.swift:151 @812da7fa`
- **Current location:** `Sources/Common/util/commonUtil.swift:149`. It is now a `let` instead of a computed property, with the same check.
- **Description:** `isUnitTest` is `NSClassFromString("XCTestCase") != nil`. Swift Testing runs, such as `--filter` on a migrated suite or `--disable-xctest`, see it as true only because the SwiftPM testing helper happens to link and load XCTest.
- **How it shows up:** if a future toolchain stops loading XCTest for Swift Testing runs, `isUnitTest` becomes false, and the tests drive the real accessibility API and monitors. Two checks added by the test-suite cleanup would make such a run fail loudly:
  - `SwiftTestingSupportTest.swift:41`
  - a `check(isUnitTest)` in the global-state trait (`SwiftTestingSupport.swift:34`)
- **Fix direction:** detect test runs explicitly, for example with an environment variable or a flag set by the test target. This is TS-11 in the test plan.

### RB-79: The server writes an error into a connection the client closed

- **Status:** Open.
- **Severity:** low · **Confidence:** speculative
- **Location:** `Sources/AppBundle/server.swift:48-50`
- **Description:** After every normal CLI request, the client closes the socket, so the server's next `readNonAtomic` fails with ENOTCONN or ENODATA. `newConnection` then writes an `Error: …` answer into the closed connection before returning.
- **How it shows up:** nothing visible: the write fails. A normal disconnect is treated as an error.
- **Fix direction:** return without answering when the read fails because the peer closed the connection.

### RB-95: `subscribe` works while the server is disabled

- **Status:** Open.
- **Severity:** low · **Confidence:** speculative
- **Location:** `Sources/AppBundle/server.swift:58-66`. The check that the server is enabled is at `:68`.
- **Description:** The server handles `subscribe` before the `isServerEnabled` check that every other command goes through.
- **How it shows up:** after `enable off`, `aerospace subscribe` still connects and gets its initial events, while every other command fails with "server is disabled". This may be intended.
- **Fix direction:** decide whether subscribing is allowed while disabled. Then check `isServerEnabled` first, or document the exception.

### RB-104: `slice(n...)` traps instead of returning nil when `n` is past the end

- **Status:** Open.
- **Severity:** low · **Confidence:** possible
- **Location:** `Sources/Common/util/ArrSlice.swift:48, 61`
- **Description:** `slice(_: PartialRangeFrom<Int>)` builds `range.lowerBound ..< count` before the range is checked. When the lower bound is greater than `count`, building the range traps, so the function never returns the nil its optional result promises.
- **How it shows up:** nothing today: every caller passes a lower bound of at most `count`. A new caller would crash instead of getting nil.
- **Fix direction:** return nil when the lower bound is greater than `count`.

## Scripts

### RB-103: `clean-xcode.sh` deletes paths that moved to `xcode/`

- **Status:** Open.
- **Severity:** low · **Confidence:** likely
- **Location:** `script/clean-xcode.sh:8, 10`
- **Description:** The script deletes `./.xcode-build` and `AeroSpace.xcodeproj` at the repository root. Since aa656637, both live in `xcode/`.
- **How it shows up:** the script no longer removes the Xcode build output, or the old project before `./generate.sh` writes a new one.
- **Fix direction:** delete `xcode/.xcode-build` and `xcode/AeroSpace.xcodeproj`.

### RB-105: The accessibility reset script uses the wrong case in the bundle ID

- **Status:** Open.
- **Severity:** low · **Confidence:** speculative
- **Location:** `script/reset-accessibility-permission-for-debug.sh:7`
- **Description:** The script resets `bobko.AeroSpace.debug`, but the debug bundle ID is `bobko.aerospace.debug` (`xcode/project.yml:43`).
- **How it shows up:** it works only if `tccutil` matches bundle IDs without regard to case. Otherwise the debug build keeps its stale permission.
- **Fix direction:** use `bobko.aerospace.debug`.

### RB-106: `setup.sh` rejects bash 6 and later

- **Status:** Open.
- **Severity:** low · **Confidence:** speculative
- **Location:** `script/setup.sh:10`
- **Description:** The version check `grep -q '^5\.' <<< "$BASH_VERSION"` accepts only bash 5.
- **How it shows up:** once Homebrew ships bash 6, every script that sources `setup.sh` fails with "Your bash version is too old".
- **Fix direction:** check `BASH_VERSINFO[0] -ge 5`.

### RB-107: The generated command help doesn't escape the docs text

- **Status:** Open.
- **Severity:** low · **Confidence:** speculative
- **Location:** `script/generate-cmd-help.sh:23`, and `:34` for the synopsis lines. `simplify` moved this code out of `generate.sh`.
- **Description:** The `:manpurpose:` line of each `docs/aerospace-*.adoc` goes into a Swift string literal in `Sources/Common/cmdHelpGenerated.swift` without escaping. The synopsis lines go into a multi-line literal the same way.
- **How it shows up:** a `"` or `\` in a purpose line produces Swift that doesn't compile, or a different string. Today's docs contain neither.
- **Fix direction:** escape `\` and `"` before writing the literals.

## Test suite

Test-suite issues are all low severity: they hide regressions but don't affect users. Since the base commit, the test-suite cleanup (TS-1 to TS-8) has landed and many suites now use Swift Testing. That work fixed most of the original test entries, which are now listed under [Resolved by the refactor](#resolved-by-the-refactor).

### RB-61: Tests can't reset two private focus globals

- **Status:** Fixed in a404d01a: `setUpWorkspacesForTests` resets both globals through a test-only reset function. Regression tests in `SetUpWorkspacesForTestsTest`.
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

- **Status:** Fixed in 907f5404, 700509a7 and 74ae80c7 (tests only). Every dump is its own test case. Parse and conversion problems, including values that `Json` or the AX mock can't represent (RB-83), are reported as issues of that case. Verified with temporary malformed dumps: each one failed only its own case. Regression test for the conversion: `AxUiElementWindowTypeTest.testMalformedDumpValuesAreRejectedWithoutDying`.
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/AppBundleTests/AxUiElementWindowTypeTest.swift:5, 19-30 @812da7fa`
- **Current location:** `Sources/AppBundleTests/AxUiElementWindowTypeTest.swift:8-12` and `:16-44`. The `as!` casts are at `:26` and `:31`, and the `dieT()` calls at `:30`, `:34` and `:39`. Two parts of the original entry are fixed:
  - TS-5 (3a7f30d2) renamed the class to match its file.
  - TS-4 added a check that at least one dump was read.
- **Description:** a single test checks every dump in `axDumps/`. A malformed dump hits `as!` or `dieT()` and aborts the whole test process instead of failing one case.
- **Fix direction:** parameterize the test over the dump files (Swift Testing `arguments:`), and report parse problems as test failures. The test-suite cleanup deferred this because it changes the test count.

### RB-70: `testServerEventDecoding` checks only the event type

- **Status:** Fixed in 39728f47 (test only): each decoded event is compared with a complete expected `ServerEvent`. A decoder that swaps or drops fields now fails the test.
- **Severity:** low · **Confidence:** possible
- **Original location:** `Sources/AppBundleTests/model/ClientServerTest.swift:96-110 @812da7fa`
- **Current location:** `Sources/AppBundleTests/model/ClientServerTest.swift:106-120`. Unchanged.
- **Description:** the test decodes six events but compares only `eventType`. It never checks the payload fields (`windowId`, `workspace`, `monitorId`, `prevWorkspace`, `mode`, `binding`). The encoding test covers only the opposite direction.
- **How it shows up:** a decoder that drops or swaps fields still passes.
- **Fix direction:** compare each decoded event with a complete expected `ServerEvent`.

### RB-83: Converting a test AX dump can still crash the test run

- **Status:** Fixed in 700509a7 and 74ae80c7, together with RB-64. Values that `Json` can't represent, including integers above `Int64.max`, now make the conversion return nil instead of dying or trapping. 74ae80c7 also affects the shared `newScalarOrNil` used by config parsing, but TOMLKit yields `Int`, so that path doesn't change.
- **Severity:** low · **Confidence:** speculative
- **Location:** `Sources/AppBundle/util/AxUiElementMock.swift:16-29`, `Sources/AppBundle/model/Json.swift:29-49`
- **Description:** The test-only conversion of AX dumps dies or traps on unexpected values, for example a non-integer number, or a `UInt` above `Int64.max`.
- **How it shows up:** a malformed AX dump crashes the whole test run instead of failing its own RB-64 case.
- **Fix direction:** report conversion problems as issues of the dump's test case.

### RB-94: `newScalarOrNil` reads JSON booleans as integers

- **Status:** Open.
- **Severity:** low · **Confidence:** speculative
- **Location:** `Sources/AppBundle/model/OrderedJson.swift:45-56` (`newScalarOrNil`, which moved there from the deleted `Json.swift`)
- **Description:** `newScalarOrNil` tries `Int64` before `Bool`. `JSONSerialization` returns booleans as `NSNumber`, which converts to `Int64`, so JSON `true` and `false` become `.int(1)` and `.int(0)`. Only Swift `Bool` values, such as those from TOMLKit, reach the `Bool` arm.
- **How it shows up:** only the test AX-dump reader parses JSON through this path. The dumps write AX booleans as 0 and 1 anyway (`dumpAxRecursive.swift:56`), and the attribute getters accept both, so nothing fails. `AxDumpJsonTest.testReadTestDump` pins the conversion.
- **Fix direction:** check for a `CFBoolean` before the integer arms, and update the test.

### RB-102: `syncFocusFromMacOs` crashes on test windows

- **Status:** Open.
- **Severity:** low · **Confidence:** speculative
- **Location:** `Sources/AppBundle/focusCache.swift:19`
- **Description:** `syncFocusFromMacOs` ends with `nativeFocused?.asMacWindow()`, which is `self as! MacWindow`. In unit tests, the native focused window comes from `appForTests` and is a `TestWindow`.
- **How it shows up:** test-only. A test that runs a session while a test window is focused crashes the test run, so sessions can't be unit-tested. Production windows are always `MacWindow`s.
- **Fix direction:** skip the update for windows that aren't `MacWindow`s.

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

Three entries were only partly resolved by the refactor. Their remaining parts are fixed on `fix-review-bugs`:
- **RB-25:** TS-3 (f7e5b183) fixed the test half. See the entry for the production half.
- **RB-61** and **RB-64:** see the [Test suite](#test-suite) section.

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
