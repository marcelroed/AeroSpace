@testable import AppBundle
import Common
import Testing

@Suite
struct ConfigCharacterizationTest {
    @Test
    func testBindingWithCommentedOutCommands() {
        let result = parseConfig(
            """
            [mode.main.binding]
                alt-a = '''
                    # workspace a
                '''
                alt-b = '''
                    # Go to workspace b
                    workspace b
                '''
            """,
        )
        expectEqual(result.errors, [])
        let bindings = result.config.modes[mainModeId]?.bindings ?? [:]
        expectEqual(bindings["alt-a"]?.commands.shellOfCommandsDescription.isEmpty, true)
        expectEqual(bindings["alt-b"]?.commands.shellOfCommandsDescription, "workspace b")
    }

    @Test
    func testDynamicGapValueOfWrongScalarType() {
        let result = parseConfig(
            """
            [gaps]
                inner.vertical = true
                inner.horizontal = '5'
                outer.left = [{ monitor.main = true }, 1]
                outer.right = [{ monitor.main = 1 }, false]
                outer.top = [{ monitor.main = 1 }, '2']
            """,
        )
        expectEqual(result.strErrors, [
            "[ERROR] gaps.inner.horizontal: Expected types are 'Int' or 'Array'. But actual type is 'String'",
            "[ERROR] gaps.inner.vertical: Expected types are 'Int' or 'Array'. But actual type is 'Bool'",
            "[ERROR] gaps.outer.left[0].monitor.main: Expected type is 'Int'. But actual type is 'Bool'",
            "[ERROR] gaps.outer.right: The last item in the array must be of type Int",
            "[ERROR] gaps.outer.top: The last item in the array must be of type Int",
        ])
        // A per-monitor value with an unusable rule keeps the default
        expectEqual(result.config.gaps, .zero)
    }

    @Test
    func testResolvedGaps() {
        let result = parseConfig(
            """
            [gaps]
                inner.horizontal = 2
                inner.vertical = [{ monitor.main = 1 }, 5]
                outer.left = [{ monitor."test monitor" = 9 }, 10]
                outer.bottom = [{ monitor."no such monitor" = 11 }, 12]
                outer.top = [{ monitor.secondary = 4 }, 6]
                outer.right = [{ monitor.2 = 3 }, { monitor.1 = 7 }, 8]
            """,
        )
        expectEqual(result.errors, [])
        let gaps = ResolvedGaps(gaps: result.config.gaps, monitor: testMonitor)
        expectEqual(gaps.inner.horizontal, 2)
        expectEqual(gaps.inner.vertical, 1)
        expectEqual(gaps.outer.left, 9)
        expectEqual(gaps.outer.bottom, 12)
        expectEqual(gaps.outer.top, 6)
        expectEqual(gaps.outer.right, 7)
    }

    @Test
    func testDynamicGapValueArrayErrors() {
        let result = parseConfig(
            """
            [gaps]
                inner.vertical = []
                inner.horizontal = [1]
                outer.left = [1, 2]
                outer.right = [{ monitor.0 = 1 }, { monitor.main = 2 }, 3]
            """,
        )
        expectEqual(result.strErrors, [
            "[ERROR] gaps.inner.vertical: The array must not be empty",
            "[ERROR] gaps.outer.left[0]: Expected type is 'Table'. But actual type is 'Int'",
            "[ERROR] gaps.outer.right[0].monitor.0: Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal",
        ])
        var expectedGaps = Gaps.zero
        expectedGaps.inner.horizontal = .constant(1)
        expectEqual(result.config.gaps, expectedGaps)
    }

    @Test
    func testNestedTablesOfWrongType() {
        expectEqual(parseConfig("gaps = 1").strErrors, ["[ERROR] gaps: Expected type is 'Table'. But actual type is 'Int'"])
        expectEqual(parseConfig("gaps.inner = 1").strErrors, ["[ERROR] gaps.inner: Expected type is 'Table'. But actual type is 'Int'"])
        expectEqual(parseConfig("gaps.outer = 'a'").strErrors, ["[ERROR] gaps.outer: Expected type is 'Table'. But actual type is 'String'"])
        expectEqual(parseConfig("gaps.inner.foo = 1").strErrors, ["[ERROR] gaps.inner.foo: Unknown key"])
        expectEqual(parseConfig("gaps.outer.foo = 1").strErrors, ["[ERROR] gaps.outer.foo: Unknown key"])
        expectEqual(parseConfig("focus-follows-mouse = 1").strErrors, ["[ERROR] focus-follows-mouse: Expected type is 'Table'. But actual type is 'Int'"])
        expectEqual(parseConfig("focus-follows-mouse.foo = true").strErrors, ["[ERROR] focus-follows-mouse.foo: Unknown key"])
        expectEqual(parseConfig("focus-follows-mouse.enabled = 1").strErrors, ["[ERROR] focus-follows-mouse.enabled: Expected type is 'Bool'. But actual type is 'Int'"])
        expectEqual(parseConfig("mode = 1").strErrors, ["[ERROR] mode: Expected type is 'Table'. But actual type is 'Int'"])
        expectEqual(parseConfig("mode.main = 1").strErrors, ["[ERROR] mode.main: Expected type is 'Table'. But actual type is 'Int'"])
        expectEqual(parseConfig("mode.main.foo = 1").strErrors, ["[ERROR] mode.main.foo: Unknown key"])
        expectEqual(parseConfig("mode.main.binding = 1").strErrors, ["[ERROR] mode.main.binding: Expected type is 'Table'. But actual type is 'Int'"])
        expectEqual(parseConfig("key-mapping = 1").strErrors, ["[ERROR] key-mapping: Expected type is 'Table'. But actual type is 'Int'"])
        expectEqual(parseConfig("key-mapping.foo = 1").strErrors, ["[ERROR] key-mapping.foo: Unknown key"])
        expectEqual(parseConfig("exec = 1").strErrors, ["[ERROR] exec: Expected type is 'Table'. But actual type is 'Int'"])
        expectEqual(parseConfig("exec.foo = 1").strErrors, ["[ERROR] exec.foo: Unknown key"])
        expectEqual(parseConfig("exec.env-vars = 1").strErrors, ["[ERROR] exec.env-vars: Expected type is 'Table'. But actual type is 'Int'"])
        expectEqual(parseConfig("workspace-to-monitor-force-assignment = 1").strErrors, ["[ERROR] workspace-to-monitor-force-assignment: Expected type is 'Table'. But actual type is 'Int'"])
        expectEqual(parseConfig("on-window-detected = 1").strErrors, ["[ERROR] on-window-detected: Expected type is 'Array'. But actual type is 'Int'"])
        expectEqual(parseConfig("on-window-detected = [1]").strErrors, [
            "[ERROR] on-window-detected[0]: Expected type is 'Table'. But actual type is 'Int'",
        ])
    }

    @Test
    func testFocusFollowsMouse() {
        let result = parseConfig("focus-follows-mouse.enabled = true")
        expectEqual(result.errors, [])
        expectEqual(result.config.focusFollowsMouse.enabled, true)
        expectEqual(parseConfig("").config.focusFollowsMouse.enabled, false)
    }

    @Test
    func testScalarKeyValues() {
        let result = parseConfig(
            """
            after-startup-command = ['focus left', 'focus right']
            start-at-login = false
            auto-reload-config = true
            automatically-unhide-macos-hidden-apps = true
            accordion-padding = 7
            enable-normalization-opposite-orientation-for-nested-containers = false
            """,
        )
        expectEqual(result.errors, [])
        expectEqual(result.config.afterStartupCommand.flatten().count, 2)
        expectEqual(result.config.startAtLogin, false)
        expectEqual(result.config.autoReloadConfig, true)
        expectEqual(result.config.automaticallyUnhideMacosHiddenApps, true)
        expectEqual(result.config.accordionPadding, 7)
        expectEqual(result.config.enableNormalizationOppositeOrientationForNestedContainers, false)

        expectEqual(parseConfig("accordion-padding = true").strErrors, ["[ERROR] accordion-padding: Expected type is 'Int'. But actual type is 'Bool'"])
        expectEqual(parseConfig("auto-reload-config = 1").strErrors, ["[ERROR] auto-reload-config: Expected type is 'Bool'. But actual type is 'Int'"])
        expectEqual(parseConfig("after-startup-command = true").strErrors, ["[ERROR] after-startup-command: Expected types are 'String' or 'Array'. But actual type is 'Bool'"])
    }

    @Test
    func testOnWindowDetectedMatcherErrors() {
        expectEqual(parseConfig("on-window-detected = [{ if.foo = 'x', run = 'focus left' }]").strErrors, ["[ERROR] on-window-detected[0].if.foo: Unknown key"])
        expectEqual(parseConfig("on-window-detected = [{ if = 1, run = '' }]").strErrors, [
            "[ERROR] on-window-detected[0].if: Expected type is 'String'. But actual type is 'Int'",
        ])
        expectEqual(parseConfig("on-window-detected = [{ if = 'foo', run = '' }]").strErrors, [
            "[ERROR] on-window-detected[0].if: Unrecognized subcommand 'foo'",
        ])
        expectEqual(parseConfig("on-window-detected = [{ if.during-aerospace-startup = 1, run = '' }]").strErrors, ["[ERROR] on-window-detected[0].if.during-aerospace-startup: Expected type is 'Bool'. But actual type is 'Int'"])
    }

    @Test
    func testLegacyMatcherDebugJson() {
        let result = parseConfig(
            """
            [[on-window-detected]]
                if.app-id = 'com.foo'
                if.app-name-regex-substring = 'name'
                if.window-title-regex-substring = 'title'
                if.workspace = 'w'
                if.during-aerospace-startup = true
                run = 'layout floating'
            [[on-window-detected]]
                if.app-id = 'com."bar"'
                check-further-callbacks = true
                run = ['layout floating', 'focus left']
            """,
        )
        expectEqual(result.errors, [])
        expectEqual(result.config.onWindowDetected.map(\.debugJson), [
            .dict([
                "matcher": .dict([
                    "app-id": .string("com.foo"),
                    "app-name-regex-substring": .string("name"),
                    "window-title-regex-substring": .string("title"),
                    "workspace": .string("w"),
                    "during-aerospace-startup": .bool(true),
                ]),
                "check-further-callbacks": .bool(false),
                "commands": .string("layout floating"),
            ]),
            .dict([
                "matcher": .dict(["app-id": .string(#"com."bar""#)]),
                "check-further-callbacks": .bool(true),
                "commands": .string("layout floating; focus left"),
            ]),
        ])
    }

    @Test
    func testWorkspaceToMonitorAssignmentOfWrongType() {
        let result = parseConfig(
            """
            [workspace-to-monitor-force-assignment]
                w = true
                x = [1, false, 'main']
                y = []
            """,
        )
        expectEqual(result.strErrors, [
            "[ERROR] workspace-to-monitor-force-assignment.w: Expected types are 'String' or 'Int'. But actual type is 'Bool'",
            "[ERROR] workspace-to-monitor-force-assignment.x[1]: Expected types are 'String' or 'Int'. But actual type is 'Bool'",
        ])
        // A workspace with an unusable pattern isn't force-assigned. Neither is one with an empty array, which is no error
        expectEqual(result.config.workspaceToMonitorForceAssignment, ["y": []])
    }

    @Test
    func testUnsupportedTomlTypes() {
        expectEqual(parseConfig("a = [1.0]").strErrors, ["[ERROR] a[0]: Unsupported TOML type: Double", "[ERROR] a: Unknown top-level key"])
        expectEqual(
            parseConfig("b = 1.0\na = [{ c = 1.0 }, [2.0, 3]]").strErrors,
            [
                "[ERROR] a[0].c: Unsupported TOML type: Double",
                "[ERROR] a[1][0]: Unsupported TOML type: Double",
                "[ERROR] b: Unsupported TOML type: Double",
                "[ERROR] a: Unknown top-level key",
            ],
        )
        expectEqual(parseConfig("a = 07:32:00").strErrors, ["[ERROR] a: Unsupported TOML type: LocalTime"])
        expectEqual(parseConfig("a = 1979-05-27T07:32:00").strErrors, ["[ERROR] a: Unsupported TOML type: LocalDateTime"])
        expectEqual(parseConfig("a = 1979-05-27T07:32:00Z").strErrors, ["[ERROR] a: Unsupported TOML type: OffsetDateTime"])
        // The array keeps the supported elements: 'exec-on-workspace-change' gets ['x']
        let result = parseConfig("exec-on-workspace-change = [1.0, 'x']")
        expectEqual(result.strErrors, ["[ERROR] exec-on-workspace-change[0]: Unsupported TOML type: Double"])
        expectEqual(result.config.execOnWorkspaceChange, ["x"])
    }

    @Test
    func testErrorOrderOfTomlConversionAndKeys() {
        let result = parseConfig(
            """
            b = 1
            a = 0
            z = 1.0
            """,
        )
        expectEqual(result.strErrors, [
            "[ERROR] z: Unsupported TOML type: Double",
            "[ERROR] a: Unknown top-level key", // Sorted
            "[ERROR] b: Unknown top-level key", // 'z' is dropped
        ])
    }

    @Test
    func testInvalidCommandInConfig() {
        let focusHelp = CmdKind.focus.help
        expectEqual(parseCommand("focus --help").helpOrNil, focusHelp)
        let result = parseConfig(
            """
            [mode.main.binding]
                alt-h = 'focus --help'
                alt-j = 'bogus'
                alt-k = 'focus left'
                alt-l = 'focus foo'
            """,
        )
        expectEqual(result.strErrors, [
            "[ERROR] mode.main.binding.alt-h: \(focusHelp)",
            "[ERROR] mode.main.binding.alt-j: Unrecognized subcommand 'bogus'",
            "[ERROR] mode.main.binding.alt-l: Can't parse 'foo'.\nPossible values: (left|down|up|right|dfs-next|dfs-prev)",
        ])
        // A binding with an invalid command is dropped
        expectEqual(result.config.modes[mainModeId]?.bindings.keys.sorted(), ["alt-k"])
        expectEqual(parseConfig("on-focus-changed = ['bogus', 'focus --help']").strErrors, ["[ERROR] on-focus-changed[0]: Unrecognized subcommand 'bogus'", "[ERROR] on-focus-changed[1]: \(focusHelp)"])
    }

    @Test
    func testCommandArrayWithBadElementIsDropped() {
        let result = parseConfig(
            """
            on-focus-changed = ['focus left', 1]
            [mode.main.binding]
                alt-a = ['focus left', 1, 'bogus']
            """,
        )
        expectEqual(result.strErrors, [
            "[ERROR] on-focus-changed[1]: Expected type is 'String'. But actual type is 'Int'",
            "[ERROR] mode.main.binding.alt-a[1]: Expected type is 'String'. But actual type is 'Int'",
            "[ERROR] mode.main.binding.alt-a[2]: Unrecognized subcommand 'bogus'",
        ])
        expectEqual(result.config.modes[mainModeId]?.bindings.isEmpty, true)
        #expect(result.config.onFocusChanged.flatten().isEmpty)
    }
}
