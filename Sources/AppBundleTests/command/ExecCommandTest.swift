@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct ExecCommandTest {
    /// The bash script is the rest of the line after the command name. The description gives back the configured text
    /// (RB-15: it added a space). GenericParseErrorTest has `exec-and-forgetfoo`
    @Test(arguments: [
        ("exec-and-forget echo 'foo'", " echo 'foo'"),
        ("exec-and-forget\techo foo", "\techo foo"),
        ("exec-and-forget\necho foo\n", "\necho foo\n"),
        ("exec-and-forget", ""),
    ] as [(String, String)])
    func parse(raw: String, bashScript: String) {
        let command = parsedCmd(raw, as: ExecAndForgetCommand.self)
        expectEqual(command?.bashScript, bashScript)
        expectEqual(command?.description, raw)
    }

    /// The script runs in bash, with the config's variables and the command's target
    @Test
    func execAndForgetLaunchesBash() async {
        setUpTree("h_tiles(*1)")
        world.config.execConfig = ExecConfig(envVariables: ["PATH": "/bin"])

        expectEqual(await runCmd("exec-and-forget echo hi", windowIdEnv: 1), .ok)
        let expected: [PlatformCall] = [.launch("/bin/bash", ["-c", " echo hi"], environment: ["PATH": "/bin", AEROSPACE_WINDOW_ID: "1"])]
        expectEqual(fake.calls(of: .launch), expected)
    }

    /// The variables name the focused and the previous workspace, and the focused window or else the workspace
    @Test
    func execOnWorkspaceChangeLaunchesWithTheWorkspaces() async {
        setUpTree("h_tiles(*1)", workspace: "a")
        #expect(Workspace.get(byName: "a").focusWorkspace())
        await checkOnFocusChangedCallbacks_nonCancellable() // Remember the focus
        world.config.execOnWorkspaceChange = ["/bin/echo", "changed"]
        world.config.execConfig = ExecConfig(envVariables: ["PATH": "/bin"])

        expectEqual(await runCmd("workspace b"), .ok)
        expectEqual(await runCmd("workspace a"), .ok)
        let toEmptyB: [String: String] = ["PATH": "/bin", AEROSPACE_FOCUSED_WORKSPACE: "b", AEROSPACE_PREV_WORKSPACE: "a", AEROSPACE_WORKSPACE: "b"]
        let toWindow1: [String: String] = ["PATH": "/bin", AEROSPACE_FOCUSED_WORKSPACE: "a", AEROSPACE_PREV_WORKSPACE: "b", AEROSPACE_WINDOW_ID: "1"]
        let expected: [PlatformCall] = [
            .launch("/bin/echo", ["changed"], environment: toEmptyB),
            .launch("/bin/echo", ["changed"], environment: toWindow1),
        ]
        expectEqual(fake.calls(of: .launch), expected)
    }
}
