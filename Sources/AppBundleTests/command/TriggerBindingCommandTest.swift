@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct TriggerBindingCommandTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        testParseSingleCommandSucc("trigger-binding foo --mode main", TriggerBindingCmdArgs(rawArgs: []).copy(\.binding, .initialized("foo")).copy(\._mode, "main"))
        testParseCommandFail("trigger-binding foo", msg: "ERROR: --mode flag is mandatory")
        testParseCommandFail("trigger-binding", msg: "ERROR: Argument \'<binding>\' is mandatory")
    }

    @Test
    func testParseDashDash() {
        testParseSingleCommandSucc(
            "trigger-binding --mode main -- foo",
            TriggerBindingCmdArgs(rawArgs: []).copy(\.binding, .initialized("foo")).copy(\._mode, "main"),
        )
        testParseSingleCommandSucc(
            "trigger-binding --mode main -- --fail-if-noop",
            TriggerBindingCmdArgs(rawArgs: []).copy(\.binding, .initialized("--fail-if-noop")).copy(\._mode, "main"),
        )
        testParseCommandFail("trigger-binding --mode main --", msg: "ERROR: Argument '<binding>' is mandatory")
    }

    @Test
    func testUnknownMode_listsAvailableModesSorted() async {
        // Ten modes, so that the dictionary order can't match the sorted order by chance (RB-13)
        let modeNames = ["main", "service", "resize", "move", "a", "z", "b", "y", "c", "x"]
        config.modes = Dictionary(uniqueKeysWithValues: modeNames.map { ($0, Mode(bindings: [:])) })

        await assertRun(
            "trigger-binding alt-h --mode unknown",
            exitCode: 2,
            stdout: [],
            stderr: ["Mode 'unknown' doesn't exist. Available modes: a,b,c,main,move,resize,service,x,y,z"],
        )
    }
}
