@testable import AppBundle
import Common
import XCTest

@MainActor
final class TestCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        testParseSingleCommandSucc(
            "test %{app-bundle-id} = foo",
            TestCmdArgs(rawArgs: [])
                .copy(\.lhs, .initialized(.app(.appBundleId)))
                .copy(\.infixOperator, .initialized(.equals))
                .copy(\.rhs, .initialized("foo")),
        )
        testParseSingleCommandSucc(
            "test-not %{app-bundle-id} ~= foo",
            TestNotCmdArgs(rawArgs: [])
                .copy(\.testArgs.lhs, .initialized(.app(.appBundleId)))
                .copy(\.testArgs.infixOperator, .initialized(.matchesRegex))
                .copy(\.testArgs.rhs, .initialized("foo")),
        )

        testParseCommandFail("test %{foo} = foo", msg: "ERROR: Can\'t parse \'foo\'.\n       Possible values: (window-id|window-is-fullscreen|window-title|window-layout|window-parent-container-layout|workspace|workspace-is-focused|workspace-is-visible|workspace-root-container-layout|app-bundle-id|app-name|app-pid|app-exec-path|app-bundle-path|monitor-id|monitor-appkit-nsscreen-screens-id|monitor-name|monitor-is-main)")
        testParseCommandFail("test foo = foo", msg: "ERROR: Left hand side must be a single interpolation variable")
        testParseCommandFail("test foo%{app-bundle-id} = foo", msg: "ERROR: Left hand side must be a single interpolation variable")
        testParseCommandFail("test", msg: "ERROR: Argument \'<lhs>\' is mandatory\nERROR: Argument \'<operator>\' is mandatory\nERROR: Argument \'<rhs>\' is mandatory")
        testParseCommandFail("test foo = %{app-bundle-id}", msg: "ERROR: Left hand side must be a single interpolation variable\nERROR: Right hand side doesn\'t allow interpolation variables")
        testParseCommandFail("test %{app-bundle-id} = %{app-bundle-id}", msg: "ERROR: Right hand side doesn\'t allow interpolation variables")
        testParseCommandFail("test %{newline} = foo", msg: "ERROR: Can\'t parse \'newline\'.\n       Possible values: (window-id|window-is-fullscreen|window-title|window-layout|window-parent-container-layout|workspace|workspace-is-focused|workspace-is-visible|workspace-root-container-layout|app-bundle-id|app-name|app-pid|app-exec-path|app-bundle-path|monitor-id|monitor-appkit-nsscreen-screens-id|monitor-name|monitor-is-main)")
        testParseCommandFail("test %{window-id} = %{invalid}", msg: "ERROR: Right hand side doesn\'t allow interpolation variables")
    }

    func testExec() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        await assertRun("test %{window-id} = 1", exitCode: 0, stdout: [], stderr: [])

        await assertRun("test %{window-id} = 2", exitCode: 1, stdout: [], stderr: [])

        await assertRun("test %{workspace-is-focused} = foo", exitCode: 2, stdout: [], stderr: ["Can\'t convert String \'foo\' to Bool"])

        await assertRun(
            "test %{workspace-is-focused} ~= foo",
            exitCode: 2,
            stdout: [],
            stderr: ["Interpolation variable: \'workspace-is-focused\' has a type of Bool. The Bool type is not compatible with \'~=\' operator."],
        )
    }

    func testExecNoWindow() async {
        assertEquals(Workspace.get(byName: name).focusWorkspace(), true)

        await assertRun("test %{window-id} = 1", exitCode: 2, stdout: [], stderr: ["No window is focused"])
    }

    func testExecWorkspaceContextSuccess() async {
        // Exercises the workspace-only branch of `_lhs` where no window is focused
        // and the lhs interpolation variable resolves against the workspace target.
        assertEquals(Workspace.get(byName: name).focusWorkspace(), true)

        await assertRun("test %{workspace-is-focused} = true", exitCode: 0, stdout: [], stderr: [])
    }

    func testExecBoolEquals() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        await assertRun("test %{workspace-is-focused} = true", exitCode: 0, stdout: [], stderr: [])

        await assertRun("test %{workspace-is-focused} = false", exitCode: 1, stdout: [], stderr: [])
    }

    func testExecIntEqualsRhsNotInt() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        await assertRun("test %{window-id} = abc", exitCode: 2, stdout: [], stderr: ["Can\'t convert String \'abc\' to Int"])
    }

    func testExecIntMatchesRegexIncompatible() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        await assertRun("test %{window-id} ~= 1", exitCode: 2, stdout: [], stderr: ["Interpolation variable: \'window-id\' has a type of Int. The Int type is not compatible with \'~=\' operator."])
    }

    func testExecStringEquals() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        await assertRun("test %{app-bundle-id} = bobko.AeroSpace.test-app", exitCode: 0, stdout: [], stderr: [])

        await assertRun("test %{app-bundle-id} = other.bundle.id", exitCode: 1, stdout: [], stderr: [])
    }

    func testExecStringMatchesRegex() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        await assertRun("test %{app-bundle-id} ~= AERO", exitCode: 0, stdout: [], stderr: [])

        await assertRun("test %{app-bundle-id} ~= zzzzz", exitCode: 1, stdout: [], stderr: [])
    }

    func testExecStringMatchesRegexInvalidPattern() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        let result = await assertRun("test %{app-bundle-id} ~= [", exitCode: 2, stdout: [])
        assertTrue(result.stderr.first?.contains("Can\'t parse \'[\' regex") ?? false)
    }

    func testExecTargetResolutionFailure() async {
        assertEquals(Workspace.get(byName: name).focusWorkspace(), true)
        let env = CmdEnv.defaultEnv.withWindowId(9999)

        await assertRun("test %{window-id} = 1", env: env, exitCode: 2, stdout: [], stderr: ["Invalid <window-id> 9999 specified in AEROSPACE_WINDOW_ID env variable"])
    }

    func testNotExec() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        // test inner=true → test-not=false
        await assertRun("test-not %{window-id} = 1", exitCode: 1, stdout: [], stderr: [])

        // test inner=false → test-not=true
        await assertRun("test-not %{window-id} = 2", exitCode: 0, stdout: [], stderr: [])

        // test inner=fail → test-not=fail (propagates without inverting)
        await assertRun("test-not %{workspace-is-focused} = foo", exitCode: 2, stdout: [], stderr: ["Can\'t convert String \'foo\' to Bool"])
    }
}
