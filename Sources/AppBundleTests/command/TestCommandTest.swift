@testable import AppBundle
import Common
import Testing

private let possibleLhsValues = "(window-id|window-is-fullscreen|window-title|window-layout|window-parent-container-layout|workspace|" +
    "workspace-is-focused|workspace-is-visible|workspace-root-container-layout|app-bundle-id|app-name|app-pid|app-exec-path|" +
    "app-bundle-path|monitor-id|monitor-appkit-nsscreen-screens-id|monitor-name|monitor-is-main)"

@Suite(.aeroSpaceGlobalState)
struct TestCommandTest {
    @Test
    func parse() {
        testParseSingleCommandSucc("test %{app-bundle-id} = foo", TestCommand(negated: false, lhs: .appBundleId, infixOperator: .equals, rhs: "foo"))
        testParseSingleCommandSucc("test-not %{app-bundle-id} ~= foo", TestCommand(negated: true, lhs: .appBundleId, infixOperator: .matchesRegex, rhs: "foo"))

        testParseCommandFail("test %{foo} = foo", msg: "Can't parse 'foo'.\nPossible values: \(possibleLhsValues)")
        testParseCommandFail("test foo = foo", msg: "Left hand side must be a single interpolation variable")
        testParseCommandFail("test foo%{app-bundle-id} = foo", msg: "Left hand side must be a single interpolation variable")
        testParseCommandFail("test", msg: "Argument '<lhs>' is mandatory")
        testParseCommandFail("test %{app-bundle-id}", msg: "Argument '<operator>' is mandatory")
        testParseCommandFail("test %{app-bundle-id} =", msg: "Argument '<rhs>' is mandatory")
        testParseCommandFail("test foo = %{app-bundle-id}", msg: "Left hand side must be a single interpolation variable")
        testParseCommandFail("test %{app-bundle-id} = %{app-bundle-id}", msg: "Right hand side doesn't allow interpolation variables")
        testParseCommandFail("test %{newline} = foo", msg: "Can't parse 'newline'.\nPossible values: \(possibleLhsValues)")
        testParseCommandFail("test %{window-id} = %{invalid}", msg: "Right hand side doesn't allow interpolation variables")
        testParseCommandFail("test %{window-id} '!=' 1", msg: "Can't parse '!='.\nPossible values: (=|~=)")
    }

    @Test
    func parseHelpPrintsOwnUsage() {
        // test-not parses its arguments like test, but its help must still be its own (RB-11)
        for (command, expectedHelp) in [("test --help", CmdKind.test.help), ("test-not --help", CmdKind.testNot.help), ("test-not -h", CmdKind.testNot.help)] {
            #expect(parseCommand(command).helpOrNil == expectedHelp, "\(command)")
        }
        #expect(CmdKind.testNot.help.hasPrefix("USAGE: test-not "))
    }

    @Test
    func exec() async {
        setUpTree("h_tiles(*1)")
        var output = await runCmd("test %{window-id} = 1")
        #expect(output == .ok)

        output = await runCmd("test %{window-id} = 2")
        #expect(output == CmdOutput(exitCode: 1))

        output = await runCmd("test %{workspace-is-focused} = foo")
        #expect(output == .fail("Can't convert String 'foo' to Bool"))

        output = await runCmd("test %{workspace-is-focused} ~= foo")
        #expect(output == .fail("Interpolation variable: 'workspace-is-focused' has a type of Bool. The Bool type is not compatible with '~=' operator."))
    }

    @Test
    func execNoWindow() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())
        let output = await runCmd("test %{window-id} = 1")
        #expect(output == .fail("No window is focused"))
    }

    @Test
    func execWorkspaceContextSuccess() async {
        // Without a focused window, the lhs interpolation variable resolves against the workspace
        #expect(Workspace.get(byName: "a").focusWorkspace())
        let output = await runCmd("test %{workspace-is-focused} = true")
        #expect(output == .ok)
    }

    @Test
    func execWorkspaceEnvNamesAnotherWorkspace() async {
        // AEROSPACE_WORKSPACE makes the command look at its workspace, not at the focused one
        setUpTree("h_tiles(*1)", workspace: "a")
        setUpTree("h_tiles(2)", workspace: "b")
        #expect(Workspace.get(byName: "a").focusWorkspace())

        var output = await runCmd("test %{workspace} = b", workspaceEnv: "b")
        #expect(output == .ok)
        output = await runCmd("test %{workspace-is-focused} = false", workspaceEnv: "b")
        #expect(output == .ok)
        output = await runCmd("test %{window-id} = 2", workspaceEnv: "b")
        #expect(output == .ok)
        output = await runCmd("test %{workspace} = a")
        #expect(output == .ok)
    }

    @Test
    func execBoolEquals() async {
        setUpTree("h_tiles(*1)")
        var output = await runCmd("test %{workspace-is-focused} = true")
        #expect(output == .ok)

        output = await runCmd("test %{workspace-is-focused} = false")
        #expect(output == CmdOutput(exitCode: 1))
    }

    @Test
    func execIntEqualsRhsNotInt() async {
        setUpTree("h_tiles(*1)")
        let output = await runCmd("test %{window-id} = abc")
        #expect(output == .fail("Can't convert String 'abc' to Int"))
    }

    @Test
    func execIntMatchesRegexIncompatible() async {
        setUpTree("h_tiles(*1)")
        let output = await runCmd("test %{window-id} ~= 1")
        #expect(output == .fail("Interpolation variable: 'window-id' has a type of Int. The Int type is not compatible with '~=' operator."))
    }

    @Test
    func execStringEquals() async {
        setUpTree("h_tiles(*1)")
        var output = await runCmd("test %{app-bundle-id} = bobko.AeroSpace.test-app")
        #expect(output == .ok)

        output = await runCmd("test %{app-bundle-id} = other.bundle.id")
        #expect(output == CmdOutput(exitCode: 1))
    }

    @Test
    func execStringMatchesRegex() async {
        setUpTree("h_tiles(*1)")
        var output = await runCmd("test %{app-bundle-id} ~= AERO")
        #expect(output == .ok)

        output = await runCmd("test %{app-bundle-id} ~= zzzzz")
        #expect(output == CmdOutput(exitCode: 1))
    }

    @Test
    func execStringMatchesRegexInvalidPattern() async {
        setUpTree("h_tiles(*1)")
        let output = await runCmd("test %{app-bundle-id} ~= [")
        #expect(output == .fail("Can't parse '[' regex: expected custom character class members"))
    }

    @Test
    func execTargetResolutionFailure() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())
        let output = await runCmd("test %{window-id} = 1", windowIdEnv: 9999)
        #expect(output == .fail("Invalid <window-id> 9999 specified in AEROSPACE_WINDOW_ID env variable"))
    }

    @Test
    func notExec() async {
        setUpTree("h_tiles(*1)")

        // test inner=true → test-not=false
        var output = await runCmd("test-not %{window-id} = 1")
        #expect(output == CmdOutput(exitCode: 1))

        // test inner=false → test-not=true
        output = await runCmd("test-not %{window-id} = 2")
        #expect(output == .ok)

        // test inner=fail → test-not=fail (propagates without inverting)
        output = await runCmd("test-not %{workspace-is-focused} = foo")
        #expect(output == .fail("Can't convert String 'foo' to Bool"))
    }
}
