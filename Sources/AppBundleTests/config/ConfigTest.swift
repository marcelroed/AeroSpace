@testable import AppBundle
import Common
import Testing

@Suite
struct ConfigTest {
    @Test
    func testParseI3Config() throws {
        let toml = try String(contentsOf: projectRoot.appending(component: "docs/config-examples/i3-like-config-example.toml"), encoding: .utf8)
        let result = parseConfig(toml)
        expectEqual(result.errors, [])
        expectEqual(result.config.execConfig, defaultConfig.execConfig)
        expectEqual(result.config.enableNormalizationFlattenContainers, false)
        expectEqual(result.config.enableNormalizationOppositeOrientationForNestedContainers, false)
    }

    @Test
    func testEmptyConfig() {
        let result = parseConfig("")
        expectEqual(result.errors, [])
        #expect(!result.isFatal)
        expectEqual(result.config.persistentWorkspaces, [])
    }

    @Test
    func testParseDefaultConfig() throws {
        let toml = try String(contentsOf: projectRoot.appending(component: "docs/config-examples/default-config.toml"), encoding: .utf8)
        let result = parseConfig(toml)
        expectEqual(result.errors, [])
    }

    @Test
    func testExecOnWorkspaceChangeDifferentTypesError() {
        let errors = parseConfig("exec-on-workspace-change = ['', 1]").strErrors
        expectEqual(errors, ["[ERROR] exec-on-workspace-change[1]: Expected type is \'String\'. But actual type is \'Int\'"])
    }

    @Test
    func testDuplicatedPersistentWorkspaces() {
        let errors = parseConfig(
            "persistent-workspaces = ['a', 'a']",
        ).strErrors
        expectEqual(errors, ["[ERROR] persistent-workspaces: Contains duplicated workspace names"])
    }

    @Test
    func testPersistentWorkspaces() {
        let result = parseConfig("persistent-workspaces = ['b', 'a']")
        expectEqual(result.errors, [])
        expectEqual(result.config.persistentWorkspaces, ["b", "a"])
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
        #expect(!result.isFatal)
        expectEqual(result.strErrors, [
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
        expectEqual(errors, ["[ERROR] mode.main.binding.alt-a[0]: Expected type is \'String\'. But actual type is \'Int\'"])
    }

    @Test
    func testDropBindings() {
        let result = parseConfig("mode.main = {}")
        #expect(!result.isFatal)
        expectEqual(result.errors, [])
        expectEqual(result.config.modes[mainModeId]?.bindings.isEmpty, true)
    }

    @Test
    func testParseMode() {
        let result = parseConfig(
            """
            [mode.main.binding]
                alt-h = 'focus left'
            """,
        )
        expectEqual(result.errors, [])
        let binding = HotkeyBinding(.option, .h, .cmd(FocusCommand(target: .direction(.left))))
        expectEqual(result.config.modes[mainModeId], Mode(bindings: [binding.descriptionWithKeyCode: binding]))
    }

    @Test
    func testModesMustContainDefaultModeError() {
        let result = parseConfig(
            """
            [mode.foo.binding]
                alt-h = 'focus left'
            """,
        )
        expectEqual(result.strErrors, ["[ERROR] mode: Please specify \'main\' mode"])
        expectEqual(result.config.modes[mainModeId], nil)
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
        expectEqual(
            result.strErrors,
            [
                "[ERROR] mode.main.binding.aalt-j: Can\'t parse modifiers in \'aalt-j\' binding",
                "[ERROR] mode.main.binding.alt-hh: Can\'t parse the key in \'alt-hh\' binding",
            ],
        )
        let binding = HotkeyBinding(.option, .k, .cmd(FocusCommand(target: .direction(.up))))
        expectEqual(result.config.modes[mainModeId], Mode(bindings: [binding.descriptionWithKeyCode: binding]))
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
        expectEqual(result.errors, [])
        expectEqual(result.config.persistentWorkspaces, [])
    }

    @Test
    func testUnknownTopLevelKeyParseError() {
        let result = parseConfig(
            """
            unknownKey = true
            enable-normalization-flatten-containers = false
            """,
        )
        expectEqual(result.strErrors, ["[ERROR] unknownKey: Unknown top-level key"])
        expectEqual(result.config.enableNormalizationFlattenContainers, false)
    }

    @Test
    func testErrorPathQuotesKeysLikeToml() {
        let result = parseConfig(
            """
            'a.b' = 1
            'x"y' = 2
            gaps.outer.left = [{ monitor.'test monitor' = true }, 1]
            """,
        )
        expectEqual(result.strErrors, [
            #"[ERROR] "a.b": Unknown top-level key"#,
            #"[ERROR] gaps.outer.left[0].monitor."test monitor": Expected type is 'Int'. But actual type is 'Bool'"#,
            #"[ERROR] "x\"y": Unknown top-level key"#,
        ])
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
        expectEqual(result.strErrors, ["[ERROR] gaps.unknownKey: Unknown key"])
        expectEqual(result.config.enableNormalizationFlattenContainers, false)
    }

    @Test
    func testTypeMismatch() {
        let errors = parseConfig("enable-normalization-flatten-containers = 'true'").strErrors
        expectEqual(errors, ["[ERROR] enable-normalization-flatten-containers: Expected type is \'Bool\'. But actual type is \'String\'"])
    }

    @Test
    func testConfigParseError() {
        #expect(parseConfig("true").isFatal)
        expectEqual(parseConfig("true").strErrors, ["[ERROR] (Line 1) Syntax error: missing =."])

        expectEqual(parseConfig("\n1").strErrors, ["[ERROR] (Line 2) Syntax error: missing =."])

        expectEqual(parseConfig("foo: 1").strErrors, ["[ERROR] (Line 1) Syntax error: missing =."])

        expectEqual(parseConfig("foo = 1.0").strErrors, ["[ERROR] foo: Unsupported TOML type: Double"])

        expectEqual(parseConfig("foo.bar = 1979-05-27").strErrors, ["[ERROR] foo.bar: Unsupported TOML type: LocalDate", "[ERROR] foo: Unknown top-level key"])
    }

    @Test
    func testMoveWorkspaceToMonitorCommandParsing() {
        #expect(parseCommand("move-workspace-to-monitor --wrap-around next").cmdOrNil?.flatten().singleOrNil() is MoveWorkspaceToMonitorCommand)
        #expect(parseCommand("move-workspace-to-display --wrap-around next").cmdOrNil == nil) // The deprecated alias is gone
    }

    @Test
    func testParseTiles() throws {
        let command = try #require(parseCommand("layout tiles h_tiles v_tiles list h_list v_list").cmdOrNil?.flatten().singleOrNil() as? LayoutCommand)
        expectEqual(Array(command.toggleBetween), [.tiles, .h_tiles, .v_tiles, .tiles, .h_tiles, .v_tiles])
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
        expectEqual(errors, [expected])
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
        expectEqual(
            result.config.workspaceToMonitorForceAssignment,
            [
                "workspace_name_1": [.sequenceNumber(1)],
                "workspace_name_2": [.main],
                "workspace_name_3": [.secondary],
                "workspace_name_4": [.pattern("built-in")],
                "workspace_name_5": [.pattern("^built-in retina display$")],
                "workspace_name_6": [.secondary, .sequenceNumber(1)],
                "workspace_name_x": [.sequenceNumber(2)],
                "7": [.pattern("foo")],
            ],
        )
        expectEqual(result.strErrors, [
            "[ERROR] workspace-to-monitor-force-assignment.w7[0]: Empty string is an illegal monitor description",
            "[ERROR] workspace-to-monitor-force-assignment.w8: Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal",
        ])
        expectEqual(defaultConfig.workspaceToMonitorForceAssignment, [:])
    }

    @Test
    func testParseOnWindowDetected() throws {
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
        expectEqual(result.config.onWindowDetected, [
            WindowDetectedCallback( // 0
                matcher: .command(.cmd(TrueCommand())),
                checkFurtherCallbacks: true,
                run: .seq([
                    .cmd(LayoutCommand(toggleBetween: NonEmptyArray(.floating))),
                    .cmd(MoveNodeToWorkspaceCommand(target: .direct(try .parse("W")))),
                ]),
            ),
            WindowDetectedCallback( // 1
                matcher: .legacy(LegacyWindowDetectedCallbackMatcher(
                    appId: "com.apple.systempreferences",
                )),
                run: .empty,
            ),
            WindowDetectedCallback( // 3
                matcher: .command(.cmd(TrueCommand())),
                run: .seq([
                    .cmd(MoveNodeToWorkspaceCommand(target: .direct(try .parse("S")))),
                    .cmd(LayoutCommand(toggleBetween: NonEmptyArray(.tiling))),
                ]),
            ),
            WindowDetectedCallback( // 4
                matcher: .command(.cmd(TrueCommand())),
                run: .seq([
                    .cmd(MoveNodeToWorkspaceCommand(target: .direct(try .parse("S")))),
                    .cmd(MoveNodeToWorkspaceCommand(target: .direct(try .parse("W")))),
                ]),
            ),
            WindowDetectedCallback( // 5
                matcher: .command(.cmd(TrueCommand())),
                run: .seq([
                    .cmd(MoveNodeToWorkspaceCommand(target: .direct(try .parse("S")))),
                    .cmd(LayoutCommand(toggleBetween: NonEmptyArray(.h_tiles))),
                ]),
            ),
            WindowDetectedCallback( // 6
                matcher: .command(.cmd(TestCommand(negated: false, lhs: .appBundleId, infixOperator: .equals, rhs: "org.alacritty"))),
                run: .cmd(MoveNodeToWorkspaceCommand(target: .direct(try .parse("T")))),
            ),
        ])

        expectEqual(result.strErrors, [
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
        expectEqual(result.config.onWindowDetected, [
            WindowDetectedCallback(
                matcher: .command(.empty),
                checkFurtherCallbacks: true,
                run: .empty,
            ),
        ])

        expectEqual(result.errors, [])
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
        expectEqual(errors, [])
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
        expectEqual(errors, ["[ERROR] (Line 1) Syntax error: invalid or missing key."])
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
        let expected = WindowDetectedCallbackMatcher.legacy(LegacyWindowDetectedCallbackMatcher(appNameRegexSubstring: try CaseInsensitiveRegex("^system settings$")))
        try expectEqual(#require(result.config.onWindowDetected.singleOrNil()).matcher, expected)
        expectEqual(result.errors, [])
    }

    @Test
    func testRegex() throws {
        #expect("System Settings".contains(caseInsensitiveRegex: try CaseInsensitiveRegex("settings")))
        #expect(!"System Settings".contains(caseInsensitiveRegex: try CaseInsensitiveRegex("^settings^")))
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
        expectEqual(result1.errors, [])
        expectEqual(
            result1.config.gaps,
            Gaps(
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
                            PerMonitorValue(description: .pattern("built-in"), value: 3),
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
        expectEqual(result2.strErrors, [
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
        expectEqual(result.errors, [])
        expectEqual(result.config.onFocusChanged.flatten().count, 1)
        #expect(result.config.onFocusChanged.flatten()[0] is FocusCommand)
        expectEqual(result.config.onModeChanged.flatten().count, 2)
        expectEqual(result.config.onFocusedMonitorChanged.flatten().count, 1)
    }

    @Test
    func testOnFocusChangedTypeError() {
        let result = parseConfig("on-focus-changed = 1")
        expectEqual(result.strErrors, ["[ERROR] on-focus-changed: Expected types are 'String' or 'Array'. But actual type is 'Int'"])
    }

    @Test
    func testParseDefaultRootContainerLayout() {
        let result = parseConfig("default-root-container-layout = 'accordion'")
        expectEqual(result.errors, [])
        expectEqual(result.config.defaultRootContainerLayout, .accordion)

        // 'list' was the old name of 'tiles'
        expectEqual(parseConfig("default-root-container-layout = 'list'").strErrors, ["[ERROR] default-root-container-layout: Can't parse layout 'list'"])

        let bad = parseConfig("default-root-container-layout = 'bogus'")
        expectEqual(bad.strErrors, ["[ERROR] default-root-container-layout: Can\'t parse layout \'bogus\'"])
    }

    @Test
    func testParseDefaultRootContainerOrientation() {
        let result = parseConfig("default-root-container-orientation = 'vertical'")
        expectEqual(result.errors, [])
        expectEqual(result.config.defaultRootContainerOrientation, .vertical)

        let bad = parseConfig("default-root-container-orientation = 'diagonal'")
        expectEqual(bad.strErrors, ["[ERROR] default-root-container-orientation: Can\'t parse default container orientation \'diagonal\'"])
    }

    @Test
    func testMissingValueIsSyntaxErrorThatPreventsReload() {
        // The TOML root is always a table, so a TOML syntax error is the only way to get no root table
        let result = parseConfig("a = ")
        #expect(result.isFatal)
        expectEqual(result.strErrors, ["[ERROR] (Line 1) Syntax error: syntax error."])
    }

    @Test
    func testParseKeyMapping() throws {
        let result = parseConfig(
            """
            [key-mapping.key-notation-to-key-code]
                q = 'q'
                unicorn = 'u'

            [mode.main.binding]
                alt-unicorn = 'workspace wonderland'
            """,
        )
        expectEqual(result.errors, [])
        expectEqual(result.config.keyMapping, KeyMapping(preset: .qwerty, rawKeyNotationToKeyCode: [
            "q": .q,
            "unicorn": .u,
        ]))
        let binding = HotkeyBinding(.option, .u, .cmd(WorkspaceCommand(target: .direct(try .parse("wonderland")))))
        expectEqual(result.config.modes[mainModeId]?.bindings, [binding.descriptionWithKeyCode: binding])

        let errors1 = parseConfig(
            """
            [key-mapping.key-notation-to-key-code]
                q = 'qw'
                ' f' = 'f'
            """,
        ).strErrors
        expectEqual(errors1, [
            "[ERROR] key-mapping.key-notation-to-key-code.\" f\": ' f' is invalid key notation",
            "[ERROR] key-mapping.key-notation-to-key-code.q: 'qw' is invalid key code",
        ])

        let dvorakResult = parseConfig("key-mapping.preset = 'dvorak'")
        expectEqual(dvorakResult.errors, [])
        expectEqual(dvorakResult.config.keyMapping, KeyMapping(preset: .dvorak, rawKeyNotationToKeyCode: [:]))
        expectEqual(dvorakResult.config.keyMapping.resolve()["quote"], .q)
        let colemakResult = parseConfig("key-mapping.preset = 'colemak'")
        expectEqual(colemakResult.errors, [])
        expectEqual(colemakResult.config.keyMapping, KeyMapping(preset: .colemak, rawKeyNotationToKeyCode: [:]))
        expectEqual(colemakResult.config.keyMapping.resolve()["f"], .e)
    }
}

extension ParseConfigResult {
    var strErrors: [String] {
        errors.map(\.description)
    }

    var isFatal: Bool {
        if case .fatal = self { true } else { false }
    }

    var config: Config {
        if case .parsed(let config, _) = self { return config }
        Issue.record("Expected a parsed config, got \(strErrors)")
        return Config()
    }
}
