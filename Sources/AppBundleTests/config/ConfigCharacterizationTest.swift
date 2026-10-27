@testable import AppBundle
import Common
import Testing

@Suite
struct ConfigCharacterizationTest: AeroSpaceTestSuite {
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
        assertEquals(result.errors, [])
        let bindings = result.config.modes[mainModeId]?.bindings ?? [:]
        assertEquals(bindings["alt-a"]?.commands.shellOfCommandsDescription, "")
        assertEquals(bindings["alt-b"]?.commands.shellOfCommandsDescription, "workspace b")
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
        assertEquals(result.strErrors, [
            "[ERROR] gaps.inner.horizontal: Unsupported type: string, expected: Int or array",
            "[ERROR] gaps.inner.vertical: Unsupported type: bool, expected: Int or array",
            "[ERROR] gaps.outer.left[0].monitor.main: Expected type is 'Int'. But actual type is 'bool'",
            "[ERROR] gaps.outer.right: The last item in the array must be of type Int",
            "[ERROR] gaps.outer.top: The last item in the array must be of type Int",
        ])
        var expectedGaps = Gaps.zero
        expectedGaps.outer.left = .perMonitor([], default: 1)
        assertEquals(result.config.gaps, expectedGaps)
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
        assertEquals(result.errors, [])
        let gaps = ResolvedGaps(gaps: result.config.gaps, monitor: mainMonitorInfo)
        assertEquals(gaps.inner.horizontal, 2)
        assertEquals(gaps.inner.vertical, 1)
        assertEquals(gaps.outer.left, 9)
        assertEquals(gaps.outer.bottom, 12)
        assertEquals(gaps.outer.top, 6)
        assertEquals(gaps.outer.right, 7)
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
        assertEquals(result.strErrors, [
            "[ERROR] gaps.inner.horizontal: The array must contain at least one monitor pattern",
            "[ERROR] gaps.inner.vertical: The array must not be empty",
            "[ERROR] gaps.outer.left[0]: Expected type is 'Table'. But actual type is 'Int'",
            "[ERROR] gaps.outer.right[0].monitor.0: Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal",
        ])
        var expectedGaps = Gaps.zero
        expectedGaps.outer.left = .perMonitor([], default: 2)
        expectedGaps.outer.right = .perMonitor([PerMonitorValue(description: .main, value: 2)], default: 3)
        assertEquals(result.config.gaps, expectedGaps)
    }

    @Test
    func testNestedTablesOfWrongType() {
        assertEquals(parseConfig("gaps = 1").strErrors, ["[ERROR] gaps: Expected type is 'Table'. But actual type is 'Int'"])
        assertEquals(parseConfig("gaps.inner = 1").strErrors, ["[ERROR] gaps.inner: Expected type is 'Table'. But actual type is 'Int'"])
        assertEquals(parseConfig("gaps.outer = 'a'").strErrors, ["[ERROR] gaps.outer: Expected type is 'Table'. But actual type is 'String'"])
        assertEquals(parseConfig("gaps.inner.foo = 1").strErrors, ["[ERROR] gaps.inner.foo: Unknown key"])
        assertEquals(parseConfig("gaps.outer.foo = 1").strErrors, ["[ERROR] gaps.outer.foo: Unknown key"])
        assertEquals(parseConfig("focus-follows-mouse = 1").strErrors, ["[ERROR] focus-follows-mouse: Expected type is 'Table'. But actual type is 'Int'"])
        assertEquals(parseConfig("focus-follows-mouse.foo = true").strErrors, ["[ERROR] focus-follows-mouse.foo: Unknown key"])
        assertEquals(
            parseConfig("focus-follows-mouse.enabled = 1").strErrors,
            ["[ERROR] focus-follows-mouse.enabled: Expected type is 'Bool'. But actual type is 'Int'"],
        )
        assertEquals(parseConfig("mode = 1").strErrors, ["[ERROR] mode: Expected type is 'Table'. But actual type is 'Int'"])
        assertEquals(parseConfig("mode.main = 1").strErrors, ["[ERROR] mode.main: Expected type is 'Table'. But actual type is 'Int'"])
        assertEquals(parseConfig("mode.main.foo = 1").strErrors, ["[ERROR] mode.main.foo: Unknown key"])
        assertEquals(parseConfig("mode.main.binding = 1").strErrors, ["[ERROR] mode.main.binding: Expected type is 'Table'. But actual type is 'Int'"])
        assertEquals(parseConfig("key-mapping = 1").strErrors, ["[ERROR] key-mapping: Expected type is 'Table'. But actual type is 'Int'"])
        assertEquals(parseConfig("key-mapping.foo = 1").strErrors, ["[ERROR] key-mapping.foo: Unknown key"])
        assertEquals(parseConfig("exec = 1").strErrors, ["[ERROR] exec: Expected type is 'Table'. But actual type is 'Int'"])
        assertEquals(parseConfig("exec.foo = 1").strErrors, ["[ERROR] exec.foo: Unknown key"])
        assertEquals(parseConfig("exec.env-vars = 1").strErrors, ["[ERROR] exec.env-vars: Expected type is 'Table'. But actual type is 'Int'"])
        assertEquals(
            parseConfig("workspace-to-monitor-force-assignment = 1").strErrors,
            ["[ERROR] workspace-to-monitor-force-assignment: Expected type is 'Table'. But actual type is 'Int'"],
        )
        assertEquals(parseConfig("on-window-detected = 1").strErrors, ["[ERROR] on-window-detected: Expected type is 'Array'. But actual type is 'Int'"])
        assertEquals(parseConfig("on-window-detected = [1]").strErrors, [
            "[ERROR] on-window-detected[0]: Expected type is 'Table'. But actual type is 'Int'",
            "[ERROR] on-window-detected[0]: Omitting 'if' is error prone. You can use `if = 'true'` to preserve the previous behavior.\nBut heads up! You may have missed 'check-further-callbacks = true'",
            "[ERROR] on-window-detected[0]: 'run' is mandatory key",
        ])
    }

    @Test
    func testFocusFollowsMouse() {
        let result = parseConfig("focus-follows-mouse.enabled = true")
        assertEquals(result.errors, [])
        assertEquals(result.config.focusFollowsMouse.enabled, true)
        assertEquals(parseConfig("").config.focusFollowsMouse.enabled, false)
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
        assertEquals(result.errors, [])
        assertEquals(result.config.afterStartupCommand.flatten().count, 2)
        assertEquals(result.config.startAtLogin, false)
        assertEquals(result.config.autoReloadConfig, true)
        assertEquals(result.config.automaticallyUnhideMacosHiddenApps, true)
        assertEquals(result.config.accordionPadding, 7)
        assertEquals(result.config.enableNormalizationOppositeOrientationForNestedContainers, false)

        assertEquals(parseConfig("accordion-padding = true").strErrors, ["[ERROR] accordion-padding: Expected type is 'Int'. But actual type is 'Bool'"])
        assertEquals(parseConfig("auto-reload-config = 1").strErrors, ["[ERROR] auto-reload-config: Expected type is 'Bool'. But actual type is 'Int'"])
        assertEquals(
            parseConfig("after-startup-command = true").strErrors,
            ["[ERROR] after-startup-command: Expected types are 'string' or 'array'. But actual type is 'bool'"],
        )
    }

    @Test
    func testOnWindowDetectedMatcherErrors() {
        assertEquals(
            parseConfig("on-window-detected = [{ if.foo = 'x', run = 'focus left' }]").strErrors,
            ["[ERROR] on-window-detected[0].if.foo: Unknown key"],
        )
        assertEquals(parseConfig("on-window-detected = [{ if = 1, run = '' }]").strErrors, [
            "[ERROR] on-window-detected[0].if: Expected type is 'String'. But actual type is 'Int'",
            "[ERROR] on-window-detected[0]: Omitting 'if' is error prone. You can use `if = 'true'` to preserve the previous behavior.\nBut heads up! You may have missed 'check-further-callbacks = true'",
        ])
        assertEquals(
            parseConfig("on-window-detected = [{ if.during-aerospace-startup = 1, run = '' }]").strErrors,
            ["[ERROR] on-window-detected[0].if.during-aerospace-startup: Expected type is 'Bool'. But actual type is 'Int'"],
        )
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
                if.app-id = 'com.bar'
                run = ['layout floating', 'focus left']
            """,
        )
        assertEquals(result.errors, [])
        assertEquals(result.config.onWindowDetected.map(\.debugJson), [
            .dict([
                "matcher": .string(#"appId="com.foo", appNameRegexSubstring="name", windowTitleRegexSubstring="title", workspace="w", duringAeroSpaceStartup=true"#),
                "commands": .string("layout floating"),
            ]),
            .dict([
                "matcher": .string(#"appId="com.bar""#),
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
            """,
        )
        assertEquals(result.strErrors, [
            "[ERROR] workspace-to-monitor-force-assignment.w: Expected types are 'string' or 'int'. But actual type is 'bool'",
            "[ERROR] workspace-to-monitor-force-assignment.x[1]: Expected types are 'string' or 'int'. But actual type is 'bool'",
        ])
        assertEquals(result.config.workspaceToMonitorForceAssignment, ["w": [], "x": [.sequenceNumber(1), .main]])
    }

    @Test
    func testUnsupportedTomlTypes() {
        assertEquals(parseConfig("a = [1.0]").strErrors, ["[ERROR] a[0]: Unsupported TOML type: Double", "[ERROR] a: Unknown top-level key"])
        assertEquals(
            parseConfig("b = 1.0\na = [{ c = 1.0 }, [2.0, 3]]").strErrors,
            [
                "[ERROR] a[0].c: Unsupported TOML type: Double",
                "[ERROR] a[1][0]: Unsupported TOML type: Double",
                "[ERROR] b: Unsupported TOML type: Double",
                "[ERROR] a: Unknown top-level key",
            ],
        )
        assertEquals(parseConfig("a = 07:32:00").strErrors, ["[ERROR] a: Unsupported TOML type: LocalTime"])
        assertEquals(parseConfig("a = 1979-05-27T07:32:00").strErrors, ["[ERROR] a: Unsupported TOML type: LocalDateTime"])
        assertEquals(parseConfig("a = 1979-05-27T07:32:00Z").strErrors, ["[ERROR] a: Unsupported TOML type: OffsetDateTime"])
        // The array keeps the supported elements: 'exec-on-workspace-change' gets ['x']
        let result = parseConfig("exec-on-workspace-change = [1.0, 'x']")
        assertEquals(result.strErrors, ["[ERROR] exec-on-workspace-change[0]: Unsupported TOML type: Double"])
        assertEquals(result.config.execOnWorkspaceChange, ["x"])
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
        assertEquals(result.strErrors, [
            "[ERROR] z: Unsupported TOML type: Double",
            "[ERROR] a: Unknown top-level key", // Sorted
            "[ERROR] b: Unknown top-level key", // 'z' is dropped
        ])
    }

    @Test
    func testInvalidCommandInConfig() {
        guard case .help(let focusHelp) = parseCommand("focus --help") else {
            Issue.record("'focus --help' must be parsed as help")
            return
        }
        let result = parseConfig(
            """
            [mode.main.binding]
                alt-h = 'focus --help'
                alt-j = 'bogus'
                alt-k = 'focus left'
            """,
        )
        assertEquals(result.strErrors, [
            "[ERROR] mode.main.binding.alt-h: \(focusHelp)",
            "[ERROR] mode.main.binding.alt-j: Unrecognized subcommand 'bogus'",
        ])
        // A binding with an invalid command is kept with an empty command
        assertEquals(result.config.modes[mainModeId]?.bindings.keys.sorted(), ["alt-h", "alt-j", "alt-k"])
        assertTrue(result.config.modes[mainModeId]?.bindings["alt-j"]?.commands.strictEquals(.empty) == true)
        assertEquals(
            parseConfig("on-focus-changed = ['bogus', 'focus --help']").strErrors,
            ["[ERROR] on-focus-changed[0]: Unrecognized subcommand 'bogus'", "[ERROR] on-focus-changed[1]: \(focusHelp)"],
        )
    }
}
