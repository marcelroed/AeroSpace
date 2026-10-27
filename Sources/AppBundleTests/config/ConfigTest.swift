@testable import AppBundle
import Common
import Testing

@Suite
struct ConfigTest {
    @Test
    func testParseI3Config() throws {
        let toml = try String(contentsOf: projectRoot.appending(component: "docs/config-examples/i3-like-config-example.toml"), encoding: .utf8)
        let result = parseConfig(toml)
        #expect(result.errors == [])
        #expect(result.config.execConfig == defaultConfig.execConfig)
        #expect(result.config.enableNormalizationFlattenContainers == false)
        #expect(result.config.enableNormalizationOppositeOrientationForNestedContainers == false)
    }

    @Test
    func testEmptyConfig() {
        let result = parseConfig("")
        #expect(result.errors == [])
        #expect(result.allowReloadConfig)
        #expect(result.config.persistentWorkspaces == [])
    }

    @Test
    func testParseDefaultConfig() throws {
        let toml = try String(contentsOf: projectRoot.appending(component: "docs/config-examples/default-config.toml"), encoding: .utf8)
        let result = parseConfig(toml)
        #expect(result.errors == [])
    }

    @Test
    func testExecOnWorkspaceChangeDifferentTypesError() {
        let errors = parseConfig("exec-on-workspace-change = ['', 1]").strErrors
        #expect(errors == ["[ERROR] exec-on-workspace-change[1]: Expected type is \'String\'. But actual type is \'Int\'"])
    }

    @Test
    func testDuplicatedPersistentWorkspaces() {
        let errors = parseConfig(
            "persistent-workspaces = ['a', 'a']",
        ).strErrors
        #expect(errors == ["[ERROR] persistent-workspaces: Contains duplicated workspace names"])
    }

    @Test
    func testPersistentWorkspaces() {
        let result = parseConfig("persistent-workspaces = ['b', 'a']")
        #expect(result.errors == [])
        #expect(result.config.persistentWorkspaces == ["b", "a"])
    }

    /// The removed legacy keys are unknown keys now
    @Test
    func testLegacyKeysAreUnknown() {
        let result = parseConfig(
            """
            config-version = 2
            after-login-command = []
            non-empty-workspaces-root-containers-layout-on-startup = 'smart'
            indent-for-nested-containers-with-the-same-orientation = 30
            """,
        )
        #expect(result.allowReloadConfig)
        #expect(result.strErrors == [
            "[ERROR] after-login-command: Unknown top-level key",
            "[ERROR] config-version: Unknown top-level key",
            "[ERROR] indent-for-nested-containers-with-the-same-orientation: Unknown top-level key",
            "[ERROR] non-empty-workspaces-root-containers-layout-on-startup: Unknown top-level key",
        ])
    }

    @Test
    func testWrongTypeForCommand() {
        let errors = parseConfig(
            """
            [mode.main.binding]
                alt-a = [1, 'focus right']
            """,
        ).strErrors
        #expect(errors == ["[ERROR] mode.main.binding.alt-a[0]: Expected type is \'String\'. But actual type is \'Int\'"])
    }

    @Test
    func testDropBindings() {
        let result = parseConfig("mode.main = {}")
        #expect(result.allowReloadConfig)
        #expect(result.errors == [])
        #expect(result.config.modes[mainModeId]?.bindings.isEmpty == true)
    }

    @Test
    func testParseMode() {
        let result = parseConfig(
            """
            [mode.main.binding]
                alt-h = 'focus left'
            """,
        )
        #expect(result.errors == [])
        let binding = HotkeyBinding(.option, .h, .cmd(FocusCommand.new(direction: .left)))
        #expect(result.config.modes[mainModeId] == Mode(bindings: [binding.descriptionWithKeyCode: binding]))
    }

    @Test
    func testModesMustContainDefaultModeError() {
        let result = parseConfig(
            """
            [mode.foo.binding]
                alt-h = 'focus left'
            """,
        )
        #expect(result.strErrors == ["[ERROR] mode: Please specify \'main\' mode"])
        #expect(result.config.modes[mainModeId] == nil)
    }

    @Test
    func testHotkeyParseError() {
        let result = parseConfig(
            """
            [mode.main.binding]
                alt-hh = 'focus left'
                aalt-j = 'focus down'
                alt-k = 'focus up'
            """,
        )
        #expect(
            result.strErrors == [
                "[ERROR] mode.main.binding.aalt-j: Can\'t parse modifiers in \'aalt-j\' binding",
                "[ERROR] mode.main.binding.alt-hh: Can\'t parse the key in \'alt-hh\' binding",
            ],
        )
        let binding = HotkeyBinding(.option, .k, .cmd(FocusCommand.new(direction: .up)))
        #expect(result.config.modes[mainModeId] == Mode(bindings: [binding.descriptionWithKeyCode: binding]))
    }

    @Test
    func testBindingsDontMakeWorkspacesPersistent() {
        let result = parseConfig(
            """
            [mode.main.binding]
                alt-1 = 'workspace 1'
                alt-2 = 'workspace 2'
                alt-3 = ['workspace 3']
                alt-4 = ['workspace 4', 'focus left']
            """,
        )
        #expect(result.errors == [])
        #expect(result.config.persistentWorkspaces == [])
    }

    @Test
    func testUnknownTopLevelKeyParseError() {
        let result = parseConfig(
            """
            unknownKey = true
            enable-normalization-flatten-containers = false
            """,
        )
        #expect(result.strErrors == ["[ERROR] unknownKey: Unknown top-level key"])
        #expect(result.config.enableNormalizationFlattenContainers == false)
    }

    @Test
    func testUnknownKeyParseError() {
        let result = parseConfig(
            """
            enable-normalization-flatten-containers = false
            [gaps]
                unknownKey = true
            """,
        )
        #expect(result.strErrors == ["[ERROR] gaps.unknownKey: Unknown key"])
        #expect(result.config.enableNormalizationFlattenContainers == false)
    }

    @Test
    func testTypeMismatch() {
        let errors = parseConfig("enable-normalization-flatten-containers = 'true'").strErrors
        #expect(errors == ["[ERROR] enable-normalization-flatten-containers: Expected type is \'Bool\'. But actual type is \'String\'"])
    }

    @Test
    func testConfigParseError() {
        #expect(!parseConfig("true").allowReloadConfig)
        #expect(parseConfig("true").strErrors == ["[ERROR] (Line 1) Syntax error: missing =."])

        #expect(parseConfig("\n1").strErrors == ["[ERROR] (Line 2) Syntax error: missing =."])

        #expect(parseConfig("foo: 1").strErrors == ["[ERROR] (Line 1) Syntax error: missing =."])

        #expect(parseConfig("foo = 1.0").strErrors == ["[ERROR] foo: Unsupported TOML type: Double"])

        #expect(parseConfig("foo.bar = 1979-05-27").strErrors == ["[ERROR] foo.bar: Unsupported TOML type: LocalDate", "[ERROR] foo: Unknown top-level key"])
    }

    @Test
    func testMoveWorkspaceToMonitorCommandParsing() {
        #expect(parseCommand("move-workspace-to-monitor --wrap-around next").cmdOrNil?.flatten().singleOrNil() is MoveWorkspaceToMonitorCommand)
        #expect(parseCommand("move-workspace-to-display --wrap-around next").cmdOrNil?.flatten().singleOrNil() is MoveWorkspaceToMonitorCommand)
    }

    @Test
    func testParseTiles() throws {
        let command = try #require(parseCommand("layout tiles h_tiles v_tiles list h_list v_list").cmdOrNil?.flatten().singleOrNil() as? LayoutCommand)
        #expect(command.args.toggleBetween.val == [.tiles, .h_tiles, .v_tiles, .tiles, .h_tiles, .v_tiles])
        testParseCommandHelp("layout tiles -h")
    }

    @Test
    func testSplitCommandAndFlattenContainersNormalization() {
        let errors = parseConfig(
            """
            enable-normalization-flatten-containers = true
            [mode.main.binding]
            [mode.foo.binding]
                alt-s = 'split horizontal'
            """,
        ).strErrors
        let expected = """
            [ERROR] The config contains:
            1. usage of 'split' command
            2. enable-normalization-flatten-containers = true
            These two settings don't play nicely together. 'split' command has no effect when enable-normalization-flatten-containers is enabled.

            My recommendation: keep the normalizations enabled, and prefer 'join-with' over 'split'.
            """
        #expect(errors == [expected])
    }

    @Test
    func testParseWorkspaceToMonitorAssignment() {
        let result = parseConfig(
            """
            [workspace-to-monitor-force-assignment]
                workspace_name_1 = 1                            # Sequence number of the monitor (from left to right, 1-based indexing)
                workspace_name_2 = 'main'                       # main monitor
                workspace_name_3 = 'secondary'                  # non-main monitor (in case when there are only two monitors)
                workspace_name_4 = 'built-in'                   # case insensitive regex substring
                workspace_name_5 = '^built-in retina display$'  # case insensitive regex match
                workspace_name_6 = ['secondary', 1]             # you can specify multiple patterns. The first matching pattern will be used
                7 = "foo"
                w7 = ['', 'main']
                w8 = 0
                workspace_name_x = '2'                          # Sequence number of the monitor (from left to right, 1-based indexing)
            """,
        )
        #expect(
            result.config.workspaceToMonitorForceAssignment == [
                "workspace_name_1": [.sequenceNumber(1)],
                "workspace_name_2": [.main],
                "workspace_name_3": [.secondary],
                "workspace_name_4": [.pattern("built-in")!],
                "workspace_name_5": [.pattern("^built-in retina display$")!],
                "workspace_name_6": [.secondary, .sequenceNumber(1)],
                "workspace_name_x": [.sequenceNumber(2)],
                "7": [.pattern("foo")!],
                "w7": [.main],
                "w8": [],
            ],
        )
        #expect(result.strErrors == [
            "[ERROR] workspace-to-monitor-force-assignment.w7[0]: Empty string is an illegal monitor description",
            "[ERROR] workspace-to-monitor-force-assignment.w8: Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal",
        ])
        #expect(defaultConfig.workspaceToMonitorForceAssignment == [:])
    }

    @Test
    func testParseOnWindowDetected() {
        let result = parseConfig(
            """
            on-window-detected = [
                { # 0
                    if = 'true',
                    check-further-callbacks = true,
                    run = ['layout floating', 'move-node-to-workspace W'],
                },
                { # 1
                    if.app-id = 'com.apple.systempreferences',
                    run = [],
                },
                {}, # 2
                { # 3
                    if = 'true', run = ['move-node-to-workspace S', 'layout tiling'],
                },
                { # 4
                    if = 'true', run = ['move-node-to-workspace S', 'move-node-to-workspace W'],
                },
                { # 5
                    if = 'true', run = ['move-node-to-workspace S', 'layout h_tiles'],
                },
                { # 6
                    if = 'test %{app-bundle-id} = org.alacritty',
                    run = ['move-node-to-workspace T'],
                },
                { if = '', run = ''}, # 7
            ]
            """,
        )
        let matcher6Args = TestCmdArgs(rawArgs: [])
            .copy(\.lhs, .initialized(.app(.appBundleId)))
            .copy(\.infixOperator, .initialized(.equals))
            .copy(\.rhs, .initialized("org.alacritty"))
        #expect(result.config.onWindowDetected == [
            WindowDetectedCallback( // 0
                matcher: .command(.cmd(TrueCommand.instance)),
                checkFurtherCallbacks: true,
                run: .seq([
                    .cmd(LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [.floating]))),
                    .cmd(MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "W"))),
                ]),
            ),
            WindowDetectedCallback( // 1
                matcher: .legacy(LegacyWindowDetectedCallbackMatcher(
                    appId: "com.apple.systempreferences",
                )),
                run: .empty,
            ),
            WindowDetectedCallback( // 3
                matcher: .command(.cmd(TrueCommand.instance)),
                run: .seq([
                    .cmd(MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "S"))),
                    .cmd(LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [.tiling]))),
                ]),
            ),
            WindowDetectedCallback( // 4
                matcher: .command(.cmd(TrueCommand.instance)),
                run: .seq([
                    .cmd(MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "S"))),
                    .cmd(MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "W"))),
                ]),
            ),
            WindowDetectedCallback( // 5
                matcher: .command(.cmd(TrueCommand.instance)),
                run: .seq([
                    .cmd(MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "S"))),
                    .cmd(LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [.h_tiles]))),
                ]),
            ),
            WindowDetectedCallback( // 6
                matcher: .command(.cmd(TestCommand(args: matcher6Args))),
                run: .cmd(MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "T"))),
            ),
        ])

        #expect(result.strErrors == [
            "[ERROR] on-window-detected[2]: Omitting \'if\' is error prone. You can use `if = \'true\'` to preserve the previous behavior.\nBut heads up! You may have missed \'check-further-callbacks = true\'",
            "[ERROR] on-window-detected[2]: \'run\' is mandatory key",
            "[ERROR] on-window-detected[7]: Omitting \'if\' is error prone. You can use `if = \'true\'` to preserve the previous behavior.\nBut heads up! You may have missed \'check-further-callbacks = true\'",
        ])
    }

    @Test
    func testParseOnWindowDetected2() {
        let result = parseConfig(
            """
            on-window-detected = [
                { check-further-callbacks = true, run = '', },
            ]
            """,
        )
        #expect(result.config.onWindowDetected == [
            WindowDetectedCallback(
                matcher: .command(.empty),
                checkFurtherCallbacks: true,
                run: .empty,
            ),
        ])

        #expect(result.errors == [])
    }

    @Test
    func testParseInlineTables() {
        let errors = parseConfig(
            """
            on-window-detected = [
                {
                    check-further-callbacks = true,
                    run = ['layout floating', 'move-node-to-workspace W'],
                },
                {
                    if.app-id = 'com.apple.systempreferences',
                    run = [],
                }
            ]
            """,
        ).errors
        #expect(errors == [])
    }

    @Test
    func testTomlParser() {
        // https://github.com/nikitabobko/AeroSpace/issues/1064
        let errors = parseConfig(
            """
            [[[on-window-detected]]
            if.app-id = 'com.apple.findmy'
            run = 'layout floating'

            [on-window-detected]]
            if.app-id = 'com.openai.chat'
            run = 'layout floating'
            """,
        ).strErrors
        #expect(errors == ["[ERROR] (Line 1) Syntax error: invalid or missing key."])
    }

    @Test
    func testParseOnWindowDetectedRegex() throws {
        let result = parseConfig(
            """
            [[on-window-detected]]
                if.app-name-regex-substring = '^system settings$'
                run = []
            """,
        )
        let expected = WindowDetectedCallbackMatcher.legacy(LegacyWindowDetectedCallbackMatcher(appNameRegexSubstring: .new("^system settings$").getOrDie()))
        #expect(try #require(result.config.onWindowDetected.singleOrNil()).matcher == expected)
        #expect(result.errors == [])
    }

    @Test
    func testRegex() {
        #expect("System Settings".contains(caseInsensitiveRegex: CaseInsensitiveRegex.new("settings").getOrDie()))
        #expect(!"System Settings".contains(caseInsensitiveRegex: CaseInsensitiveRegex.new("^settings^").getOrDie()))
    }

    @Test
    func testParseGaps() {
        let result1 = parseConfig(
            """
            [gaps]
                inner.horizontal = 10
                inner.vertical = [{ monitor."main" = 1 }, { monitor."secondary" = 2 }, 5]
                outer.left = 12
                outer.bottom = 13
                outer.top = [{ monitor."built-in" = 3 }, { monitor."secondary" = 4 }, 6]
                outer.right = [{ monitor.2 = 7 }, 8]
            """,
        )
        #expect(result1.errors == [])
        #expect(
            result1.config.gaps == Gaps(
                inner: .init(
                    vertical: .perMonitor(
                        [PerMonitorValue(description: .main, value: 1), PerMonitorValue(description: .secondary, value: 2)],
                        default: 5,
                    ),
                    horizontal: .constant(10),
                ),
                outer: .init(
                    left: .constant(12),
                    bottom: .constant(13),
                    top: .perMonitor(
                        [
                            PerMonitorValue(description: .pattern("built-in")!, value: 3),
                            PerMonitorValue(description: .secondary, value: 4),
                        ],
                        default: 6,
                    ),
                    right: .perMonitor([PerMonitorValue(description: .sequenceNumber(2), value: 7)], default: 8),
                ),
            ),
        )

        let result2 = parseConfig(
            """
            [gaps]
                inner.horizontal = [true]
                inner.vertical = [{ foo.main = 1 }, { monitor = { foo = 2, bar = 3 } }, 1]
            """,
        )
        #expect(result2.strErrors == [
            "[ERROR] gaps.inner.horizontal: The last item in the array must be of type Int",
            "[ERROR] gaps.inner.vertical[0]: The table is expected to have a single key \'monitor\'",
            "[ERROR] gaps.inner.vertical[1].monitor: The table is expected to have a single key",
        ])
    }

    @Test
    func testOnFocusChangedAsSingleStringAndAsList() {
        let result = parseConfig(
            """
            on-focus-changed = 'focus left'
            on-mode-changed = ['focus right', 'focus up']
            on-focused-monitor-changed = 'focus down'
            """,
        )
        #expect(result.errors == [])
        #expect(result.config.onFocusChanged.flatten().count == 1)
        #expect(result.config.onFocusChanged.flatten()[0] is FocusCommand)
        #expect(result.config.onModeChanged.flatten().count == 2)
        #expect(result.config.onFocusedMonitorChanged.flatten().count == 1)
    }

    @Test
    func testOnFocusChangedTypeError() {
        let result = parseConfig("on-focus-changed = 1")
        #expect(result.strErrors == ["[ERROR] on-focus-changed: Expected types are 'String' or 'Array'. But actual type is 'Int'"])
    }

    @Test
    func testParseDefaultRootContainerLayout() {
        let result = parseConfig("default-root-container-layout = 'accordion'")
        #expect(result.errors == [])
        #expect(result.config.defaultRootContainerLayout == .accordion)

        let listResult = parseConfig("default-root-container-layout = 'list'")
        #expect(listResult.errors == [])
        #expect(listResult.config.defaultRootContainerLayout == .tiles)

        let bad = parseConfig("default-root-container-layout = 'bogus'")
        #expect(bad.strErrors == ["[ERROR] default-root-container-layout: Can\'t parse layout \'bogus\'"])
    }

    @Test
    func testParseDefaultRootContainerOrientation() {
        let result = parseConfig("default-root-container-orientation = 'vertical'")
        #expect(result.errors == [])
        #expect(result.config.defaultRootContainerOrientation == .vertical)

        let bad = parseConfig("default-root-container-orientation = 'diagonal'")
        #expect(bad.strErrors == ["[ERROR] default-root-container-orientation: Can\'t parse default container orientation \'diagonal\'"])
    }

    @Test
    func testMissingValueIsSyntaxErrorThatPreventsReload() {
        // The TOML root is always a table, so a TOML syntax error is the only way to get no root table
        let result = parseConfig("a = ")
        #expect(!result.allowReloadConfig)
        #expect(result.strErrors == ["[ERROR] (Line 1) Syntax error: syntax error."])
    }

    @Test
    func testParseKeyMapping() {
        let result = parseConfig(
            """
            [key-mapping.key-notation-to-key-code]
                q = 'q'
                unicorn = 'u'

            [mode.main.binding]
                alt-unicorn = 'workspace wonderland'
            """,
        )
        #expect(result.errors == [])
        #expect(result.config.keyMapping == KeyMapping(preset: .qwerty, rawKeyNotationToKeyCode: [
            "q": .q,
            "unicorn": .u,
        ]))
        let binding = HotkeyBinding(.option, .u, .cmd(WorkspaceCommand(args: WorkspaceCmdArgs(target: .direct(.parse("wonderland").getOrDie())))))
        #expect(result.config.modes[mainModeId]?.bindings == [binding.descriptionWithKeyCode: binding])

        let errors1 = parseConfig(
            """
            [key-mapping.key-notation-to-key-code]
                q = 'qw'
                ' f' = 'f'
            """,
        ).strErrors
        #expect(errors1 == [
            "[ERROR] key-mapping.key-notation-to-key-code: ' f' is invalid key notation",
            "[ERROR] key-mapping.key-notation-to-key-code.q: 'qw' is invalid key code",
        ])

        let dvorakResult = parseConfig("key-mapping.preset = 'dvorak'")
        #expect(dvorakResult.errors == [])
        #expect(dvorakResult.config.keyMapping == KeyMapping(preset: .dvorak, rawKeyNotationToKeyCode: [:]))
        #expect(dvorakResult.config.keyMapping.resolve()["quote"] == .q)
        let colemakResult = parseConfig("key-mapping.preset = 'colemak'")
        #expect(colemakResult.errors == [])
        #expect(colemakResult.config.keyMapping == KeyMapping(preset: .colemak, rawKeyNotationToKeyCode: [:]))
        #expect(colemakResult.config.keyMapping.resolve()["f"] == .e)
    }
}

extension ParseConfigResult {
    var strErrors: [String] {
        errors.map(\.description)
    }
}
