@testable import AppBundle
import Common
import Testing

@Suite
struct ConfigTest {
    /// `nil` is an empty config
    @Test(arguments: ["i3-like-config-example.toml", "default-config.toml", nil] as [String?])
    func parsesCleanly(_ example: String?) throws {
        let toml = try example.map { try String(contentsOf: configExamples.appending(component: $0), encoding: .utf8) } ?? ""
        let result = parseConfig(toml)
        #expect(!result.isFatal)
        expectEqual(result.errors, [])
    }

    /// The guide includes default-config.toml, so a key in it is in both
    @Test
    func everyKeyIsInTheDefaultConfig() throws {
        let toml = try String(contentsOf: configExamples.appending(component: "default-config.toml"), encoding: .utf8)
        let guide = try String(contentsOf: projectRoot.appending(component: "docs/guide.adoc"), encoding: .utf8)
        #expect(guide.contains("include::config-examples/default-config.toml[]"))
        for key in configFields.keys.sorted() {
            // `key = `, `key.child = `, `[key]` or `[key.child]`, also in a comment
            let assignment = try Regex(#"(^|[\s\[])"# + key + #"( =|\.|\])"#).anchorsMatchLineEndings()
            #expect(toml.contains(assignment), "Add '\(key)' to default-config.toml")
        }
    }

    @Test
    func scalarKeys() {
        let result = parseConfig(
            """
            after-startup-command = ['focus left', 'focus right']
            on-focus-changed = 'focus left'
            on-mode-changed = ['focus right', 'focus up']
            start-at-login = true
            auto-reload-config = true
            automatically-unhide-macos-hidden-apps = true
            accordion-padding = 7
            enable-normalization-flatten-containers = false
            enable-normalization-opposite-orientation-for-nested-containers = false
            default-root-container-layout = 'accordion'
            default-root-container-orientation = 'vertical'
            focus-follows-mouse.enabled = true
            """,
        )
        expectEqual(result.errors, [])
        let config = result.config
        expectEqual(config.afterStartupCommand.flatten().count, 2)
        expectEqual(config.onFocusChanged.shellOfCommandsDescription, "focus left")
        expectEqual(config.onModeChanged.flatten().count, 2)
        expectEqual(config.startAtLogin, true)
        expectEqual(config.autoReloadConfig, true)
        expectEqual(config.automaticallyUnhideMacosHiddenApps, true)
        expectEqual(config.accordionPadding, 7)
        expectEqual(config.enableNormalizationFlattenContainers, false)
        expectEqual(config.enableNormalizationOppositeOrientationForNestedContainers, false)
        expectEqual(config.defaultRootContainerLayout, .accordion)
        expectEqual(config.defaultRootContainerOrientation, .vertical)
        expectEqual(config.focusFollowsMouse.enabled, true)
    }

    @Test(arguments: [
        ("persistent-workspaces = ['b', 'a']", ["b", "a"], []),
        ("persistent-workspaces = ['a', 'a']", [], ["[ERROR] persistent-workspaces: Contains duplicated workspace names"]),
        (
            """
            [mode.main.binding]
                alt-1 = 'workspace 1'
                alt-2 = ['workspace 2', 'focus left']
            """,
            [], [], // Bindings don't make their workspaces persistent
        ),
    ] as [(String, [String], [String])])
    func persistentWorkspaces(toml: String, expected: [String], errors: [String]) {
        let result = parseConfig(toml)
        expectEqual(result.strErrors, errors)
        expectEqual(Array(result.config.persistentWorkspaces), expected)
    }

    /// No config to apply: a reload keeps the current one
    @Test(arguments: [
        ("true", "(Line 1) Syntax error: missing =."),
        ("foo: 1", "(Line 1) Syntax error: missing =."),
        ("\n1", "(Line 2) Syntax error: missing =."),
        ("a = ", "(Line 1) Syntax error: syntax error."),
        // https://github.com/nikitabobko/AeroSpace/issues/1064
        (
            """
            [[[on-window-detected]]
            if.app-id = 'com.apple.findmy'
            run = 'layout floating'

            [on-window-detected]]
            if.app-id = 'com.openai.chat'
            run = 'layout floating'
            """,
            "(Line 1) Syntax error: invalid or missing key.",
        ),
    ] as [(String, String)])
    func syntaxErrors(toml: String, fatalMessage: String) {
        let result = parseConfig(toml)
        #expect(result.isFatal)
        expectEqual(result.strErrors, ["[ERROR] " + fatalMessage])
    }

    /// A monitor is a sequence number, `main`, `secondary` or a pattern, alone or in an array of them
    @Test
    func testParseWorkspaceToMonitorAssignment() {
        let result = parseConfig(
            """
            [workspace-to-monitor-force-assignment]
                w1 = 1
                w2 = 'main'
                w3 = 'secondary'
                w4 = ['secondary', 1]
                w5 = '2'
                7 = "foo"
            """,
        )
        expectEqual(result.errors, [])
        expectEqual(result.config.workspaceToMonitorForceAssignment, [
            "w1": [.sequenceNumber(1)],
            "w2": [.main],
            "w3": [.secondary],
            "w4": [.secondary, .sequenceNumber(1)],
            "w5": [.sequenceNumber(2)],
            "7": [.pattern("foo")],
        ])
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
                { check-further-callbacks = true, run = '' }, # 8: no error, unlike 2 and 7
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
            WindowDetectedCallback( // 8
                matcher: .command(.empty),
                checkFurtherCallbacks: true,
                run: .empty,
            ),
        ])

        expectEqual(result.strErrors, [
            "[ERROR] on-window-detected[2]: Omitting \'if\' is error prone. You can use `if = \'true\'` to preserve the previous behavior.\nBut heads up! You may have missed \'check-further-callbacks = true\'",
            "[ERROR] on-window-detected[2]: \'run\' is mandatory key",
            "[ERROR] on-window-detected[7]: Omitting \'if\' is error prone. You can use `if = \'true\'` to preserve the previous behavior.\nBut heads up! You may have missed \'check-further-callbacks = true\'",
        ])
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
    }
}

private let configExamples = projectRoot.appending(component: "docs/config-examples")

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
