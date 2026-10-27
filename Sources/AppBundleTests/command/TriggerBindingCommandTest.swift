@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct TriggerBindingCommandTest {
    @Test
    func parse() {
        testParseSingleCommandSucc("trigger-binding foo --mode main", TriggerBindingCmdArgs(rawArgs: []).copy(\.binding, .initialized("foo")).copy(\._mode, "main"))
        testParseSingleCommandSucc(
            "trigger-binding --mode main -- foo",
            TriggerBindingCmdArgs(rawArgs: []).copy(\.binding, .initialized("foo")).copy(\._mode, "main"),
        )
        testParseSingleCommandSucc(
            "trigger-binding --mode main -- --fail-if-noop",
            TriggerBindingCmdArgs(rawArgs: []).copy(\.binding, .initialized("--fail-if-noop")).copy(\._mode, "main"),
        )
    }

    @Test(arguments: [
        ("trigger-binding foo", "ERROR: --mode flag is mandatory"),
        ("trigger-binding", "ERROR: Argument '<binding>' is mandatory"),
        ("trigger-binding --mode main --", "ERROR: Argument '<binding>' is mandatory"),
    ])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        #expect(output == .fail(error))
    }

    @Test
    func unknownMode_listsAvailableModesSorted() async {
        // Ten modes, so that the dictionary order can't match the sorted order by chance (RB-13)
        let modeNames = ["main", "service", "resize", "move", "a", "z", "b", "y", "c", "x"]
        config.modes = Dictionary(uniqueKeysWithValues: modeNames.map { ($0, Mode(bindings: [:])) })

        let output = await runCmd("trigger-binding alt-h --mode unknown")
        #expect(output == .fail("Mode 'unknown' doesn't exist. Available modes: a,b,c,main,move,resize,service,x,y,z"))
    }
}
