@testable import AppBundle
import Common
import Testing

@Suite
struct ConfigErrorsTest {
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


    @Test(.aeroSpaceGlobalState) // Resolves the patterns against the monitors
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


    /// A per-monitor value with an unusable rule keeps the default. Only `inner.horizontal` is ever usable in these rows
    @Test(arguments: [
        (
            """
            [gaps]
                inner.vertical = true
                inner.horizontal = '5'
                outer.left = [{ monitor.main = true }, 1]
                outer.right = [{ monitor.main = 1 }, false]
                outer.top = [{ monitor.main = 1 }, '2']
            """,
            [
                "[ERROR] gaps.inner.horizontal: Expected types are 'Int' or 'Array'. But actual type is 'String'",
                "[ERROR] gaps.inner.vertical: Expected types are 'Int' or 'Array'. But actual type is 'Bool'",
                "[ERROR] gaps.outer.left[0].monitor.main: Expected type is 'Int'. But actual type is 'Bool'",
                "[ERROR] gaps.outer.right: The last item in the array must be of type Int",
                "[ERROR] gaps.outer.top: The last item in the array must be of type Int",
            ],
            0,
        ),
        (
            """
            [gaps]
                inner.vertical = []
                inner.horizontal = [1]
                outer.left = [1, 2]
                outer.right = [{ monitor.0 = 1 }, { monitor.main = 2 }, 3]
            """,
            [
                "[ERROR] gaps.inner.vertical: The array must not be empty",
                "[ERROR] gaps.outer.left[0]: Expected type is 'Table'. But actual type is 'Int'",
                "[ERROR] gaps.outer.right[0].monitor.0: Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal",
            ],
            1,
        ),
        (
            """
            [gaps]
                inner.horizontal = [true]
                inner.vertical = [{ foo.main = 1 }, { monitor = { foo = 2, bar = 3 } }, 1]
            """,
            [
                "[ERROR] gaps.inner.horizontal: The last item in the array must be of type Int",
                "[ERROR] gaps.inner.vertical[0]: The table is expected to have a single key 'monitor'",
                "[ERROR] gaps.inner.vertical[1].monitor: The table is expected to have a single key",
            ],
            0,
        ),
    ] as [(String, [String], Int)])
    func gapErrors(toml: String, errors: [String], innerHorizontal: Int) {
        let result = parseConfig(toml)
        expectEqual(result.strErrors, errors)
        var expected = Gaps.zero
        expected.inner.horizontal = .constant(innerHorizontal)
        expectEqual(result.config.gaps, expected)
    }

    @Test(arguments: [
        // A table of the wrong type, or an unknown key, for each table decoder
        ("gaps.inner = 1", ["[ERROR] gaps.inner: Expected type is 'Table'. But actual type is 'Int'"]),
        ("focus-follows-mouse.foo = true", ["[ERROR] focus-follows-mouse.foo: Unknown key"]),
        ("mode = 1", ["[ERROR] mode: Expected type is 'Table'. But actual type is 'Int'"]),
        ("mode.main = 1", ["[ERROR] mode.main: Expected type is 'Table'. But actual type is 'Int'"]),
        ("mode.main.binding = 1", ["[ERROR] mode.main.binding: Expected type is 'Table'. But actual type is 'Int'"]),
        ("key-mapping = 1", ["[ERROR] key-mapping: Expected type is 'Table'. But actual type is 'Int'"]),
        ("exec = 1", ["[ERROR] exec: Expected type is 'Table'. But actual type is 'Int'"]),
        ("exec.env-vars = 1", ["[ERROR] exec.env-vars: Expected type is 'Table'. But actual type is 'Int'"]),
        ("workspace-to-monitor-force-assignment = 1", ["[ERROR] workspace-to-monitor-force-assignment: Expected type is 'Table'. But actual type is 'Int'"]),
        ("on-window-detected = 1", ["[ERROR] on-window-detected: Expected type is 'Array'. But actual type is 'Int'"]),
        ("on-window-detected = [1]", ["[ERROR] on-window-detected[0]: Expected type is 'Table'. But actual type is 'Int'"]),
        // Scalars
        ("enable-normalization-flatten-containers = 'true'", ["[ERROR] enable-normalization-flatten-containers: Expected type is 'Bool'. But actual type is 'String'"]),
        ("accordion-padding = true", ["[ERROR] accordion-padding: Expected type is 'Int'. But actual type is 'Bool'"]),
        ("on-focus-changed = 1", ["[ERROR] on-focus-changed: Expected types are 'String' or 'Array'. But actual type is 'Int'"]),
        ("exec-on-workspace-change = ['', 1]", ["[ERROR] exec-on-workspace-change[1]: Expected type is 'String'. But actual type is 'Int'"]),
        ("default-root-container-layout = 'list'", ["[ERROR] default-root-container-layout: Can't parse layout 'list'"]), // The old name of 'tiles'
        ("default-root-container-orientation = 'diagonal'", ["[ERROR] default-root-container-orientation: Can't parse default container orientation 'diagonal'"]),
        // Window rule matchers
        ("on-window-detected = [{ if.foo = 'x', run = 'focus left' }]", ["[ERROR] on-window-detected[0].if.foo: Unknown key"]),
        ("on-window-detected = [{ if = 1, run = '' }]", ["[ERROR] on-window-detected[0].if: Expected type is 'String'. But actual type is 'Int'"]),
        ("on-window-detected = [{ if = 'foo', run = '' }]", ["[ERROR] on-window-detected[0].if: Unrecognized subcommand 'foo'"]),
        // TOML types that no key accepts. Conversion errors come first, then the key errors in key order
        ("a = [1.0]", ["[ERROR] a[0]: Unsupported TOML type: Double", "[ERROR] a: Unknown top-level key"]),
        ("b = 1.0\na = [{ c = 1.0 }, [2.0, 3]]", [
            "[ERROR] a[0].c: Unsupported TOML type: Double",
            "[ERROR] a[1][0]: Unsupported TOML type: Double",
            "[ERROR] b: Unsupported TOML type: Double",
            "[ERROR] a: Unknown top-level key",
        ]),
        ("foo.bar = 1979-05-27", ["[ERROR] foo.bar: Unsupported TOML type: LocalDate", "[ERROR] foo: Unknown top-level key"]),
        ("a = 07:32:00", ["[ERROR] a: Unsupported TOML type: LocalTime"]),
        ("a = 1979-05-27T07:32:00", ["[ERROR] a: Unsupported TOML type: LocalDateTime"]),
        ("a = 1979-05-27T07:32:00Z", ["[ERROR] a: Unsupported TOML type: OffsetDateTime"]),
        ("b = 1\na = 0\nz = 1.0", [
            "[ERROR] z: Unsupported TOML type: Double",
            "[ERROR] a: Unknown top-level key",
            "[ERROR] b: Unknown top-level key", // 'z' is dropped, so it isn't also unknown
        ]),
    ] as [(String, [String])])
    func typeErrors(toml: String, errors: [String]) {
        expectEqual(parseConfig(toml).strErrors, errors)
    }

    /// An error drops only its own value. The elements of a collection are independent: a bad one is dropped
    @Test
    func anErrorDropsOnlyItsValue() {
        let result = parseConfig(
            """
            unknownKey = true
            accordion-padding = 7
            exec-on-workspace-change = [1.0, 'x']
            [workspace-to-monitor-force-assignment]
                w = true
                x = [1, false, 'main']
                y = []
            """,
        )
        expectEqual(result.strErrors, [
            "[ERROR] exec-on-workspace-change[0]: Unsupported TOML type: Double",
            "[ERROR] unknownKey: Unknown top-level key",
            "[ERROR] workspace-to-monitor-force-assignment.w: Expected types are 'String' or 'Int'. But actual type is 'Bool'",
            "[ERROR] workspace-to-monitor-force-assignment.x[1]: Expected types are 'String' or 'Int'. But actual type is 'Bool'",
        ])
        expectEqual(result.config.accordionPadding, 7)
        // The conversion drops the unsupported element before the array is decoded
        expectEqual(result.config.execOnWorkspaceChange, ["x"])
        // A workspace with an unusable pattern isn't force-assigned. Neither is one with an empty array, which is no error
        expectEqual(result.config.workspaceToMonitorForceAssignment, ["y": []])
    }

    /// A binding with an invalid command is dropped, and so is a callback
    @Test(arguments: [
        (
            """
            [mode.main.binding]
                alt-h = 'focus --help'
                alt-j = 'bogus'
                alt-k = 'focus left'
                alt-l = 'focus foo'
            """,
            [
                "[ERROR] mode.main.binding.alt-h: \(CmdKind.focus.help)",
                "[ERROR] mode.main.binding.alt-j: Unrecognized subcommand 'bogus'",
                "[ERROR] mode.main.binding.alt-l: Can't parse 'foo'.\nPossible values: (left|down|up|right|dfs-next|dfs-prev)",
            ],
            ["alt-k"], "",
        ),
        (
            "on-focus-changed = ['bogus', 'focus --help']",
            ["[ERROR] on-focus-changed[0]: Unrecognized subcommand 'bogus'", "[ERROR] on-focus-changed[1]: \(CmdKind.focus.help)"],
            [], "",
        ),
        (
            """
            on-focus-changed = ['focus left', 1]
            [mode.main.binding]
                alt-a = ['focus left', 1, 'bogus']
            """,
            [
                "[ERROR] on-focus-changed[1]: Expected type is 'String'. But actual type is 'Int'",
                "[ERROR] mode.main.binding.alt-a[1]: Expected type is 'String'. But actual type is 'Int'",
                "[ERROR] mode.main.binding.alt-a[2]: Unrecognized subcommand 'bogus'",
            ],
            [], "",
        ),
    ] as [(String, [String], [String], String)])
    func commandErrors(toml: String, errors: [String], bindings: [String], onFocusChanged: String) {
        let result = parseConfig(toml)
        expectEqual(result.strErrors, errors)
        expectEqual(result.config.modes[mainModeId]?.bindings.keys.sorted() ?? [], bindings)
        expectEqual(result.config.onFocusChanged.shellOfCommandsDescription, onFocusChanged)
    }
}
